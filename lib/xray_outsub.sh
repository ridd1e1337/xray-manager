#!/usr/bin/env bash
# shellcheck shell=bash

# Outbound subscriptions (3x-ui "outbound subs"): import a remote list of share
# links as Xray outbounds tagged PREFIX-1…N, optionally grouped by a balancer
# of the same name. URLs may embed tokens, so they live in a 0600 secret.
# Refresh replaces the whole set in one transaction; if a rule still points at
# a tag that disappeared, validation fails and the old set is kept.

SBM_XRAY_OUTSUBS="${SBM_XRAY_OUTSUBS:-$SBM_SECRETS/xray-outsubs.json}"
SBM_XRAY_OUTSUB_MAX="${SBM_XRAY_OUTSUB_MAX:-200}"

xray_outsub_urls() { [[ -s "$SBM_XRAY_OUTSUBS" ]] && jq -c . "$SBM_XRAY_OUTSUBS" || printf '{}\n'; }

# Fetch and convert; prints [{tag,name,outbound}] for valid links only.
xray_outsub_fetch() (
  local url=$1 prefix=$2 dir body links
  dir=$(mktemp -d "$SBM_RUN/outsub.XXXXXX") || return 1
  trap 'rm -rf -- "$dir"' EXIT
  curl --fail --silent --show-error --location --proto '=https,http' --max-redirs 3 --connect-timeout 15 --max-time 60 \
    --max-filesize 10485760 -A 'xray-manager' "$url" -o "$dir/body" || { log_error '订阅下载失败。'; return 1; }
  body=$(tr -d '\r' <"$dir/body")
  if ! grep -q '://' <<<"$body"; then body=$(tr -d '\n ' <<<"$body" | base64 -d 2>/dev/null | tr -d '\r') || { log_error '订阅内容既不是链接列表也不是 base64。'; return 1; }; fi
  links=$(grep -E '^[a-z0-9]+://' <<<"$body" | head -n "$SBM_XRAY_OUTSUB_MAX")
  [[ -n "$links" ]] || { log_error '订阅中没有可识别的分享链接。'; return 1; }
  # jq -R runs the converter once per line in a single process; duplicates are dropped.
  printf '%s\n' "$links" | jq -R -c --arg tag x -f "$SBM_LIB/libexec/share_to_xray.jq" |
    jq -s -c --arg prefix "$prefix" '
      ([.[] | select(.error == null)] | unique_by(.outbound | del(.tag))) as $ok |
      {skipped:([.[] | select(.error != null) | .error] | group_by(.) | map({reason:.[0], count:length})),
       items:[$ok | to_entries[] | {tag:"\($prefix)-\(.key + 1)", name:.value.name, outbound:(.value.outbound | del(.tag))}]}'
)

