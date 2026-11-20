# 3x-ui 入站功能对照（Xray 部分）

来源：MHSanaei/3x-ui main 分支前端 Zod schema、表单序列化与 Go 配置生成（2026-11-20 读取）。
xray-manager 只使用 Xray-core，因此 3x-ui 中**不由 Xray 运行**的 MTProto（mtg sidecar）、
AmneziaWG（amneziawg-go）、TUIC（内置 Go 服务）不在范围内；TUIC 等可使用 sb-manager。

状态：✅ 已支持并用真实流量实测　🟡 可通过原生 JSON 设置（`--xray-inbound-json` / `--transport-json` / `--tls-json` / `--sockopt-json`）　⬜ 待做

## 协议

| 协议 | Xray protocol | 状态 | 说明 |
|---|---|---|---|
| VLESS | vless | ✅ | decryption（X25519/ML-KEM，含 xorpub/random 变体）、flow、fallbacks、reverse |
| VMess | vmess | ✅ | 任意传输，none/TLS；另有 WS + CF Tunnel 模板 |
| Trojan | trojan | ✅ | 任意传输，TLS/REALITY，fallbacks |
| Shadowsocks | shadowsocks | ✅ | 2022 多用户与 AEAD、network、传输与 TLS；ivCheck 在 Xray 26 中已不解析（3x-ui 写入也无效） |
| Hysteria2 | hysteria | ✅ | Salamander、masquerade、`--udp-idle-timeout`、quicParams（`--quic-congestion/--quic-idle-timeout/--quic-keepalive`，其余字段 JSON） |
| WireGuard | wireguard | ✅ | secretKey、mtu、noKernelTun、每用户一个 peer |
| HTTP | http | ✅ | accounts、`--allow-transparent` |
| Mixed/SOCKS | socks | ✅ | auth、accounts、udp、ip |
| Tunnel（dokodemo-door） | tunnel | ✅ | 目标地址/端口、network、followRedirect、`--port-map` |
| MASQUE | masque | ✅ | address、mtu、users(pass)、masqueSettings.path，TLS h3 |
| TUN | tun | ⬜ | 主机网络入口，默认不提供（会改动主机路由） |

## 传输（vmess/vless/trojan/shadowsocks 可选）

RAW（header none/http）、mKCP（mtu/tti/uplinkCapacity/downlinkCapacity/cwndMultiplier/maxSendingWindow，旧 header/seed 走 finalmask mkcp-legacy）、
WebSocket（path/host/headers/heartbeatPeriod/acceptProxyProtocol）、gRPC（serviceName/authority/multiMode）、
HTTPUpgrade（path/host/headers/acceptProxyProtocol）、XHTTP（mode/path/host/headers/xPadding*/sessionID*/seq*/uplink*/sc*/serverMaxHeaderBytes/noSSEHeader；xmux 等为客户端字段）、XDrive（仅 VLESS）。

## 安全层

- TLS：serverName、min/maxVersion、cipherSuites、rejectUnknownSni、disableSystemRoot、enableSessionResumption、alpn、curvePreferences、echServerKeys、certificates（文件或内联、usage、ocspStapling、oneTimeLoading、buildChain）；客户端 fingerprint/echConfigList/pinnedPeerCertSha256/verifyPeerCertByName。
- REALITY（vless/trojan；tcp/grpc/xhttp）：show、xver、target、serverNames、privateKey、min/maxClientVer、maxTimediff、shortIds、mldsa65Seed、limitFallbackUpload/Download；客户端 publicKey/fingerprint/serverName/spiderX/mldsa65Verify。

## 其他

- sniffing：enabled、destOverride、metadataOnly、routeOnly、ipsExcluded、domainsExcluded。
- sockopt：mark、tcpKeepAlive*、tcpMaxSeg、tcpUserTimeout、tcpWindowClamp、acceptProxyProtocol、tcpFastOpen、penetrate、V6Only、tcpcongestion、tproxy、trustedXForwardedFor、customSockopt（以及 JSON 才能设的 tcpMptcp、domainStrategy、dialerProxy、interface、happyEyeballs 等）。
- finalmask：tcp（fragment、sudoku、header-custom、xmc、filter）、udp（salamander、mkcp-legacy、header-custom、xdns、xicmp、noise、sudoku、realm、filter）、quicParams。REALITY 与 tcp finalmask 组合会使 Xray 崩溃，必须拒绝（Xray-core#6453）。
- fallbacks：vless/trojan，RAW + TLS/REALITY，name/alpn/path/dest/xver。
- 客户端：email、limitIp、totalGB、expiryTime、enable、reset（xm 对应 `xm user limit`：--quota/--reset-day/--days/--ip-limit）。
- 入站：listen（IP 或 UDS）、port、tag、整入站流量配额/重置（xm 对应 `xm traffic set`）、分享地址、外部代理。

