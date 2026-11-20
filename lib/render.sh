#!/usr/bin/env bash
# shellcheck shell=bash

node_transport_kinds() {
  local node=$1 protocol network
  protocol=$(jq -r '.protocol' <<<"$node")
  case "$protocol" in
    vmess-ws-cf|http|socks|mixed) printf 'tcp\n' ;;
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

validate_state_semantics() {
  local state=$1 ids count node id protocol port domain cert_dir kind key user_ids user_id enabled_users realm_url realm_domain realm_port realm_id
  state_validate "$state" || return 1
  if declare -F traffic_validate_state >/dev/null 2>&1; then
    traffic_validate_state "$state" || return 1
  fi
  if declare -F nginx_stream_validate_state >/dev/null 2>&1; then
    nginx_stream_validate_state "$state" || die 'TCP/SNI 复用状态无效。'
  fi
  ids=$(jq -r '.nodes[].id' "$state" | sort)
  count=$(printf '%s\n' "$ids" | sed '/^$/d' | uniq -d | wc -l)
  (( count == 0 )) || die "状态中存在重复节点 ID。"
  if [[ $(jq -r '.api.enabled // false' "$state") == true ]]; then
    version_ge "$(core_current_version)" 1.14.0-rc.1 || die 'sing-box API/Dashboard 需要 1.14+ 核心。'
    [[ -r "$(state_secret_path api)" ]] || die 'API secret 文件缺失。'
  fi
  if [[ $(jq -r '.realm.enabled // false' "$state") == true ]]; then
    version_ge "$(core_current_version)" 1.14.0-rc.1 || die 'Hysteria Realm 需要 sing-box 1.14.0-rc.1 或更高版本核心。'
    [[ -r "$SBM_REALM_SECRET" ]] || die 'Hysteria Realm secret 文件缺失。'
    realm_url=$(jq -r '.realm.public_url // ""' "$state")
    [[ "$realm_url" =~ ^https?://[^/[:space:]]+$ ]] || die "无效 Realm 公网 URL：$realm_url"
    realm_domain=$(jq -r '.realm.tls_domain // ""' "$state")
    if [[ -n "$realm_domain" ]]; then
      [[ -s "$SBM_CERTS/$realm_domain/fullchain.pem" && -s "$SBM_CERTS/$realm_domain/key.pem" ]] || die "Realm 缺少证书：$SBM_CERTS/$realm_domain/{fullchain.pem,key.pem}"
    fi
  fi

  declare -A occupied=() realm_ids=()
  if nginx_stream_state_enabled "$state"; then
    port=$(jq -r '.nginx_stream.port' "$state")
    occupied[tcp:$port]='TCP/SNI 复用入口'
  fi
  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    id=$(jq -r '.id' <<<"$node")
    if declare -F nginx_stream_effective_node >/dev/null 2>&1; then
      node=$(nginx_stream_effective_node "$state" "$node")
    fi
    protocol=$(jq -r '.protocol' <<<"$node")
    port=$(jq -r '.port' <<<"$node")
    validate_node_id "$id" || die "节点 ID 不规范：$id"
    validate_port "$port" || die "节点 $id 的端口无效：$port"
    case "$protocol" in vmess-ws-cf|vmess|shadowsocks|hysteria2|trojan|vless|socks|http|mixed|tunnel) ;; *) die "节点 $id 使用未知协议：$protocol" ;; esac
    if [[ $(jq -r '.enabled' <<<"$node") == true ]]; then
      if [[ "$protocol" != vmess-ws-cf ]]; then
        local endpoint_address
        endpoint_address=$(jq -r '.server_address // ""' <<<"$node")
        validate_address "$endpoint_address" || die "节点 $id 的客户端服务器地址无效或为空。"
      fi
      if [[ "$protocol" == snell ]]; then
        version_ge "$(core_current_version)" 1.14.0-rc.1 || die 'Snell 需要 sing-box 1.14.0-rc.1 或更高版本核心。'
        if [[ $(jq -r '.snell_version // 5' <<<"$node") == 6 ]]; then
          version_ge "$(core_current_version)" 1.14.0-rc.2 || die 'Snell v6 需要 sing-box 1.14.0-rc.2 或更高版本核心。'
        fi
      fi
      if [[ "$protocol" == hysteria2 ]] && { [[ $(jq -r '.obfs.type // ""' <<<"$node") == gecko ]] || [[ $(jq -r '.disable_chrome_parrot // false' <<<"$node") == true ]] || [[ -n $(jq -r '.bbr_profile // ""' <<<"$node") ]] || [[ $(jq -r '.brutal_debug // false' <<<"$node") == true ]]; }; then
        version_ge "$(core_current_version)" 1.14.0-rc.1 || die '当前 Hysteria2 配置包含 1.14+ 功能，需要 sing-box 1.14.0-rc.1 或更高版本核心。'
      fi
      if [[ "$protocol" == hysteria2 && $(jq -r '.realm_enabled // false' <<<"$node") == true ]]; then
        [[ $(jq -r '.realm.enabled // false' "$state") == true ]] || die "节点 $id 启用了 Hysteria Realm，但全局 Realm 服务未启用。"
        realm_id=$(jq -r '.realm_id // ""' <<<"$node")
        [[ "$realm_id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] || die "节点 $id 的 Realm ID 无效：$realm_id"
        [[ -z ${realm_ids[$realm_id]+x} ]] || die "Realm ID 重复：$realm_id（节点 ${realm_ids[$realm_id]} 与 $id）"
        realm_ids[$realm_id]=$id
      fi
    fi
    user_ids=$(jq -r '.users[].id' <<<"$node" | sort)
    count=$(printf '%s\n' "$user_ids" | sed '/^$/d' | uniq -d | wc -l)
    (( count == 0 )) || die "节点 $id 存在重复用户 ID。"
    if [[ $(jq -r '.enabled' <<<"$node") == true ]]; then
      enabled_users=$(jq '[.users[] | select(.enabled==true)] | length' <<<"$node")
      (( enabled_users > 0 )) || jq -e 'all(.users[]; .limits.suspended!=null or .enabled)' <<<"$node" >/dev/null || die "启用节点 $id 至少需要一个启用用户。"
      while IFS= read -r kind; do
        key="$kind:$port"
        [[ -z ${occupied[$key]+x} ]] || die "端口冲突：$id 与 ${occupied[$key]} 同时占用 ${port}/${kind^^}。"
        occupied[$key]=$id
      done < <(node_transport_kinds "$node")
      if { [[ "$protocol" == hysteria2 ]] || { xray_stream_protocol "$protocol" && [[ $(xray_node_security "$node") == tls ]]; }; } \
        && ! jq -e '(.xray.inbound.streamSettings.tlsSettings.certificates // [])|length>0' <<<"$node" >/dev/null; then
        domain=$(jq -r '.domain // ""' <<<"$node")
        validate_domain "$domain" || die "节点 $id 的 TLS 域名无效：$domain"
        cert_dir="$SBM_CERTS/$domain"
        [[ -s "$cert_dir/fullchain.pem" && -s "$cert_dir/key.pem" ]] || die "节点 $id 缺少证书：$cert_dir/{fullchain.pem,key.pem}"
      fi
      while IFS= read -r user_id; do
        [[ -r "$(state_user_secret_path "$id" "$user_id")" ]] || die "节点 $id 的用户 $user_id 缺少密钥文件。"
      done < <(jq -r '.users[] | select(.enabled==true) | .id' <<<"$node")
      if [[ "$protocol" == hysteria2 || "$protocol" == snell || "$protocol" == shadowtls || ("$protocol" == vless && $(jq -r '.security' <<<"$node") == reality) ]]; then
        [[ -r "$(state_secret_path "$id")" ]] || die "节点 $id 缺少协议级密钥文件。"
      fi
      if xray_stream_protocol "$protocol"; then
        local vless_secret='{}'
        [[ ! -r "$(state_secret_path "$id")" ]] || vless_secret=$(state_get_secret "$id") || return 1
        vless_profile_validate "$node" "$vless_secret" "$state" || return 1
      fi
      if [[ "$protocol" == snell || "$protocol" == shadowtls ]]; then
        [[ $(jq -r '.credential_revision // 0' <<<"$node") == 1 ]] || die "节点 $id 的安全凭据尚未迁移，请通过 xm 命令初始化状态。"
      fi
    fi
  done < <(jq -c '.nodes[]?' "$state")
  if [[ $(jq -r '.realm.enabled // false' "$state") == true ]]; then
    realm_port=$(jq -r '.realm.port' "$state")
    [[ -z ${occupied[tcp:$realm_port]+x} ]] || die "Realm 端口冲突：${occupied[tcp:$realm_port]} 已占用 ${realm_port}/TCP。"
  fi
}

node_enabled_credentials() {
  local node=$1 node_id user user_id secret credentials='[]'
  node_id=$(jq -r '.id' <<<"$node")
  while IFS= read -r user; do
    user_id=$(jq -r '.id' <<<"$user")
    secret=$(state_get_user_secret "$node_id" "$user_id")
    credentials=$(jq -c --argjson user "$user" --argjson secret "$secret" '. + [$user + $secret]' <<<"$credentials")
  done < <(jq -c '.users[] | select(.enabled==true)' <<<"$node")
  printf '%s\n' "$credentials"
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
