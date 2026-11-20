#!/usr/bin/env bash
# shellcheck shell=bash

xray_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf '64\n' ;;
    aarch64|arm64) printf 'arm64-v8a\n' ;;
    armv7l|armv7|armhf) printf 'arm32-v7a\n' ;;
    i386|i486|i586|i686) printf '32\n' ;;
    *) die "Xray 暂不支持的 CPU 架构：$(uname -m)" ;;
  esac
}

xray_release_json() {
  local version=${1:-latest}
  if [[ "$version" == latest ]]; then github_api 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'
  else github_api "https://api.github.com/repos/XTLS/Xray-core/releases/tags/v${version#v}"; fi
}

xray_current_version() {
  local output
  [[ -x "$SBM_XRAY_BIN" ]] || return 0
  output=$("$SBM_XRAY_BIN" version 2>/dev/null) || return 1
  [[ "$output" =~ Xray[[:space:]]+([0-9]{2,4}\.[0-9]+\.[0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

xray_asset_name() {
  case "$2" in
    64|32|arm64-v8a|arm32-v7a) printf 'Xray-linux-%s.zip\n' "$2" ;;
    *) return 1 ;;
  esac
}

xray_download_version() (
  local requested=${1:-latest} arch json version name url digest expected work target size
  dependency_require_feature xray >&2 || return 1
  arch=$(xray_arch) || return 1
  json=$(xray_release_json "$requested") || { log_error '无法获取 Xray 官方 Release。'; return 1; }
  version=$(jq -r '.tag_name // empty | ltrimstr("v")' <<<"$json") || return 1
  [[ "$version" =~ ^[0-9]{2,4}\.[0-9]+\.[0-9]+$ ]] || { log_error "无效 Xray 版本：$version"; return 1; }
  name=$(xray_asset_name "$version" "$arch") || return 1
  url=$(jq -r --arg n "$name" 'first(.assets[] | select(.name==$n) | .browser_download_url) // empty' <<<"$json") || return 1
  digest=$(jq -r --arg n "$name" 'first(.assets[] | select(.name==$n) | .digest) // empty' <<<"$json") || return 1
  [[ "$url" == "https://github.com/XTLS/Xray-core/releases/download/"* ]] || { log_error '缺少官方 Xray 下载地址。'; return 1; }
  target="$SBM_CORE_DIR/xray/$version/xray"
  if [[ -x "$target" ]]; then
    "$target" version >/dev/null 2>&1 || return 1
    printf '%s\n' "$target"
    return 0
  fi
  mkdir -p "$SBM_CACHE" "$SBM_CORE_DIR/xray" || return 1
  size=$(jq -r --arg n "$name" 'first(.assets[] | select(.name==$n) | .size) // 0' <<<"$json") || return 1
  [[ "$size" =~ ^[1-9][0-9]*$ ]] || return 1
  core_check_free_space "$SBM_CACHE" "$((size + 40000000))" || return 1
  core_check_free_space "$SBM_CORE_DIR" 40000000 || return 1
  work=$(mktemp -d "$SBM_CACHE/xray.XXXXXX") || return 1
  trap 'rm -rf -- "$work"; rm -f -- "$target.new"' EXIT
  download_file_with_retries "$url" "$work/core.zip" "Xray $version" 5 || return 1
  if [[ "$digest" != sha256:* ]]; then
    url=$(jq -r --arg n "$name.dgst" 'first(.assets[] | select(.name==$n) | .browser_download_url) // empty' <<<"$json") || return 1
    [[ "$url" == "https://github.com/XTLS/Xray-core/releases/download/"* ]] || { log_error 'Xray Release 缺少 SHA-256 摘要。'; return 1; }
    download_file_with_retries "$url" "$work/digest" 'Xray 摘要' 5 || return 1
    expected=$(awk -F= '/^SHA2?-256=/{gsub(/[[:space:]]/, "", $2); print tolower($2); exit}' "$work/digest") || return 1
    [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || { log_error 'Xray SHA-256 摘要无效。'; return 1; }
    digest="sha256:$expected"
  fi
  verify_asset_digest "$work/core.zip" "$digest" || { log_error 'Xray 下载摘要不匹配。'; return 1; }
  # Routing is generated locally; the large geoip/geosite databases are unused.
  install -d -m 0755 "$SBM_CORE_DIR/xray/$version" || return 1
  unzip -p "$work/core.zip" xray >"$target.new" || return 1
  chmod 0755 "$target.new" || return 1
  "$target.new" version >/dev/null 2>&1 || { log_error 'Xray 无法在当前架构运行。'; return 1; }
  mv -f "$target.new" "$target" || return 1
  ensure_program_permissions || return 1
  artifact_record xray "$version" "https://github.com/XTLS/Xray-core/releases/download/v$version/$name" "$digest" "$target" >&2 || return 1
  printf '%s\n' "$target"
)

xray_prune_versions() {
  local active directory
  [[ -d "$SBM_CORE_DIR/xray" ]] || return 0
  # A failed recovery may still need the previous executable until repaired.
  [[ -z $(find "$SBM_BACKUPS" -name .recovery-pending -print -quit 2>/dev/null) ]] || return 0
  active=$(readlink -f "$SBM_XRAY_BIN" 2>/dev/null || true)
  [[ "$active" == "$SBM_CORE_DIR/xray/"* ]] || return 0
  # Keep the active build and the newest other build for xm core rollback.
  local keep=''
  keep=$(find "$SBM_CORE_DIR/xray" -mindepth 1 -maxdepth 1 -type d ! -path "$(dirname "$active")" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR==1{print $2}')
  for directory in "$SBM_CORE_DIR/xray"/*; do
    [[ -d "$directory" && ! -L "$directory" ]] || continue
    [[ "$active" == "$directory/xray" || "$directory" == "$keep" ]] || rm -rf -- "$directory" || return 1
  done
}

xray_node_override() {
  jq -c --arg direction "$2" '(.xray // {})[$direction] // {}' <<<"$1"
}

xray_apply_override() {
  local rendered=$1 override=$2
  jq -e 'type=="object" and (.settings==null or (.settings|type)=="object") and (.streamSettings==null or (.streamSettings|type)=="object")' <<<"$override" >/dev/null || {
    log_error 'Xray 扩展及 settings/streamSettings 必须是 JSON 对象。'; return 1;
  }
  jq --argjson override "$override" '
    . as $base | . * ($override
      | if .settings==null then del(.settings) else . end
      | if .streamSettings==null then del(.streamSettings) else . end
      | del(.protocol,.tag,.listen,.port,.settings.clients,.settings.accounts,.settings.password))
    | .protocol=$base.protocol | .tag=$base.tag | .listen=$base.listen | .port=$base.port
    | .settings=((.settings // {})
        + (if $base.settings.clients!=null then {clients:$base.settings.clients} else {} end)
        + (if $base.settings.accounts!=null then {accounts:$base.settings.accounts} else {} end)
        + (if $base.settings.password!=null then {password:$base.settings.password} else {} end))
  ' <<<"$rendered"
}

# Per-protocol Xray inbounds. Client `email` is "<node>:<user>" for every
# protocol so the Stats API and per-user limits work uniformly.
xray_tls_settings() {
  local domain=$1 alpn=${2:-}
  jq -n --arg cert "$SBM_CERTS/$domain/fullchain.pem" --arg key "$SBM_CERTS/$domain/key.pem" --arg alpn "$alpn" \
    '{security:"tls",tlsSettings:({certificates:[{certificateFile:$cert,keyFile:$key}]}
      + (if $alpn=="" then {} else {alpn:($alpn|split(","))} end))}'
}

xray_protocol_inbound() {
  local node=$1 credentials=$2 secret=$3 id protocol base clients domain mode
  id=$(jq -r '.id' <<<"$node"); protocol=$(jq -r '.protocol' <<<"$node"); domain=$(jq -r '.domain // ""' <<<"$node")
  base=$(jq -n --arg tag "in-$id" --arg listen "$(jq -r '.listen // "::"' <<<"$node")" --argjson port "$(jq -r '.port' <<<"$node")" \
    '{tag:$tag,listen:$listen,port:$port}') || return 1
  case "$protocol" in
    vmess)
      clients=$(jq --arg n "$id" '[.[] | {id:.uuid,email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
      jq --argjson c "$clients" '. + {protocol:"vmess",settings:{clients:$c}}' <<<"$base";;
    vmess-ws-cf)
      clients=$(jq --arg n "$id" '[.[] | {id:.uuid,email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
      jq --argjson c "$clients" --arg path "$(jq -r '.ws_path' <<<"$node")" \
        '. + {protocol:"vmess",settings:{clients:$c},streamSettings:{network:"ws",wsSettings:{path:$path}}}' <<<"$base";;
    trojan)
      clients=$(jq --arg n "$id" '[.[] | {password,email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
      jq --argjson c "$clients" --argjson tls "$(xray_tls_settings "$domain")" \
        '. + {protocol:"trojan",settings:{clients:$c},streamSettings:({network:"raw"}+$tls)}' <<<"$base";;
    shadowsocks)
      mode=$(jq -r '.credential_mode // "legacy"' <<<"$node")
      if [[ $(jq -r '.method' <<<"$node") != 2022-* ]]; then
        # Classic AEAD: every client carries its own method and password.
        clients=$(jq --arg n "$id" --arg method "$(jq -r '.method' <<<"$node")" '[.[] | {method:$method,password,email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
        jq --argjson c "$clients" \
          --arg network "$(jq -r 'if (.network // "tcp")=="udp" then "udp" else "tcp,udp" end' <<<"$node")" \
          '. + {protocol:"shadowsocks",settings:{clients:$c,network:$network}}' <<<"$base"
      elif [[ "$mode" == multi ]]; then
        clients=$(jq --arg n "$id" '[.[] | {password,email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
        jq --argjson c "$clients" --arg method "$(jq -r '.method' <<<"$node")" --arg psk "$(jq -r '.server_password' <<<"$secret")" \
          --arg network "$(jq -r 'if (.network // "tcp")=="udp" then "udp" elif (.network // "tcp")=="tcp" then "tcp,udp" else .network end' <<<"$node")" \
          '. + {protocol:"shadowsocks",settings:{method:$method,password:$psk,clients:$c,network:$network}}' <<<"$base"
      else
        jq --arg n "$id" --argjson u "$(jq -c '.[0]' <<<"$credentials")" --arg method "$(jq -r '.method' <<<"$node")" \
          --arg network "$(jq -r 'if (.network // "tcp")=="udp" then "udp" else "tcp,udp" end' <<<"$node")" \
          '. + {protocol:"shadowsocks",settings:{method:$method,password:$u.password,email:($n+":"+$u.id),level:0,network:$network}}' <<<"$base"
      fi;;
    hysteria2)
      if [[ $(jq -r '.obfs.type // ""' <<<"$node") == salamander && -z $(jq -r '.obfs_password // ""' <<<"$secret") ]]; then
        log_error "Hysteria2 节点 $id 启用了 Salamander 但缺少混淆密码；请重新执行 xm node set $id --obfs salamander。"; return 1
      fi
      clients=$(jq --arg n "$id" '[.[] | {auth:.password,email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
      jq --argjson c "$clients" --argjson tls "$(xray_tls_settings "$domain" h3)" --arg obfs "$(jq -r '.obfs.type // ""' <<<"$node")" \
        --arg obfs_password "$(jq -r '.obfs_password // ""' <<<"$secret")" --arg masquerade "$(jq -r '.masquerade // ""' <<<"$node")" '
        . + {protocol:"hysteria",settings:{version:2,clients:$c},
             streamSettings:({network:"hysteria",hysteriaSettings:({version:2}
               + (if $masquerade=="" then {} else {masquerade:{type:"proxy",url:$masquerade,rewriteHost:true}} end))} + $tls
               + (if $obfs=="salamander" then {finalmask:{udp:[{type:"salamander",settings:{password:$obfs_password}}]}} else {} end))}' <<<"$base";;
    socks|mixed)
      clients=$(jq '[.[] | {user:.username,pass:.password}]' <<<"$credentials") || return 1
      jq --argjson a "$clients" '. + {protocol:"socks",settings:{auth:"password",accounts:$a,udp:true}}' <<<"$base";;
    http)
      clients=$(jq '[.[] | {user:.username,pass:.password}]' <<<"$credentials") || return 1
      jq --argjson a "$clients" '. + {protocol:"http",settings:{accounts:$a}}' <<<"$base";;
    masque)
      # MASQUE rejects ":" in emails; "@" is outside the id charset, and the
      # Stats collector maps it back to "<node>:<user>".
      clients=$(jq --arg n "$id" '[.[] | {pass:.password,email:($n+"@"+.id),level:0}]' <<<"$credentials") || return 1
      jq --argjson c "$clients" --argjson tls "$(xray_tls_settings "$domain" h3)" --arg subnet "$(jq -r '.subnet' <<<"$node")" --argjson mtu "$(jq -r '.mtu // 1280' <<<"$node")" \
        '. + {protocol:"masque",settings:{address:[($subnet|sub("\\.0/24$";".1/24"))],mtu:$mtu,users:$c},
              streamSettings:({network:"masque",masqueSettings:{path:"/.well-known/masque/ip/*/*/"}} + $tls)}' <<<"$base";;
    wireguard)
      # Userspace stack only: never create a host interface or routes.
      clients=$(jq --arg n "$id" '[.[] | {publicKey:.public_key,allowedIPs:[.address+"/32"],email:($n+":"+.id),level:0}]' <<<"$credentials") || return 1
      jq --argjson c "$clients" --arg sk "$(jq -r '.private_key' <<<"$secret")" --argjson mtu "$(jq -r '.mtu // 1420' <<<"$node")" \
        '. + {protocol:"wireguard",settings:{secretKey:$sk,mtu:$mtu,noKernelTun:true,peers:$c}}' <<<"$base";;
    tunnel)
      jq --argjson n "$node" '. + {protocol:"tunnel",settings:{address:$n.target_address,port:$n.target_port,network:$n.network,followRedirect:($n.follow_redirect // false)}}' <<<"$base";;
    *) log_error "Xray 不支持此协议：$protocol"; return 1;;
  esac
}

# Protocols whose transport and security are fully configurable (3x-ui
# parity): VLESS, generic VMess, Trojan and Shadowsocks share one stream
# builder; Hysteria, SOCKS/HTTP and the CF-tunnel VMess keep fixed streams.
xray_stream_protocol() { [[ "$1" =~ ^(vless|vmess|trojan|shadowsocks)$ ]]; }

xray_node_security() {
  jq -r 'if .security!=null then .security elif .protocol=="trojan" then "tls" else "none" end' <<<"$1"
}

xray_inbound_for_node() {
  local node=$1 credentials=$2 secret=$3 id domain rendered users security flow target protocol
  protocol=$(jq -r '.protocol' <<<"$node")
  if ! xray_stream_protocol "$protocol"; then
    rendered=$(xray_protocol_inbound "$node" "$credentials" "$secret") || return 1
    xray_apply_override "$rendered" "$(xray_node_override "$node" inbound)"
    return
  fi
  id=$(jq -r '.id' <<<"$node"); domain=$(jq -r '.domain // ""' <<<"$node")
  flow=$(jq -r '.flow // ""' <<<"$node"); security=$(xray_node_security "$node")
  if [[ "$protocol" == vless ]]; then
    # email is the per-user Stats API key; keep it unique across nodes.
    users=$(jq --arg flow "$flow" --arg node "$id" '[.[] | {id:.uuid,email:($node+":"+.id),level:0} + (if $flow=="" then {} else {flow:$flow} end)]' <<<"$credentials") || return 1
    rendered=$(jq -n --arg tag "in-$id" --arg listen "$(jq -r '.listen // "::"' <<<"$node")" \
      --argjson port "$(jq -r '.port' <<<"$node")" --argjson clients "$users" \
      '{tag:$tag,listen:$listen,port:$port,protocol:"vless",settings:{clients:$clients,decryption:"none"},streamSettings:{network:"raw"}}') || return 1
  else
    # Reuse the protocol settings, then rebuild the stream generically.
    rendered=$(xray_protocol_inbound "$node" "$credentials" "$secret" | jq '.streamSettings={network:"raw"}') || return 1
  fi
  if [[ "$security" == reality ]]; then
    target=$(format_hostport "$(jq -r '.handshake_server' <<<"$node")" "$(jq -r '.handshake_port' <<<"$node")") || return 1
    rendered=$(jq --arg target "$target" --arg server_name "$domain" \
      --arg private "$(jq -r '.reality_private_key' <<<"$secret")" --arg short_id "$(jq -r '.reality_short_id' <<<"$secret")" \
      '.streamSettings += {security:"reality",realitySettings:{show:false,target:$target,xver:0,serverNames:[$server_name],privateKey:$private,shortIds:[$short_id]}}' <<<"$rendered") || return 1
  elif [[ "$security" == tls ]]; then
    rendered=$(jq --arg cert "$SBM_CERTS/$domain/fullchain.pem" --arg key "$SBM_CERTS/$domain/key.pem" \
      '.streamSettings += {security:"tls",tlsSettings:{certificates:[{certificateFile:$cert,keyFile:$key}]}}' <<<"$rendered") || return 1
  fi
  rendered=$(xray_apply_override "$rendered" "$(xray_node_override "$node" inbound)") || return 1
  local stream
  stream=$(vless_stream_normalize "$(jq -c '.streamSettings' <<<"$rendered")") || return 1
  # Fallbacks need an explicit HTTP/1.1 ALPN; add h2 only for h2 fallbacks.
  jq --argjson stream "$stream" '.streamSettings=$stream
    | if ((.settings.fallbacks // [])|length)>0 and .streamSettings.security=="tls" and .streamSettings.tlsSettings.alpn==null then
        .streamSettings.tlsSettings.alpn=(if any(.settings.fallbacks[]; .alpn=="h2") then ["h2","http/1.1"] else ["http/1.1"] end)
      else . end' <<<"$rendered"
}

# Rendered inbounds are cached by content. The key hashes the manager
# version, certificate directory, the effective node JSON and the raw bytes
# of its user and node secret files, so a cache hit needs no jq at all and
# any change to inputs produces a new key.
xray_render_config() {
  local state=$1 output=$2 id node users dir key file credentials secret nsec inbound inbounds u
  local -a rendered=() files=()
  dir=$(vless_cache_dir 2>/dev/null) || dir=''
  # One pass: effective node (443-mux route applied) and enabled user ids.
  while IFS=$'\t' read -r id node users; do
    files=(); for u in $users; do files+=("$(state_user_secret_path "$id" "$u")"); done
    nsec=$(state_secret_path "$id"); file=''
    if [[ -n "$dir" ]]; then
      key=$({ printf '%s\0' render "$SBM_VERSION" "$SBM_CERTS" "$node"; cat -- "${files[@]}" 2>/dev/null; [[ ! -r "$nsec" ]] || cat -- "$nsec"; } | sha256sum | awk '{print $1}')
      file="$dir/$key.inbound.json"
    fi
    if [[ -n "$file" && -s "$file" ]]; then
      inbound=$(<"$file")
    else
      credentials=$(node_enabled_credentials "$node") || return 1
      secret='{}'; [[ ! -r "$nsec" ]] || secret=$(state_get_secret "$id") || return 1
      inbound=$(xray_inbound_for_node "$node" "$credentials" "$secret") || return 1
      [[ -z "$file" ]] || { (umask 077; printf '%s\n' "$inbound" >"$file.$$" && mv -f "$file.$$" "$file") 2>/dev/null || rm -f "$file.$$"; }
    fi
    rendered+=("$inbound")
  done < <(jq -r '(.nginx_stream.enabled // false) as $mux | (.nginx_stream.routes // []) as $routes |
    .nodes[]? | select(.enabled==true and any(.users[]?; .enabled==true)) | . as $n |
    ([$routes[] | select(.node_id==$n.id)] | first) as $r |
    (if $mux and $r != null then .listen="127.0.0.1" | .port=$r.backend_port else . end) |
    [.id, tojson, ([.users[] | select(.enabled==true) | .id] | join(" "))] | join("\t")' "$state")
  if (( ${#rendered[@]} )); then inbounds=$(printf '%s\n' "${rendered[@]}" | jq -cs .) || return 1; else inbounds='[]'; fi
  local routing='{"outbounds":[{"tag":"direct","protocol":"freedom"}]}'
  if declare -F xray_routing_render >/dev/null 2>&1; then routing=$(xray_routing_render "$state") || return 1; fi
  # Loopback-only Stats API for per-user traffic and online-IP limits.
  # Shared manager settings apply to both cores: log level and the direct
  # outbound's IP family preference (sing-box domain_strategy equivalent).
  local loglevel ip_strategy
  case "$(jq -r '.settings.log_level // "info"' "$state")" in
    trace|debug) loglevel=debug;; info) loglevel=info;; warn) loglevel=warning;; *) loglevel=error;;
  esac
  case "$(jq -r '.settings.outbound_ip_strategy // "prefer_ipv4"' "$state")" in
    prefer_ipv6) ip_strategy=UseIPv6v4;; ipv4_only) ip_strategy=UseIPv4;; *) ip_strategy=UseIPv4v6;;
  esac
  routing=$(jq -c --arg s "$ip_strategy" '.outbounds |= map(if .tag=="direct" then .settings=((.settings // {})+{domainStrategy:$s}) else . end)' <<<"$routing") || return 1
  jq -n --argjson inbounds "$inbounds" --argjson routing "$routing" --arg loglevel "$loglevel" --arg api "127.0.0.1:$(jq -r '.settings.xray_api_port // 10085' "$state")" '{
    log:{loglevel:$loglevel},
    api:{tag:"api",listen:$api,services:["StatsService"]},
    stats:{},
    policy:{levels:{"0":{statsUserUplink:true,statsUserDownlink:true,statsUserOnline:true}},
      system:{statsInboundUplink:true,statsInboundDownlink:true,statsOutboundUplink:true,statsOutboundDownlink:true}},
    inbounds:$inbounds} + $routing' >"$output" || return 1
  chmod 0640 "$output" && set_group_if_exists "$SBM_SERVICE_USER" "$output"
}