## 面板级功能（3x-ui main @ 5297fd3，2026-11-13）

状态：✅ 已有　⬜ 待做　➖ 不适用于终端脚本（说明原因）

| 领域 | 3x-ui 功能 | xm | 说明 |
|---|---|---|---|
| 用户 | 每用户配额、到期、在线 IP 上限、启停、轮换 | ✅ | `xm user limit` |
| 用户 | 批量添加用户 | ✅ | `xm user add NODE --count N [--prefix P] [--quota/--days/--ip-limit]` |
| 用户 | 首次使用后才开始计时的到期（delayed start） | ✅ | `--expire-after-first-use N` |
| 用户 | 按日/周/月自动重置流量 | ✅ | `--reset-period day|week|month --reset-day N` |
| 用户 | 查看在线 IP / 在线用户 | ✅ | `xm user online` |
| 用户 | 删除已耗尽用户、修改已用流量、用户导出导入 | ✅ | `xm user purge-depleted`、`set-usage`、`export`/`import` |
| 用户 | HWID 设备数限制 | ➖ | 依赖订阅客户端上报设备 ID，Xray 本身不提供 |
| 入站 | 克隆节点、重置全部流量、导出全部链接 | ✅ | `xm node clone`、`xm traffic reset all`、`xm share all` |
| 入站 | 入站级配额、到期、端口冲突检查、回落 | ✅ | `xm traffic set`、`xm node expiry` |
| Xray | 出站、WARP、负载均衡、分流规则 | ✅ | `xm xray outbound/warp/balancer/route` |
| Xray | geoip/geosite 数据下载与 `geosite:`/`geoip:` 规则 | ✅ | `xm xray geo update` |
| Xray | 出站连通性测试、路由测试 | ✅ | `xm xray outbound test`、`xm xray route test DOMAIN|IP[:PORT]` |
| Xray | Observatory、DNS / FakeDNS、路由域名策略、日志级别与访问日志 | 自动 / ✅ / ✅ / ✅ | leastPing/leastLoad 负载均衡自动启用 burstObservatory；`xm xray dns`、`xm xray route strategy`、`xm xray log access` |
| Xray | NordVPN / PIA 账号出站 | ➖ | 需第三方账号 API；可用 `xm xray outbound add` 导入 WireGuard 出站 |
| Xray | 出站订阅（远程链接池作为出站） | ✅ | `xm xray outbound sub add NAME URL`，每日刷新，可自动建负载均衡 |
| Xray | 核心版本切换、回滚、自动更新 | ✅ | `xm core` |
| 订阅 | 链接 / Xray JSON / mihomo / sing-box 格式、Subscription-Userinfo | ✅ | |
| 订阅 | 按 User-Agent 自动选择格式、base64、备注模板、到期/耗尽占位节点、Profile-Title | ✅ | `xm subscription remark` |
| 机器人 | 状态、节点、用户、启停、续期、订阅 | ✅ | `xm notify bot` |
| 机器人 | 用户自助查询（tgId）、到期/流量预警、备份发送到 Telegram、在线列表 | ✅ | `xm user tg`、`/me` `/link`、`xm notify bot backup on`、`/online` |
| 工具 | UUID/X25519/ML-KEM/ECH 密钥生成、REALITY 目标检查、证书哈希 | ✅ | `xm tools` |
| 运维 | 备份恢复、面板自更新、BBR、证书、防火墙、Fail2ban | ✅ | |
| 多机 | 多节点管理 | ➖ | 由配套项目 sb-manager-web 负责 |
| Web | 网页登录 2FA/LDAP、PWA、主题与多语言、Discord、SMTP | ➖ | 终端脚本无网页登录；通知已有 Telegram/Webhook |
