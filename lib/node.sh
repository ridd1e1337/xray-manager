#!/usr/bin/env bash
# shellcheck shell=bash

node_protocol_label() {
  case "$1" in
    vmess) printf 'VMess' ;;
    tunnel) printf 'Tunnel' ;;
    wireguard) printf 'WireGuard' ;;
    masque) printf 'MASQUE' ;;
    vmess-ws-cf) printf 'VMess-WS-CF' ;;
    shadowsocks) printf 'Shadowsocks' ;;
    hysteria2) printf 'Hysteria2' ;;
    trojan) printf 'Trojan' ;;
    vless) printf 'VLESS' ;;
    socks) printf 'SOCKS5' ;;
    http) printf 'HTTP Proxy' ;;
    mixed) printf 'SOCKS5 + HTTP' ;;
    *) printf '%s' "$1" ;;
  esac
}

node_port_in_state() {
  local kind=$1 port=$2 state=${3:-$SBM_STATE}
  jq -e --arg kind "$kind" --argjson port "$port" "$SBM_JQ_NODE_KINDS"'
    ($kind=="tcp" and ((.nginx_stream.enabled==true and .nginx_stream.port==$port) or any(.nginx_stream.routes[]?; .backend_port==$port)))
    or any(.nodes[]? | select(.enabled==true); .port==$port and (kinds | index($kind)) != null)' "$state" >/dev/null
}

node_auto_address() {
  local domain=${1:-} ipv4
  if [[ -n "$domain" ]]; then
    printf '%s\n' "$domain"
    return 0
  fi
  ipv4=$(jq -r '.settings.public_ipv4 // ""' "$SBM_STATE")
  if [[ -z "$ipv4" ]]; then
    _settings_detect_public_ip >/dev/null
    ipv4=$(jq -r '.settings.public_ipv4 // ""' "$SBM_STATE")
  fi
  [[ -n "$ipv4" ]] || die '未探测到公网 IPv4；请使用 --address 手动指定客户端连接地址。'
  printf '%s\n' "$ipv4"
}

node_choose_port() {
  local kind=$1 i port
  for ((i=0; i<200; i++)); do
    port=$((20000 + RANDOM % 35000))
    if ! node_port_in_state "$kind" "$port" && ! host_port_in_use "$kind" "$port"; then printf '%s\n' "$port"; return 0; fi
  done
  die "无法自动选择空闲端口。"
}

host_port_in_use() {
  local kind=$1 port=$2
  command_exists ss || return 1
  if [[ "$kind" == tcp ]]; then
    ss -H -ltn 2>/dev/null | awk '{print $4}' | pipe_has -E "(^|\]|:)$port$|:$port$"
  else
    ss -H -lun 2>/dev/null | awk '{print $5 " " $4}' | pipe_has -E "(^|\]|:)$port$|:$port$"
  fi
}

# Whether the Xray process listens on PORT/KIND (tcp or udp).
xray_port_in_use() {
  local kind=$1 port=$2 flags
  command_exists ss || return 1
  [[ "$kind" == tcp ]] && flags=-ltnp || flags=-lunp
  ss -H "$flags" 2>/dev/null | awk -v p="$port" '
    $0 ~ /"xray"/ { addr = ($1 == "tcp" || $1 == "udp") ? $5 : $4; n = split(addr, a, ":"); if (a[n] == p) found = 1 }
    END { exit !found }'
}

node_runtime_port_in_use() {
  local node=$1 kind=$2 state=${3:-$SBM_STATE}
  if declare -F nginx_stream_effective_node >/dev/null 2>&1; then
    node=$(nginx_stream_effective_node "$state" "$node") || return 1
  fi
  xray_port_in_use "$kind" "$(jq -r '.port' <<<"$node")"
}

node_list_json() {
  local tag=${1:-} region=${2:-}
  jq --arg tag "$tag" --arg region "$region" '[.nodes[]
    | select($tag=="" or (.metadata.tags | index($tag)) != null)
    | select($region=="" or .metadata.region==$region)]' "$SBM_STATE"
}

node_list() {
  local json=${1:-0} tag=${2:-} region=${3:-} id p enabled port endpoint metadata name
  if [[ "$json" == "1" ]]; then node_list_json "$tag" "$region"; return $?; fi
  printf '%-18s %-18s %-8s %-10s %-20s %-14s %s\n' 'ID' '协议' '状态' '端口' '域名/地址' '地区/标签' '名称'
  printf '%-18s %-18s %-8s %-10s %-20s %-14s %s\n' '------------------' '------------------' '--------' '----------' '--------------------' '--------------' '----'
  # One jq pass for the whole table: per-node jq calls dominated latency.
  while IFS=$'\t' read -r id p enabled port endpoint metadata name; do
    printf '%-18s %-18s %-8s %-10s %-20s %-14s %s\n' "$id" "$(node_protocol_label "$p")" "$enabled" "$port" "$endpoint" "$metadata" "$name"
  done < <(node_list_json "$tag" "$region" | jq -r --slurpfile state "$SBM_STATE" '
    ($state[0]) as $s | ($s.nginx_stream.port // 443) as $pub |
    (if ($s.nginx_stream.enabled // false) then ($s.nginx_stream.routes // []) else [] end) as $routes |
    .[] | . as $n | ([$routes[] | select(.node_id==$n.id)] | first) as $r |
    [.id, .protocol, (if .enabled then "启用" else "停用" end),
     (if $r then "\($pub)→\($r.backend_port)" else (.port|tostring) end),
     (.domain // .server_address // "-" | if .=="" then "-" else . end),
     (([.metadata.region] + (.metadata.tags // []) | map(select(. != null and length>0)) | join(",")) | if .=="" then "-" else . end),
     .name] | @tsv')
}

node_show() {
  local id=$1 json=${2:-0} node
  node=$(state_get_node "$id")
  [[ -n "$node" ]] || die "节点不存在：$id"
  if [[ "$json" == 1 ]]; then
    jq . <<<"$node"
    return $?
  fi
  printf '%s\n' "$node" | jq .
  printf '元数据：备注=%s；地区=%s；用途=%s；线路=%s；标签=%s\n' \
    "$(jq -r '.metadata.remark // "-"' <<<"$node")" "$(jq -r '.metadata.region // "-"' <<<"$node")" \
    "$(jq -r '.metadata.purpose // "-"' <<<"$node")" "$(jq -r '.metadata.line // "-"' <<<"$node")" \
    "$(jq -r 'if (.metadata.tags|length)>0 then (.metadata.tags|join(",")) else "-" end' <<<"$node")"
  if declare -F nginx_stream_route_for_node >/dev/null 2>&1; then
    local route
    route=$(nginx_stream_route_for_node "$SBM_STATE" "$id")
    [[ -z "$route" ]] || printf 'TCP/SNI 复用（%s）：%s\n' "$(mux_backend_label)" "$(jq -c . <<<"$route")"
  fi
  printf '用户：%s 个，启用 %s 个\n' "$(jq '.users|length' <<<"$node")" "$(jq '[.users[]|select(.enabled)]|length' <<<"$node")"
}

node_json_argument() {
  local value=${1:?}
  if [[ "$value" == @* ]]; then
    [[ -r "${value#@}" ]] || die "JSON 文件不可读：${value#@}"
    cat -- "${value#@}"
  else
    printf '%s\n' "$value"
  fi
}

node_validate_json_object() {
  local label=$1 value=$2
  jq -e 'type == "object" and ((.by_tag // {}) | type == "object") and all(.by_tag[]?; type == "object")' <<<"$value" >/dev/null 2>&1 || die "$label 必须是 JSON 对象，by_tag 的每项也必须是对象；支持直接传 JSON 或 @FILE。"
}

# 3x-ui fields with first-class flags. Each maps to an Xray inbound fragment
# that is deep-merged into .xray.inbound, the same store --xray-inbound-json uses.
node_native_fragment() {
  local protocol=$1 flag=$2 value=$3 int='^[0-9]{1,4}$'
  case "$flag" in
    --udp-idle-timeout|--quic-congestion|--quic-idle-timeout|--quic-keepalive)
      [[ "$protocol" == hysteria2 ]] || die "$flag 仅用于 Hysteria2 节点。";;
    --allow-transparent) [[ "$protocol" == http ]] || die '--allow-transparent 仅用于 HTTP 节点。';;
    --port-map) [[ "$protocol" == tunnel ]] || die '--port-map 仅用于 Tunnel 节点。';;
  esac
  case "$flag" in
    --udp-idle-timeout)
      [[ "$value" =~ $int ]] && (( value >= 2 && value <= 600 )) || die 'UDP 空闲超时须为 2-600 秒。'
      jq -cn --argjson v "$value" '{streamSettings:{hysteriaSettings:{version:2,udpIdleTimeout:$v}}}';;
    --quic-congestion)
      case "$value" in reno|bbr|brutal|force-brutal) ;; *) die '拥塞控制须为 reno|bbr|brutal|force-brutal。';; esac
      jq -cn --arg v "$value" '{streamSettings:{finalmask:{quicParams:{congestion:$v}}}}';;
    --quic-idle-timeout|--quic-keepalive)
      [[ "$value" =~ $int ]] && (( value >= 1 && value <= 600 )) || die "$flag 须为 1-600 秒。"
      jq -cn --argjson v "$value" --arg k "$([[ "$flag" == --quic-idle-timeout ]] && echo maxIdleTimeout || echo keepAlivePeriod)" \
        '{streamSettings:{finalmask:{quicParams:{($k):$v}}}}';;
    --allow-transparent)
      [[ "$value" == true || "$value" == false ]] || die '--allow-transparent 须为 true 或 false。'
      jq -cn --argjson v "$value" '{settings:{allowTransparent:$v}}';;
    --port-map)
      # LISTEN_PORT=HOST:PORT[,...]; "none" clears the map.
      if [[ "$value" == none ]]; then printf '{"settings":{"portMap":{}}}\n'; return $?; fi
      [[ "$value" =~ ^[0-9]{1,5}=[^,=[:space:]]+:[0-9]{1,5}(,[0-9]{1,5}=[^,=[:space:]]+:[0-9]{1,5})*$ ]] || die '--port-map 格式：端口=主机:端口[,…]，或 none。'
      jq -cn --arg v "$value" '{settings:{portMap:($v|split(",")|map(split("=")|{key:.[0],value:.[1]})|from_entries)}}';;
    *) return 1;;
  esac
}

