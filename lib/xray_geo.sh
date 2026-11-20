#!/usr/bin/env bash
# shellcheck shell=bash

# Optional geoip.dat / geosite.dat for `geoip:` and `geosite:` routing rules
# (3x-ui parity). Files are downloaded only on request (~28 MiB) from
# Loyalsoldier/v2ray-rules-dat, verified against the GitHub release digest,
# and kept in a fixed asset directory that Xray reads through
# XRAY_LOCATION_ASSET (the binary directory changes with every core switch).

SBM_XRAY_ASSET_DIR="${SBM_XRAY_ASSET_DIR:-$SBM_VAR/xray-assets}"
SBM_XRAY_GEO_REPO="${SBM_XRAY_GEO_REPO:-Loyalsoldier/v2ray-rules-dat}"

xray_geo_installed() { [[ -s "$SBM_XRAY_ASSET_DIR/geoip.dat" && -s "$SBM_XRAY_ASSET_DIR/geosite.dat" ]]; }

# Whether any routing rule needs the geo databases.
xray_geo_required() {
  jq -e 'any(.xray_routing.rules[]?; ((.domain // "") | test("(^|,)geosite:")) or ((.ip // "") | test("(^|,)geoip:")))' "${1:-$SBM_STATE}" >/dev/null
}

xray_geo_status() {
  if xray_geo_installed; then
    jq -r '"geo 数据：已安装（\(.source) \(.version)，更新于 \(.updated_at)）"' "$SBM_XRAY_ASSET_DIR/version.json" 2>/dev/null \
      || printf 'geo 数据：已安装\n'
    du -sh "$SBM_XRAY_ASSET_DIR" 2>/dev/null | awk '{print "占用空间：" $1}'
  else
    printf 'geo 数据：未安装（运行 xm xray geo update 后可使用 geosite:/geoip: 规则）\n'
  fi
  if xray_geo_required; then printf '当前路由规则使用 geosite:/geoip:\n'; fi
}

_xray_geo_update() (
  local json tag work name url digest backup rc=0 restart=0
  json=$(curl --fail --silent --show-error --location --connect-timeout 15 --max-time 60 \
    "https://api.github.com/repos/$SBM_XRAY_GEO_REPO/releases/latest") || { log_error '无法获取 geo 数据发布信息。'; return 1; }
  tag=$(jq -r '.tag_name // empty' <<<"$json")
  [[ "$tag" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || { log_error 'geo 数据发布版本无效。'; return 1; }
  if xray_geo_installed && [[ $(jq -r '.version // ""' "$SBM_XRAY_ASSET_DIR/version.json" 2>/dev/null) == "$tag" ]]; then
    log_ok "geo 数据已是最新：$tag"; return 0
  fi
  mkdir -p "$SBM_XRAY_ASSET_DIR" && chmod 0755 "$SBM_XRAY_ASSET_DIR" || return 1
  core_check_free_space "$SBM_XRAY_ASSET_DIR" 70000000 || return 1
  work=$(mktemp -d "$SBM_XRAY_ASSET_DIR/.update.XXXXXX") || return 1
  backup=$(mktemp -d "$SBM_XRAY_ASSET_DIR/.backup.XXXXXX") || { rm -rf -- "$work"; return 1; }
  trap 'rm -rf -- "$work" "$backup"' EXIT
  for name in geoip.dat geosite.dat; do
    url=$(jq -r --arg n "$name" 'first(.assets[] | select(.name==$n) | .browser_download_url) // empty' <<<"$json")
    digest=$(jq -r --arg n "$name" 'first(.assets[] | select(.name==$n) | .digest) // empty' <<<"$json")
    [[ "$url" == "https://github.com/$SBM_XRAY_GEO_REPO/releases/download/"* && "$digest" == sha256:* ]] \
      || { log_error "geo 数据发布缺少 $name 或其摘要。"; return 1; }
    download_file_with_retries "$url" "$work/$name" "$name" 5 || return 1
    verify_asset_digest "$work/$name" "$digest" || { log_error "$name 摘要不匹配。"; return 1; }
    chmod 0644 "$work/$name" || return 1
  done
  jq -n --arg source "$SBM_XRAY_GEO_REPO" --arg version "$tag" --arg at "$(now_iso)" \
    '{source:$source,version:$version,updated_at:$at}' >"$work/version.json" || return 1
  # Keep the old files until the new set validates with the current config.
  for name in geoip.dat geosite.dat version.json; do
    [[ ! -e "$SBM_XRAY_ASSET_DIR/$name" ]] || cp -p "$SBM_XRAY_ASSET_DIR/$name" "$backup/$name" || return 1
  done
  for name in geoip.dat geosite.dat version.json; do mv -f "$work/$name" "$SBM_XRAY_ASSET_DIR/$name" || rc=1; done
  if (( rc == 0 )) && xray_geo_required && [[ -x "$SBM_XRAY_BIN" ]]; then
    restart=1
    xray_validate_config "$SBM_XRAY_BIN" "$SBM_CONFIG" || rc=1
  fi
  if (( rc == 0 && restart )) && [[ "$SBM_SKIP_INIT" != 1 ]]; then
    # Rewrites the unit too, so hosts upgraded from older units gain XRAY_LOCATION_ASSET.
    xray_service_reconcile 1 || rc=1
  fi
  if (( rc != 0 )); then
    for name in geoip.dat geosite.dat version.json; do
      if [[ -e "$backup/$name" ]]; then mv -f "$backup/$name" "$SBM_XRAY_ASSET_DIR/$name"; else rm -f "$SBM_XRAY_ASSET_DIR/$name"; fi
    done
    (( ! restart )) || xray_service_reconcile 1 || true
    log_error 'geo 数据更新失败，已恢复原文件。'; return 1
  fi
  log_ok "geo 数据已更新：$tag（$(du -sh "$SBM_XRAY_ASSET_DIR" 2>/dev/null | awk '{print $1}')）"
)

xray_geo_remove_unlocked() {
  ! xray_geo_required || { log_error '路由规则仍在使用 geosite:/geoip:，请先删除这些规则。'; return 1; }
  rm -f -- "$SBM_XRAY_ASSET_DIR/geoip.dat" "$SBM_XRAY_ASSET_DIR/geosite.dat" "$SBM_XRAY_ASSET_DIR/version.json"
  rmdir "$SBM_XRAY_ASSET_DIR" 2>/dev/null || true
  log_ok '已删除 geo 数据。'
}

xray_geo_cli() {
  case "${1:-status}" in
    status) xray_geo_status;;
    update) require_root; with_lock _xray_geo_update;;
    remove) require_root; with_lock xray_geo_remove_unlocked;;
    *) usage_die '用法：xm xray geo status|update|remove';;
  esac
}
