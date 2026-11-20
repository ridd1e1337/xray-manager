#!/usr/bin/env bash
# shellcheck shell=bash

if ! declare -F dependency_require_feature >/dev/null 2>&1 && [[ -f "$SBM_LIB/lib/dependencies.sh" ]]; then
  # shellcheck source=lib/dependencies.sh
  source "$SBM_LIB/lib/dependencies.sh"
fi
if ! declare -F prepare_singbox_binary_for_backend >/dev/null 2>&1; then
  # shellcheck source=lib/runtime-security.sh
  source "$SBM_LIB/lib/runtime-security.sh"
fi

sb_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    armv7l|armv7|armhf) printf 'armv7\n' ;;
    i386|i486|i586|i686) printf '386\n' ;;
    *) die "暂不支持的 CPU 架构：$(uname -m)" ;;
  esac
}
cloudflared_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    armv7l|armv7|armhf) printf 'arm\n' ;;
    i386|i486|i586|i686) printf '386\n' ;;
    *) die "暂不支持的 CPU 架构：$(uname -m)" ;;
  esac
}

download_file_with_retries() {
  local url=$1 output=$2 label=${3:-文件} attempts=${4:-5} attempt delay
  rm -f "$output"
  for ((attempt=1; attempt<=attempts; attempt++)); do
    if curl --fail --location --silent --show-error \
      --connect-timeout 15 --max-time 600 \
      "$url" -o "$output"; then
      if [[ -s "$output" ]]; then
        return 0
      fi
      log_warn "$label 下载结果为空（第 $attempt/$attempts 次）。"
    else
      log_warn "$label 下载失败（第 $attempt/$attempts 次）。"
    fi
    rm -f "$output"
    (( attempt < attempts )) || break
    delay=$((attempt * 2))
    sleep "$delay"
  done
  rm -f "$output"
  die "$label 下载失败，已重试 $attempts 次。"
}

github_api() {
  local url=$1 attempt output delay attempts=5
  for ((attempt=1; attempt<=attempts; attempt++)); do
    if output=$(curl --fail --silent --show-error --location \
      --connect-timeout 15 --max-time 120 \
      -H 'Accept: application/vnd.github+json' \
      -H 'User-Agent: xray-manager' "$url"); then
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
        return 0
      fi
    fi
    log_warn "GitHub API 请求失败（第 $attempt/$attempts 次）。"
    (( attempt < attempts )) || break
    delay=$((attempt * 2))
    sleep "$delay"
  done
  return 1
}

verify_asset_digest() {
  local file=$1 digest=${2:-}
  [[ -n "$digest" && "$digest" == sha256:* ]] || return 2
  local expected=${digest#sha256:} actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
}

artifact_record() {
  local name=$1 version=$2 url=$3 digest=$4 binary=${5:-} manifest tmp details='' binary_digest=''
  manifest="$SBM_VAR/install-manifest.json"
  mkdir -p "$SBM_VAR"
  if [[ -n "$binary" && -x "$binary" ]]; then
    details=$("$binary" version 2>/dev/null | head -n 20 || true)
    binary_digest="sha256:$(sha256sum "$binary" | awk '{print $1}')"
  fi
  tmp=$(mktemp "$SBM_VAR/.install-manifest.XXXXXX")
  if [[ -s "$manifest" ]] && jq -e 'type=="object" and (.artifacts|type=="array")' "$manifest" >/dev/null 2>&1; then
    jq --arg name "$name" --arg version "$version" --arg url "$url" --arg digest "$digest" \
      --arg installed_at "$(now_iso)" --arg details "$details" --arg binary_digest "$binary_digest" '
        .artifacts |= (map(select(.name != $name)) + [{
          name:$name, version:$version, source_url:$url, digest:$digest,
          installed_at:$installed_at, binary_digest:$binary_digest, version_output:$details
        }])
      ' "$manifest" >"$tmp"
  else
    jq -n --arg name "$name" --arg version "$version" --arg url "$url" --arg digest "$digest" \
      --arg installed_at "$(now_iso)" --arg details "$details" --arg binary_digest "$binary_digest" '{schema_version:1,artifacts:[{
        name:$name,version:$version,source_url:$url,digest:$digest,
        installed_at:$installed_at,binary_digest:$binary_digest,version_output:$details
      }]}' >"$tmp"
  fi
  chmod 0640 "$tmp"
  mv -f "$tmp" "$manifest"
}