_node_add() {
  local type=$1; shift
  local id='' name='' port='' domain='' address='' address_supplied=0 address_source=auto path='' method='2022-blake3-aes-256-gcm' network='tcp' mux=true enabled=true obfs='' masquerade='' security='tls' flow='auto' handshake_server='' handshake_port=443 outbound_json='{}' xray_inbound_json='{}' xray_outbound_json='{}'
  local remark='' region='' purpose='' line='' tags='' proxy_listen='127.0.0.1' proxy_listen_supplied=0 vless_preview='' vless_network='' vless_listen='::'
  local -a vless_options=() native_flags=()
  local security_supplied=0 tunnel_target='' follow_redirect=false wg_subnet='' wg_mtu=1420
  while (($#)); do
    case "$1" in
      --listen) proxy_listen=${2:?}; proxy_listen_supplied=1; shift 2;;
      --id) id=${2:?}; shift 2;; --name) name=${2:?}; shift 2;; --port) port=${2:?}; shift 2;;
      --domain) domain=${2:?}; shift 2;; --address) address=${2:?}; address_supplied=1; address_source=manual; shift 2;; --path) path=${2:?}; shift 2;;
      --method) method=${2:?}; shift 2;; --network) network=${2:?}; shift 2;; --no-mux) mux=false; shift;;
      --obfs) obfs=${2:?}; shift 2;; --masquerade) masquerade=${2:?}; shift 2;; --disabled) enabled=false; shift;;
      --obfs-host|--obfs-min-packet-size|--obfs-max-packet-size|--disable-chrome-parrot|--enable-chrome-parrot|--bbr-profile|--brutal-debug|--no-brutal-debug|--congestion-control|--strict-mode|--wildcard-sni|--quic|--snell-version|--snell-mode|--realm-id|--realm-ip-version|--realm-port-mapping|--no-realm-port-mapping|--clear-realm|--sing-box-inbound-json|--inbound-json) usage_die "$1 是 sing-box 专属参数，xray-manager 不支持；请使用 sb-manager（Xray 入站扩展用 --xray-inbound-json）。";;
      --security) security=${2:?}; security_supplied=1; shift 2;;
      --target) tunnel_target=${2:?}; shift 2;; --follow-redirect) follow_redirect=true; shift;;
      --subnet) wg_subnet=${2:?}; shift 2;; --mtu) wg_mtu=${2:?}; shift 2;;
      --udp-idle-timeout|--quic-congestion|--quic-idle-timeout|--quic-keepalive|--allow-transparent|--port-map)
        (($# >= 2)) || usage_die "缺少参数值：$1"; native_flags+=("$1" "$2"); shift 2;;
      --flow) (($# >= 2)) || usage_die '缺少 flow 值；可显式传空字符串。'; flow=$2; shift 2;;
      --transport|--host|--service-name|--xhttp-mode|--tls-server-name|--fingerprint|--alpn|--allow-insecure|--pinned-cert-sha256|--verify-name|--packet-encoding|--vless-encryption|--vless-decryption|--transport-json|--tls-json|--sockopt-json|--fallbacks|--fallback-dest|--sniffing|--sniff-dest|--tcp-fast-open|--accept-proxy-protocol)
        (($# >= 2)) || usage_die "缺少参数值：$1"
        vless_options+=("$1" "$2"); shift 2;;
      --handshake-server) handshake_server=${2:?}; shift 2;; --handshake-port) handshake_port=${2:?}; shift 2;;
      --sing-box-outbound-json|--outbound-json) outbound_json=$(node_json_argument "${2:?}"); node_validate_json_object 'sing-box outbound JSON' "$outbound_json"; shift 2;;
      --xray-inbound-json) xray_inbound_json=$(node_json_argument "${2:?}"); node_validate_json_object 'Xray inbound JSON' "$xray_inbound_json"; shift 2;;
      --xray-outbound-json) xray_outbound_json=$(node_json_argument "${2:?}"); node_validate_json_object 'Xray outbound JSON' "$xray_outbound_json"; shift 2;;
      --remark) [[ $# -ge 2 ]] || die '缺少备注'; remark=$2; shift 2;; --region) [[ $# -ge 2 ]] || die '缺少地区'; region=$2; shift 2;; --purpose) [[ $# -ge 2 ]] || die '缺少用途'; purpose=$2; shift 2;; --line) [[ $# -ge 2 ]] || die '缺少线路'; line=$2; shift 2;; --tags) [[ $# -ge 2 ]] || die '缺少标签'; tags=$2; shift 2;;
      *) die "未知参数：$1";;
    esac
  done
  domain=${domain%.}; domain=${domain,,}
  if [[ "$SBM_SKIP_INIT" != 1 ]] && ! command_exists ss && declare -F dependency_require_feature >/dev/null 2>&1; then
    dependency_require_feature probe || die '节点端口探测需要 iproute2/ss；请运行 xm deps install probe。'
  fi
  if [[ "$proxy_listen_supplied" == 1 ]]; then
    case "$type" in socks|socks5|http|mixed|vless) ;; *) usage_die '--listen 目前仅用于 VLESS 与 socks/http/mixed 代理入口。';; esac
  fi
  local protocol base transport secret node_secret='' node candidate user_secret_path default_address created_at reality_secret=''
  if [[ "$type" == vless ]]; then
    [[ -z "$path" ]] || vless_options+=(--path "$path")
    [[ "$proxy_listen_supplied" != 1 ]] || vless_options+=(--listen "$proxy_listen")
    vless_preview=$(jq -n --arg domain "$domain" --arg security "$security" --arg flow "$flow" \
      --arg hs "$handshake_server" --argjson hp "$handshake_port" --argjson inbound "$xray_inbound_json" --argjson outbound "$xray_outbound_json" \
      '{protocol:"vless",domain:$domain,security:$security,flow:$flow,handshake_server:$hs,handshake_port:$hp,xray:{inbound:$inbound,outbound:$outbound}}') || return 1
    vless_preview=$(vless_config_apply "$vless_preview" "${vless_options[@]}") || return 1
    security=$(jq -r '.security' <<<"$vless_preview"); flow=$(jq -r '.flow // ""' <<<"$vless_preview")
    vless_network=$(vless_node_network "$vless_preview") || return 1
    xray_inbound_json=$(jq -c '.xray.inbound // {}' <<<"$vless_preview"); xray_outbound_json=$(jq -c '.xray.outbound // {}' <<<"$vless_preview")
    vless_listen=$(jq -r '.listen // "::"' <<<"$vless_preview")
  elif (( ${#vless_options[@]} > 0 )) && [[ ! "$type" =~ ^(vmess|trojan|ss|shadowsocks)$ ]]; then
    usage_die '传输与安全层参数用于 VLESS、VMess、Trojan、Shadowsocks。'
  fi
  case "$type" in
    anytls|tuic|naive|shadowtls|snell) usage_die "xray-manager 只使用 Xray-core，Xray 不支持 $type；请使用 sb-manager。";;
  esac
  default_address=$(jq -r '.settings.default_server_address // ""' "$SBM_STATE")
  case "$type" in
    vmess)
      # Generic VMess (3x-ui parity): any Xray transport, security none/tls.
      protocol=vmess; base=vmess; transport=tcp; port=${port:-$(node_choose_port tcp)}
      (( security_supplied )) || security=none
      [[ "$security" == none || "$security" == tls ]] || die 'VMess 安全层只能是 none 或 tls。'
      if [[ "$security" == tls ]]; then validate_domain "$domain" || die 'VMess TLS 需要 --domain。'; fi
      name=${name:-VMess}; address=${address:-${default_address:-${domain:-}}}
      secret=$(jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}')
      ;;
    vmess-ws-cf)
      protocol=vmess-ws-cf; base=vmess-cf; transport=tcp
      [[ -n "$port" ]] || port=$(node_choose_port tcp)
      [[ -n "$path" ]] || path="/$(random_hex 16)-vm"
      path=$(normalize_ws_path "$path")
      [[ -n "$name" ]] || name='VMess WS Cloudflare'
      [[ -n "$address" ]] || address=$domain
      secret=$(jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}')
      ;;
    ss|shadowsocks)
      protocol=shadowsocks; base=ss; transport=tcp
      [[ -n "$port" ]] || port=8388
      [[ -n "$name" ]] || name='Shadowsocks'
      [[ -n "$address" ]] || address=$default_address
      case "$method" in 2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305|aes-128-gcm|aes-256-gcm|chacha20-poly1305|chacha20-ietf-poly1305|xchacha20-poly1305|xchacha20-ietf-poly1305) ;; *) die "不支持的 Shadowsocks 方法：$method";; esac
      [[ "$network" == tcp || "$network" == udp ]] || die 'Shadowsocks network 必须是 tcp（TCP+UDP）或 udp。'
      mux=false  # Xray does not implement sing-box multiplex
      secret=$(jq -n --arg password "$(ss2022_key "$method")" '{password:$password}')
      ;;
    hy2|hysteria2)
      protocol=hysteria2; base=hy2; transport=udp
      [[ -n "$port" ]] || port=443
      [[ -n "$domain" ]] || die "Hysteria2 必须指定 --domain。"
      validate_domain "$domain" || die "无效域名：$domain"
      [[ -n "$name" ]] || name='Hysteria2'
      [[ -n "$address" ]] || address=${default_address:-$domain}
      # Xray's Hysteria inbound: TLS (h3), optional Salamander obfs and masquerade.
      [[ -z "$obfs" || "$obfs" == salamander ]] || die 'Xray Hysteria2 混淆只支持 salamander（Gecko 为 sing-box 专属）。'
      secret=$(jq -n --arg password "$(random_password 24)" --arg obfs_password "$([[ -n "$obfs" ]] && random_password 18 || true)" '{password:$password,obfs_password:$obfs_password}')
      ;;
    trojan)
      protocol=trojan; base=trojan; transport=tcp; port=${port:-443}; [[ -n "$domain" || "$security" != reality ]] || domain=$SBM_RECOMMENDED_REALITY_SNI; [[ -n "$domain" ]] || die 'Trojan TLS 必须指定 --domain。'; validate_domain "$domain" || die "无效域名：$domain"; name=${name:-Trojan}; address=${address:-${default_address:-$domain}}; secret=$(jq -n --arg password "$(random_password 24)" '{password:$password}')
      ;;
    vless)
      protocol=vless; base=vless
      transport=$(vless_node_listener_kinds "$vless_preview") || return 1
      port=${port:-443}
      case "$security" in none|tls|reality) ;; *) die 'VLESS security 必须是 none、tls 或 reality。';; esac
      if [[ "$security" == reality && -z "$domain" ]]; then
        domain=$(jq -r '.xray.inbound.streamSettings.realitySettings.serverNames[0] // "www.apple.com"' <<<"$vless_preview")
      fi
      [[ "$security" == none ]] || { validate_domain "$domain" || die 'VLESS TLS/Reality 需要有效域名。'; }
      name=${name:-VLESS}; address=${address:-${default_address:-$domain}}
      case "$flow" in ''|xtls-rprx-vision) ;; *) die 'VLESS flow 仅支持 xtls-rprx-vision 或空值。';; esac
      if [[ "$security" == reality ]]; then
        if [[ -z "$handshake_server" ]] && jq -e '.xray.inbound.streamSettings.realitySettings.target // .xray.inbound.streamSettings.realitySettings.dest' <<<"$vless_preview" >/dev/null; then handshake_server=$domain; fi
        [[ -n "$handshake_server" ]] || handshake_server=$domain  # REALITY target defaults to the SNI site
        validate_domain "$handshake_server" || validate_ipv4 "$handshake_server" || validate_ipv6 "$handshake_server" || die 'Reality 握手目标必须是域名或 IP。'
        validate_port "$handshake_port" || die '无效 Reality 握手端口。'
      fi
      [[ -x "$SBM_XRAY_BIN" ]] || _xray_install >&2 || return 1
      secret=$(jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}') || return 1
      [[ "$security" != reality ]] || reality_secret=$(protocol_vless_generate_reality_secret) || return 1
      ;;
    socks|socks5|http|mixed)
      protocol=$type; [[ "$protocol" != socks5 ]] || protocol=socks
      base=$protocol; transport=tcp; port=${port:-1080}; name=${name:-$protocol}
      case "$proxy_listen" in 127.0.0.1|::1|0.0.0.0|::) ;; *) die '代理监听仅支持 127.0.0.1、::1、0.0.0.0、::。';; esac
      secret=$(jq -n --arg username "$(random_hex 12)" --arg password "$(random_password 24)" '{username:$username,password:$password}')
      if [[ "$address_supplied" == 0 && ( "$proxy_listen" == 127.0.0.1 || "$proxy_listen" == ::1 ) ]]; then address=$proxy_listen; address_supplied=1; address_source=manual; fi
      ;;
    masque)
      # Xray MASQUE (connect-ip over HTTP/3); TLS certificate required.
      protocol=masque; base=masque; transport=udp; port=${port:-443}; name=${name:-MASQUE}
      validate_domain "$domain" || die 'MASQUE 需要 --domain（TLS 证书域名）。'
      address=${address:-${default_address:-$domain}}
      [[ -n "$wg_subnet" ]] || wg_subnet="10.14.$((RANDOM % 250 + 1)).0/24"
      [[ "$wg_subnet" =~ ^10\.[0-9]{1,3}\.[0-9]{1,3}\.0/24$ ]] || die 'MASQUE 子网须为 10.x.y.0/24。'
      (( wg_mtu >= 1280 )) || die 'MASQUE MTU 至少 1280。'
      [[ "$wg_mtu" != 1420 ]] || wg_mtu=1280
      secret=$(jq -n --arg pass "$(random_password 24)" '{password:$pass}')
      ;;
    wireguard|wg)
      protocol=wireguard; base=wireguard; transport=udp; port=${port:-$(node_choose_port udp)}; name=${name:-WireGuard}
      [[ -n "$wg_subnet" ]] || wg_subnet="10.66.$((RANDOM % 250 + 1)).0/24"
      [[ "$wg_subnet" =~ ^10\.([0-9]{1,3})\.([0-9]{1,3})\.0/24$ ]] && (( BASH_REMATCH[1] <= 255 && BASH_REMATCH[2] <= 255 )) || die 'WireGuard 子网须为 10.x.y.0/24。'
      [[ "$wg_mtu" =~ ^[0-9]+$ ]] && (( wg_mtu >= 1280 && wg_mtu <= 1500 )) || die 'WireGuard MTU 须为 1280-1500。'
      node_secret=$(wireguard_keypair) || return 1
      secret=$(jq --arg address "${wg_subnet%.0/24}.2" '. + {address:$address}' <<<"$(wireguard_keypair)") || return 1
      ;;
    tunnel|dokodemo|dokodemo-door)
      # Xray tunnel (dokodemo-door): forward a local port to one target.
      protocol=tunnel; base=tunnel; port=${port:?端口转发必须指定 --port。}; name=${name:-Tunnel}
      [[ "$tunnel_target" =~ ^(.+):([0-9]{1,5})$ ]] || die '请用 --target HOST:PORT 指定转发目标。'
      validate_address "${BASH_REMATCH[1]#[}" >/dev/null 2>&1 || validate_address "${BASH_REMATCH[1]}" || die "无效转发目标：$tunnel_target"
      validate_port "${BASH_REMATCH[2]}" || die "无效转发端口：$tunnel_target"
      case "$network" in tcp|udp|tcp,udp) ;; *) die 'Tunnel network 必须是 tcp、udp 或 tcp,udp。';; esac
      transport=${network%%,*}; address=${address:-127.0.0.1}; address_supplied=1
      secret='{}'
      ;;
    *) die "不支持的协议：$type";;
  esac
  if [[ "$address_supplied" == 0 ]]; then
    case "$protocol" in
      vless|trojan)
        if [[ "$security" == reality || ( "$protocol" == vless && "$security" != tls ) ]]; then address=$(node_auto_address ''); else address=$(node_auto_address "$domain"); fi
        ;;
      *) address=$(node_auto_address "$domain");;
    esac
    address_source=auto
  fi
  if [[ "$protocol" == hysteria2 ]]; then
    node_secret=$(jq -n --arg obfs_password "$(jq -r '.obfs_password // ""' <<<"$secret")" '{obfs_password:$obfs_password}')
    secret=$(jq '{password}' <<<"$secret")
  fi
  if [[ "$protocol" == trojan && "$security_supplied" == 1 && "$security" == reality ]]; then
    [[ -n "$handshake_server" ]] || handshake_server=$domain
    reality_secret=$(protocol_vless_generate_reality_secret) || return 1
  fi
  if [[ ( "$protocol" == vless || "$protocol" == trojan ) && "$security" == reality && -n "$reality_secret" ]]; then
    node_secret=$(jq -n --arg hs "$handshake_server" --argjson hp "$handshake_port" --argjson reality "$reality_secret" '$reality + {handshake_server:$hs,handshake_port:$hp}')
  fi
  if website_mux_managed && [[ "$transport" == tcp && "$port" == 443 ]]; then
    case "$protocol" in trojan|vless) port=$(node_choose_port tcp) || return 1;; esac
  fi
  validate_port "$port" || die "无效端口：$port"
  [[ -n "$id" ]] || id=$(state_unique_id "$base")
  validate_node_id "$id" || die "节点 ID 只能包含小写字母、数字、点、下划线和连字符。"
  state_node_exists "$id" && die "节点已存在：$id"
  if [[ "$enabled" == true && -n "$transport" ]] && node_port_in_state "$transport" "$port"; then
    die "已启用节点或复用入口占用 ${port}/${transport^^}；请换端口。"
  fi
  if [[ "$enabled" == true && -n "$transport" ]] && host_port_in_use "$transport" "$port"; then
    die "系统已有程序监听 ${port}/${transport^^}；请换端口或先停用冲突服务。"
  fi
  created_at=$(now_iso)

  case "$protocol" in
    vmess)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg domain "$domain" --arg address "$address" --arg security "$security" --arg now "$created_at" --argjson enabled "$enabled" \
        '{id:$id,name:$name,protocol:"vmess",enabled:$enabled,listen:"::",port:$port,domain:$domain,server_address:$address,security:$security,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    vmess-ws-cf)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg path "$path" --arg domain "$domain" --arg address "$address" --arg now "$created_at" --argjson enabled "$enabled" \
        '{id:$id,name:$name,protocol:"vmess-ws-cf",enabled:$enabled,listen:"127.0.0.1",port:$port,ws_path:$path,domain:$domain,client_address:$address,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    shadowsocks)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg network "$network" --arg method "$method" --arg address "$address" --arg address_source "$address_source" --arg now "$created_at" --argjson mux "$mux" --argjson enabled "$enabled" \
        '{id:$id,name:$name,protocol:"shadowsocks",enabled:$enabled,listen:"::",port:$port,network:$network,method:$method,multiplex:$mux,server_address:$address,server_address_source:$address_source,credential_mode:"legacy",created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    hysteria2)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg domain "$domain" --arg address "$address" --arg obfs "$obfs" \
        --arg masquerade "$masquerade" --arg now "$created_at" --argjson enabled "$enabled" \
        '{id:$id,name:$name,protocol:"hysteria2",enabled:$enabled,listen:"::",port:$port,domain:$domain,server_address:$address,obfs:(if $obfs=="" then {} else {type:$obfs} end),masquerade:$masquerade,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    trojan)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg domain "$domain" --arg address "$address" --arg now "$created_at" --argjson enabled "$enabled" '{id:$id,name:$name,protocol:"trojan",enabled:$enabled,listen:"::",port:$port,domain:$domain,server_address:$address,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    vless)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg domain "$domain" --arg address "$address" --arg security "$security" --arg flow "$flow" --arg hs "$handshake_server" --argjson hp "$handshake_port" --arg now "$created_at" --argjson enabled "$enabled" --arg listen "$vless_listen" '{id:$id,name:$name,protocol:"vless",enabled:$enabled,listen:$listen,port:$port,domain:$domain,server_address:$address,security:$security,flow:(if $flow=="" then null else $flow end),handshake_server:(if $hs=="" then null else $hs end),handshake_port:$hp,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    masque)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg domain "$domain" --arg address "$address" --arg subnet "$wg_subnet" --argjson mtu "$wg_mtu" --arg now "$created_at" --argjson enabled "$enabled" \
        '{id:$id,name:$name,protocol:"masque",enabled:$enabled,listen:"::",port:$port,domain:$domain,server_address:$address,subnet:$subnet,mtu:$mtu,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    wireguard)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg address "$address" --arg subnet "$wg_subnet" --argjson mtu "$wg_mtu" --arg now "$created_at" --argjson enabled "$enabled" \
        '{id:$id,name:$name,protocol:"wireguard",enabled:$enabled,listen:"::",port:$port,server_address:$address,subnet:$subnet,mtu:$mtu,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    tunnel)
      node=$(jq -n --arg id "$id" --arg name "$name" --argjson port "$port" --arg target "$tunnel_target" --arg network "$network" --argjson follow "$follow_redirect" --arg address "$address" --arg listen "$([[ $proxy_listen_supplied == 1 ]] && printf %s "$proxy_listen" || printf '::')" --arg now "$created_at" --argjson enabled "$enabled" \
        '($target|capture("^\\[?(?<h>.+?)\\]?:(?<p>[0-9]+)$")) as $t |
         {id:$id,name:$name,protocol:"tunnel",enabled:$enabled,listen:$listen,port:$port,server_address:$address,target_address:$t.h,target_port:($t.p|tonumber),network:$network,follow_redirect:$follow,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
    socks|http|mixed)
      node=$(jq -n --arg id "$id" --arg name "$name" --arg protocol "$protocol" --arg listen "$proxy_listen" --argjson port "$port" --arg address "$address" --arg now "$created_at" --argjson enabled "$enabled" '{id:$id,name:$name,protocol:$protocol,enabled:$enabled,listen:$listen,port:$port,server_address:$address,created_at:$now,users:[{id:"default",name:$name,enabled:true,created_at:$now}]}')
      ;;
  esac
  node=$(jq --arg remark "$remark" --arg region "$region" --arg purpose "$purpose" --arg line "$line" --arg tags "$tags" '
    .traffic={configured:false,enabled:false,quota_bytes:null,quota_mode:"total",reset_day:1,upload_rate_bps:null,download_rate_bps:null}
    | .metadata={remark:$remark,region:$region,purpose:$purpose,line:$line,tags:($tags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length>0)) | unique)}
  ' <<<"$node")
  node=$(jq --argjson outbound "$outbound_json" '.singbox={outbound:$outbound}' <<<"$node")
  local i frag
  for ((i = 0; i < ${#native_flags[@]}; i += 2)); do
    frag=$(node_native_fragment "$protocol" "${native_flags[i]}" "${native_flags[i+1]}") || return 1
    xray_inbound_json=$(jq -c --argjson f "$frag" '. * $f' <<<"$xray_inbound_json")
  done
  node=$(jq --argjson inbound "$xray_inbound_json" --argjson outbound "$xray_outbound_json" ".xray={inbound:\$inbound,outbound:\$outbound}" <<<"$node")
  if [[ "$protocol" == vless ]]; then
    node=$(jq --argjson xray "$(jq -c '.xray' <<<"$vless_preview")" '.xray=$xray' <<<"$node") || return 1
  elif [[ "$protocol" =~ ^(vmess|trojan|shadowsocks)$ ]]; then
    # Transport/security options share the VLESS profile engine.
    local -a stream_args=()
    (( ! security_supplied )) || stream_args+=(--security "$security")
    if [[ "$security" == reality ]]; then
      node=$(jq --arg hs "$handshake_server" --argjson hp "$handshake_port" '.handshake_server=$hs | .handshake_port=$hp' <<<"$node") || return 1
    fi
    [[ -z "$path" || "$protocol" == vmess-ws-cf ]] || stream_args+=(--path "$path")
    [[ -z "$domain" || "$protocol" == trojan ]] || stream_args+=(--domain "$domain")
    stream_args+=("${vless_options[@]}")
    if (( ${#stream_args[@]} > 0 )); then node=$(vless_config_apply "$node" "${stream_args[@]}") || return 1; fi
    if [[ "$protocol" == shadowsocks || "$protocol" == vmess ]] && [[ $(jq -r '.security // "none"' <<<"$node") != none ]]; then
      validate_domain "$(jq -r '.domain // ""' <<<"$node")" || die 'TLS 需要有效的 --domain。'
    fi
  fi
  if [[ "$protocol" != vmess-ws-cf ]]; then
    node=$(jq --arg source "$address_source" '.server_address_source=$source' <<<"$node")
  fi
  if [[ "$enabled" == true ]]; then
    case "$protocol" in
      hysteria2|masque) _cert_prepare_node_domain "$domain" || return 1;;
      vless|vmess|trojan|shadowsocks)
        if [[ $(xray_node_security "$node") == tls ]] && ! jq -e '(.xray.inbound.streamSettings.tlsSettings.certificates // [])|length>0' <<<"$node" >/dev/null; then
          _cert_prepare_node_domain "$(jq -r '.domain' <<<"$node")" || return 1
        fi;;
    esac
  fi
  user_secret_path=$(state_user_secret_path "$id" default)
  state_write_user_secret "$id" default "$secret" || return 1
  [[ -z "$node_secret" ]] || state_write_secret "$id" "$node_secret" || return 1
  candidate=$(state_candidate)
  jq --argjson node "$node" '.nodes += [$node]' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" "add-$id"; then rm -f "$candidate" "$user_secret_path"; return 1; fi
  rm -f "$candidate"
  log_ok "已添加节点：$id ($(node_protocol_label "$protocol"))"
  [[ "$enabled" == true ]] || log_warn "节点当前为停用状态。"
}
node_add() {
  [[ ${SBM_DRY_RUN:-0} != 1 ]] || usage_die '添加节点不支持 --dry-run；请退出预览模式后再操作。'
  with_state_transaction node-add _node_add "$@"
}

_node_set_enabled() {
  local id=$1 value=$2 candidate
  state_node_exists "$id" || die "节点不存在：$id"
  if [[ "$value" == true && "$SBM_SKIP_INIT" != 1 ]] && ! command_exists ss && declare -F dependency_require_feature >/dev/null 2>&1; then
    dependency_require_feature probe || die '节点端口探测需要 iproute2/ss；请运行 xm deps install probe。'
  fi
  if [[ "$value" == true ]] && jq -e --arg id "$id" --argjson now "$(date +%s)" '.nodes[]|select(.id==$id)|.expiry.at!=null and .expiry.at<=$now' "$SBM_STATE" >/dev/null; then die '节点已到期，请先续期或清除到期策略。'; fi
  candidate=$(state_candidate)
  jq --arg id "$id" --argjson value "$value" '(.nodes[] | select(.id==$id)) |= (.enabled=$value | if $value==false and .expiry.suspended==true then .expiry.resume_enabled=false else . end)' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" "${value}-$(printf '%s' "$id")"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}
node_enable() { with_state_transaction node-enable _node_set_enabled "$1" true; }
node_disable() { with_state_transaction node-disable _node_set_enabled "$1" false; }

_node_delete() {
  local id=$1 candidate
  state_node_exists "$id" || die "节点不存在：$id"
  candidate=$(state_candidate)
  jq --arg id "$id" '.nodes |= map(select(.id!=$id))
    | .nginx_stream.routes |= map(select(.node_id!=$id))
    | if .nginx_stream.enabled == true and (.nginx_stream.routes|length)==0 then .nginx_stream.enabled=false else . end
    | if .tunnel.node_id==$id then .tunnel={mode:"none",node_id:null,domain:null,client_address:null,protocol:"http2"} else . end' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" "delete-$id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate" "$(state_secret_path "$id")"
  rm -rf -- "$(state_user_secret_dir "$id")"
  rm -rf -- "$SBM_EXPORTS/nodes/$id"
  log_ok "已删除节点：$id"
}
node_delete() { with_state_transaction node-delete _node_delete "$1"; }

_node_rotate() {
  local id=$1 user_id=${2:-default} node protocol path old new candidate backup node_secret
  node=$(state_get_node "$id"); [[ -n "$node" ]] || die "节点不存在：$id"
  state_user_exists "$id" "$user_id" || die "用户不存在：$id/$user_id"
  protocol=$(jq -r '.protocol' <<<"$node"); path=$(state_user_secret_path "$id" "$user_id"); backup=$(mktemp "$SBM_RUN/secret.backup.XXXXXX"); cp -a "$path" "$backup"
  case "$protocol" in
    vmess|vmess-ws-cf) new=$(jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}') ;;
    shadowsocks) new=$(jq -n --arg password "$(ss2022_key "$(jq -r '.method' <<<"$node")")" '{password:$password}') ;;
    hysteria2)
      new=$(jq -n --arg password "$(random_password 24)" '{password:$password}') ;;
    trojan) new=$(jq -n --arg password "$(random_password 24)" '{password:$password}') ;;
    vless) new=$(jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}') ;;
    socks|http|mixed) new=$(jq -n --arg username "$(random_hex 12)" --arg password "$(random_password 24)" '{username:$username,password:$password}') ;;
  esac
  state_write_user_secret "$id" "$user_id" "$new" || return 1
  candidate=$(state_candidate); cp "$SBM_STATE" "$candidate"
  if ! apply_candidate_state "$candidate" "rotate-$id"; then cp -a "$backup" "$path"; rm -f "$candidate" "$backup"; return 1; fi
  rm -f "$candidate" "$backup"
  log_ok "已轮换用户凭据：$id/$user_id。旧分享链接立即失效。"
}
node_rotate() { with_state_transaction node-rotate _node_rotate "$@"; }

