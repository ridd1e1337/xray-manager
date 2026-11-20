# 协议安全边界

基于当前渲染器、凭据管理与客户端导出代码的说明，不是第三方安全审计。

| 协议 | 默认配置与结论 |
| --- | --- |
| VLESS + REALITY | Xray 生成 X25519 密钥与随机 shortId；目标站默认 `www.apple.com:443`；Xray ≥ 26.9.8 要求 X25519MLKEM768。 |
| VLESS/VMess/Trojan + TLS | 使用本机签发证书；Xray 已移除 allowInsecure，自签证书用 `--pinned-cert-sha256` 或 `--verify-name`。 |
| VLESS Encryption | 可选 ML-KEM/X25519 加密层，客户端参数由服务端解密配置推导。 |
| Trojan + REALITY | 与 VLESS 相同的 REALITY 参数；mihomo 不支持该组合，导出时拒绝。 |
| Shadowsocks 2022 | 随机 PSK，多用户为“服务端 PSK:用户 PSK”；AEAD 方法每用户随机密码，无前向保密，仅用于兼容旧客户端。 |
| Hysteria2 | 必须 TLS；可选 Salamander 混淆和伪装站。 |
| WireGuard | 每用户独立密钥对与 /32 地址；Xray 用户态栈（noKernelTun），不改动主机网卡。 |
| MASQUE | HTTP/3 + TLS，每用户随机密码。 |
| SOCKS/HTTP/mixed | 默认只监听本机并生成认证；监听公网需显式 `--listen`。 |
| Tunnel | 无认证的端口转发，只应在可信网络或防火墙后使用。 |

通用规则：
- 凭据只保存在 `secrets/`（0600），状态文件只记录结构；分享、导出、备份均视为机密。
- 客户端配置由服务端有效配置推导，目标格式无法表达的安全字段一律拒绝导出，不会降级。
- 流量统计 API 只监听 `127.0.0.1`。
