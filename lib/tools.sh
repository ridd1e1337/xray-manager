#!/usr/bin/env bash
# shellcheck shell=bash

# Key/cert generators and checks (3x-ui "tools"), backed by the installed
# Xray binary so formats always match the running core.

tools_xray() {
  [[ -x "$SBM_XRAY_BIN" ]] || die 'Xray 尚未安装，请先运行 xm core update。'
  "$SBM_XRAY_BIN" "$@"
}

# Judge a REALITY target: TLS 1.3 with SNI, X25519MLKEM768 (required by
# current Xray REALITY clients), certificate covering the name, latency.
tools_reality_check() {
  local domain=${1:?用法：xm tools reality-check DOMAIN} out start ms ok=1 section name covered=0
  validate_domain "$domain" || die "无效域名：$domain"
  [[ -x "$SBM_XRAY_BIN" ]] || die 'Xray 尚未安装，请先运行 xm core update。'
  start=${EPOCHREALTIME/./}
  out=$(timeout 20 "$SBM_XRAY_BIN" tls ping "$domain" 2>&1) || true
  ms=$(( (${EPOCHREALTIME/./} - start) / 1000 ))
  section=$(awk '/Pinging with SNI/{f=1} f' <<<"$out")
  printf 'REALITY 目标检查：%s（耗时 %s ms）\n' "$domain" "$ms"
  if grep -q 'Handshake succeeded' <<<"$section"; then printf '  [通过] 带 SNI 握手成功\n'; else printf '  [失败] 带 SNI 握手失败\n'; ok=0; fi
  if grep -q 'TLS Version:.*TLS 1.3' <<<"$section"; then printf '  [通过] TLS 1.3\n'; else printf '  [失败] 不支持 TLS 1.3\n'; ok=0; fi
  if grep -q 'Post-Quantum key exchange:.*true' <<<"$section"; then printf '  [通过] 支持 X25519MLKEM768\n'
  else printf '  [失败] 不支持 X25519MLKEM768（Xray 26.9.8+ REALITY 需要）\n'; ok=0; fi
  for name in $(sed -n 's/.*allowed domains:[[:space:]]*\[\(.*\)\].*/\1/p' <<<"$section" | head -1); do
    [[ "$name" == "$domain" || ( "$name" == '*.'* && "${domain#*.}" == "${name#\*.}" ) ]] && covered=1
  done
  if (( covered )); then printf '  [通过] 证书覆盖该域名\n'; else printf '  [警告] 证书域名列表未包含 %s\n' "$domain"; fi
  if (( ok )); then log_ok "$domain 适合作为 REALITY 目标。"; else log_error "$domain 不适合作为 REALITY 目标。"; return 1; fi
}

# SHA-256 of a certificate for --pinned-cert-sha256: a PEM file or HOST[:PORT].
tools_cert_hash() {
  local target=${1:?用法：xm tools cert-hash FILE|HOST[:PORT]} host port
  if [[ -r "$target" ]]; then
    openssl x509 -in "$target" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f'; return $?
  fi
  host=${target%:*}; port=${target##*:}; [[ "$port" != "$target" ]] || port=443
  validate_port "$port" || die "无效端口：$port"
  timeout 15 openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f'
}

tools_cli() {
  local action=${1:-help}; shift || true
  case "$action" in
    uuid|x25519|wg|mldsa65|mlkem768|vlessenc) tools_xray "$action" "$@";;
    ech) tools_xray tls ech --serverName "${1:?用法：xm tools ech DOMAIN}";;
    reality-check) tools_reality_check "$@";;
    cert-hash) tools_cert_hash "$@";;
    *) usage_die '用法：xm tools uuid|x25519|wg|mldsa65|mlkem768|vlessenc|ech DOMAIN|reality-check DOMAIN|cert-hash FILE|HOST[:PORT]';;
  esac
}
