#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SOURCE_PATH=${BASH_SOURCE[0]}
while [[ -L "$SOURCE_PATH" ]]; do
  SOURCE_DIR=$(cd -P -- "$(dirname -- "$SOURCE_PATH")" && pwd)
  SOURCE_PATH=$(readlink "$SOURCE_PATH")
  [[ "$SOURCE_PATH" == /* ]] || SOURCE_PATH="$SOURCE_DIR/$SOURCE_PATH"
done
SELF_DIR=$(cd -P -- "$(dirname -- "$SOURCE_PATH")" && pwd)
SBM_LIB="${SBM_LIB:-$SELF_DIR}"
# shellcheck source=lib/common.sh
source "$SBM_LIB/lib/common.sh"
source "$SBM_LIB/lib/dependencies.sh"
source "$SBM_LIB/lib/service.sh"
source "$SBM_LIB/lib/state.sh"
source "$SBM_LIB/lib/nginx_stream.sh"
source "$SBM_LIB/lib/mux.sh"
source "$SBM_LIB/lib/website_mux.sh"
source "$SBM_LIB/lib/caddy.sh"
source "$SBM_LIB/lib/maintenance.sh"
source "$SBM_LIB/protocols/vmess_ws_cf.sh"
source "$SBM_LIB/protocols/hysteria2.sh"
source "$SBM_LIB/protocols/vless.sh"
source "$SBM_LIB/protocols/proxy.sh"
source "$SBM_LIB/lib/render.sh"
source "$SBM_LIB/lib/xray.sh"
source "$SBM_LIB/lib/vless_profile.sh"
source "$SBM_LIB/lib/vless_config.sh"
source "$SBM_LIB/lib/openlist.sh"
source "$SBM_LIB/lib/reality_site.sh"
source "$SBM_LIB/lib/core.sh"
source "$SBM_LIB/lib/manager.sh"
source "$SBM_LIB/lib/node.sh"
source "$SBM_LIB/lib/traffic.sh"
source "$SBM_LIB/lib/traffic_groups.sh"
source "$SBM_LIB/lib/shaping.sh"
source "$SBM_LIB/lib/expiry.sh"
source "$SBM_LIB/lib/user_limits.sh"
source "$SBM_LIB/lib/xray_routing.sh"
source "$SBM_LIB/lib/xray_geo.sh"
source "$SBM_LIB/lib/xray_outsub.sh"
source "$SBM_LIB/lib/tools.sh"
source "$SBM_LIB/lib/telegram_bot.sh"
source "$SBM_LIB/lib/firewall.sh"
source "$SBM_LIB/lib/vps.sh"
source "$SBM_LIB/lib/notification.sh"
source "$SBM_LIB/lib/health.sh"
source "$SBM_LIB/lib/status.sh"
source "$SBM_LIB/lib/export.sh"
source "$SBM_LIB/lib/compat.sh"
source "$SBM_LIB/lib/cert.sh"
source "$SBM_LIB/lib/public_ip.sh"
source "$SBM_LIB/lib/tunnel.sh"
source "$SBM_LIB/lib/tunnel_routes.sh"
source "$SBM_LIB/lib/subscription.sh"
source "$SBM_LIB/lib/substore.sh"
source "$SBM_LIB/lib/substore_remote.sh"
source "$SBM_LIB/lib/bbr.sh"
source "$SBM_LIB/lib/hysteria2_tuning.sh"
source "$SBM_LIB/lib/tcp_tuning.sh"
source "$SBM_LIB/lib/network.sh"
source "$SBM_LIB/lib/benchmark.sh"
source "$SBM_LIB/lib/doctor.sh"
source "$SBM_LIB/lib/uninstall.sh"
source "$SBM_LIB/lib/ui.sh"
source "$SBM_LIB/lib/config.sh"
source "$SBM_LIB/lib/template.sh"

sb_help_full() {
  cat <<'EOF_HELP'
用法：
  xm                              打开交互面板
  xm [--json] [--yes] [--dry-run] [--quiet] <命令>  通用选项可放在命令前
  xm status [--json]              查看统一状态
  xm vps init [--dry-run]         新 VPS 一键安装 Caddy、UFW、Fail2ban 并放行基础端口
  xm vps status [--json]          查看 VPS 基础环境状态
  xm vps systems                 查看各功能支持的 Linux 系统与当前环境
  xm node list [--json] [--tag TAG] [--region REGION] 列出节点
  xm quick                       添加节点向导
  xm node add <vless|vmess|vmess-ws-cf|trojan|ss|hy2|wireguard|masque|tunnel|socks|http|mixed> [参数]
  xm node expiry ID [--days N|--at UTC_TIMESTAMP|--clear]
  xm node show <ID>
  xm node schema                 输出节点表单描述 JSON（协议与参数；供网页面板生成表单）
  xm panel schema                输出功能页描述 JSON（用户、流量、出站与分流、系统；供网页面板生成界面）
  xm node enable|disable|delete|rotate <ID>
  xm node clone SRC_ID NEW_ID [--port N] [--name NAME]   复制节点设置，重新生成凭据
  xm node set <ID> --port N|--address HOST|--domain DOMAIN|--name NAME|--path PATH|--listen IP
                 [--remark TEXT] [--region REGION] [--purpose PURPOSE] [--line LINE] [--tags a,b]
                 [--method METHOD] [--network tcp|udp] [--obfs salamander|none] [--masquerade URL]
                 传输（VLESS/VMess/Trojan/SS）：[--transport raw|ws|grpc|httpupgrade|xhttp|kcp|hysteria]
                 [--security none|tls|reality] [--host H] [--service-name N] [--xhttp-mode MODE]
                 [--tls-server-name SNI] [--fingerprint FP] [--alpn a,b] [--pinned-cert-sha256 HEX[,HEX]]
                 [--verify-name NAME[,NAME]] [--handshake-server DOMAIN] [--handshake-port N]
                 VLESS：[--flow FLOW] [--vless-auth x25519|mlkem768|none [--vless-auth-mode native|xorpub|random] | --vless-encryption E --vless-decryption D] [--packet-encoding xudp|packetaddr|none]
                 [--reality-mldsa65 true|false] [--ech DOMAIN|none]   自动生成 ML-DSA-65 / ECH 密钥
                 回落（VLESS/Trojan）：[--fallback-dest PORT|HOST:PORT|none] [--fallbacks JSON|@FILE|none]
                 [--sniffing on|route-only|off] [--sniff-dest http,tls,quic,fakedns]
                 [--tcp-fast-open true|false] [--accept-proxy-protocol true|false] [--sockopt-json JSON|@FILE]
                 [--transport-json JSON|@FILE] [--tls-json JSON|@FILE]
                 [--xray-inbound-json JSON|@FILE] [--xray-outbound-json JSON|@FILE]
  xm user list <NODE_ID>
  xm user add <NODE_ID> <USER_ID> [NAME]
  xm user add <NODE_ID> --count N [--prefix P] [--start K] [--quota 50G] [--days 30] [--ip-limit 2] [--reset-day 1]  批量添加
  xm user online [NODE_ID]        在线用户与 IP
  xm user purge-depleted [NODE_ID]  删除流量耗尽或已到期的用户
  xm user set-usage NODE_ID USER_ID SIZE   修改本周期已用流量
  xm user tg NODE_ID USER_ID TG_USER_ID|none   绑定 Telegram：用户私聊机器人 /me /link，并接收到期/流量预警
  xm user export NODE_ID USER_ID [文件] | import NODE_ID 文件 [新ID]   迁移用户（含凭据，客户端无需重导）
  xm user enable|disable|delete|rotate <NODE_ID> <USER_ID>
  xm user limit <NODE_ID> <USER_ID> [--quota SIZE|unlimited] [--reset-day 1-28|none]
                 [--days N|--expire-at UTC|--expire-after-first-use N|--no-expiry]
                 [--reset-period day|week|month] [--ip-limit N|unlimited] [--clear]
  xm user stats [NODE_ID] [--json] | reset-usage <NODE_ID> <USER_ID> | tick
  xm share <ID> [--user USER_ID] [--qr]
  xm share all
  xm export outbounds
  xm subscription create [7d|never] [mixed|tun|xray|mihomo] [--live] [--user NODE_ID:USER_ID] [--base-url HTTPS_URL]
  xm subscription list|status|revoke <ID_OR_TOKEN>
  xm subscription remark show|set TEMPLATE|clear   用户订阅节点名模板，如 '{name} | 剩余 {remaining} | {days} 天'
                                 订阅地址不带 ?format 时按客户端自动选择：Clash/mihomo、sing-box、v2rayN/Shadowrocket（base64）
  xm bbr enable|disable|status [--json]
  xm tcp plan|enable --bandwidth Mbps --rtt MS [--dry-run] [--json]
  xm tcp status [--json]|disable   TCP 自适应缓冲区、MTU 黑洞探测与恢复
  xm network ping HOST [--count 1-30] [--ipv4|--ipv6] [--json]
  xm network speed HOST [--port N] [--seconds 1-30] [--streams 1-16] [--direction up|down] [--json]
  xm network history [--json]|compare BEFORE AFTER [--json]
  xm hy2 buffer enable|disable|status [--json]
  xm mux status [--json]|enable [PORT] [--backend nginx|caddy]|disable|backend nginx|caddy|auto [NODE_IDS]
  xm mux route list|add NODE_ID SNI [BACKEND_PORT]|remove NODE_ID
  xm mux caddy                   导出现有 Caddy L4 的 HTTPS listener_wrappers 配置
  xm mux setup [--server auto|nginx|caddy] [--config FILE] [--binary FILE] [--build-caddy]
                                 一键接入现有网站，共用 443 并自动同步节点
  xm mux detach                  恢复接入前的网站配置，节点恢复独立端口
  xm caddy status|apt|manage|update [--check]|rollback
                                 Caddy 官方包接入、定制版升级与回滚
  xm maintenance status|run       查看/执行项目缓存与一天日志保留策略
  xm traffic group set ID --nodes NODE1,NODE2 --quota 500G [--reset-day 1] [--quota-mode total|download]
  xm traffic group status [--json]|remove ID|reset ID
  xm traffic shaping plan|enable IFACE --capacity 1G | disable | status [--json]
  xm traffic status [NODE_ID] [--json]
  xm traffic set NODE_ID [--quota 100G|unlimited] [--reset-day 1-28]
                 [--rate 50M|unlimited] [--upload-rate RATE] [--download-rate RATE]
                 [--quota-mode total|download]
  xm traffic disable|remove NODE_ID
  xm traffic reset NODE_ID|all [--yes]
  xm notify status|configure|disable|test|check
  xm notify bot enable --admin TG_USER_ID[,ID] | disable | status   Telegram 命令机器人
  xm health status|check|enable|disable [WARN_DAYS]
  xm health configure --disk-free N --memory-max N [...]
  xm config validate|diff [--json]

  xm cert setup-cloudflare [TOKEN] [ZONE_ID] [EMAIL]
  xm cert setup <cloudflare|aliyun|dnspod|namesilo> --email EMAIL [--stdin] [变量=值 …]
                                 配置 DNS-01 服务商；--stdin 从标准输入读取 变量=值（每行一个），凭据不进入进程列表
                                 变量：CF_Token | Ali_Key Ali_Secret | DP_Id DP_Key | Namesilo_Key
  xm cert status               以 JSON 输出当前 DNS 服务商、邮箱和可选服务商
  xm cert issue <DOMAIN> [EMAIL]
  xm cert list [--json]|renew|inspect <DOMAIN>|delete <DOMAIN>

  xm substore remote set -|https://域名/后端路径 [--name 来源名] [--display 显示名] [--tag 主节点库]
                                 接入已有的中心 Sub-Store：本机节点作为一个来源推送过去，节点变化后自动更新
  xm substore remote push|status [--json]|disable
  xm substore install|update [--version VERSION] [--frontend-version VERSION] [--port PORT]
  xm substore enable|disable|status [--json]|access|sync [NAME]|backup FILE|restore FILE
  xm substore source add NAME URL [COLLECTION]|list [--json]|remove NAME|check NAME
  xm tunnel managed UUID CREDENTIALS_JSON
  xm tunnel route list|add ID DOMAIN LOCAL_URL [PATH_REGEX]|remove ID
  xm tunnel fixed <NODE_ID> <DOMAIN> [TOKEN] [CLIENT_ADDRESS]
  xm tunnel quick <NODE_ID>
  xm tunnel refresh|set-token|status [--json]|stop

  xm settings show|refresh-ip|address <auto|HOST>
                                 refresh-ip：服务器换 IP 后更新公网地址、本机的 Cloudflare DNS 记录和分享链接（每 15 分钟也会自动检查）
  xm settings outbound-ip <prefer_ipv4|prefer_ipv6|ipv4_only>
  xm firewall status|ports|clear-iptables|ufw-allow [--yes]
  xm firewall fail2ban|ufw [--yes] [--dry-run]

  xm core check|update [VERSION]|capabilities|policy <manual|notify|patch|stable>|auto   Xray-core 管理
  xm xray status|config [文件]|api-port PORT
  xm xray traffic [--json|reset]  Xray 入站/出站累计流量
  xm xray routing [--json]         查看 Xray 出站、负载均衡与路由
  xm xray outbound add TAG --json JSON|@FILE [--via TAG] | remove TAG | test [TAG]
  xm xray outbound sub add NAME URL [--prefix P] [--balancer leastPing|leastLoad|random|roundRobin|none]
                     | list | refresh [NAME] | remove NAME   导入远程订阅为出站（每日自动刷新）
  xm xray warp [--tag warp] --register | --private-key KEY --address-v4 IP [--address-v6 IP] [--reserved a,b,c]
  xm xray balancer set TAG --selectors a,b [--strategy random|roundRobin|leastPing|leastLoad] [--fallback TAG] | remove TAG
  xm xray route add [--node ID] [--user NODE:USER] [--domain domain:x|geosite:cn] [--ip CIDR|geoip:cn] [--network tcp|udp] [--port P] --to TAG|balancer:TAG
  xm xray route remove INDEX | default direct|TAG|balancer:TAG | test DOMAIN|IP[:PORT]
  xm tools uuid|x25519|wg|mldsa65|mlkem768|vlessenc|ech DOMAIN   用当前 Xray 生成密钥/参数
  xm tools reality-check DOMAIN    检查网站是否适合作为 REALITY 目标
  xm tools cert-hash FILE|HOST[:PORT]  证书 SHA-256（用于 --pinned-cert-sha256）
  xm xray dns show|set SERVERS [--strategy UseIP|UseIPv4|UseIPv6] [--fakedns]|clear   Xray 内置 DNS
  xm xray route strategy AsIs|IPIfNonMatch|IPOnDemand   路由域名策略（geoip 规则匹配域名请求时用 IPIfNonMatch）
  xm xray log access on|off|status   访问日志（默认关闭）；xm logs access 查看
  xm xray geo status|update|remove  geoip/geosite 数据（约 28 MiB，按需下载），启用 geosite:/geoip: 规则
  xm openlist status|install|update|setup DOMAIN [caddy|nginx]|detach DOMAIN
  xm reality status|setup DOMAIN [nginx|caddy] [--node ID] [--init-vps]|detach
  xm vps reality DOMAIN [nginx|caddy] [--node ID]  一键部署 OpenList、Reality 与基础防护
  xm update [--check]             更新管理脚本与受管 Caddy
  xm update auto enable|disable|status [--json]|run  每日更新脚本与受管 Caddy
  xm cloudflared status|install|update|policy <manual|notify|patch|stable>
  xm deps status [--json]|install <low-port|traffic|subscription|bbr|probe|scheduler|logrotate|benchmark|shaping|substore>
  xm acme update
  xm logs [all|xray|access|tunnel|mux|nginx|follow] [行数]
  xm restart
  xm uninstall [--purge] [--yes]

节点添加常用参数：
  --id ID --name NAME --port PORT --domain DOMAIN --address HOST
  --uuid UUID --password PASSWORD --short-id HEX   指定首个用户的凭据 / Reality Short ID（默认自动生成）
  TLS:   没有可用证书时自动创建 Cloudflare DNS only 记录并签发证书。
         CLI 请先执行 xm cert setup-cloudflare；已有冲突 DNS 会被拒绝，--disabled 不申请证书。
  VLESS/VMess/Trojan/SS：--transport … --security … 见 xm node set；Trojan/VLESS 可用 Reality。
  VMess-WS-CF：--path PATH（配合 Cloudflare Tunnel）
  SS:    --method 2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305
         |aes-128-gcm|aes-256-gcm|chacha20-ietf-poly1305|xchacha20-ietf-poly1305 --network tcp|udp
  HY2:   --obfs salamander --masquerade URL --udp-idle-timeout 2-600
         --quic-congestion reno|bbr|brutal|force-brutal --quic-idle-timeout N --quic-keepalive N
  HTTP:  --allow-transparent true|false
  WireGuard：--subnet 10.x.y.0/24 --mtu 1420（每个用户一个 peer）
  MASQUE：--domain DOMAIN --subnet 10.x.y.0/24 --mtu 1280（HTTP/3 connect-ip）
  Tunnel：--target HOST:PORT --network tcp|udp|tcp,udp [--follow-redirect] [--port-map 端口=主机:端口,…|none]
  SOCKS5/HTTP/mixed: --listen 127.0.0.1|::1|0.0.0.0|::（默认本机，自动生成认证）
  Xray 扩展：--xray-inbound-json JSON|@FILE 可写入任意 Xray 入站字段（sniffing、streamSettings、
             sockopt、finalmask 等）；protocol、tag、端口、用户和凭据由管理器保护。
  通用:  --disabled --remark TEXT --region REGION --purpose PURPOSE --line LINE --tags a,b
EOF_HELP
}

SBM_HELP_TOPICS='status node panel quick user share export subscription substore tunnel cert traffic notify health tcp bbr hy2 network vps firewall mux caddy maintenance settings core xray openlist reality update cloudflared deps acme config tools logs restart uninstall'

sb_help_overview() {
  cat <<EOF_OVERVIEW
xray-manager ${SBM_VERSION}：状态驱动的 Xray-core 多协议管理器

用法：xm [通用选项] <命令> [参数]
直接运行 xm 打开交互面板，新手推荐从面板开始。

常用：
  status        查看服务和节点状态
  quick         添加节点向导
  node          添加、修改、启停和删除节点
  share         显示节点分享链接、二维码或客户端配置
  user          管理多用户节点的用户
  update        更新管理脚本与受管 Caddy
  logs          查看运行日志

节点与客户端：export  subscription  substore  tunnel  cert
流量与监控：  traffic  notify  health  probe
网络调优：    tcp  bbr  hy2  network
服务器与网站：vps  firewall  mux  caddy  openlist  reality  maintenance  settings
核心与维护：  core  xray  tools  cloudflared  deps  acme  config
重启与卸载：  restart  uninstall

通用选项：--json  --yes|-y  --dry-run  --quiet|-q  --no-color  --version

查看某个命令的完整用法：xm help <命令>（或 xm <命令> --help）
查看全部命令：          xm help all
EOF_OVERVIEW
}

sb_help_canonical_topic() {
  case "$1" in
    hysteria2) printf 'hy2';; nginx-stream) printf 'mux';; quick) printf 'node';;
    *) printf '%s' "$1";;
  esac
}

sb_help_is_topic() {
  local topic
  for topic in $SBM_HELP_TOPICS hysteria2 nginx-stream; do [[ "$topic" == "$1" ]] && return 0; done
  return 1
}

sb_help_topic() {
  local topic
  topic=$(sb_help_canonical_topic "$1")
  printf 'xm %s 用法：\n' "$topic"
  sb_help_full | awk -v topic="$topic" '
    /^用法：/ { in_usage=1; next }
    /^节点添加常用参数：/ { in_usage=0; in_params=1 }
    in_usage && /^  xm / {
      split($0, words, " "); cmd=words[2]
      current = (cmd == topic || (topic == "node" && (cmd == "quick" || cmd == "user")) || (topic == "doctor" && (cmd == "repair" || cmd == "probe")) || (topic == "backup" && cmd == "restore"))
      if (current) print
      next
    }
    in_usage && /^ +[^ ]/ { if (current) print; next }
    in_usage { current=0; next }
    in_params && topic == "node" { print }
  '
}

sb_suggest_command() {
  local input=$1 best
  best=$(printf '%s\n' $SBM_HELP_TOPICS help version | awk -v input="$input" '
    function min3(a, b, c) { m=a; if (b<m) m=b; if (c<m) m=c; return m }
    function dist(s, t,   i, j, n, m, cost, d) {
      n=length(s); m=length(t)
      for (i=0; i<=n; i++) d[i,0]=i
      for (j=0; j<=m; j++) d[0,j]=j
      for (i=1; i<=n; i++) for (j=1; j<=m; j++) {
        cost=(substr(s,i,1)==substr(t,j,1)) ? 0 : 1
        d[i,j]=min3(d[i-1,j]+1, d[i,j-1]+1, d[i-1,j-1]+cost)
      }
      return d[n,m]
    }
    { k=dist(input, $0); if (index($0, input) == 1 && length(input) >= 2) k=0
      if (best == "" || k < bestd) { best=$0; bestd=k } }
    END { limit=(length(input) <= 4) ? 1 : 2; if (best != "" && bestd <= limit) print best }
  ')
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}

sb_help() {
  local topic=${1:-}
  case "$topic" in
    '') sb_help_overview ;;
    all) printf 'xray-manager %s：状态驱动的 Xray-core 多协议管理器\n\n' "$SBM_VERSION"; sb_help_full ;;
    *)
      if sb_help_is_topic "$topic"; then sb_help_topic "$topic"; return 0; fi
      local guess; guess=$(sb_suggest_command "$topic")
      usage_die "没有 $topic 的帮助${guess:+；您是否想查看：xm help $guess}。运行 xm help 查看命令列表。"
      ;;
  esac
}

main() {
  local cli_json=0 cli_yes=0 cli_dry_run=0 cli_quiet=0
  while (($#)); do
    case "$1" in
      --json) cli_json=1; shift;; --yes|-y) cli_yes=1; shift;; --dry-run) cli_dry_run=1; shift;; --quiet|-q) cli_quiet=1; shift;; --no-color) NO_COLOR=1; shift;; *) break;;
    esac
  done
  export SBM_OUTPUT_JSON=$cli_json SBM_ASSUME_YES=$cli_yes SBM_DRY_RUN=$cli_dry_run SBM_QUIET=$cli_quiet
  if [[ ${NO_COLOR:-} != "" ]]; then C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; fi
  local cmd=${1:-menu}
  if [[ "$cmd" != menu && "$cmd" != help ]] && sb_help_is_topic "$cmd"; then
    case "${2:-}" in -h|--help|help) sb_help "$cmd"; return 0;; esac
    case "${3:-}" in -h|--help) sb_help "$cmd"; return 0;; esac
  fi
  if [[ "$cmd" != menu && "$cmd" != __ui-step ]] && ! sb_help_is_topic "$cmd"; then
    case "$cmd" in
      -h|--help|help|-V|--version|version|uninstall) ;;
      *)
        local guess; guess=$(sb_suggest_command "$cmd")
        usage_die "未知命令：$cmd${guess:+；您是否想输入：xm $guess}。运行 xm help 查看命令列表。"
        ;;
    esac
  fi
  if sb_help_is_topic "$cmd"; then SBM_HELP_CONTEXT=$(sb_help_canonical_topic "$cmd"); fi
  case "$cmd" in
    -h|--help|help) shift || true; sb_help "${1:-}"; return 0;;
    -V|--version|version) printf 'xray-manager %s\n' "$SBM_VERSION"; return 0;;
    tcp) shift; require_command jq; tcp_tuning_cli "$@"; return $?;;
    network) shift; require_command jq; network_cli "$@"; return $?;;
    update) shift; manager_update_cli "$@"; return $? ;;
    vps) shift; vps_cli "$@"; return $? ;;
    maintenance) shift; require_root; maintenance_cli "$@"; return $? ;;
    uninstall)
      require_root
      local purge=0 assume_yes=${SBM_ASSUME_YES:-0} arg
      shift
      for arg in "$@"; do
        case "$arg" in --purge) purge=1;; --yes|-y) assume_yes=1;; *) die "未知卸载参数：$arg";; esac
      done
      uninstall_manager "$purge" "$assume_yes"
      return 0
      ;;
  esac

  require_root
  require_command jq; require_command openssl; require_command flock
  if [[ ${SBM_SKIP_STATE_INIT:-0} != 1 || "$cmd" != cert || ${2:-} != hook ]]; then
    state_init
  fi

  case "$cmd" in
    menu) ui_main ;;
    quick)
      ui_menu_loop ui_add_node
      case ${SBM_UI_RESULT:-0} in 203) ui_reload;; 0|206) ui_main;; esac
      ;;
    __ui-step) shift; ui_worker "$@" ;;
    substore) shift; substore_cli "$@" ;;
    status)
      local json=${SBM_OUTPUT_JSON:-0} arg
      shift
      while (($#)); do case "$1" in --json) json=1; shift;; *) usage_die '用法：xm status [--json]';; esac; done
      if (( json )); then
        local status_data
        status_data=$(status_json); printf '%s\n' "$status_data"; status_exit_code "$status_data"
      else
        status_summary
      fi
      ;;
    panel)
      # Feature pages for the web panel: what to show and which commands each
      # button runs.  The panel renders this as-is, so a new feature only needs
      # an entry in schemas/panel.json.
      [[ ${2:-} == schema && $# == 2 ]] || usage_die '用法：xm panel schema'
      jq --arg version "$SBM_VERSION" '. + {manager_version:$version}' "$SBM_LIB/schemas/panel.json"
      ;;
    node)
      local action=${2:-list}; shift 2 || true
      case "$action" in
        list)
          local json=${SBM_OUTPUT_JSON:-0} tag='' region='' arg
          while (($#)); do
            case "$1" in --json) json=1; shift;; --tag) tag=${2:?缺少标签}; shift 2;; --region) region=${2:?缺少地区}; shift 2;; *) usage_die '用法：xm node list [--json] [--tag TAG] [--region REGION]';; esac
          done
          node_list "$json" "$tag" "$region"
          ;;
        expiry) node_expiry_cli "$@" ;;
        schema) (($# == 0)) || usage_die '用法：xm node schema'; node_schema ;;
        compat) [[ "${2:-}" != --json ]] || SBM_OUTPUT_JSON=1; node_compat "${1:?用法：xm node compat ID [--json]}" "${SBM_OUTPUT_JSON:-0}" ;;
        add) (($# >= 1)) || die '缺少协议'; node_add "$@" ;;
        show) [[ $# == 1 || ( $# == 2 && $2 == --json ) ]] || usage_die '用法：xm node show ID [--json]'; node_show "$1" "$([[ ${2:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)" ;;
        enable) node_enable "${1:?缺少节点 ID}" ;;
        disable) node_disable "${1:?缺少节点 ID}" ;;
        delete) node_delete "${1:?缺少节点 ID}" ;;
        rotate) node_rotate "${1:?缺少节点 ID}" ;;
        set)
          local id=${1:?缺少节点 ID}; shift; local -a set_args=() set_arg
          while (($#)); do if [[ "$1" == --dry-run ]]; then export SBM_DRY_RUN=1; shift; else set_args+=("$1"); shift; fi; done
          (( ${#set_args[@]} >= 2 )) || usage_die '缺少修改参数'; node_set "$id" "${set_args[@]}"
          ;;
        clone) (($# >= 2)) || usage_die '用法：xm node clone SRC_ID NEW_ID [--port N] [--name NAME] [--domain DOMAIN]'; node_clone "$@" ;;
        *) usage_die "未知 node 操作：$action" ;;
      esac
      ;;
    firewall)
      local action=${2:-ports} assume_yes=${SBM_ASSUME_YES:-0} dry_run=${SBM_DRY_RUN:-0} json=${SBM_OUTPUT_JSON:-0} arg
      shift 2 || true
      while (($#)); do
        case "$1" in --yes|-y) assume_yes=1; shift;; --dry-run) dry_run=1; shift;; --json) json=1; shift;; *) usage_die '用法：xm firewall status|ports|clear-iptables|ufw-allow|fail2ban|ufw [--yes] [--dry-run] [--json]';; esac
      done
      [[ "$dry_run" == 0 || "$action" == ufw || "$action" == setup-ufw ]] || die '--dry-run 仅适用于 xm firewall ufw。'
      case "$action" in
        status) firewall_status "$json" ;;
        ports|list) firewall_list_protocol_ports "$json" ;;
        clear-iptables) firewall_clear_iptables_input_deny "$assume_yes" ;;
        ufw-allow) firewall_ufw_allow_protocol_ports "$assume_yes" ;;
        fail2ban|setup-fail2ban) firewall_setup_fail2ban "$assume_yes" ;;
        ufw|setup-ufw) firewall_setup_ufw "$assume_yes" "$dry_run" ;;
        *) usage_die '用法：xm firewall status|ports|clear-iptables|ufw-allow|fail2ban|ufw [--yes]' ;;
      esac
      ;;
    user)
      local action=${2:-list}; shift 2 || true
      case "$action" in
        list) (($# >= 1)) || die '缺少节点 ID'; node_user_list "$1" "$([[ ${2:-} == --json ]] && echo 1 || echo 0)" ;;
        add)
          if [[ "${2:-}" == --count ]]; then
            # xm user add NODE --count N [--prefix P] [--start K] [--quota ..] [--days ..] [--ip-limit ..] [--reset-day ..]
            local b_node=$1 b_count=${3:?缺少数量} b_prefix=user b_start=1; shift 3
            local -a b_rest=()
            while (($#)); do case "$1" in --prefix) b_prefix=${2:?}; shift 2;; --start) b_start=${2:?}; shift 2;; *) b_rest+=("$1"); shift;; esac; done
            node_user_batch_add "$b_node" "$b_prefix" "$b_count" "$b_start" "${b_rest[@]}"
          else
            (($# >= 2)) || die '用法：xm user add NODE_ID USER_ID [NAME] | xm user add NODE_ID --count N [--prefix P]'; node_user_add "$1" "$2" "${3:-$2}"
          fi ;;
        purge-depleted) node_user_purge_depleted "${1:-}" ;;
        tg) (($# == 3)) || die '用法：xm user tg NODE_ID USER_ID TG_USER_ID|none'; user_tg_set "$1" "$2" "$3" ;;
        set-usage) (($# == 3)) || die '用法：xm user set-usage NODE_ID USER_ID SIZE'; user_usage_set "$1" "$2" "$3" ;;
        export) (($# >= 2)) || die '用法：xm user export NODE_ID USER_ID [文件]'; user_export "$1" "$2" "${3:-}" ;;
        import) (($# >= 2)) || die '用法：xm user import NODE_ID 文件 [新用户ID]'; user_import "$1" "$2" "${3:-}" ;;
        online) user_online "${1:-}" ;;
        enable) (($# == 2)) || die '用法：xm user enable NODE_ID USER_ID'; node_user_enable "$1" "$2" ;;
        disable) (($# == 2)) || die '用法：xm user disable NODE_ID USER_ID'; node_user_disable "$1" "$2" ;;
        delete) (($# == 2)) || die '用法：xm user delete NODE_ID USER_ID'; node_user_delete "$1" "$2" ;;
        rotate) (($# == 2)) || die '用法：xm user rotate NODE_ID USER_ID'; node_rotate "$1" "$2" ;;
        limit) user_limit_cli "$@" ;;
        stats)
          local stats_node='' stats_json=0
          while (($#)); do case "$1" in --json) stats_json=1; shift;; *) [[ -z "$stats_node" ]] || usage_die '用法：xm user stats [NODE_ID] [--json]'; stats_node=$1; shift;; esac; done
          user_stats "$stats_node" "$stats_json" ;;
        reset-usage) (($# == 2)) || die '用法：xm user reset-usage NODE_ID USER_ID'; user_usage_reset "$1" "$2" ;;
        tick) (($# == 0)) || die '用法：xm user tick'; user_limits_tick ;;
        *) usage_die "未知 user 操作：$action" ;;
      esac
      ;;
    share)
      local id=${2:-all} qr=0 user_id='' arg
      shift 2 || true
      while (($#)); do
        case "$1" in --qr) qr=1; shift;; --user) user_id=${2:?缺少用户 ID}; shift 2;; *) die "未知分享参数：$1";; esac
      done
      [[ "$id" == all ]] && node_share_all || node_share "$id" "$qr" "$user_id"
      ;;
    export)
      case ${2:-outbounds} in
        outbounds) export_all_outbounds ;;
        *) die '当前支持：xm export outbounds' ;;
      esac
      ;;
    cert)
      local action=${2:-list}
      case "$action" in
        setup-cloudflare) cert_setup_cloudflare "${3:-}" "${4:-}" "${5:-}" ;;
        setup) cert_setup "${@:3}" ;;
        status) cert_status_json ;;
        issue) cert_issue "${3:?缺少域名}" "${4:-}" ;;
        list) [[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && cert_list_json || cert_list ;;
        renew) cert_renew "$([[ ${3:-} == --quiet ]] && echo 1 || echo 0)" ;;
        inspect) cert_inspect "${3:?缺少域名}" ;;
        delete) cert_delete "${3:?缺少域名}" ;;
        hook) cert_hook "${3:?缺少域名}" ;;
        *) usage_die "未知 cert 操作：$action" ;;
      esac
      ;;
    tunnel)
      if [[ ${2:-} == managed || ${2:-} == route ]]; then shift; tunnel_routes_cli "$@"; return $?; fi
      local action=${2:-status}
      case "$action" in
        fixed) tunnel_setup_fixed "${3:?缺少节点 ID}" "${4:?缺少域名}" "${5:-}" "${6:-}" ;;
        quick) tunnel_setup_quick "${3:?缺少节点 ID}" ;;
        refresh) tunnel_refresh_quick ;;
        refresh-auto) tunnel_refresh_auto ;;
        set-token) tunnel_set_token "${3:-}" ;;
        status) tunnel_status "$([[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)" ;;
        stop) tunnel_stop ;;
        *) usage_die "未知 tunnel 操作：$action" ;;
      esac
      ;;
    subscription)
      local action=${2:-status}
      case "$action" in
        create) shift 2; subscription_create_cli "$@" ;;
        list) subscription_list "$([[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)" ;;
        status) subscription_status "$([[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)" ;;
        revoke) [[ $# == 3 ]] || usage_die '用法：xm subscription revoke ID_OR_TOKEN'; subscription_revoke "$3" ;;
        remark) shift 2; subscription_remark_cli "$@" ;;
        *) usage_die '用法：xm subscription create [7d|never] [mixed|tun|xray|mihomo] [--live] [--user NODE_ID:USER_ID] [--base-url HTTPS_URL] | list | status | revoke ID_OR_TOKEN' ;;
      esac
      ;;
    bbr)
      local action=${2:-status}
      case "$action" in
        enable) (($# == 2)) || usage_die '用法：xm bbr enable'; bbr_enable;;
        disable) (($# == 2)) || usage_die '用法：xm bbr disable'; bbr_disable;;
        status) (($# <= 3)) || usage_die '用法：xm bbr status [--json]'; bbr_status "$([[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)";;
        *) usage_die '用法：xm bbr enable|disable|status [--json]';;
      esac
      ;;
    hy2|hysteria2)
      [[ ${2:-} == buffer || ${2:-} == udp-buffer ]] || usage_die '用法：xm hy2 buffer enable|disable|status [--json]'
      local buffer_action=${3:-status}
      case "$buffer_action" in
        enable) (($# == 3)) || usage_die '用法：xm hy2 buffer enable'; hy2_udp_buffer_enable;;
        disable) (($# == 3)) || usage_die '用法：xm hy2 buffer disable'; hy2_udp_buffer_disable;;
        status) (($# <= 4)) || usage_die '用法：xm hy2 buffer status [--json]'; hy2_udp_buffer_status "$([[ ${4:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)";;
        *) usage_die '用法：xm hy2 buffer enable|disable|status [--json]';;
      esac
      ;;
    caddy) shift; caddy_cli "$@" ;;
    mux|nginx-stream)
      mux_cli "$@"
      ;;
    traffic)
      if [[ ${2:-} == shaping ]]; then shift 2; shaping_cli "$@"; return $?; fi
      if [[ ${2:-} == group ]]; then shift 2; traffic_group_cli "$@"; return $?; fi
      local action=${2:-status}
      case "$action" in
        status)
          local target=all json=${SBM_OUTPUT_JSON:-0} arg
          shift 2 || true
          for arg in "$@"; do
            case "$arg" in --json) json=1;; *) [[ "$target" == all ]] || usage_die '用法：xm traffic status [NODE_ID] [--json]'; target=$arg;; esac
          done
          traffic_status "$target" "$json"
          ;;
        set)
          local id=${3:?缺少节点 ID}; shift 3; local -a traffic_args=()
          while (($#)); do if [[ "$1" == --dry-run ]]; then export SBM_DRY_RUN=1; shift; else traffic_args+=("$1"); shift; fi; done
          traffic_set "$id" "${traffic_args[@]}"
          ;;
        disable) (($# == 3)) || die '用法：xm traffic disable NODE_ID'; traffic_disable "$3" ;;
        remove) (($# == 3)) || die '用法：xm traffic remove NODE_ID'; traffic_remove "$3" ;;
        reset)
          local target=${3:?缺少节点 ID} assume_yes=${SBM_ASSUME_YES:-0}
          if (($# != 3)) && ! { (($# == 4)) && [[ ${4:-} == --yes || ${4:-} == -y ]]; }; then
            usage_die '用法：xm traffic reset NODE_ID|all [--yes]'
          fi
          (($# == 3 && ${SBM_ASSUME_YES:-0} != 1)) || assume_yes=1
          if [[ "$assume_yes" == 1 ]] || confirm "确认清零 $target 的本周期流量统计？" N; then traffic_reset "$target"; fi
          ;;
        reconcile) (($# == 2)) || die '用法：xm traffic reconcile'; traffic_reconcile ;;
        sync) (($# == 2)) || die '用法：xm traffic sync'; traffic_checkpoint ;;
        tick) (($# == 2)) || die '用法：xm traffic tick'; traffic_tick ;;
        *) usage_die '用法：xm traffic status|set|disable|remove|reset' ;;
      esac
      ;;
    notify)
      local action=${2:-status}; shift 2 || true
      case "$action" in
        status)
          (($# == 0)) || { (($# == 1)) && [[ ${1:-} == --json ]]; } || usage_die '用法：xm notify status [--json]'
          notification_status "$([[ ${1:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)"
          ;;
        configure)
          local provider=${1:?缺少通知渠道}; shift
          notification_configure_cli "$provider" "$@"
          ;;
        disable) (($# == 0)) || usage_die '用法：xm notify disable'; notification_disable ;;
        test) (($# == 0)) || usage_die '用法：xm notify test'; notification_test ;;
        check) (($# == 0)) || usage_die '用法：xm notify check'; with_lock notification_traffic_check_unlocked ;;
        bot) telegram_bot_cli "$@" ;;
        *) usage_die '用法：xm notify status|configure|disable|test|check|bot';;
      esac
      ;;
    health)
      local action=${2:-status}; shift 2 || true
      case "$action" in
        status)
          (($# == 0)) || { (($# == 1)) && [[ ${1:-} == --json ]]; } || usage_die '用法：xm health status [--json]'
          health_status "$([[ ${1:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)"
          ;;
        check)
          (($# == 0)) || { (($# == 1)) && [[ ${1:-} == --json ]]; } || usage_die '用法：xm health check [--json]'
          health_check "$([[ ${1:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)"
          ;;
        enable) (($# <= 1)) || usage_die '用法：xm health enable [证书预警天数]'; health_enable "${1:-}" ;;
        disable) (($# == 0)) || usage_die '用法：xm health disable'; health_disable ;;
        configure) (($# >= 2)) || usage_die '用法：xm health configure --disk-free N --memory-max N [...]'; health_configure_resources "$@" ;;
        tick) (($# == 0)) || usage_die '用法：xm health tick'; health_tick ;;
        *) usage_die '用法：xm health status|check|enable|disable [WARN_DAYS]';;
      esac
      ;;
    core)
      local action=${2:-check}
      case "$action" in
        check) local rc=0; core_check_update || rc=$?; [[ "$rc" == 0 || "$rc" == 10 ]] || return "$rc" ;;
        update) core_update "${3:-latest}" ;;
        capabilities) (($# <= 3)) || usage_die '用法：xm core capabilities'; core_capabilities ;;
        policy) core_set_policy "${3:?缺少策略}" ;;
        auto) core_auto_update ;;
        *) usage_die "未知 core 操作：$action" ;;
      esac
      ;;
    xray)
      local action=${2:-status}
      case "$action" in
        status) xray_status ;;
        install|update) core_update "${3:-latest}" ;;
        config)
          (($# <= 3)) || usage_die '用法：xm xray config [文件]'
          [[ -x "$SBM_XRAY_BIN" ]] || die 'Xray 尚未安装，请先运行 xm core update。'
          with_lock xray_render_validate "${3:-$SBM_CONFIG}"
          log_ok "Xray 配置已生成：${3:-$SBM_CONFIG}"
          ;;
        policy) core_set_policy "${3:?缺少策略}" ;;
        api-port) (($# == 3)) || usage_die '用法：xm xray api-port PORT'; xray_set_api_port "$3" ;;
        routing) xray_routing_cli show "${3:-}" ;;
        outbound|balancer|route) shift 1; xray_routing_cli "$@" ;;
        warp) shift 2; xray_warp_cli "$@" ;;
        geo) shift 2; xray_geo_cli "$@" ;;
        dns) shift 2; xray_dns_cli "$@" ;;
        log) [[ "${3:-}" == access ]] || usage_die '用法：xm xray log access on|off|status'; xray_access_log_cli "${4:-status}" ;;
        traffic)
          case "${3:-}" in
            ''|--json) xray_traffic "$([[ ${3:-} == --json ]] && echo 1 || echo 0)" ;;
            reset) xray_traffic_reset ;;
            *) usage_die '用法：xm xray traffic [--json|reset]' ;;
          esac ;;
        *) usage_die '用法：xm xray status|update|config|policy <manual|notify|patch|stable>|api-port PORT|traffic|routing|outbound|warp|balancer|route|geo' ;;
      esac
      ;;
    tools) shift; tools_cli "$@" ;;
    openlist)
      local action=${2:-status}
      case "$action" in
        status) (($# <= 2)) || usage_die '用法：xm openlist status'; openlist_status ;;
        install) (($# == 2)) || usage_die '用法：xm openlist install'; openlist_install ;;
        update) (($# == 2)) || usage_die '用法：xm openlist update'; openlist_update ;;
        detach) (($# == 3)) || usage_die '用法：xm openlist detach DOMAIN'; openlist_detach "$3" ;;
        setup)
          (($# >= 3 && $# <= 4)) || usage_die '用法：xm openlist setup DOMAIN [caddy|nginx]'
          openlist_setup "$3" "${4:-caddy}"
          ;;
        *) usage_die '用法：xm openlist status|install|update|setup DOMAIN [caddy|nginx]|detach DOMAIN' ;;
      esac
      ;;
    reality) shift; reality_site_cli "$@" ;;
    cloudflared)
      local action=${2:-status}
      case "$action" in
        status)
          (($# <= 3)) || usage_die '用法：xm cloudflared status [--json]'
          if [[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]]; then
            local installed=false version=''
            if [[ -x "$SBM_CLOUDFLARED_BIN" ]]; then installed=true; version=$(cloudflared_current_version || true); fi
            jq -n --argjson installed "$installed" --arg version "$version" --arg path "$SBM_CLOUDFLARED_BIN" \
              '{installed:$installed,version:(if $version=="" then null else $version end),path:$path}'
          elif [[ -x "$SBM_CLOUDFLARED_BIN" ]]; then
            printf 'cloudflared：%s\n路径：%s\n' "$(cloudflared_current_version || printf '未知版本')" "$SBM_CLOUDFLARED_BIN"
          else
            printf 'cloudflared：未安装（按需执行 xm cloudflared install）\n'
          fi
          ;;
        install) (($# == 2)) || usage_die '用法：xm cloudflared install'; cloudflared_install ;;
        update) (($# == 2)) || usage_die '用法：xm cloudflared update'; cloudflared_update ;;
        policy) (($# == 3)) || usage_die '用法：xm cloudflared policy <manual|notify|patch|stable>'; cloudflared_set_policy "$3" ;;
        *) usage_die '用法：xm cloudflared status|install|update|policy <manual|notify|patch|stable>' ;;
      esac
      ;;
    deps)
      local action=${2:-status} json=0 feature
      case "$action" in
        status)
          [[ ${3:-} == --json ]] && json=1
          (($# <= 3)) || usage_die '用法：xm deps status [--json]'
          dependency_status "$json"
          ;;
        install)
          feature=${3:?缺少功能名}
          (($# == 3)) || usage_die '用法：xm deps install FEATURE'
          dependency_require_feature "$feature" || die "无法准备功能依赖：$feature"
          log_ok "功能依赖已就绪：$feature"
          ;;
        *) usage_die '用法：xm deps status [--json]|install FEATURE' ;;
      esac
      ;;
    acme) [[ ${2:-} == update ]] || usage_die '用法：xm acme update'; acme_update ;;
    config)
      local action=${2:-validate}; shift 2 || true
      case "$action" in
        validate)
          [[ $# == 0 || ( $# == 1 && $1 == --json ) ]] || usage_die '用法：xm config validate [--json]'
          config_validate "$([[ ${1:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)"
          ;;
        diff)
          [[ $# == 0 || ( $# == 1 && $1 == --json ) ]] || usage_die '用法：xm config diff [--json]'
          config_diff "$([[ ${1:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)"
          ;;
        *) usage_die '用法：xm config validate|diff [--json]' ;;
      esac
      ;;
    logs) show_logs "${2:-all}" "${3:-100}" ;;
    restart) runtime_services_reconcile; nginx_stream_reconcile; traffic_reconcile; [[ $(jq -r '.tunnel.mode' "$SBM_STATE") != none ]] && service_try_restart "$SBM_TUNNEL_SERVICE"; status_summary ;;
    settings)
      case ${2:-show} in
        show) settings_show_addresses "$([[ ${3:-} == --json || ${SBM_OUTPUT_JSON:-0} == 1 ]] && echo 1 || echo 0)" ;;
        detect-ip|refresh-ip) public_ip_refresh ;;
        address) settings_set_default_address "${3:?缺少地址}" ;;
        outbound-ip) settings_set_outbound_ip_strategy "${3:?缺少出站 IP 策略}" ;;
        *) usage_die '用法：xm settings show|refresh-ip|address <auto|HOST>|outbound-ip <prefer_ipv4|prefer_ipv6|ipv4_only>' ;;
      esac
      ;;
    *) usage_die "未知命令：$cmd；运行 xm help 查看帮助。" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