# Current Xray infers the config format from the file extension and rejects
# extensionless candidates even with -format json. BusyBox mktemp lacks
# --suffix, so test a config.json copy inside a private temporary directory.
xray_test_config() (
  local bin=$1 config=$2 log=$3 dir
  mkdir -p "$SBM_RUN" || return 1
  dir=$(mktemp -d "$SBM_RUN/xray-test.XXXXXX") || return 1
  trap 'rm -rf -- "$dir"' EXIT
  chmod 0700 "$dir" && cp "$config" "$dir/config.json" || return 1
  XRAY_LOCATION_ASSET="${SBM_XRAY_ASSET_DIR:-$SBM_VAR/xray-assets}" "$bin" run -test -config "$dir/config.json" >"$log" 2>&1
)

xray_validate_config() {
  xray_test_config "$1" "$2" "$SBM_RUN/xray-config-check.log" || {
    log_error "Xray 配置检查失败；日志：$SBM_RUN/xray-config-check.log"; return 1;
  }
}

xray_write_service() {
  local backend=$1 unit
  unit=$(service_file_path "$SBM_XRAY_SERVICE") || return 1
  case "$backend" in
    systemd)
      mkdir -p "$SBM_SYSTEMD_DIR" || return 1
      cat >"$unit.new" <<EOF_UNIT || return 1