_node_set() {
  local id=$1; shift
  local candidate tmp key value node protocol
  node=$(state_get_node "$id"); [[ -n "$node" ]] || die "节点不存在：$id"
  candidate=$(state_candidate); cp "$SBM_STATE" "$candidate"
  while (($#)); do
    key=$1
    case "$key" in
      --obfs-host|--obfs-min-packet-size|--obfs-max-packet-size|--disable-chrome-parrot|--enable-chrome-parrot|--bbr-profile|--brutal-debug|--no-brutal-debug|--congestion-control|--strict-mode|--wildcard-sni|--snell-version|--snell-mode|--realm-id|--realm-ip-version|--realm-port-mapping|--no-realm-port-mapping|--clear-realm|--sing-box-inbound-json|--inbound-json)
        rm -f "$candidate"; die "$key 是 sing-box 专属参数，xray-manager 不支持；请使用 sb-manager（Xray 入站扩展用 --xray-inbound-json）。";;
      --sing-box-outbound-json|--outbound-json) value=$(node_json_argument "${2:?}"); node_validate_json_object 'sing-box outbound JSON' "$value"; shift 2;;
      --xray-inbound-json) value=$(node_json_argument "${2:?}"); node_validate_json_object 'Xray inbound JSON' "$value"; shift 2;;
      --xray-outbound-json) value=$(node_json_argument "${2:?}"); node_validate_json_object 'Xray outbound JSON' "$value"; shift 2;;
      *) value=${2-}; shift 2;;
    esac
    case "$key" in
      --name) tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.name)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --port) validate_port "$value" || die "无效端口：$value"; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --argjson v "$value" '(.nodes[]|select(.id==$id)|.port)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --address) validate_address "$value" || die "无效地址"; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)) |= if .protocol=="vmess-ws-cf" then .client_address=$v else .server_address=$v | .server_address_source="manual" end' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --domain) validate_domain "$value" || die "无效域名：$value"; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.domain)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --path) value=$(normalize_ws_path "$value"); tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.ws_path)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --method)
        case "$value" in 2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305|aes-128-gcm|aes-256-gcm|chacha20-poly1305|chacha20-ietf-poly1305|xchacha20-poly1305|xchacha20-ietf-poly1305) ;; *) rm -f "$candidate"; die "无效 Shadowsocks 方法：$value";; esac
        # 2022 keys have fixed lengths; switching family or key size needs new credentials.
        [[ "$(jq -r '.method' <<<"$node")" == "$value" || ( "$value" != 2022-* && "$(jq -r '.method' <<<"$node")" != 2022-* ) ]] || { rm -f "$candidate"; die '更换 2022 方法会改变密钥长度；请新建节点。'; }
        tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.method)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --network) [[ "$value" == tcp || "$value" == udp ]] || { rm -f "$candidate"; die "network 必须是 tcp 或 udp"; }; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.network)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --obfs) [[ "$value" == salamander || "$value" == none || -z "$value" ]] || { rm -f "$candidate"; die "Xray Hysteria2 混淆只支持 salamander 或 none。"; }
        if [[ "$value" == salamander && -z "$(state_get_secret "$id" 2>/dev/null | jq -r '.obfs_password // ""')" ]]; then
          state_write_secret "$id" "$( (state_get_secret "$id" 2>/dev/null || echo '{}') | jq -c --arg p "$(random_password 18)" '(. // {}) + {obfs_password:$p}')" || { rm -f "$candidate"; return 1; }
        fi
        tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)) |= if .protocol=="hysteria2" then .obfs=(if ($v=="" or $v=="none") then {} else {type:$v} end) else . end' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --masquerade) [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die 'masquerade 不能包含控制字符'; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.masquerade)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --security) [[ "$value" == "$(jq -r --arg id "$id" '.nodes[]|select(.id==$id)|.security' "$candidate")" ]] || { rm -f "$candidate"; die 'VLESS security 创建后不可直接切换；请新建目标类型节点。'; };;
      --flow) [[ -z "$value" || "$value" == xtls-rprx-vision ]] || { rm -f "$candidate"; die 'VLESS flow 仅支持 xtls-rprx-vision 或空值。'; }; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.flow)=(if $v=="" then null else $v end)' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --handshake-server) validate_domain "$value" || { [[ $(jq -r '.protocol' <<<"$node") == vless ]] && { validate_ipv4 "$value" || validate_ipv6 "$value"; }; } || { rm -f "$candidate"; die "无效握手目标：$value"; }; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.handshake_server)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --handshake-port) validate_port "$value" || die "无效握手端口"; tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --argjson v "$value" '(.nodes[]|select(.id==$id)|.handshake_port)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --sing-box-outbound-json|--outbound-json) tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --argjson v "$value" '(.nodes[]|select(.id==$id)|.singbox.outbound)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --xray-inbound-json) tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --argjson v "$value" '(.nodes[]|select(.id==$id)|.xray.inbound)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --udp-idle-timeout|--quic-congestion|--quic-idle-timeout|--quic-keepalive|--allow-transparent|--port-map)
        value=$(node_native_fragment "$(jq -r '.protocol' <<<"$node")" "$key" "$value") || { rm -f "$candidate"; return 1; }
        tmp=$(mktemp "$SBM_RUN/edit.XXXXXX")
        # portMap is replaced, not merged, so "none" and new maps drop old entries.
        jq --arg id "$id" --argjson v "$value" '(.nodes[]|select(.id==$id)|.xray.inbound) |=
          ((. // {}) | if $v.settings.portMap != null then .settings.portMap = {} else . end | . * $v)' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --xray-outbound-json) tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --argjson v "$value" '(.nodes[]|select(.id==$id)|.xray.outbound)=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate";;
      --remark|--region|--purpose|--line)
        local field=${key#--}
        [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] || die "节点元数据不能包含控制字符。"
        tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg field "$field" --arg v "$value" '(.nodes[]|select(.id==$id)|.metadata[$field])=$v' "$candidate" >"$tmp"; mv "$tmp" "$candidate"
        ;;
      --tags)
        tmp=$(mktemp "$SBM_RUN/edit.XXXXXX"); jq --arg id "$id" --arg v "$value" '(.nodes[]|select(.id==$id)|.metadata.tags)=($v | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length>0)) | unique)' "$candidate" >"$tmp"; mv "$tmp" "$candidate"
        ;;
      *) rm -f "$candidate"; die "不支持的修改参数：$key";;
    esac
  done
  protocol=$(jq -r --arg id "$id" '.nodes[]|select(.id==$id)|.protocol' "$candidate")
  [[ "$protocol" == vmess-ws-cf || -n $(jq -r --arg id "$id" '.nodes[]|select(.id==$id)|.server_address // ""' "$candidate") ]] || log_warn "节点尚未设置客户端服务器地址。"
  if [[ ${SBM_DRY_RUN:-0} == 1 ]]; then
    config_preview_candidate "$candidate"
    rm -f "$candidate"
    return 0
  fi
  if ! apply_candidate_state "$candidate" "edit-$id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}
