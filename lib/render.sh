#!/usr/bin/env bash
# shellcheck shell=bash

node_transport_kinds() {
  local node=$1 protocol network
  protocol=$(jq -r '.protocol' <<<"$node")
  case "$protocol" in
    vmess-ws-cf|http|socks|mixed) printf 'tcp\n' ;;
    wireguard|masque) printf 'udp\n' ;;
    tunnel) case "$(jq -r '.network' <<<"$node")" in tcp) printf 'tcp\n';; udp) printf 'udp\n';; *) printf 'tcp\nudp\n';; esac ;;
    vless|vmess|trojan) vless_node_listener_kinds "$node" ;;
    hysteria2) printf 'udp\n' ;;
    shadowsocks)
      network=$(jq -r '.network // "tcp"' <<<"$node")
      case "$network" in tcp) printf 'tcp\n';; udp) printf 'udp\n';; *) printf 'tcp\nudp\n';; esac
      ;;
    *) return 1 ;;
  esac
}

# Return the user-supplied sing-box extension for a node.  The extension is
# intentionally kept as JSON so new sing-box fields can be used before the
# manager has a dedicated flag for them.
singbox_node_override() {
  local node=$1 direction=$2
  jq -c --arg direction "$direction" '
    if ((.singbox // {}) | type) == "object"
       and ((.singbox[$direction] // {}) | type) == "object"
    then (.singbox[$direction] // {})
    else {}
    end
  ' <<<"$node"
}

# Apply an extension to a generated sing-box object.  ShadowTLS and other
# compound protocols render an array; by default the extension targets the
# primary object.  An optional `by_tag` map targets individual array members,
# which makes nested protocols fully extensible as well.
singbox_apply_override() {
  local rendered=$1 override=$2
  jq --argjson override "$override" '
    def safe_extension:
      del(.type, .tag, .listen, .listen_port, .server, .server_port,
          .users, .password, .uuid, .psk);
    if ($override | type) != "object" or ($override | length) == 0 then .
    elif type == "array" then
      . as $items
      | ($override.by_tag // {}) as $by_tag
      | ($override | del(.by_tag) | safe_extension) as $default
      | [ range(0; ($items | length)) as $i
          | $items[$i] as $item
          | if (($by_tag | type) == "object" and (($by_tag[$item.tag // ""] // null) | type == "object"))
            then $item * ($by_tag[$item.tag] | safe_extension)
            elif $i == 0 then $item * $default
            else $item
            end
        ]
    else . * ($override | del(.by_tag) | safe_extension)
    end
  ' <<<"$rendered"
}

# jq definitions shared by validation, port checks and status: which
# sockets (tcp/udp) a node listens on, mirroring node_transport_kinds.
SBM_JQ_NODE_KINDS='
    def net: (.xray.inbound.streamSettings.method // .xray.inbound.streamSettings.network // "raw" | ascii_downcase
      | if .=="tcp" or .=="" then "raw" elif .=="websocket" then "ws" elif .=="splithttp" then "xhttp" elif .=="mkcp" then "kcp" else . end);
    def security: if .security!=null then .security elif .protocol=="trojan" then "tls" else "none" end;
    def kinds:
      if .protocol|IN("vmess-ws-cf","http","socks","mixed") then ["tcp"]
      elif .protocol|IN("wireguard","masque","hysteria2") then ["udp"]
      elif .protocol=="tunnel" or .protocol=="shadowsocks" then
        ((.network // "tcp") | if .=="tcp" then ["tcp"] elif .=="udp" then ["udp"] else ["tcp","udp"] end)
      elif .protocol|IN("vless","vmess","trojan") then
        (net as $n | if $n|IN("kcp","hysteria") then ["udp"] elif $n=="xdrive" then []
         elif $n=="xhttp" and (.xray.inbound.streamSettings.tlsSettings.alpn==["h3"]) and ((.xray.inbound.streamSettings.security // .security)=="tls") then ["udp"]
         else ["tcp"] end)
      else [] end;
'

# Cross-node checks in one jq pass. jq emits tab-separated work items:
#   E <message>              hard error
#   A <node> <address>       client address to validate
#   C <node> <domain>        TLS certificate must exist
#   U <node> <user>          user secret must exist
#   S <node>                 protocol-level secret must exist
#   V <node> <json> <users>  run the Xray stream profile check (skipped when
#                            node, secrets and Xray build are unchanged)
validate_state_semantics() {
  local state=$1 tag a b c node secret dir marker u
  local -a files=()
  dir=$(vless_cache_dir 2>/dev/null) || dir=''
  state_validate "$state" || return 1
  if declare -F traffic_validate_state >/dev/null 2>&1; then traffic_validate_state "$state" || return 1; fi
  if declare -F nginx_stream_validate_state >/dev/null 2>&1; then nginx_stream_validate_state "$state" || die 'TCP/SNI 复用状态无效。'; fi
  while IFS=$'\t' read -r tag a b c; do
    case "$tag" in
      E) die "$a";;
      A) validate_address "$b" || die "节点 $a 的客户端服务器地址无效或为空。";;
      C) validate_domain "$b" || die "节点 $a 的 TLS 域名无效：$b"
         [[ -s "$SBM_CERTS/$b/fullchain.pem" && -s "$SBM_CERTS/$b/key.pem" ]] || die "节点 $a 缺少证书：$SBM_CERTS/$b/{fullchain.pem,key.pem}";;
      U) [[ -r "$(state_user_secret_path "$a" "$b")" ]] || die "节点 $a 的用户 $b 缺少密钥文件。";;
      S) [[ -r "$(state_secret_path "$a")" ]] || die "节点 $a 缺少协议级密钥文件。";;
      V) node=$b; marker=''
         if [[ -n "$dir" ]]; then
           files=(); for u in $c; do files+=("$(state_user_secret_path "$a" "$u")"); done
           [[ ! -r "$(state_secret_path "$a")" ]] || files+=("$(state_secret_path "$a")")
           marker="$dir/$(vless_cache_key profile-valid "$node" "$(cat -- "${files[@]}" 2>/dev/null | sha256sum)").valid"
           [[ ! -e "$marker" ]] || continue
         fi
         secret='{}'; [[ ! -r "$(state_secret_path "$a")" ]] || secret=$(state_get_secret "$a") || return 1
         vless_profile_validate "$node" "$secret" "$state" || return 1
         [[ -z "$marker" ]] || (umask 077; : >"$marker") 2>/dev/null || true;;
    esac
  done < <(jq -r "$SBM_JQ_NODE_KINDS"'
    def tab: map(tostring) | join("\t");
    (.nginx_stream.enabled // false) as $mux | (.nginx_stream.routes // []) as $routes |
    [.nodes[]?.id] as $ids |
    (if ($ids|length) != ($ids|unique|length) then ["E","状态中存在重复节点 ID。"]|tab else empty end),
    ( [ (if $mux then {key:"tcp:\(.nginx_stream.port)", owner:"TCP/SNI 复用入口"} else empty end),
        (.nodes[]? | select(.enabled==true) | . as $n |
          ([$routes[] | select(.node_id==$n.id)] | first) as $r |
          (if $mux and $r != null then $r.backend_port else $n.port end) as $port |
          kinds[] | {key:"\(.):\($port)", owner:$n.id, port:$port, kind:.}) ]
      | group_by(.key)[] | select(length>1)
      | ["E","端口冲突：\(.[1].owner) 与 \(.[0].owner) 同时占用 \(.[1].port)/\(.[1].kind|ascii_upcase)。"] | tab ),
    ( .nodes[]? | . as $n |
      (if (.id|test("^[a-z0-9][a-z0-9._-]{0,47}$")|not) then ["E","节点 ID 不规范：\(.id)"]|tab else empty end),
      (if (.port|type)!="number" or .port<1 or .port>65535 then ["E","节点 \(.id) 的端口无效：\(.port)"]|tab else empty end),
      (if (.protocol|IN("vmess-ws-cf","vmess","shadowsocks","hysteria2","trojan","vless","socks","http","mixed","tunnel","wireguard","masque")|not)
        then ["E","节点 \(.id) 使用未知协议：\(.protocol)"]|tab else empty end),
      ([.users[]?.id] | if length != (unique|length) then ["E","节点 \($n.id) 存在重复用户 ID。"]|tab else empty end),
      ( select(.enabled==true) |
        (if .protocol!="vmess-ws-cf" then ["A",.id,(.server_address // "")]|tab else empty end),
        (if ([.users[]? | select(.enabled==true)]|length)==0 and (all(.users[]?; .limits.suspended!=null or .enabled)|not)
          then ["E","启用节点 \(.id) 至少需要一个启用用户。"]|tab else empty end),
        (if (.protocol|IN("hysteria2","masque") or (IN("vless","vmess","trojan","shadowsocks") and ($n|security)=="tls"))
            and (((.xray.inbound.streamSettings.tlsSettings.certificates // [])|length)==0)
          then ["C",.id,(.domain // "")]|tab else empty end),
        (.users[]? | select(.enabled==true) | ["U",$n.id,.id]|tab),
        (if .protocol=="hysteria2" or (.protocol|IN("vless","trojan") and ($n|security)=="reality") then ["S",.id]|tab else empty end),
        (if .protocol|IN("vless","vmess","trojan","shadowsocks") then
          ([$routes[] | select(.node_id==$n.id)] | first) as $r |
          ["V", .id, (if $mux and $r != null then .listen="127.0.0.1" | .port=$r.backend_port else . end | tojson),
           ([.users[]? | select(.enabled==true) | .id] | join(" "))] | join("\t")
         else empty end) ) )
  ' "$state")
}

node_enabled_credentials() {
  local node=$1 node_id user_id path
  local -a paths=()
  node_id=$(jq -r '.id' <<<"$node")
  while IFS= read -r user_id; do
    path=$(state_user_secret_path "$node_id" "$user_id")
    [[ -r "$path" ]] || die "用户密钥文件不存在：$path"
    paths+=("$path")
  done < <(jq -r '.users[] | select(.enabled==true) | .id' <<<"$node")
  (( ${#paths[@]} )) || { printf '[]\n'; return 0; }
  # All user secrets in one jq call, zipped onto the enabled users in order.
  jq -c -n --argjson node "$node" '[$node.users[] | select(.enabled==true)] as $u | [inputs] as $s
    | [range(0; $u|length) as $i | $u[$i] + $s[$i]]' "${paths[@]}"
}

# xray-manager renders every node into one Xray configuration. The
# candidate pipeline is the same as sb-manager: render, check with the
# installed core, install atomically, reconcile, roll back on failure.
render_config_from_state() {
  local state=$1 output=$2
  validate_state_semantics "$state" || return 1
  xray_render_config "$state" "$output"
}

core_validate_config() { xray_validate_config "$SBM_XRAY_BIN" "$1"; }
core_validate_config_with() {
  local bin=$1 config=$2 log=${3:-$SBM_RUN/xray-config-check.log}
  xray_test_config "$bin" "$config" "$log"
}

runtime_render_candidates() {
  local state=$1 config=$2
  if xray_runtime_required "$state" && [[ ! -x "$SBM_XRAY_BIN" ]]; then
    _xray_install_binary >&2 || return 1
  fi
  render_config_from_state "$state" "$config" || return 1
  if [[ -x "$SBM_XRAY_BIN" ]]; then core_validate_config "$config" || return 1; fi
}

apply_candidate_state() (
  local candidate=$1 reason=${2:-change} tmp_config
  website_mux_sync_routes "$candidate" || return 1
  tmp_config=$(mktemp "$SBM_RUN/config.candidate.XXXXXX") || return 1
  trap 'rm -f -- "$tmp_config"' EXIT
  runtime_render_candidates "$candidate" "$tmp_config" || return 1
  state_install_candidate "$candidate" "$tmp_config" "$reason" || return 1
  log_ok '配置已应用。'
)

render_current_config() (
  local tmp backup retain=0 restored=1
  tmp=$(mktemp "$SBM_RUN/config.current.XXXXXX") || return 1
  backup=$(mktemp -d "$SBM_BACKUPS/config-current.XXXXXX") || { rm -f "$tmp"; return 1; }
  trap 'rm -f -- "$tmp"; (( retain )) || rm -rf -- "$backup"' EXIT
  printf '%s\n' "$$" >"$backup/.operation-pid" || return 1
  runtime_render_candidates "$SBM_STATE" "$tmp" || return 1
  [[ ! -f "$SBM_CONFIG" ]] || cp -a "$SBM_CONFIG" "$backup/config" || return 1
  if ! { safe_install_file "$tmp" "$SBM_CONFIG" 0640 && set_group_if_exists "$SBM_SERVICE_USER" "$SBM_CONFIG"; }; then
    if [[ -f "$backup/config" ]]; then cp -a "$backup/config" "$SBM_CONFIG" || restored=0
    else rm -f "$SBM_CONFIG" || restored=0; fi
    if (( ! restored )); then
      retain=1; touch "$backup/.recovery-pending"
      log_error "配置恢复未完成，临时记录最多保留 23 小时：$backup"
    fi
    return 1
  fi
)
