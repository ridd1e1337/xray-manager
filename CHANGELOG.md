# Changelog

xray-manager 由 sb-manager 0.1.0-alpha.82 拆分而来，此后独立编号；之前的历史见 sb-manager 仓库。

## Unreleased

## 0.1.0-alpha.16

- xray-manager 只使用 Xray：移除 sing-box 内置 TCP/SNI 复用后端（只保留 nginx/caddy/nginx-site，旧状态自动改为 nginx）、
  对 sing-box 进程的端口识别、`xm api`/`xm realm`/`settings dns` 的专用提示、安装与卸载中的 sing-box 服务名、
  Alpine 依赖中的 gcompat（Xray 与 cloudflared 均为静态程序）；导出 sing-box 客户端配置时不再调用本机 sing-box 检查。
  sing-box 仍作为客户端格式之一保留在分享与订阅中。

## 0.1.0-alpha.15

- 性能：状态内容与版本都未变化时跳过启动时的迁移、校验与凭据检查（`/run/xray-manager/.state-ready`），只读命令与面板每页更快；
  状态页并行探测 UFW/Fail2ban，资源指标每页只算一次。改坏的状态仍会被完整检查。

## 0.1.0-alpha.14

- 不留垃圾：状态迁移失败时不再在 `/etc/xray-manager` 留下空的 `.state-normalize.*`；拿到管理锁时清理配置与密钥目录中过期的点开头临时文件。

## 0.1.0-alpha.13

- 性能：状态结构校验与 8 个模块校验并行运行，按原顺序报告第一个错误（失败项在前台重跑以保留原有提示）。

## 0.1.0-alpha.12

- 性能：同一份状态内容在一次命令里只完整校验一次（原来一次操作会重复校验最多三次）；分享页三种客户端格式在显示链接时并行生成
  （4.2 → 2.5 秒）；状态页与健康检查对 UFW/Fail2ban 只探测一次（1.7 → 1.4 秒）。输出不变。

## 0.1.0-alpha.11

- 出站订阅（3x-ui 对齐）：`xm xray outbound sub add NAME URL [--balancer leastPing|…|none]` 把远程订阅（链接列表或 base64）
  导入为出站 `NAME-1…N` 并建同名负载均衡；每日任务自动刷新，失败保留原节点；订阅地址存于 0600 密钥文件。
  新增 `libexec/share_to_xray.jq`：vless/vmess/trojan/ss/hysteria2/socks/http 链接转 Xray 出站，拒绝 allowInsecure，
  已用 xm 自身全部协议的分享链接往返实测。面板分流菜单 13。
- 修复：路由测试在使用 leastPing/leastLoad 负载均衡时无法启动；结果中注明所属负载均衡。

## 0.1.0-alpha.10

- Telegram 机器人（3x-ui 对齐）：`/online`；`/backup` 把完整备份发到管理员会话（含凭据，需 `xm notify bot backup on` 开启）。
- `xm user tg NODE USER TG_ID`：绑定后该用户私聊机器人可用 `/me`（用量、到期）与 `/link`（分享链接），只能看到自己的数据。
- 到期前 3 天、流量达 80% 时各提醒一次（管理员通知渠道；已绑定的用户也会收到），按周期去重。

## 0.1.0-alpha.9

- `xm node clone SRC NEW`：复制节点全部设置（含传输、REALITY 目标、QUIC 参数），自动选端口并重新生成全部凭据。
- 修复：节点模板此前会传入已移除的 sing-box 参数而失败，且不保存 Xray 传输设置；现在保存 `xray.inbound`
  （剔除私钥、用户等机密）并支持全部协议。
- `xm user set-usage`（修改本周期已用流量）、`xm user export|import`（同协议节点间迁移用户，凭据不变）；面板用户菜单 17–19。

## 0.1.0-alpha.8

- `xm xray dns set SERVERS [--strategy UseIP|UseIPv4|UseIPv6] [--fakedns]|clear`：Xray 内置 DNS 与 FakeDNS。
- `xm xray route strategy AsIs|IPIfNonMatch|IPOnDemand`：路由域名策略。
- 访问日志默认关闭（此前 Xray 会把每条连接写入日志）；`xm xray log access on|off`，`xm logs access` 查看。
- 面板：Xray 菜单 10。

## 0.1.0-alpha.7

- 订阅（3x-ui 对齐）：不带 `?format` 时按 User-Agent 自动选择——Clash/mihomo/Stash/FlClash → mihomo，
  sing-box/SFA/Hiddify → sing-box，v2rayN/v2rayNG/Shadowrocket/Happ/NekoBox 等 → base64 链接；新增 `format=base64`；
  返回 `Profile-Title`、`Profile-Update-Interval`。用户停用/到期/流量用尽时返回说明原因的占位节点。
- `xm subscription remark set '{name} | 剩余 {remaining} | {days}天'`：用户订阅链接的节点名模板（面板订阅菜单 4）。

## 0.1.0-alpha.6

