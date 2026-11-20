#!/usr/bin/env bash
# shellcheck shell=bash

# Hysteria2 share link and sing-box/mihomo client outbound. The Xray server
# inbound and Xray client outbound live in lib/xray.sh and lib/export.sh.

protocol_hy2_share() {
  local node=$1 secret=$2 node_secret=${3:-'{}'}
  [[ -n $(jq -r '.server_address // ""' <<<"$node") ]] || { log_warn "节点 $(jq -r '.id' <<<"$node") 尚未配置服务器地址。"; return 1; }
  jq -r -n --argjson n "$node" --argjson s "$secret" --argjson ns "$node_secret" '
    (if ($n.server_address|contains(":")) then "[\($n.server_address)]" else $n.server_address end) as $host |
    "hysteria2://\($s.password|@uri)@\($host):\($n.port)/?sni=\($n.domain|@uri)&insecure=0"
    + (if ($n.obfs.type // "") != "" then "&obfs=\($n.obfs.type|@uri)&obfs-password=\(($ns.obfs_password // "")|@uri)" else "" end)
    + "#\($n.name|@uri)"'
}

protocol_hy2_client_outbound() {
  local node=$1 secret=$2 node_secret=${3:-'{}'}
  jq -n --argjson n "$node" --argjson s "$secret" --argjson ns "$node_secret" '
    {type:"hysteria2", tag:"proxy-\($n.id)", server:($n.server_address // ""), server_port:$n.port,
     password:$s.password, tls:{enabled:true, server_name:$n.domain}}
    + (if ($n.obfs.type // "") != "" then {obfs:{type:$n.obfs.type, password:($ns.obfs_password // "")}} else {} end)'
}