_xray_outsub_apply() {
  local name=$1 url=$2 prefix=$3 balancer=$4 result items outbounds tags count
  result=$(xray_outsub_fetch "$url" "$prefix") || return 1
  items=$(jq -c '.items' <<<"$result"); count=$(jq 'length' <<<"$items")
  (( count > 0 )) || { log_error '订阅中没有可转换的节点。'; jq -r '.skipped[] | "  跳过 \(.count) 条：\(.reason)"' <<<"$result" >&2; return 1; }
  tags=$(jq -c '[.[].tag]' <<<"$items")
  # Replace this subscription's previous outbounds (secret objects + state refs).
  outbounds=$(xray_outbounds_read | jq -c --arg prefix "$prefix" --argjson items "$items" '
    with_entries(select(.key | startswith($prefix + "-") | not)) + ($items | map({key:.tag, value:.outbound}) | from_entries)') || return 1
  _xray_routing_commit '
    .xray_routing.outbounds = ([.xray_routing.outbounds[] | select(.tag | startswith($prefix + "-") | not)]
      + ($items | map({tag, protocol:.outbound.protocol, via:null, subscription:$name})))
    | .xray_routing.subscriptions = ([(.xray_routing.subscriptions // [])[] | select(.name != $name)]
      + [{name:$name, prefix:$prefix, balancer:$balancer, count:($tags|length), updated_at:$now}])
    | if $balancer == "none" then .xray_routing.balancers |= map(select(.tag != $name))
      else .xray_routing.balancers = ([.xray_routing.balancers[] | select(.tag != $name)]
        + [{tag:$name, selectors:$tags, strategy:$balancer, fallback:"direct"}]) end' "$outbounds" \
    --arg name "$name" --arg prefix "$prefix" --arg balancer "$balancer" --argjson items "$items" --argjson tags "$tags" --arg now "$(now_iso)" \
    || { log_error "若有路由规则直接指向 $prefix-N，节点数变化后会失效；建议让规则指向负载均衡 balancer:$name。原节点保持不变。"; return 1; }
  (umask 077; jq -c --arg n "$name" --arg u "$url" '.[$n]=$u' <<<"$(xray_outsub_urls)" >"$SBM_XRAY_OUTSUBS.tmp" && mv -f "$SBM_XRAY_OUTSUBS.tmp" "$SBM_XRAY_OUTSUBS") || return 1
  log_ok "出站订阅 $name：导入 $count 个节点（标签 $prefix-1…$prefix-$count$([[ "$balancer" == none ]] || echo "，负载均衡 $name")）"
  jq -r '.skipped[] | "  跳过 \(.count) 条：\(.reason)"' <<<"$result"
}

_xray_outsub_remove() {
  local name=$1 prefix outbounds
  prefix=$(jq -r --arg n "$name" '(.xray_routing.subscriptions // [])[] | select(.name==$n) | .prefix' "$SBM_STATE")
  [[ -n "$prefix" ]] || { log_error "出站订阅不存在：$name"; return 1; }
  outbounds=$(xray_outbounds_read | jq -c --arg prefix "$prefix" 'with_entries(select(.key | startswith($prefix + "-") | not))') || return 1
  _xray_routing_commit '
    .xray_routing.outbounds |= map(select(.tag | startswith($prefix + "-") | not))
    | .xray_routing.balancers |= map(select(.tag != $name))
    | .xray_routing.subscriptions |= map(select(.name != $name))' "$outbounds" --arg name "$name" --arg prefix "$prefix" || return 1
  (umask 077; jq -c --arg n "$name" 'del(.[$n])' <<<"$(xray_outsub_urls)" >"$SBM_XRAY_OUTSUBS.tmp" && mv -f "$SBM_XRAY_OUTSUBS.tmp" "$SBM_XRAY_OUTSUBS") || return 1
  log_ok "已删除出站订阅：$name"
}

# Refresh all (or one) subscriptions; used by the CLI and the daily task.
xray_outsub_refresh() {
  local only=${1:-} row name prefix balancer url rc=0
  while IFS=$'\t' read -r name prefix balancer; do
    [[ -n "$name" ]] || continue
    url=$(jq -r --arg n "$name" '.[$n] // empty' <<<"$(xray_outsub_urls)")
    [[ -n "$url" ]] || { log_error "出站订阅 $name 缺少地址。"; rc=1; continue; }
    with_state_transaction xray-outsub _xray_outsub_apply "$name" "$url" "$prefix" "$balancer" || rc=1
  done < <(jq -r --arg only "$only" '(.xray_routing.subscriptions // [])[] | select($only=="" or .name==$only) | [.name,.prefix,.balancer] | @tsv' "$SBM_STATE")
  return "$rc"
}

xray_outsub_cli() {
  local action=${1:-list} name url prefix balancer=leastPing
  case "$action" in
    list) jq -r '(.xray_routing.subscriptions // []) | if length==0 then "（无出站订阅）" else .[] | "\(.name)  \(.count) 个节点  前缀 \(.prefix)  负载均衡 \(.balancer)  更新于 \(.updated_at)" end' "$SBM_STATE";;
    add)
      name=${2:-}; url=${3:-}
      [[ -n "$name" && -n "$url" ]] || usage_die '用法：xm xray outbound sub add NAME URL [--prefix P] [--balancer leastPing|leastLoad|random|roundRobin|none]'
      shift 3; prefix=$name
      while (($#)); do case "$1" in --prefix) prefix=${2:?}; shift 2;; --balancer) balancer=${2:?}; shift 2;; *) usage_die "未知参数：$1";; esac; done
      xray_routing_validate_tag "$name" && xray_routing_validate_tag "$prefix-1" || return 1
      [[ "$balancer" =~ ^(leastPing|leastLoad|random|roundRobin|none)$ ]] || die '负载均衡策略无效。'
      [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || die '订阅地址须为 http(s) URL。'
      jq -e --arg n "$name" '(.xray_routing.subscriptions // [])|any(.name==$n)|not' "$SBM_STATE" >/dev/null || die "出站订阅已存在：$name"
      jq -e --arg p "$prefix" '(.xray_routing.outbounds // [])|any(.tag|startswith($p + "-"))|not' "$SBM_STATE" >/dev/null || die "前缀 $prefix 与现有出站冲突。"
      require_root; with_state_transaction xray-outsub _xray_outsub_apply "$name" "$url" "$prefix" "$balancer";;
    refresh) require_root; xray_outsub_refresh "${2:-}";;
    remove) [[ -n "${2:-}" ]] || usage_die '用法：xm xray outbound sub remove NAME'; require_root; with_state_transaction xray-outsub _xray_outsub_remove "$2";;
    *) usage_die '用法：xm xray outbound sub list|add NAME URL [--prefix P] [--balancer STRATEGY|none]|refresh [NAME]|remove NAME';;
  esac
}