core_check_free_space() {
  local path=${1:-$SBM_CORE_DIR} required=${2:-${SBM_CORE_MIN_FREE_BYTES:-260000000}} available
  [[ "$required" =~ ^[0-9]+$ ]] || required=260000000
  available=$(df -Pk "$path" 2>/dev/null | awk 'NR==2 {printf "%.0f\n", $4 * 1024; exit}') || return 1
  [[ "$available" =~ ^[0-9]+$ ]] || { log_error "无法确认磁盘剩余空间：$path"; return 1; }
  if (( available < required )); then
    log_error "磁盘剩余空间不足：$(numfmt --to=iec "$available" 2>/dev/null || printf '%s bytes' "$available")，至少需要约 $(numfmt --to=iec "$required" 2>/dev/null || printf '%s bytes' "$required") 才能安全下载/解压核心。"
    log_error '请清理磁盘或使用容量充足的安装目录后重试。'
    return 1
  fi
}

# --- Xray core (the only proxy core of xray-manager) ----------------------
# Core helpers (status, doctor,
# backup, panel and CLI share one interface.
core_current_version() { xray_current_version; }
core_latest_version() { xray_latest_version; }
core_download_version() { xray_download_version "${1:-latest}"; }
core_prune_cached_versions() { xray_prune_versions; }
core_update() { require_root; with_lock _xray_install "${1:-latest}"; }

core_check_update() {
  local current latest
  current=$(core_current_version || true); latest=$(core_latest_version) || { log_error '无法查询 Xray 最新官方版本。'; return 1; }
  printf '当前 Xray：%s\n最新 Xray：%s\n' "${current:-未安装}" "$latest"
  if [[ -n "$current" && "$current" != "$latest" ]] && version_ge "$latest" "$current"; then printf '可运行 xm core update 更新。\n'; fi
}

core_capabilities() {
  printf 'Xray-core %s\n' "$(core_current_version || printf '未安装')"
  printf '入站协议：VLESS（RAW/WS/gRPC/HTTPUpgrade/XHTTP/mKCP/Hysteria，TLS/Reality/VLESS 加密）、VMess、Trojan、Shadowsocks 2022、Hysteria2、SOCKS、HTTP\n'
  printf '统计 API：用户/入站/出站流量与在线 IP（仅本机回环监听）\n'
}

_core_set_policy() {
  local policy=$1 candidate
  case "$policy" in manual|notify|patch|stable) ;; *) die '更新策略必须是 manual、notify、patch 或 stable。';; esac
  candidate=$(state_candidate)
  jq --arg p "$policy" '.settings.core_update_policy=$p' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" core-policy; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "Xray 自动更新策略：$policy（patch 只更新同一年月发布，stable 更新任意新版本）"
}
core_set_policy() { with_state_transaction core-policy _core_set_policy "$@"; }

core_auto_update() {
  xray_auto_update || log_warn 'Xray 自动更新检查未完成。'
  cloudflared_auto_update || log_warn 'cloudflared 自动更新检查未完成。'
}

cloudflared_auto_update() {
  local policy current latest current_series latest_series
  policy=$(jq -r '.settings.cloudflared_update_policy // "notify"' "$SBM_STATE" 2>/dev/null || printf 'notify')
  [[ "$policy" != manual ]] || return 0
  [[ -x "$SBM_CLOUDFLARED_BIN" ]] || return 0
  [[ $(jq -r '.tunnel.mode // "none"' "$SBM_STATE") != none ]] || return 0
  current=$(cloudflared_current_version || true)
  latest=$(cloudflared_latest_version) || return 1
  [[ -n "$current" && -n "$latest" && "$current" != "$latest" ]] || return 0
  mkdir -p "$SBM_VAR/updates"
  jq -n --arg now "$(now_iso)" --arg current "$current" --arg latest "$latest" --arg policy "$policy" \
    '{checked_at:$now,current:$current,latest:$latest,policy:$policy}' >"$SBM_VAR/updates/cloudflared.json"
  case "$policy" in
    notify) log_warn "发现 cloudflared 更新：$current → $latest。运行 xm cloudflared update。" ;;
    patch|stable)
      current_series=${current%%.*}; latest_series=${latest%%.*}
      if [[ "$policy" == patch && "$current_series" == "$latest_series" ]] || [[ "$policy" == stable && "$current_series" == "$latest_series" ]]; then
        cloudflared_install
      else
        log_warn "发现跨系列 cloudflared 更新 $latest；请手动运行 xm cloudflared update。"
      fi
      ;;
  esac
}

