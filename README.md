# xray-manager

`xray-manager`（命令 `xm`）是基于官方 Xray-core 的终端脚本面板，目标是用一个 Bash 脚本做到 3x-ui
的全部 Xray 功能：多协议入站、全部传输与 TLS/REALITY 参数、多用户、用户流量配额/到期/在线 IP
限制、订阅、出站/WARP/负载均衡/分流。支持 systemd 与 OpenRC（Debian、Ubuntu、Alpine、
Rocky、Alma、Fedora、Arch、openSUSE）。

可与 [sb-manager](https://github.com/ridd1e1337/sb-manager)（sing-box，命令 `sb`）在同一台机器共存：
配置目录、服务名、端口和防火墙表互不重叠。TUIC、AnyTLS、NaiveProxy、ShadowTLS、Snell 等
sing-box 协议请使用 sb-manager。

当前版本：`0.1.0-alpha.10`

## 安装

root 执行（Alpine 先 `apk add --no-cache bash curl tar ca-certificates`）：

```bash
curl -fsSL https://github.com/ridd1e1337/xray-manager/raw/refs/heads/main/install.sh | bash
```

安装器自动识别 systemd/OpenRC，从 [XTLS/Xray-core Release](https://github.com/XTLS/Xray-core/releases)
下载最新 Xray 并核对摘要，完成后打开面板。新 VPS 可追加 `-s -- --init-vps` 同时安装
Caddy、UFW、Fail2ban（放行 22/TCP、80/TCP、443/TCP、443/UDP，保留当前 SSH 端口与已有规则）；
普通安装不会修改防火墙。

## 三步上手

```bash
xm
```

1. 输入 `2` 添加节点 → `1` VLESS → 一路回车，得到推荐的 VLESS + REALITY（Vision）节点。
2. 复制屏幕上的分享链接或扫二维码，导入 v2rayN / v2rayNG / Shadowrocket / Clash Verge 等客户端。
3. 输入 `3` 管理节点：添加用户、设置流量和到期、生成该用户的订阅链接。

需要 TLS 的协议输入 Cloudflare 托管的域名即可：首次填写 API Token（Zone:Read、DNS:Edit）后，
自动创建 DNS 记录并申请证书。

## 支持的协议

| 协议 | 传输 / 安全层 | 客户端导出 |
|---|---|---|
| VLESS | RAW、WS、gRPC、HTTPUpgrade、XHTTP、mKCP、Hysteria；TLS、REALITY、VLESS Encryption；Vision、回落 | 分享链接、Xray、mihomo、sing-box* |
| VMess | 同上（无 REALITY）；另有 WS + Cloudflare Tunnel 模板 | 分享链接、Xray、mihomo、sing-box |
| Trojan | 任意传输；TLS、REALITY；回落 | 分享链接、Xray、mihomo（REALITY 除外） |
| Shadowsocks | 2022（多用户）与 AEAD；可叠加传输与 TLS | 分享链接、Xray、mihomo |
| Hysteria2 | Salamander、伪装站 | 分享链接、Xray、mihomo |
| WireGuard | 每个用户一个 peer，用户态栈 | wg-quick、Xray、mihomo |
| MASQUE | HTTP/3 connect-ip | Xray |
| Tunnel | dokodemo-door 端口转发 TCP/UDP | — |
| SOCKS5 / HTTP / mixed | 用户名密码认证 | 分享链接、Xray、mihomo |

\* Xray ≥ 26.9.8 的 REALITY 要求 X25519MLKEM768，sing-box 客户端暂不兼容，会说明原因并跳过。
导出格式无法完整表达的字段一律拒绝导出并提示，不会生成比服务端弱的配置。

3x-ui 功能对照见 [docs/3XUI_PARITY.md](docs/3XUI_PARITY.md)。

## 常用命令

```bash
xm status                          # 服务与节点状态
xm node add vless --transport xhttp --security tls --domain a.example.com
xm node add trojan --transport grpc --security reality
xm node add ss --method 2022-blake3-aes-256-gcm --transport ws --security tls --domain b.example.com
xm node add wireguard --port 51820
xm node set NODE --sniffing route-only --tcp-fast-open true
xm node set NODE --xray-inbound-json @extra.json   # 任意 Xray 入站字段
xm share NODE [--qr]               # 分享链接 / 二维码 / 客户端配置
xm user add NODE alice
xm user limit NODE alice --quota 100G --reset-day 1 --days 30 --ip-limit 2
xm subscription create never mihomo --live --user NODE:alice
xm xray warp --register            # WARP 出站
xm xray route add --domain domain:openai.com --to warp
xm help [命令]                     # 完整用法
```

`--xray-inbound-json` 可写入 3x-ui 中任何高级字段（sniffing、sockopt、finalmask、xhttp extra、
TLS 证书选项等）；协议、标签、端口、用户和凭据由管理器保护。

## 用户限制

流量配额、重置日、到期和在线 IP 上限适用于除 SOCKS/HTTP/mixed/Tunnel 外的所有协议，
数据来自仅监听 `127.0.0.1` 的 Xray Stats API。超限用户暂停但保留凭据，续期或到重置日后自动恢复。
用户订阅返回 `Subscription-Userinfo`（用量、配额、到期）。

## 运维

- **共用 443**：`xm mux setup` 接入已有 Nginx/Caddy 网站做 SNI 分流；`xm reality setup DOMAIN nginx|caddy`
  让 VLESS REALITY 与真实网站共用 443。
- **Cloudflare Tunnel**、**Sub-Store**、**OpenList**、**Telegram 通知与命令机器人**、健康检查、备份恢复、
  BBR/TCP 调优、测速：见面板对应菜单或 `xm help`。
- **更新**：`xm core update|rollback|policy`（Xray，保留上一版可回滚），`xm update`（脚本与 Caddy）。
- **不留垃圾**：文件只放在 `/etc/xray-manager`、`/var/lib/xray-manager`、`/var/log/xray-manager`、
  `/run/xray-manager` 与 `/usr/local/lib/xray-manager`；缓存和日志最长保留约一天，中断操作留下的
  临时文件自动清理。`xm uninstall --purge` 全部移除。

更多：[运维功能](docs/OPERATIONAL_FEATURES.md) · [状态文件](docs/STATE_SCHEMA.md) ·
[协议安全边界](docs/PROTOCOL_SECURITY.md) · [架构](docs/ARCHITECTURE.md)