node_set() {
  local id=$1 node; shift
  node=$(state_get_node "$id") || return 1
  if xray_stream_protocol "$(jq -r '.protocol // ""' <<<"$node")"; then
    local arg
    for arg in "$@"; do
      case "$arg" in --transport|--security|--flow|--path|--host|--service-name|--xhttp-mode|--tls-server-name|--fingerprint|--alpn|--allow-insecure|--pinned-cert-sha256|--verify-name|--packet-encoding|--vless-encryption|--vless-decryption|--transport-json|--tls-json|--sockopt-json|--fallbacks|--fallback-dest|--sniffing|--sniff-dest|--tcp-fast-open|--accept-proxy-protocol|--xray-inbound-json|--xray-outbound-json)
        node_vless_configure "$id" "$@"; return $?;; esac
    done
  fi
  if [[ ${SBM_DRY_RUN:-0} == 1 ]]; then with_lock _node_set "$id" "$@"; else with_state_transaction node-edit _node_set "$id" "$@"; fi
}

# WireGuard keys come from Xray; peers get the next free host in the node
# subnet (the server keeps .1).
wireguard_keypair() {
  local out private public
  [[ -x "$SBM_XRAY_BIN" ]] || _xray_install_binary >&2 || return 1
  out=$("$SBM_XRAY_BIN" wg 2>/dev/null) || return 1
  private=$(awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' <<<"$out")
  public=$(awk -F': *' 'tolower($1) ~ /public/ {print $2; exit}' <<<"$out")
  [[ "$private" =~ ^[A-Za-z0-9+/]{43}=$ && "$public" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { log_error '无法生成 WireGuard 密钥。'; return 1; }
  jq -n --arg private "$private" --arg public "$public" '{private_key:$private,public_key:$public}'
}

wireguard_next_address() {
  local node=$1 prefix used host user_id file
  prefix=$(jq -r '.subnet' <<<"$node" | sed -E 's#\.[0-9]+/24$##')
  used=' 1 '
  while IFS= read -r user_id; do
    file=$(state_user_secret_path "$(jq -r '.id' <<<"$node")" "$user_id")
    [[ -r "$file" ]] && used+="$(jq -r '.address // ""' "$file" | awk -F. '{print $4}') "
  done < <(jq -r '.users[]?.id' <<<"$node")
  for ((host=2; host<255; host++)); do [[ "$used" == *" $host "* ]] || { printf '%s.%s\n' "$prefix" "$host"; return 0; }; done
  log_error 'WireGuard 子网地址已用尽。'; return 1
}

node_user_generate_secret() {
  local node=$1 user_id=${2:-default} protocol
  protocol=$(jq -r '.protocol' <<<"$node")
  case "$protocol" in
    vmess|vmess-ws-cf) jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}' ;;
    masque) jq -n --arg pass "$(random_password 24)" '{password:$pass}' ;;
    wireguard) jq --arg address "$(wireguard_next_address "$node")" '. + {address:$address}' <<<"$(wireguard_keypair)" ;;
    shadowsocks) jq -n --arg password "$(ss2022_key "$(jq -r '.method' <<<"$node")")" '{password:$password}' ;;
    hysteria2|trojan) jq -n --arg password "$(random_password 24)" '{password:$password}' ;;
    vless) jq -n --arg uuid "$(random_uuid)" '{uuid:$uuid}' ;;
    socks|http|mixed) jq -n --arg username "$(random_hex 12)" --arg password "$(random_password 24)" '{username:$username,password:$password}' ;;
    *) die "协议暂不支持多用户：$protocol" ;;
  esac
}