[Unit]
Description=xray-manager Xray-core service
Documentation=https://xtls.github.io/
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=$SBM_SERVICE_USER
Group=$SBM_SERVICE_USER
Environment=XRAY_LOCATION_ASSET=$SBM_XRAY_ASSET_DIR
ExecStart=$SBM_XRAY_BIN run -config $SBM_CONFIG
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576
TasksMax=1024
MemoryAccounting=true
TasksAccounting=true
UMask=0027
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
ReadOnlyPaths=$SBM_ETC $SBM_LIB

[Install]
WantedBy=multi-user.target
EOF_UNIT
      chmod 0644 "$unit.new" && mv -f "$unit.new" "$unit" || return 1 ;;
    openrc)
      dependency_require_feature low-port || return 1
      setcap cap_net_bind_service=+ep "$(readlink -f "$SBM_XRAY_BIN")" || {
        log_error '无法授予 Xray 低端口能力，未切换为 root 服务。'; return 1;
      }
      write_openrc_supervised_service "$unit" 'xray-manager xray' 'xray-manager Xray-core service' /usr/bin/env "XRAY_LOCATION_ASSET=$SBM_XRAY_ASSET_DIR $SBM_XRAY_BIN run -config $SBM_CONFIG" "$SBM_SERVICE_USER" "$SBM_XRAY_LOG" "$SBM_XRAY_ERROR_LOG" 'after firewall' || return 1 ;;
    *) log_error 'Xray 需要 systemd 或 OpenRC。'; return 1 ;;
  esac
}

