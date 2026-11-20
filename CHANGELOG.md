# Changelog

xray-manager 由 sb-manager 0.1.0-alpha.82 拆分而来，此后独立编号；之前的历史见 sb-manager 仓库。

## Unreleased

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