node_user_list() {
  local node_id=$1 json=${2:-0} node
  node=$(state_get_node "$node_id"); [[ -n "$node" ]] || die "节点不存在：$node_id"
  if [[ "$json" == 1 ]]; then jq '.users' <<<"$node"; return $?; fi
  printf '%-18s %-8s %s\n' 'USER_ID' '状态' '名称'
  jq -r '.users[] | [.id,(if .enabled then "启用" else "停用" end),.name] | @tsv' <<<"$node" |
    while IFS=$'\t' read -r id enabled name; do printf '%-18s %-8s %s\n' "$id" "$enabled" "$name"; done
}

_node_user_add() {
  local node_id=$1 user_id=$2 name=${3:-$2} node protocol secret candidate node_secret
  validate_node_id "$user_id" || die "用户 ID 只能包含小写字母、数字、点、下划线和连字符。"
  node=$(state_get_node "$node_id"); [[ -n "$node" ]] || die "节点不存在：$node_id"
  state_user_exists "$node_id" "$user_id" && die "用户已存在：$node_id/$user_id"
  secret=$(node_user_generate_secret "$node" "$user_id")
  state_write_user_secret "$node_id" "$user_id" "$secret" || return 1
  candidate=$(state_candidate)
  jq --arg nid "$node_id" --arg uid "$user_id" --arg name "$name" --arg now "$(now_iso)" '
    (.nodes[] | select(.id==$nid) | .users) += [{id:$uid,name:$name,enabled:true,created_at:$now}]
  ' "$SBM_STATE" >"$candidate"
  protocol=$(jq -r '.protocol' <<<"$node")
  if [[ "$protocol" == shadowsocks && $(jq -r '.credential_mode // "legacy"' <<<"$node") == legacy && $(jq -r '.method' <<<"$node") == 2022-* ]]; then
    node_secret=$(jq -n --arg server_password "$(ss2022_key "$(jq -r '.method' <<<"$node")")" '{server_password:$server_password}')
    state_write_secret "$node_id" "$node_secret" || return 1
    jq --arg nid "$node_id" '(.nodes[] | select(.id==$nid) | .credential_mode)="multi"' "$candidate" >"$candidate.tmp"
    mv "$candidate.tmp" "$candidate"
    log_warn "Shadowsocks 节点已切换到 2022 多用户模式；原单用户分享链接需要重新导出。"
  fi
  if ! apply_candidate_state "$candidate" "user-add-$node_id-$user_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "已添加用户：$node_id/$user_id"
}
node_user_add() { with_state_transaction user-add _node_user_add "$@"; }