xray_service_reconcile() {
  local restart=${1:-1}
  [[ "$SBM_SKIP_INIT" != 1 ]] || return 0
  if ! xray_runtime_required; then
    if service_exists "$SBM_XRAY_SERVICE"; then
      service_disable "$SBM_XRAY_SERVICE" && service_stop "$SBM_XRAY_SERVICE" || return 1
      service_reset_failed "$SBM_XRAY_SERVICE"
    fi
    return 0
  fi
  [[ -x "$SBM_XRAY_BIN" && -s "$SBM_XRAY_CONFIG" ]] || { log_error 'Xray 程序或 VLESS 配置缺失。'; return 1; }
  if [[ "$restart" == 0 ]] && service_active "$SBM_XRAY_SERVICE"; then return 0; fi
  # Restarting drops in-memory counters; fold them into the ledger first.
  if declare -F user_usage_collect_unlocked >/dev/null 2>&1; then user_usage_collect_unlocked || true; fi
  xray_write_service "$(init_system)" && service_reload_manager && service_enable "$SBM_XRAY_SERVICE" || return 1
  service_restart "$SBM_XRAY_SERVICE" && service_wait_active "$SBM_XRAY_SERVICE" 20 2 || {
    service_failure_report "$SBM_XRAY_SERVICE"; return 1;
  }
}

