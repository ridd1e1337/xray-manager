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
| Shadowsocks | shadowsocks | ✅ | 2022 多用户与 AEAD、network、传输与 TLS；ivCheck 🟡（JSON） |
| Hysteria2 | hysteria | ✅ | Salamander、masquerade；udpIdleTimeout、quicParams 🟡（JSON） |
| WireGuard | wireguard | ✅ | secretKey、mtu、noKernelTun、每用户一个 peer |
| HTTP | http | ✅ | accounts；allowTransparent 🟡（JSON） |
| Mixed/SOCKS | socks | ✅ | auth、accounts、udp、ip |
| Tunnel（dokodemo-door） | tunnel | ✅ | 目标地址/端口、network、followRedirect；portMap 🟡（JSON） |
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
