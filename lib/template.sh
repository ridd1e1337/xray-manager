#!/usr/bin/env bash
# shellcheck shell=bash

node_clone_defaults() {
  local node=$1
  # Non-secret settings only. The Xray override keeps transport/TLS options but
  # drops anything credential-shaped a hand-written override might contain.
  jq '{name,protocol,domain:(.domain // ""),server_address:(.server_address // ""),client_address:(.client_address // ""),
      port,listen,network:(.network // ""),method:(.method // ""),ws_path:(.ws_path // ""),
      obfs:(.obfs.type // ""),masquerade:(.masquerade // ""),security:(.security // ""),flow:(.flow // ""),
      handshake_server:(.handshake_server // ""),handshake_port:(.handshake_port // 443),
      subnet:(.subnet // ""),mtu:(.mtu // null),target_address:(.target_address // ""),target_port:(.target_port // null),
      follow_redirect:(.follow_redirect // false),
      metadata:(.metadata // {remark:"",region:"",purpose:"",line:"",tags:[]}),
      xray:{inbound:((.xray.inbound // {}) | del(.settings.clients, .settings.accounts, .settings.password, .settings.decryption, .settings.peers,
                     .settings.secretKey, .streamSettings.realitySettings.privateKey, .streamSettings.realitySettings.shortIds,
                     .streamSettings.realitySettings.mldsa65Seed)),
            outbound:((.xray.outbound // {}) | del(.settings, .streamSettings.realitySettings.publicKey, .streamSettings.realitySettings.shortId))},
      singbox:{outbound:(.singbox.outbound // {})}}' <<<"$node"
}


node_add_from_defaults() {
  local defaults=$1 id=$2 protocol value disabled=0 key
  shift 2
  protocol=$(jq -r '.protocol' <<<"$defaults")
  local -A v=()
  for key in name port domain server_address listen network method ws_path obfs masquerade security flow handshake_server handshake_port subnet mtu target_address target_port; do
    v[$key]=$(jq -r --arg k "$key" '.[$k] // "" | tostring' <<<"$defaults")
  done
  local remark region purpose line tags
  remark=$(jq -r '.metadata.remark // ""' <<<"$defaults"); region=$(jq -r '.metadata.region // ""' <<<"$defaults")
  purpose=$(jq -r '.metadata.purpose // ""' <<<"$defaults"); line=$(jq -r '.metadata.line // ""' <<<"$defaults"); tags=$(jq -r '(.metadata.tags // [])|join(",")' <<<"$defaults")
  while (($#)); do
    case "$1" in
      --name|--port|--address|--domain|--remark|--region|--purpose|--line|--tags)
        value=${2:?缺少参数值}
        case "$1" in
          --name) v[name]=$value;; --port) v[port]=$value;; --address) v[server_address]=$value;; --domain) v[domain]=$value;;
          --remark) remark=$value;; --region) region=$value;; --purpose) purpose=$value;; --line) line=$value;; --tags) tags=$value;;
        esac
        shift 2;;
      --disabled) disabled=1; shift;; *) die "模板创建不支持参数：$1";;
    esac
  done
  local -a args=("$protocol" --id "$id" --name "${v[name]:-$id}" --port "${v[port]}")
  [[ -z "${v[server_address]}" || "$protocol" == tunnel ]] || args+=(--address "${v[server_address]}")
  [[ -z "${v[domain]}" ]] || args+=(--domain "${v[domain]}")
  [[ $(jq -c '.xray.inbound // {}' <<<"$defaults") == '{}' ]] || args+=(--xray-inbound-json "$(jq -c '.xray.inbound' <<<"$defaults")")
  [[ $(jq -c '.xray.outbound // {}' <<<"$defaults") == '{}' ]] || args+=(--xray-outbound-json "$(jq -c '.xray.outbound' <<<"$defaults")")
  [[ $(jq -c '.singbox.outbound // {}' <<<"$defaults") == '{}' ]] || args+=(--sing-box-outbound-json "$(jq -c '.singbox.outbound' <<<"$defaults")")
  case "$protocol" in
    socks|http|mixed) args+=(--listen "${v[listen]}");;
    vmess-ws-cf) [[ -z "${v[ws_path]}" ]] || args+=(--path "${v[ws_path]}");;
    shadowsocks) args+=(--method "${v[method]}" --network "${v[network]:-tcp}"); [[ -z "${v[security]}" ]] || args+=(--security "${v[security]}");;
    hysteria2) [[ "${v[obfs]}" != salamander ]] || args+=(--obfs salamander); [[ -z "${v[masquerade]}" ]] || args+=(--masquerade "${v[masquerade]}");;
    vless|vmess|trojan)
      [[ -z "${v[security]}" ]] || args+=(--security "${v[security]}")
      [[ "$protocol" != vless ]] || args+=(--flow "${v[flow]}")
      [[ "${v[security]}" != reality ]] || args+=(--handshake-server "${v[handshake_server]}" --handshake-port "${v[handshake_port]}");;
    wireguard) [[ -z "${v[mtu]}" ]] || args+=(--mtu "${v[mtu]}");;
    masque) [[ -z "${v[mtu]}" ]] || args+=(--mtu "${v[mtu]}");;
    tunnel) args+=(--target "$(format_hostport "${v[target_address]}" "${v[target_port]}")" --network "${v[network]:-tcp}"); [[ $(jq -r '.follow_redirect // false' <<<"$defaults") != true ]] || args+=(--follow-redirect);;
  esac
  [[ -z "$remark" ]] || args+=(--remark "$remark"); [[ -z "$region" ]] || args+=(--region "$region")
  [[ -z "$purpose" ]] || args+=(--purpose "$purpose"); [[ -z "$line" ]] || args+=(--line "$line"); [[ -z "$tags" ]] || args+=(--tags "$tags")
  (( disabled == 0 )) || args+=(--disabled)
  node_add "${args[@]}"
}

# 3x-ui "clone inbound": same settings, new ID/port, fresh credentials.
node_clone() {
  local src=${1:?用法：xm node clone SRC_ID NEW_ID [--port N] [--name NAME] [--domain DOMAIN]} id=${2:?缺少新节点 ID} node port
  shift 2
  node=$(state_get_node "$src"); [[ -n "$node" ]] || die "节点不存在：$src"
  port=$(node_choose_port "$(node_transport_kinds "$node" | sed -n 1p)") || return 1
  node_add_from_defaults "$(node_clone_defaults "$node")" "$id" --port "$port" --name "$(jq -r '.name' <<<"$node") copy" "$@"
}