xray_render_validate() (
  local output=${1:-$SBM_XRAY_CONFIG} config
  mkdir -p "$(dirname "$output")" || return 1
  config=$(mktemp "$(dirname "$output")/.xray-config.XXXXXX") || return 1
  trap 'rm -f -- "$config"' EXIT
  xray_render_config "$SBM_STATE" "$config" && xray_validate_config "$SBM_XRAY_BIN" "$config" || return 1
  mv -f "$config" "$output"
)

# Switch the managed binary to TARGET after checking the current config with
# it; restore the previous binary and runtime snapshot on any failure.
_xray_switch_to() {
  local target=$1 old config backup rc=0
  old=$(readlink -f "$SBM_XRAY_BIN" 2>/dev/null || true)
  [[ -L "$SBM_XRAY_BIN" || ! -e "$SBM_XRAY_BIN" ]] || { log_error "已有非托管 Xray 程序：$SBM_XRAY_BIN，拒绝覆盖。"; return 1; }
  if [[ "$old" == "$target" ]]; then log_ok "Xray 已是 $(xray_current_version)"; return 0; fi
  config=$(mktemp "$SBM_RUN/xray-candidate.XXXXXX") || return 1
  render_config_from_state "$SBM_STATE" "$config" && xray_validate_config "$target" "$config" || { rm -f "$config"; return 1; }
  backup=$(snapshot_create core-switch) || { rm -f "$config"; return 1; }
  touch "$backup/force-core-restart" || { rm -f "$config"; rm -rf -- "$backup"; return 1; }
  mkdir -p "$(dirname "$SBM_XRAY_BIN")" || { rm -f "$config"; rm -rf -- "$backup"; return 1; }
  if ln -sfn "$target" "$SBM_XRAY_BIN.new" && mv -Tf "$SBM_XRAY_BIN.new" "$SBM_XRAY_BIN"; then
    safe_install_file "$config" "$SBM_CONFIG" 0640 && set_group_if_exists "$SBM_SERVICE_USER" "$SBM_CONFIG" || rc=1
    (( rc != 0 )) || xray_service_reconcile 1 || rc=1
  else rc=1; fi
  rm -f "$config"
  if (( rc != 0 )); then
    if [[ -n "$old" && -x "$old" ]]; then ln -sfn "$old" "$SBM_XRAY_BIN.new" && mv -Tf "$SBM_XRAY_BIN.new" "$SBM_XRAY_BIN" || return 1
    else rm -f "$SBM_XRAY_BIN"; fi
    if snapshot_restore "$backup"; then rm -rf -- "$backup"
    else touch "$backup/.recovery-pending"; log_error "Xray 恢复未完成，临时恢复记录最多保留 23 小时：$backup"; fi
    return 1
  fi
  rm -rf -- "$backup"
  xray_prune_versions || return 1
  log_ok "Xray 已切换到 $(xray_current_version)"
}