# Batch add (3x-ui "add bulk"): PREFIX-1 … PREFIX-N in one transaction, with
# optional limits applied to every new user.
_node_user_batch_add() {
  local node_id=$1 prefix=$2 count=$3 start=${4:-1} node protocol secret candidate users='[]' i user_id limits='null' now
  shift 4
  node=$(state_get_node "$node_id"); [[ -n "$node" ]] || die "节点不存在：$node_id"
  [[ "$count" =~ ^[1-9][0-9]{0,3}$ ]] && (( count <= 1000 )) || die '数量必须为 1-1000。'
  [[ "$start" =~ ^[0-9]{1,6}$ ]] || die '起始编号无效。'
  validate_node_id "$prefix-$start" || die '前缀只能包含小写字母、数字、点、下划线和连字符。'
  protocol=$(jq -r '.protocol' <<<"$node")
  [[ "$protocol" != tunnel ]] || die '端口转发节点没有用户。'
  now=$(date +%s)
  local quota=null days=null ip=null reset=null value
  while (($#)); do
    case "$1" in
      --quota) quota=$(traffic_nullable_size "${2:?}") || die "无效配额：$2"; shift 2;;
      --days) [[ "${2:?}" =~ ^[1-9][0-9]{0,3}$ ]] || die '天数必须为 1-3650。'; days=$((now + $2 * 86400)); shift 2;;
      --ip-limit) [[ "${2:?}" =~ ^[1-9][0-9]{0,3}$ ]] || die 'IP 数必须为 1-1024。'; ip=$2; shift 2;;
      --reset-day) [[ "${2:?}" =~ ^[0-9]+$ ]] && (( 10#$2 >= 1 && 10#$2 <= 28 )) || die '每月重置日必须是 1-28。'; reset=$((10#$2)); shift 2;;
      *) die "未知参数：$1";;
    esac
  done
  if [[ "$quota" != null || "$days" != null || "$ip" != null ]]; then
    [[ ! "$protocol" =~ ^(socks|http|mixed)$ || ( "$quota" == null && "$ip" == null ) ]] || die 'SOCKS/HTTP 账号不能设置流量配额或在线 IP。'
    limits=$(jq -cn --argjson q "$quota" --argjson r "$reset" --argjson e "$days" --argjson i "$ip" \
      '{quota_bytes:$q,reset_day:$r,expires_at:$e,ip_limit:$i,suspended:null,suspended_until:null,resume_enabled:false}')
  fi
  for ((i = start; i < start + count; i++)); do
    user_id="$prefix-$i"
    validate_node_id "$user_id" || die "用户 ID 过长：$user_id"
    jq -e --arg u "$user_id" 'any(.users[]; .id==$u)' <<<"$node" >/dev/null && die "用户已存在：$node_id/$user_id"
    secret=$(node_user_generate_secret "$node" "$user_id") || return 1
    state_write_user_secret "$node_id" "$user_id" "$secret" || return 1
    # Keep the in-memory node current so WireGuard addresses stay unique.
    node=$(jq -c --arg u "$user_id" '.users += [{id:$u,name:$u,enabled:true}]' <<<"$node")
    users=$(jq -c --arg u "$user_id" --arg now "$(now_iso)" --argjson l "$limits" \
      '. + [{id:$u,name:$u,enabled:true,created_at:$now} + (if $l==null then {} else {limits:$l} end)]' <<<"$users")
  done
  candidate=$(state_candidate)
  jq --arg nid "$node_id" --argjson users "$users" '(.nodes[] | select(.id==$nid) | .users) += $users' "$SBM_STATE" >"$candidate" || { rm -f "$candidate"; return 1; }
  if [[ "$protocol" == shadowsocks && $(jq -r '.credential_mode // "legacy"' <<<"$node") == legacy && $(jq -r '.method' <<<"$node") == 2022-* ]]; then
    state_write_secret "$node_id" "$(jq -n --arg p "$(ss2022_key "$(jq -r '.method' <<<"$node")")" '{server_password:$p}')" || return 1
    jq --arg nid "$node_id" '(.nodes[] | select(.id==$nid) | .credential_mode)="multi"' "$candidate" >"$candidate.tmp" && mv "$candidate.tmp" "$candidate"
    log_warn "Shadowsocks 节点已切换到 2022 多用户模式；原单用户分享链接需要重新导出。"
  fi
  if ! apply_candidate_state "$candidate" "user-batch-$node_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "已添加 $count 个用户：$node_id/$prefix-$start … $prefix-$((start + count - 1))"
}
node_user_batch_add() { with_state_transaction user-batch _node_user_batch_add "$@"; }