- `xm xray outbound test [TAG]`：为每个出站临时启动本机 Xray 测连通与延迟，支持链式出站，不影响运行中的服务。
- `xm xray route test DOMAIN|IP[:PORT]`：用当前规则（含 geosite、负载均衡）判断目标会走哪个出口，出站全部替换为黑洞，不发出流量。
- `xm tools`：用当前 Xray 生成 UUID/X25519/WireGuard/ML-KEM-768/ML-DSA-65/VLESS 加密/ECH；`reality-check` 检查 TLS 1.3、
  X25519MLKEM768 与证书覆盖；`cert-hash` 计算证书 SHA-256。自定义 REALITY 目标时面板自动检查并提示。
- 面板：Xray 菜单 8/9、分流菜单 11/12。

## 0.1.0-alpha.5

- 用户（3x-ui 对齐）：`xm user add NODE --count N` 在一个事务里批量添加并可同时设配额/天数/在线 IP；
  `--expire-after-first-use N` 首次产生流量后才开始计时；`--reset-period day|week|month` 按日/周/月重置流量；
  `xm user online` 查看在线用户与 IP；`xm user purge-depleted` 删除流量耗尽或已到期的用户。面板用户菜单 12–16。

## 0.1.0-alpha.4

- 新增 `xm xray geo status|update|remove`（面板 9 → 10）：按需下载 Loyalsoldier geoip/geosite（约 28 MiB），
  按 GitHub 发布摘要校验，新文件先通过 Xray 配置检查再替换，失败恢复；已安装时每日任务每 7 天刷新。
  分流规则支持 `geosite:`、`geoip:`（如 `geoip:private`），实测拦截生效。
- 分享页统一：先显示链接与二维码，Xray / mihomo / sing-box 配置各自独立导出，某种格式无法表达时只跳过该格式；
  MASQUE 显示 Xray 配置文件。
- 修复：诊断与健康检查只检测 TCP，UDP 节点（Hysteria2、WireGuard、MASQUE、UDP 转发）被误报未监听。
- 清理：sing-box 专属参数统一给出“请使用 sb-manager”的提示；删除 Snell/ShadowTLS 分享路径。
- 文档：3XUI_PARITY 新增面板级功能对照表。

## 0.1.0-alpha.3

- 状态精简：读取时移除 sb-manager 遗留的 sing-box 字段（`api`、`realm`、DNS 设置、`core_channel`、
  Hysteria2 Realm/Gecko/BBR/Chrome 选项）；分享链接与模板只保留 Xray 支持的参数，输出不变。
- 修复：Sub-Store 安装函数的默认端口仍为 sb-manager 的 3001，与共存的 sb 冲突；改为 3002。
- 文档：重写 ARCHITECTURE、STATE_SCHEMA，OPERATIONAL_FEATURES 去除 sing-box/Snell 内容。

## 0.1.0-alpha.2

- 3x-ui 参数：`--udp-idle-timeout`、`--quic-congestion/--quic-idle-timeout/--quic-keepalive`（Hysteria2）、
  `--allow-transparent`（HTTP）、`--port-map`（Tunnel）；Xray 客户端导出新增 Hysteria2 与 SOCKS/HTTP/mixed。
- 修复：已有 Hysteria2 节点后启用 Salamander 时生成混淆密码（之前为空，`xray -test` 不报错但运行时监听失败）；
  `node set --method` 支持 AEAD；VLESS/Trojan REALITY 未给握手目标时默认使用 SNI 站点，客户端地址用公网 IP。
- 面板：VLESS 向导首项为“推荐 REALITY + Vision”，只需选端口；向导步骤回车即取推荐值。
- 性能（23 节点）：添加节点 22.6→5.0 秒；渲染按内容缓存 3.1→0.36 秒；状态校验 2.9→0.76 秒；
  流量页 5.6→0.7 秒；节点选择 2.6→0.45 秒；面板 20 个页面均在 0.8 秒内打开（完整状态页 1.6 秒）。

## 0.1.0-alpha.1

- 只使用 Xray-core：单核心候选配置 → 校验 → 原子安装 → 回滚；命令 `xm`，配置 `/etc/xray-manager`，
  服务 `xm-*`，可与 sb-manager 共存。
- 协议：VLESS、VMess（任意传输/TLS，及 WS + CF Tunnel 模板）、Trojan（任意传输，TLS/REALITY）、
  Shadowsocks（2022 与 AEAD，可叠加传输/TLS）、Hysteria2、WireGuard、MASQUE、Tunnel、
  SOCKS/HTTP/mixed。均用 Xray、mihomo 客户端以真实流量验证。
- 客户端导出：分享链接、Xray、mihomo、sing-box、wg-quick；无法表达的字段拒绝导出并说明原因。
- 用户级流量配额、重置日、到期与在线 IP 上限覆盖全部多用户协议。
- 面板向导新增 VMess/Trojan/SS 传输选择、WireGuard、Tunnel、MASQUE；标题栏、更新、诊断菜单改为 Xray。
- 性能：`node list`、`status`、健康检查和面板标题改为单次 jq 处理（19 个节点：4.0→0.5 秒、8.7→1.6 秒、
  标题 0.43→0.05 秒）；状态页同时检测 UDP 监听。
- 拿到管理锁时清理中断操作遗留的临时文件；移除 sing-box 渲染器、无用函数与 sing-box 专属文档。