# First install (setup or a transaction that needs the core): link only.
_xray_install_binary() {
  local target
  [[ ! -x "$SBM_XRAY_BIN" ]] || return 0
  target=$(xray_download_version latest) || return 1
  mkdir -p "$(dirname "$SBM_XRAY_BIN")" && ln -sfn "$target" "$SBM_XRAY_BIN.new" && mv -Tf "$SBM_XRAY_BIN.new" "$SBM_XRAY_BIN"
}

_xray_install() {
  local version=${1:-latest} target
  target=$(xray_download_version "$version") || return 1
  _xray_switch_to "$target"
}
xray_install() { require_root; with_lock _xray_install "${1:-latest}"; }

xray_latest_version() { xray_release_json latest | jq -r '.tag_name // empty | ltrimstr("v")'; }

xray_status() {
  if [[ ! -x "$SBM_XRAY_BIN" ]]; then printf 'Xray：未安装\n'; return 0; fi
  printf 'Xray：%s\n服务：%s\n配置：%s\n' "$(xray_current_version || printf '未知版本')" "$(status_service_state "$SBM_SERVICE")" "$SBM_CONFIG"
}

# Same policy semantics as sb-manager's core updates: manual / notify /
# patch (same minor series) / stable (any newer release).
xray_auto_update() {
  [[ -x "$SBM_XRAY_BIN" ]] || return 0
  local policy current latest
  policy=$(jq -r '.settings.core_update_policy // "notify"' "$SBM_STATE") || return 1
  [[ "$policy" != manual ]] || return 0
  current=$(xray_current_version) || return 1
  latest=$(xray_latest_version) || return 1
  [[ -n "$latest" && "$current" != "$latest" ]] && version_ge "$latest" "$current" || return 0
  case "$policy" in
    notify) log_warn "发现 Xray 更新：$current → $latest；运行 xm core update。" ;;
    patch) [[ "${latest%.*}" == "${current%.*}" ]] || { log_warn "Xray $latest 不属于当前 ${current%.*} 系列，patch 策略不自动更新。"; return 0; }
      with_lock _xray_install "$latest" ;;
    stable) with_lock _xray_install "$latest" ;;
  esac
}
