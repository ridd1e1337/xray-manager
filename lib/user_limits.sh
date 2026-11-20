#!/usr/bin/env bash
# shellcheck shell=bash

# Per-user limits. Expiry applies to every multi-user protocol. Quota and
# online-IP limits need per-user counters, which only the Xray VLESS runtime
# provides through its loopback Stats API.
#
# A suspended user keeps its credentials. `.enabled` is set to false so every
# renderer and exporter already excludes it, and `.limits.resume_enabled`
# remembers the operator's intent for automatic recovery.

user_limits_default_api_port() { jq -r '.settings.xray_api_port // 10085' "${1:-$SBM_STATE}"; }

user_limits_key() { printf '%s:%s\n' "$1" "$2"; }

user_limits_validate_state() {
  jq -e '
    def int_or_null($min;$max): .==null or (type=="number" and floor==. and .>=$min and .<=$max);
    ((.settings.xray_api_port // 10085)|type=="number" and floor==. and .>=1 and .<=65535)
    and ((.settings.xray_api_port // 10085) as $api | all(.nodes[]?; .port!=$api))
    and all(.nodes[]?; . as $node | all(.users[]?; (.limits // null) as $l |
      $l==null or ($l|type=="object"
        and (.quota_bytes|int_or_null(1;9000000000000000))
        and ((.reset_period // "month")|IN("day","week","month"))
        and (if (.reset_period // "month")=="week" then (.reset_day|int_or_null(1;7))
             elif (.reset_period // "month")=="day" then true else (.reset_day|int_or_null(1;28)) end)
        and ((.expire_after_days // null)|int_or_null(1;3650))
        and (.expires_at|int_or_null(1;253402300799))
        and (.ip_limit|int_or_null(1;1024))
        and ((.suspended // null)|IN(null,"quota","expired","ip"))
        and ((.suspended_until // null)|int_or_null(1;253402300799))
        and ((.resume_enabled // false)|type=="boolean")
        and (((.quota_bytes==null and .ip_limit==null)) or ($node.protocol|IN("socks","http","mixed")|not)))))
  ' "$1" >/dev/null || { log_error '用户限额状态无效：流量配额与在线 IP 限制不适用于 SOCKS/HTTP，且节点端口不能与 Xray 统计 API 端口相同（xm xray api-port）。'; return 1; }
}

user_usage_validate() {
  jq -e '
    type=="object" and .schema_version==1 and (.users|type=="object")
    and all(.users[]; type=="object"
      and all((.upload_bytes,.download_bytes,.total_upload_bytes,.total_download_bytes)|(.//0); type=="number" and floor==. and .>=0)
      and ((.cycle_id // 0)|type=="number"))
  ' "$1" >/dev/null 2>&1
}

user_usage_init_unlocked() {
  local tmp
  mkdir -p "$(dirname "$SBM_USER_USAGE")" || return 1
  if [[ -e "$SBM_USER_USAGE" ]]; then
    user_usage_validate "$SBM_USER_USAGE" || { log_error "用户流量账本损坏：$SBM_USER_USAGE"; return 1; }
    return 0
  fi
  tmp=$(mktemp "$(dirname "$SBM_USER_USAGE")/.user-usage.XXXXXX") || return 1
  jq -n --arg now "$(now_iso)" '{schema_version:1,updated_at:$now,users:{}}' >"$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0600 "$tmp" && mv -f "$tmp" "$SBM_USER_USAGE"
}

# Replace the ledger atomically with the result of a jq program.
user_usage_update_unlocked() {
  local program=$1 tmp
  shift
  user_usage_init_unlocked || return 1
  tmp=$(mktemp "$(dirname "$SBM_USER_USAGE")/.user-usage.XXXXXX") || return 1
  jq --arg now "$(now_iso)" "$@" "$program | .updated_at=\$now" "$SBM_USER_USAGE" >"$tmp" \
    && user_usage_validate "$tmp" && chmod 0600 "$tmp" && mv -f "$tmp" "$SBM_USER_USAGE" || { rm -f "$tmp"; return 1; }
}

user_limits_xray_ready() {
  [[ "$SBM_SKIP_INIT" != 1 && -x "$SBM_XRAY_BIN" ]] || return 1
  service_active "$SBM_XRAY_SERVICE" 2>/dev/null
}

user_limits_xray_api() {
  "$SBM_XRAY_BIN" api "$1" -s "127.0.0.1:$(user_limits_default_api_port)" -t 5 "${@:2}" 2>/dev/null
}

# Read and reset Xray's per-user counters, then add the deltas to the ledger.
# Called before Xray restarts so counters are not lost with the process.
user_usage_collect_unlocked() {
  local output stats
  user_limits_xray_ready || return 0
  # Verified against Xray 26.11: {"stat":[{"name":"user>>>E>>>traffic>>>uplink","value":N}]};
  # zero counters omit "value". Inbound/outbound counters use the same shape.
  output=$(user_limits_xray_api statsquery -pattern '' -reset) || { log_warn '无法读取 Xray 流量统计。'; return 0; }
  stats=$(jq -c '
    def bucket($kind):
      [(.stat // [])[] | (.name|split(">>>")) as $p
        | select(($p|length)==4 and $p[0]==$kind and $p[2]=="traffic")
        | {key:($p[1]|sub("@";":")),dir:$p[3],value:((.value // 0)|tonumber)}]
      | group_by(.key) | map({key:.[0].key,value:{
          up:([.[]|select(.dir=="uplink").value]|add // 0),
          down:([.[]|select(.dir=="downlink").value]|add // 0)}}) | from_entries;
    {users:bucket("user"),inbounds:bucket("inbound"),outbounds:bucket("outbound")}
  ' <<<"$output" 2>/dev/null) || { log_warn 'Xray 流量统计格式无法识别。'; return 0; }
  jq -e 'any(.[][]; .up>0 or .down>0)' <<<"$stats" >/dev/null || return 0
  user_usage_update_unlocked '
    reduce ($stats.users|to_entries[]) as $e (.;
      .users[$e.key] = ((.users[$e.key] // {}) as $u | $u + {
        upload_bytes:(($u.upload_bytes // 0)+$e.value.up),
        download_bytes:(($u.download_bytes // 0)+$e.value.down),
        total_upload_bytes:(($u.total_upload_bytes // 0)+$e.value.up),
        total_download_bytes:(($u.total_download_bytes // 0)+$e.value.down)}))
    | reduce ("inbounds","outbounds") as $kind (.;
        reduce ($stats[$kind]|to_entries[]) as $e (.;
          .[$kind][$e.key] = ((.[$kind][$e.key] // {}) as $t | {
            upload_bytes:(($t.upload_bytes // 0)+$e.value.up),
            download_bytes:(($t.download_bytes // 0)+$e.value.down)})))
  ' --argjson stats "$stats"
}

# Online IPs come from Xray's statsUserOnline policy (activity in the last 20s).
user_limits_online_ips() {
  local email=$1 output
  # MASQUE nodes register "<node>@<user>" with Xray.
  if [[ $(jq -r --arg n "${email%%:*}" '.nodes[]?|select(.id==$n)|.protocol' "$SBM_STATE") == masque ]]; then email=${email/:/@}; fi
  output=$(user_limits_xray_api statsonlineiplist -email "$email") || { printf '[]\n'; return 0; }
  jq -c '(.ips // .ipList // .ip_list // {}) | if type=="object" then keys elif type=="array" then map(if type=="object" then (.ip // .key // empty) else . end) else [] end' <<<"$output" 2>/dev/null || printf '[]\n'
}

user_limits_online_map() {
  local key ips map='{}'
  user_limits_xray_ready || { printf '{}\n'; return 0; }
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    ips=$(user_limits_online_ips "$key")
    map=$(jq -c --arg key "$key" --argjson ips "$ips" '.[$key]=($ips|length)' <<<"$map") || return 1
  done < <(jq -r '.nodes[]? | select(.protocol|IN("socks","http","mixed")|not) | .id as $n | .users[] | select(.limits.ip_limit!=null and .enabled==true) | "\($n):\(.id)"' "$SBM_STATE")
  printf '%s\n' "$map"
}

# Start a new cycle for users whose monthly reset day has passed.
# Billing cycle number for a user: UTC days, weeks starting on reset_day
# (1=Monday … 7=Sunday) or months starting on reset_day. Epoch day 0 is a
# Thursday, so ISO weekday(d) = ((d + 3) % 7) + 1.
user_cycle_id() {
  local period=$1 day=$2 now_day
  now_day=$(( $(date -u +%s) / 86400 ))
  case "$period" in
    day) printf '%d\n' "$now_day";;
    week) printf '%d\n' $(( (now_day + 3 - (day - 1)) / 7 ));;
    *) traffic_cycle_id "$day";;
  esac
}

user_usage_rollover_unlocked() {
  local cycles='{}' row key period day
  while IFS=$'\t' read -r key period day; do
    [[ -n "$key" ]] || continue
    cycles=$(jq -c --arg key "$key" --argjson cycle "$(user_cycle_id "$period" "$day")" '.[$key]=$cycle' <<<"$cycles") || return 1
  done < <(jq -r '.nodes[]? | .id as $n | .users[] | select(.limits.reset_day!=null or .limits.reset_period=="day")
    | ["\($n):\(.id)", (.limits.reset_period // "month"), (.limits.reset_day // 1)] | @tsv' "$SBM_STATE")
  [[ "$cycles" != '{}' ]] || return 0
  row=$(jq -c --argjson cycles "$cycles" '[.users as $u | $cycles|to_entries[] | select(($u[.key].cycle_id // 0)!=.value)] | length' "$SBM_USER_USAGE" 2>/dev/null || echo 1)
  [[ "$row" != 0 ]] || return 0
  user_usage_update_unlocked '
    reduce ($cycles|to_entries[]) as $e (.;
      if (.users[$e.key].cycle_id // 0)==$e.value then .
      else .users[$e.key]=((.users[$e.key] // {}) + {cycle_id:$e.value,upload_bytes:0,download_bytes:0}) end)
  ' --argjson cycles "$cycles"
}

# Pure state transition shared by the periodic tick and limit edits.
USER_LIMITS_EVAL_JQ='
  def eval($now;$usage;$online):
    .nodes |= map(.id as $nid | .users |= map(
      (.limits // null) as $l |
      if $l==null then . else
        ($nid+":"+.id) as $key |
        ((($usage[$key].upload_bytes) // 0) + (($usage[$key].download_bytes) // 0)) as $used |
        (($online[$key]) // 0) as $ips |
        # Delayed start (3x-ui): the clock starts at the first recorded traffic.
        (if ($l.expire_after_days // null)!=null
            and ((($usage[$key].total_upload_bytes // 0) + ($usage[$key].total_download_bytes // 0) + $used) > 0)
          then .limits.expires_at=($now + $l.expire_after_days*86400) | .limits.expire_after_days=null else . end) |
        (.limits) as $l |
        if ($l.suspended // null)==null then
          (if $l.expires_at!=null and $l.expires_at<=$now then "expired"
           elif $l.quota_bytes!=null and $used>=$l.quota_bytes then "quota"
           elif $l.ip_limit!=null and $ips>$l.ip_limit then "ip" else null end) as $reason |
          if $reason==null or (.enabled|not) then . else
            .limits.suspended=$reason | .limits.resume_enabled=.enabled | .enabled=false
            | .limits.suspended_until=(if $reason=="ip" then $now+600 else null end) end
        else
          (if $l.suspended=="expired" then ($l.expires_at==null or $l.expires_at>$now)
           elif $l.suspended=="quota" then ($l.quota_bytes==null or $used<$l.quota_bytes)
           else ($l.ip_limit==null or ($l.suspended_until // 0)<=$now) end) as $ok |
          if $ok then .enabled=($l.resume_enabled // true) | .limits.suspended=null | .limits.suspended_until=null | .limits.resume_enabled=false
          else . end
        end
      end));
  eval($now;$usage;$online) | eval($now;$usage;$online)'

user_limits_eval_file() {
  local input=$1 output=$2 online=${3:-'{}'} usage='{}'
  [[ ! -s "$SBM_USER_USAGE" ]] || usage=$(jq -c '.users' "$SBM_USER_USAGE") || return 1
  jq --argjson now "$(date +%s)" --argjson usage "$usage" --argjson online "$online" "$USER_LIMITS_EVAL_JQ" "$input" >"$output"
}

_user_limits_apply() {
  local candidate=$1
  if ! apply_candidate_state "$candidate" user-limits; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}

user_limits_notify_changes() {
  local before=$1 after=$2 row
  [[ $(jq -r '.notifications.enabled // false' "$after") == true ]] || return 0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    notification_send user_limit "$row" || true
  done < <(jq -rn --slurpfile a "$before" --slurpfile b "$after" '
    def users($s): [$s[0].nodes[]? | .id as $n | .users[] | {key:"\($n)/\(.id)",value:(.limits.suspended // null)}] | from_entries;
    users($a) as $old | users($b) as $new |
    $new | to_entries[] | select(.value!=$old[.key]) |
    if .value==null then "用户 \(.key) 已自动恢复。"
    else "用户 \(.key) 已暂停：" + ({quota:"流量配额用尽",expired:"已到期",ip:"在线 IP 超出限制，10 分钟后自动重试"}[.value]) end')
}

user_limits_tick_unlocked() {
  local online candidate
  if ! jq -e 'any(.nodes[]?.users[]?; .limits!=null)' "$SBM_STATE" >/dev/null; then
    user_usage_collect_unlocked || true
    if declare -F subscription_refresh_user_bundles >/dev/null 2>&1; then subscription_refresh_user_bundles || true; fi
    return 0
  fi
  user_usage_init_unlocked || return 1
  user_usage_collect_unlocked || true
  user_usage_rollover_unlocked || return 1
  online=$(user_limits_online_map) || online='{}'
  candidate=$(state_candidate) || return 1
  user_limits_eval_file "$SBM_STATE" "$candidate" "$online" || { rm -f "$candidate"; return 1; }
  if jq -e --slurpfile current "$SBM_STATE" '. == $current[0]' "$candidate" >/dev/null; then
    rm -f "$candidate"
    if declare -F subscription_refresh_user_bundles >/dev/null 2>&1; then subscription_refresh_user_bundles || true; fi
    user_limits_warn_unlocked || true
    return 0
  fi
  local before
  before=$(mktemp "$SBM_RUN/user-limits-before.XXXXXX") || { rm -f "$candidate"; return 1; }
  cp "$SBM_STATE" "$before" || { rm -f "$candidate" "$before"; return 1; }
  _state_transaction_run user-limits _user_limits_apply "$candidate" || { rm -f "$before"; return 1; }
  user_limits_notify_changes "$before" "$SBM_STATE" || true
  rm -f "$before"
  user_limits_warn_unlocked || true
}
user_limits_tick() { require_root; with_lock user_limits_tick_unlocked; }

_user_limit_set() {
  local node_id=$1 user_id=$2 node protocol candidate value now at
  shift 2
  node=$(state_get_node "$node_id"); [[ -n "$node" ]] || die "节点不存在：$node_id"
  state_user_exists "$node_id" "$user_id" || die "用户不存在：$node_id/$user_id"
  protocol=$(jq -r '.protocol' <<<"$node")
  local -A set=()
  now=$(date +%s)
  while (($#)); do
    case "$1" in
      --quota)
        value=${2:?缺少配额}; set[quota_bytes]=$(traffic_nullable_size "$value") || die "无效配额：$value（示例：50G、unlimited）"; shift 2;;
      --reset-period)
        value=${2:?缺少重置周期}; [[ "$value" =~ ^(day|week|month)$ ]] || die '重置周期必须是 day、week 或 month。'
        set[reset_period]="\"$value\""; shift 2;;
      --expire-after-first-use)
        value=${2:?缺少天数}; [[ "$value" =~ ^[1-9][0-9]{0,3}$ ]] && (( value <= 3650 )) || die '天数必须为 1-3650。'
        set[expire_after_days]=$value; set[expires_at]=null; shift 2;;
      --reset-day)
        value=${2:?缺少重置日}
        if [[ "$value" == none ]]; then set[reset_day]=null
        else [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value >= 1 && 10#$value <= 28 )) || die '重置日必须是 1-28（按周时 1-7，周一=1）或 none。'; set[reset_day]=$((10#$value)); fi
        shift 2;;
      --days)
        value=${2:?缺少天数}; [[ "$value" =~ ^[1-9][0-9]{0,3}$ ]] && (( value <= 3650 )) || die '天数必须为 1-3650。'
        at=$(jq -r --arg n "$node_id" --arg u "$user_id" --argjson now "$now" '.nodes[]|select(.id==$n)|.users[]|select(.id==$u)|[.limits.expires_at // 0,$now]|max' "$SBM_STATE")
        set[expires_at]=$((at + value * 86400)); shift 2;;
      --expire-at)
        value=${2:?缺少时间}; [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die '时间须为 UTC，如 2027-01-01T00:00:00Z。'
        at=$(jq -ner --arg at "$value" '$at|fromdateiso8601') || die '到期时间无效。'
        (( at > now )) || die '到期时间必须晚于当前时间。'
        set[expires_at]=$at; shift 2;;
      --no-expiry) set[expires_at]=null; shift;;
      --ip-limit)
        value=${2:?缺少 IP 数}
        if [[ "$value" == unlimited || "$value" == none ]]; then set[ip_limit]=null
        else [[ "$value" =~ ^[1-9][0-9]{0,3}$ ]] && (( value <= 1024 )) || die 'IP 数必须为 1-1024 或 unlimited。'; set[ip_limit]=$value; fi
        shift 2;;
      --clear) set[clear]=1; shift;;
      *) die "未知用户限额参数：$1";;
    esac
  done
  # SOCKS/HTTP accounts have no Xray user email, so no per-user counters.
  if [[ "$protocol" =~ ^(socks|http|mixed)$ ]] && { [[ ${set[quota_bytes]:-null} != null ]] || [[ ${set[ip_limit]:-null} != null ]]; }; then
    die 'SOCKS/HTTP 账号在 Xray 中没有用户统计，不能设置流量配额或在线 IP；可使用到期时间或节点级流量控制（xm traffic set）。'
  fi
  if [[ ${set[ip_limit]:-null} != null ]] && jq -e '
      ((.listen // "::")|IN("127.0.0.1","::1","localhost"))
      and ((.xray.inbound.streamSettings.sockopt.acceptProxyProtocol // false)|not)
      and ((.xray.inbound.streamSettings.sockopt.trustedXForwardedFor // [])|length==0)' <<<"$node" >/dev/null; then
    # Xray never records loopback sources as online IPs.
    log_warn '该节点只监听本机，经反向代理接入时 Xray 看不到客户端 IP，在线 IP 限制不会生效；请让代理发送 PROXY protocol 并执行 --accept-proxy-protocol true，或配置 sockopt.trustedXForwardedFor。'
  fi
  local patch='{}' key
  [[ ! -v set[expires_at] || -v set[expire_after_days] || ${set[expires_at]} == null ]] || set[expire_after_days]=null
  for key in quota_bytes reset_day reset_period expires_at expire_after_days ip_limit; do
    [[ -v set[$key] ]] || continue
    patch=$(jq -c --arg key "$key" --argjson value "${set[$key]}" '.[$key]=$value' <<<"$patch") || return 1
  done
  [[ ! -v set[clear] ]] || patch='{"quota_bytes":null,"reset_day":null,"reset_period":null,"expires_at":null,"expire_after_days":null,"ip_limit":null}'
  user_usage_collect_unlocked || true
  candidate=$(state_candidate) || return 1
  jq --arg n "$node_id" --arg u "$user_id" --argjson patch "$patch" '
    (.nodes[]|select(.id==$n)|.users[]|select(.id==$u)) |=
      (.limits=({quota_bytes:null,reset_day:null,expires_at:null,ip_limit:null,suspended:null,suspended_until:null,resume_enabled:false} + (.limits // {}) + $patch)
       | if .limits.quota_bytes==null and .limits.expires_at==null and .limits.ip_limit==null and (.limits.expire_after_days // null)==null then
           (if .limits.suspended!=null then .enabled=(.limits.resume_enabled // true) else . end) | del(.limits)
         else . end)
  ' "$SBM_STATE" >"$candidate.raw" || { rm -f "$candidate" "$candidate.raw"; return 1; }
  if [[ -v set[reset_day] || -v set[reset_period] ]]; then
    local period day
    read -r period day < <(jq -r --arg n "$node_id" --arg u "$user_id" '.nodes[]|select(.id==$n)|.users[]|select(.id==$u)|[(.limits.reset_period // "month"),(.limits.reset_day // 1)]|@tsv' "$candidate.raw")
    if [[ "$period" == week ]] && (( day > 7 )); then rm -f "$candidate" "$candidate.raw"; die '按周重置时 --reset-day 为 1-7（周一=1）。'; fi
    user_usage_update_unlocked '.users[$key]=((.users[$key] // {}) + {cycle_id:$cycle})' \
      --arg key "$(user_limits_key "$node_id" "$user_id")" --argjson cycle "$(user_cycle_id "$period" "$day")" || return 1
  fi
  user_limits_eval_file "$candidate.raw" "$candidate" || { rm -f "$candidate" "$candidate.raw"; return 1; }
  rm -f "$candidate.raw"
  if [[ ${SBM_DRY_RUN:-0} == 1 ]]; then config_preview_candidate "$candidate"; rm -f "$candidate"; return 0; fi
  if ! apply_candidate_state "$candidate" "user-limit-$node_id-$user_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "已更新用户限额：$node_id/$user_id"
}

user_limit_cli() {
  local node_id=${1:-} user_id=${2:-}
  [[ -n "$node_id" && -n "$user_id" ]] || usage_die '用法：xm user limit NODE_ID USER_ID [--quota SIZE|unlimited] [--reset-day 1-28|none] [--days N|--expire-at UTC|--no-expiry] [--ip-limit N|unlimited] [--clear]'
  if (($# == 2)); then user_stats_json "$node_id" | jq --arg u "$user_id" '.[] | select(.user==$u)'; return; fi
  require_root
  if [[ ${SBM_DRY_RUN:-0} == 1 ]]; then with_lock _user_limit_set "$@"
  else with_state_transaction user-limit _user_limit_set "$@"; fi
}

_user_usage_reset() {
  local key
  key=$(user_limits_key "$1" "$2")
  state_user_exists "$1" "$2" || die "用户不存在：$1/$2"
  user_usage_collect_unlocked || true
  user_usage_update_unlocked '.users[$key]=((.users[$key] // {}) + {upload_bytes:0,download_bytes:0})' --arg key "$key" || return 1
  user_limits_tick_unlocked || return 1
  log_ok "已清零本周期用户流量：$1/$2"
}
user_usage_reset() { require_root; with_lock _user_usage_reset "$@"; }

user_stats_json() {
  local filter=${1:-} usage='{}' online='{}'
  [[ ! -s "$SBM_USER_USAGE" ]] || usage=$(jq -c '.users' "$SBM_USER_USAGE")
  if [[ $EUID -eq 0 ]] && user_limits_xray_ready; then
    local key
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      online=$(jq -c --arg key "$key" --argjson ips "$(user_limits_online_ips "$key")" '.[$key]=$ips' <<<"$online")
    done < <(jq -r --arg f "$filter" '.nodes[]? | select((.protocol|IN("socks","http","mixed")|not) and ($f=="" or .id==$f)) | .id as $n | .users[] | select(.enabled) | "\($n):\(.id)"' "$SBM_STATE")
  fi
  jq --arg f "$filter" --argjson usage "$usage" --argjson online "$online" '[
    .nodes[]? | select($f=="" or .id==$f) | .id as $n | .protocol as $p | .users[] |
    ("\($n):\(.id)") as $key | ($usage[$key] // {}) as $u |
    {node:$n,user:.id,name,protocol:$p,enabled,
     upload_bytes:($u.upload_bytes // 0),download_bytes:($u.download_bytes // 0),
     total_upload_bytes:($u.total_upload_bytes // 0),total_download_bytes:($u.total_download_bytes // 0),
     online_ips:($online[$key] // null),limits:(.limits // null),
     stats:(if ($p|IN("socks","http","mixed")) then "unavailable" else "xray" end)}]' "$SBM_STATE"
}

user_stats() {
  local filter=${1:-} json=${2:-0} rows
  [[ -z "$filter" ]] || state_node_exists "$filter" || die "节点不存在：$filter"
  if [[ $EUID -eq 0 ]]; then with_lock user_usage_collect_unlocked || true; fi
  rows=$(user_stats_json "$filter") || return 1
  if [[ "$json" == 1 ]]; then printf '%s\n' "$rows"; return; fi
  printf '%-14s %-12s %-6s %-11s %-11s %-12s %-8s %s\n' 节点 用户 状态 本期上行 本期下行 配额 在线IP 到期
  jq -r '.[] | [.node,.user,
      (if .limits.suspended!=null then "暂停:"+.limits.suspended elif .enabled then "启用" else "停用" end),
      (.upload_bytes|tostring),(.download_bytes|tostring),
      (if .limits.quota_bytes==null then "-" else (.limits.quota_bytes|tostring) end),
      (if .online_ips==null then "-" else (.online_ips|length|tostring) + (if .limits.ip_limit==null then "" else "/"+(.limits.ip_limit|tostring) end) end),
      (if .limits.expires_at==null then "-" else (.limits.expires_at|todateiso8601) end),
      .stats] | @tsv' <<<"$rows" |
    while IFS=$'\t' read -r node user status up down quota ips expiry stats; do
      if [[ "$stats" != xray ]]; then up=-; down=-; else up=$(traffic_format_bytes "$up"); down=$(traffic_format_bytes "$down"); fi
      [[ "$quota" == - ]] || quota=$(traffic_format_bytes "$quota")
      printf '%-14s %-12s %-6s %-11s %-11s %-12s %-8s %s\n' "$node" "$user" "$status" "$up" "$down" "$quota" "$ips" "$expiry"
    done
}

xray_traffic_json() {
  [[ -s "$SBM_USER_USAGE" ]] || { printf '{"inbounds":{},"outbounds":{}}\n'; return 0; }
  jq '{updated_at,inbounds:(.inbounds // {}),outbounds:(.outbounds // {})}' "$SBM_USER_USAGE"
}

xray_traffic() {
  local json=${1:-0} rows
  if [[ $EUID -eq 0 ]]; then with_lock user_usage_collect_unlocked || true; fi
  rows=$(xray_traffic_json) || return 1
  if [[ "$json" == 1 ]]; then printf '%s\n' "$rows"; return; fi
  printf '%-10s %-28s %-12s %s\n' 类型 标签 上行 下行
  jq -r '(.inbounds|to_entries[]|["入站",.key,.value.upload_bytes,.value.download_bytes]),
         (.outbounds|to_entries[]|["出站",.key,.value.upload_bytes,.value.download_bytes]) | @tsv' <<<"$rows" |
    while IFS=$'\t' read -r kind tag up down; do
      printf '%-10s %-28s %-12s %s\n' "$kind" "$tag" "$(traffic_format_bytes "$up")" "$(traffic_format_bytes "$down")"
    done
}

_xray_traffic_reset() {
  user_usage_collect_unlocked || true
  user_usage_update_unlocked '.inbounds={} | .outbounds={}' || return 1
  log_ok '已清零 Xray 入站/出站累计流量。'
}
xray_traffic_reset() { require_root; with_lock _xray_traffic_reset; }

# Online users and their source IPs from the Stats API (activity in the last
# ~20 s), like 3x-ui's online list and client IP log.
user_online() {
  local filter=${1:-} key ips count=0
  [[ -z "$filter" ]] || state_node_exists "$filter" || die "节点不存在：$filter"
  require_root
  user_limits_xray_ready || die 'Xray 未运行，无法读取在线信息。'
  printf '%-28s %s\n' '节点:用户' '在线 IP'
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    ips=$(user_limits_online_ips "$key" | jq -r 'join(", ")')
    [[ -n "$ips" ]] || continue
    printf '%-28s %s\n' "$key" "$ips"; count=$((count + 1))
  done < <(jq -r --arg f "$filter" '.nodes[]? | select(.enabled and (.protocol|IN("socks","http","mixed","tunnel")|not) and ($f=="" or .id==$f))
    | .id as $n | .users[] | select(.enabled) | "\($n):\(.id)"' "$SBM_STATE")
  (( count )) || printf '当前没有在线用户。\n'
}

# 3x-ui "edit used traffic": set this cycle's usage (counted as download).
_user_usage_set() {
  local node_id=$1 user_id=$2 value=$3 bytes
  state_user_exists "$node_id" "$user_id" || die "用户不存在：$node_id/$user_id"
  if [[ "$value" == 0 ]]; then bytes=0; else bytes=$(traffic_parse_size "$value") || die "无效流量：$value（示例：10G、0）"; fi
  user_usage_init_unlocked || return 1
  user_usage_collect_unlocked || true
  user_usage_update_unlocked '.users[$key]=((.users[$key] // {}) + {upload_bytes:0,download_bytes:$bytes})' \
    --arg key "$(user_limits_key "$node_id" "$user_id")" --argjson bytes "$bytes" || return 1
  user_limits_tick_unlocked || return 1
  log_ok "已将 $node_id/$user_id 本周期已用流量设为 $(traffic_format_bytes "$bytes")"
}
user_usage_set() { require_root; with_lock _user_usage_set "$@"; }

# Portable user record (3x-ui client export): profile, limits and the
# credential, so a user can move to another node of the same protocol without
# re-importing the client. The file is a secret (0600).
user_export() {
  local node_id=$1 user_id=$2 output=${3:-} node record
  require_root
  node=$(state_get_node "$node_id"); [[ -n "$node" ]] || die "节点不存在：$node_id"
  state_user_exists "$node_id" "$user_id" || die "用户不存在：$node_id/$user_id"
  record=$(jq -n --argjson node "$node" --arg u "$user_id" --argjson secret "$(state_get_user_secret "$node_id" "$user_id")" '
    ($node.users[] | select(.id==$u)) as $user |
    {format:"xray-manager-user",version:1,protocol:$node.protocol,method:($node.method // null),
     user:($user | {id,name,enabled,limits}),secret:$secret}') || return 1
  if [[ -z "$output" ]]; then printf '%s\n' "$record"; return; fi
  (umask 077; printf '%s\n' "$record" >"$output") && log_ok "已导出用户：$output（含凭据，请妥善保管）"
}

_user_import() {
  local node_id=$1 file=$2 new_id=${3:-} node record protocol user_id candidate
  node=$(state_get_node "$node_id"); [[ -n "$node" ]] || die "节点不存在：$node_id"
  record=$(jq -ce 'select(.format=="xray-manager-user" and .version==1)' "$file") || die '不是有效的用户导出文件。'
  protocol=$(jq -r '.protocol' <<<"$record")
  [[ "$protocol" == "$(jq -r '.protocol' <<<"$node")" ]] || die "协议不同：文件为 $protocol，目标节点为 $(jq -r '.protocol' <<<"$node")。"
  [[ "$protocol" != shadowsocks || $(jq -r '.method' <<<"$record") == $(jq -r '.method' <<<"$node") ]] || die 'Shadowsocks 加密方式不同，凭据不可复用。'
  [[ "$protocol" != wireguard ]] || die 'WireGuard 用户地址属于原节点子网，请在目标节点新建用户。'
  user_id=${new_id:-$(jq -r '.user.id' <<<"$record")}
  validate_node_id "$user_id" || die "无效用户 ID：$user_id"
  state_user_exists "$node_id" "$user_id" && die "用户已存在：$node_id/$user_id"
  state_write_user_secret "$node_id" "$user_id" "$(jq -c '.secret' <<<"$record")" || return 1
  candidate=$(state_candidate) || return 1
  jq --arg n "$node_id" --arg u "$user_id" --argjson r "$record" --arg now "$(now_iso)" '
    (.nodes[]|select(.id==$n)|.users) += [($r.user + {id:$u,created_at:$now}) | with_entries(select(.value!=null))]' "$SBM_STATE" >"$candidate" || { rm -f "$candidate"; return 1; }
  if ! apply_candidate_state "$candidate" "user-import-$node_id-$user_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "已导入用户：$node_id/$user_id"
}
user_import() { require_root; with_state_transaction user-import _user_import "$@"; }

_user_tg_set() {
  local node_id=$1 user_id=$2 value=$3 candidate tg=null
  state_user_exists "$node_id" "$user_id" || die "用户不存在：$node_id/$user_id"
  if [[ "$value" != none ]]; then [[ "$value" =~ ^[1-9][0-9]{0,15}$ ]] || die 'Telegram 用户 ID 须为数字（可让用户向 @userinfobot 查询）。'; tg=$value; fi
  candidate=$(state_candidate) || return 1
  jq --arg n "$node_id" --arg u "$user_id" --argjson tg "$tg" '(.nodes[]|select(.id==$n)|.users[]|select(.id==$u)) |= (if $tg==null then del(.tg_id) else .tg_id=$tg end)' "$SBM_STATE" >"$candidate" || { rm -f "$candidate"; return 1; }
  if ! apply_candidate_state "$candidate" "user-tg-$node_id-$user_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  if [[ "$tg" == null ]]; then log_ok "已解除 $node_id/$user_id 的 Telegram 绑定。"
  else log_ok "已绑定 $node_id/$user_id → Telegram $tg；该用户私聊机器人可用 /me 与 /link，并接收到期/流量预警。"; fi
}
user_tg_set() { require_root; with_state_transaction user-tg _user_tg_set "$@"; }

# Expiry (≤3 days) and quota (≥80%) warnings, once per user/kind/period.
# Sent to the admin notification channel and, when bound, to the user.
SBM_USER_WARNINGS="${SBM_USER_WARNINGS:-$SBM_VAR/user-warnings.json}"
user_limits_warn_unlocked() {
  local usage='{}' sent='{}' rows row key msg tg token
  [[ $(jq -r '.notifications.enabled // false' "$SBM_STATE") == true ]] || return 0
  [[ ! -s "$SBM_USER_USAGE" ]] || usage=$(jq -c '.users' "$SBM_USER_USAGE") || return 0
  [[ ! -s "$SBM_USER_WARNINGS" ]] || sent=$(jq -c . "$SBM_USER_WARNINGS" 2>/dev/null) || sent='{}'
  rows=$(jq -c --argjson usage "$usage" --argjson sent "$sent" --argjson now "$(date +%s)" '
    [.nodes[]? | .id as $n | .users[] | select(.enabled and .limits!=null) | . as $u | "\($n):\(.id)" as $k | ($usage[$k] // {}) as $use |
      ((if $u.limits.expires_at!=null and $u.limits.expires_at>$now and ($u.limits.expires_at-$now)<=259200 then
          {key:"\($k):expire:\($u.limits.expires_at)", msg:"用户 \($n)/\($u.id) 将于 \($u.limits.expires_at|todateiso8601) 到期。"} else empty end),
       (if $u.limits.quota_bytes!=null and ((($use.upload_bytes // 0)+($use.download_bytes // 0)) >= $u.limits.quota_bytes*0.8) then
          {key:"\($k):quota:\($use.cycle_id // 0)", msg:"用户 \($n)/\($u.id) 本期流量已用 \(((($use.upload_bytes // 0)+($use.download_bytes // 0))*100/$u.limits.quota_bytes)|floor)%。"} else empty end))
      | select($sent[.key]==null) + {tg:($u.tg_id // null)}]' "$SBM_STATE") || return 0
  [[ "$rows" != '[]' ]] || return 0
  token=$(jq -r 'select(.provider=="telegram")|.bot_token // empty' "$SBM_NOTIFICATION_SECRET" 2>/dev/null || true)
  while IFS= read -r row; do
    key=$(jq -r '.key' <<<"$row"); msg=$(jq -r '.msg' <<<"$row"); tg=$(jq -r '.tg // empty' <<<"$row")
    notification_send user_limit "$msg" || true
    if [[ -n "$tg" && -n "$token" && $(jq -r '.notifications.bot.enabled // false' "$SBM_STATE") == true ]]; then
      telegram_bot_reply "$token" "$tg" "提醒：$msg" || true
    fi
    sent=$(jq -c --arg k "$key" --argjson now "$(date +%s)" '.[$k]=$now' <<<"$sent")
  done < <(jq -c '.[]' <<<"$rows")
  # Keep the journal small: entries older than 40 days are dropped.
  (umask 077; jq -c --argjson now "$(date +%s)" 'with_entries(select(.value > $now - 3456000))' <<<"$sent" >"$SBM_USER_WARNINGS.tmp" && mv -f "$SBM_USER_WARNINGS.tmp" "$SBM_USER_WARNINGS")
}