# Remove users whose quota or expiry is exhausted (3x-ui "delete depleted").
_node_user_purge_depleted() {
  local filter=${1:-} candidate list
  list=$(jq -r --arg f "$filter" '.nodes[]? | select($f=="" or .id==$f) | .id as $n | .users[] | select((.limits.suspended // "")|IN("quota","expired")) | "\($n)/\(.id)"' "$SBM_STATE")
  [[ -n "$list" ]] || { log_info '没有已耗尽或已到期的用户。'; return 0; }
  printf '将删除：\n%s\n' "$list"
  confirm '确认删除这些用户及其凭据？' || return 1
  candidate=$(state_candidate)
  jq --arg f "$filter" '.nodes |= map(if $f=="" or .id==$f then
      .users |= map(select((.limits.suspended // "")|IN("quota","expired")|not)) else . end)' "$SBM_STATE" >"$candidate" || { rm -f "$candidate"; return 1; }
  jq -e 'all(.nodes[]?; (.users|length)>0)' "$candidate" >/dev/null || { rm -f "$candidate"; die '删除后会有节点没有用户；请先为该节点保留或添加一个用户。'; }
  if ! apply_candidate_state "$candidate" user-purge; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  local entry; while IFS= read -r entry; do rm -f -- "$(state_user_secret_path "${entry%%/*}" "${entry#*/}")"; done <<<"$list"
  log_ok "已删除 $(wc -l <<<"$list") 个用户。"
}
node_user_purge_depleted() { with_state_transaction user-purge _node_user_purge_depleted "$@"; }

_node_user_set_enabled() {
  local node_id=$1 user_id=$2 value=$3 candidate
  state_user_exists "$node_id" "$user_id" || die "用户不存在：$node_id/$user_id"
  candidate=$(state_candidate)
  jq --arg nid "$node_id" --arg uid "$user_id" --argjson value "$value" '
    (.nodes[] | select(.id==$nid) | .users[] | select(.id==$uid)) |=
      (.enabled=$value | if .limits!=null then .limits.suspended=null | .limits.suspended_until=null | .limits.resume_enabled=false else . end)
  ' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" "user-$value-$node_id-$user_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}
node_user_enable() { with_state_transaction user-enable _node_user_set_enabled "$1" "$2" true; }
node_user_disable() { with_state_transaction user-disable _node_user_set_enabled "$1" "$2" false; }

_node_user_delete() {
  local node_id=$1 user_id=$2 candidate
  state_user_exists "$node_id" "$user_id" || die "用户不存在：$node_id/$user_id"
  candidate=$(state_candidate)
  jq --arg nid "$node_id" --arg uid "$user_id" '
    (.nodes[] | select(.id==$nid) | .users) |= map(select(.id!=$uid))
  ' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" "user-delete-$node_id-$user_id"; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate" "$(state_user_secret_path "$node_id" "$user_id")"
  rm -rf -- "$SBM_EXPORTS/nodes/$node_id/$user_id"
  if [[ -s "$SBM_USER_USAGE" ]] && declare -F user_usage_update_unlocked >/dev/null 2>&1; then
    user_usage_update_unlocked 'del(.users[$key])' --arg key "$node_id:$user_id" || log_warn '用户流量账本清理失败。'
  fi
  log_ok "已删除用户：$node_id/$user_id"
}
node_user_delete() { with_state_transaction user-delete _node_user_delete "$@"; }

_settings_set_default_address() {
  local address=$1 candidate
  if [[ "$address" == auto ]]; then _settings_detect_public_ip; return $?; fi
  validate_address "$address" || die "无效地址：$address"
  candidate=$(state_candidate)
  jq --arg a "$address" '.settings.default_server_address=$a | .settings.default_server_address_source="manual"' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" settings-address; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}
settings_set_default_address() { with_state_transaction settings-address _settings_set_default_address "$@"; }

_settings_set_log_level() {
  local level=$1 candidate
  case "$level" in trace|debug|info|warn|error|fatal|panic) ;; *) die "无效日志级别：$level" ;; esac
  candidate=$(state_candidate)
  jq --arg v "$level" '.settings.log_level=$v' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" log-level; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}
settings_set_log_level() { with_state_transaction settings-log-level _settings_set_log_level "$@"; }

_settings_set_outbound_ip_strategy() {
  local strategy=$1 candidate
  case "$strategy" in prefer_ipv4|prefer_ipv6|ipv4_only) ;; *) die '出站 IP 策略必须是 prefer_ipv4、prefer_ipv6 或 ipv4_only。';; esac
  candidate=$(state_candidate)
  jq --arg strategy "$strategy" '.settings.outbound_ip_strategy=$strategy' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" outbound-ip-strategy; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
}
settings_set_outbound_ip_strategy() { with_state_transaction settings-outbound-ip _settings_set_outbound_ip_strategy "$@"; }


_settings_detect_public_ip() {
  local ipv4='' ipv6='' chosen candidate
  ipv4=$(detect_public_ipv4 || true); ipv6=$(detect_public_ipv6 || true); chosen=${ipv4:-$ipv6}
  [[ -n "$chosen" ]] || die '无法从多个独立 HTTPS 服务探测公网 IP。'
  candidate=$(state_candidate)
  jq --arg ipv4 "$ipv4" --arg ipv6 "$ipv6" --arg chosen "$chosen" --arg now "$(now_iso)" '
    .settings.public_ipv4=$ipv4 | .settings.public_ipv6=$ipv6 |
    .settings.public_ip_detected_at=$now | .settings.default_server_address=$chosen |
    .settings.default_server_address_source="auto" |
    .nodes |= map(if (.server_address_source // "") == "auto" then .server_address=$chosen else . end)
  ' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" settings-detect-ip; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "公网入口探测完成：IPv4=${ipv4:--} IPv6=${ipv6:--}"
}
settings_detect_public_ip() { with_state_transaction settings-detect-ip _settings_detect_public_ip; }


settings_show_addresses() {
  if [[ ${1:-0} == 1 ]]; then jq '.settings | {default_server_address,default_server_address_source,public_ipv4,public_ipv6,outbound_ip_strategy,public_ip_detected_at}' "$SBM_STATE"; return $?; fi
  jq -r '"默认入口：\(.settings.default_server_address // "-")\n来源：\(.settings.default_server_address_source // "-")\n公网 IPv4：\(.settings.public_ipv4 // "-")\n公网 IPv6：\(.settings.public_ipv6 // "-")\n出站 IP 策略：\(.settings.outbound_ip_strategy // "prefer_ipv4")\n探测时间：\(.settings.public_ip_detected_at // "-")"' "$SBM_STATE"
}