_core_rollback() {
  local active previous
  active=$(readlink -f "$SBM_XRAY_BIN" 2>/dev/null || true)
  previous=$(find "$SBM_CORE_DIR/xray" -mindepth 2 -maxdepth 2 -type f -name xray ! -path "$active" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR==1{print $2}')
  [[ -n "$previous" && -x "$previous" ]] || { log_error '没有可回滚的上一版 Xray。'; return 1; }
  _xray_switch_to "$previous"
}
core_rollback() { require_root; with_lock _core_rollback; }

cloudflared_release_json() { github_api 'https://api.github.com/repos/cloudflare/cloudflared/releases/latest'; }
cloudflared_latest_version() {
  local json tag
  json=$(cloudflared_release_json) || return 1
  tag=$(jq -r '.tag_name // empty' <<<"$json")
  [[ -n "$tag" ]] || return 1
  printf '%s\n' "${tag#v}"
}
cloudflared_current_version() {
  local output
  [[ -x "$SBM_CLOUDFLARED_BIN" ]] || return 0
  output=$("$SBM_CLOUDFLARED_BIN" version 2>/dev/null) || return 1
  if [[ $output =~ ([0-9]{4}\.[0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

cloudflared_download_latest() {
  local arch json version asset_name url digest tmp target
  arch=$(cloudflared_arch)
  json=$(cloudflared_release_json) || die "无法获取 cloudflared Release 信息。"
  version=$(jq -r '.tag_name // empty' <<<"$json" | sed 's/^v//')
  [[ -n "$version" ]] || die "cloudflared Release 信息缺少版本号。"
  asset_name="cloudflared-linux-${arch}"
  url=$(jq -r --arg n "$asset_name" 'first(.assets[] | select(.name==$n) | .browser_download_url) // empty' <<<"$json")
  digest=$(jq -r --arg n "$asset_name" 'first(.assets[] | select(.name==$n) | (.digest // "")) // empty' <<<"$json")
  [[ -n "$url" ]] || die "未找到 cloudflared 资产：$asset_name"
  target="$SBM_CORE_DIR/cloudflared/$version/cloudflared"
  if [[ -x "$target" ]]; then
    "$target" version 2>/dev/null | grep -Fq "$version" || die "已缓存的 cloudflared $version 无法通过版本校验。"
    ensure_program_permissions
    artifact_record cloudflared "$version" "$url" "${digest:-previously-verified}" "$target"
    printf '%s\n' "$target"
    return 0
  fi
  mkdir -p "$SBM_CORE_DIR"
  mkdir -p "$SBM_CACHE"
  core_check_free_space "$SBM_CACHE" "${SBM_CLOUDFLARED_MIN_FREE_BYTES:-160000000}"
  core_check_free_space "$SBM_CORE_DIR" "${SBM_CLOUDFLARED_MIN_FREE_BYTES:-160000000}"
  mkdir -p "$(dirname "$target")"
  chmod 0755 "$SBM_CORE_DIR" "$SBM_CORE_DIR/cloudflared" "$(dirname "$target")"
  tmp=$(mktemp "$SBM_CACHE/cloudflared.XXXXXX")
  log_info "下载 cloudflared $version ($arch)…"
  download_file_with_retries "$url" "$tmp" "cloudflared $version" 5
  [[ -n "$digest" && "$digest" == sha256:* ]] || { rm -f "$tmp"; die "Release API 未提供 cloudflared SHA-256 摘要，已拒绝安装。"; }
  verify_asset_digest "$tmp" "$digest" || { rm -f "$tmp"; die "cloudflared 校验失败。"; }
  if ! { chmod 0755 "$tmp" && mv -f "$tmp" "$target"; }; then
    rm -f "$tmp"
    die "无法写入 cloudflared，可能是磁盘空间不足：$target"
  fi
  rm -f "$tmp"
  ensure_program_permissions
  if ! "$target" version >/dev/null 2>&1; then
    rm -rf "$(dirname "$target")"
    die "下载的 cloudflared 核心无法执行。"
  fi
  artifact_record cloudflared "$version" "$url" "$digest" "$target"
  printf '%s\n' "$target"
}

cloudflared_prune_cached_versions() {
  local keep=${SBM_CLOUDFLARED_RETENTION:-1} current path version
  local -a dirs=()
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=1
  [[ -z $(find "$SBM_BACKUPS" -maxdepth 4 -type f -name .recovery-pending -print -quit 2>/dev/null) ]] || return 0
  (( keep >= 1 )) || keep=1
  current=$(readlink -f "$SBM_CLOUDFLARED_BIN" 2>/dev/null || true)
  [[ -d "$SBM_CORE_DIR/cloudflared" ]] || return 0
  while IFS= read -r path; do [[ -n "$path" ]] && dirs+=("$path"); done < <(
    find "$SBM_CORE_DIR/cloudflared" -mindepth 2 -maxdepth 2 -type f -name cloudflared -perm -u+x -printf '%T@ %p\n' 2>/dev/null |
      sort -nr | awk '{sub(/^[^ ]+ /, ""); print}'
  )
  local retained=0 max_others=$((keep - 1))
  [[ -n "$current" ]] || max_others=$keep
  for path in "${dirs[@]}"; do
    if [[ "$path" == "$current" ]]; then
      continue
    fi
    if (( retained < max_others )); then
      retained=$((retained + 1))
      continue
    fi
    version=$(dirname "$path")
    rm -rf -- "$version"
  done
}

cloudflared_require() {
  [[ -x "$SBM_CLOUDFLARED_BIN" ]] || die 'Cloudflare Tunnel 组件尚未安装；请先运行：xm cloudflared install'
  validate_runtime_binary_path cloudflared "$SBM_CLOUDFLARED_BIN"
}

_cloudflared_install() {
  local binary old new_linked=0 mode
  binary=$(cloudflared_download_latest)
  old=$(readlink -f "$SBM_CLOUDFLARED_BIN" 2>/dev/null || true)
  validate_runtime_binary_path cloudflared "$binary"
  ensure_program_permissions
  mkdir -p "$SBM_BIN_DIR"
  mkdir -p "$SBM_VAR/cloudflared-home" "$SBM_LOG_DIR"
  chown "$SBM_SERVICE_USER":"$SBM_SERVICE_USER" "$SBM_VAR/cloudflared-home" "$SBM_LOG_DIR" 2>/dev/null || true
  chmod 0750 "$SBM_VAR/cloudflared-home" "$SBM_LOG_DIR" 2>/dev/null || true
  ln -sfn "$binary" "$SBM_CLOUDFLARED_BIN.new"
  mv -Tf "$SBM_CLOUDFLARED_BIN.new" "$SBM_CLOUDFLARED_BIN"
  new_linked=1
  ensure_program_permissions
  mode=$(jq -r '.tunnel.mode // "none"' "$SBM_STATE" 2>/dev/null || printf 'none')
  if declare -F tunnel_reconcile >/dev/null 2>&1 && [[ "$mode" != none ]]; then
    if ! tunnel_reconcile 1; then
      if [[ -n "$old" && -x "$old" ]]; then
        ln -sfn "$old" "$SBM_CLOUDFLARED_BIN"
      elif (( new_linked )); then
        rm -f "$SBM_CLOUDFLARED_BIN"
      fi
      return 1
    fi
  fi
  cloudflared_prune_cached_versions
  if [[ "$old" == "$binary" ]]; then
    log_ok 'cloudflared 已是最新版。'
  else
    log_ok "cloudflared 已安装/更新至 $(cloudflared_current_version || printf '未知版本')。"
  fi
}
cloudflared_install() { with_lock _cloudflared_install; }

_cloudflared_update() {
  _cloudflared_install
}
cloudflared_update() { with_lock _cloudflared_update; }

_cloudflared_set_policy() {
  local policy=$1 candidate
  case "$policy" in manual|notify|patch|stable) ;; *) die 'cloudflared 更新策略必须是 manual、notify、patch 或 stable。';; esac
  candidate=$(state_candidate)
  jq --arg p "$policy" '.settings.cloudflared_update_policy=$p' "$SBM_STATE" >"$candidate"
  if ! apply_candidate_state "$candidate" cloudflared-policy; then rm -f "$candidate"; return 1; fi
  rm -f "$candidate"
  log_ok "cloudflared 自动更新策略：$policy"
}
cloudflared_set_policy() { with_state_transaction cloudflared-policy _cloudflared_set_policy "$@"; }
