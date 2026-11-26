# xray-manager

`xray-manager`（命令 `xm`）是基于官方 Xray-core 的终端脚本面板，目标是用一个 Bash 脚本做到 3x-ui
的全部 Xray 功能：多协议入站、全部传输与 TLS/REALITY 参数、多用户、用户流量配额/到期/在线 IP
限制、订阅、出站/WARP/负载均衡/分流。支持 systemd 与 OpenRC（Debian、Ubuntu、Alpine、
Rocky、Alma、Fedora、Arch、openSUSE）。

可与 [sb-manager](https://github.com/ridd1e1337/sb-manager)（sing-box，命令 `sb`）在同一台机器共存：
配置目录、服务名、端口和防火墙表互不重叠。TUIC、AnyTLS、NaiveProxy、ShadowTLS、Snell 等
sing-box 协议请使用 sb-manager。

当前版本：`0.1.0-alpha.51`

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

## 用户

```bash
xm user add NODE --count 20 --prefix vip --quota 50G --days 30   # 批量添加
xm user limit NODE alice --expire-after-first-use 30             # 首次使用后开始计时
xm user limit NODE alice --reset-period week --reset-day 1       # 每周一重置流量（day/week/month）
xm user online                                                  # 在线用户与 IP
xm user set-usage NODE alice 0 | purge-depleted                 # 修改已用流量 / 删除耗尽用户
xm user export NODE alice f.json && xm user import NODE2 f.json # 迁移用户，凭据不变
xm user tg NODE alice 123456789                                 # 绑定 Telegram：/me /link 与到期提醒
```

流量配额、重置周期、到期和在线 IP 上限适用于除 SOCKS/HTTP/mixed/Tunnel 外的所有协议，
数据来自仅监听 `127.0.0.1` 的 Xray Stats API。超限用户暂停但保留凭据，续期或到重置日后自动恢复；
到期前 3 天、流量达 80% 时提醒一次。

## 订阅

用户订阅返回 `Subscription-Userinfo`。订阅地址不带 `?format` 时按客户端自动选择格式
（Clash/mihomo、sing-box、v2rayN/Shadowrocket 的 base64 链接）；停用或到期的用户收到说明原因的占位节点。
`xm subscription remark set '{name} | 剩余 {remaining} | {days}天'` 设置节点名模板。

## 出站与分流

```bash
xm xray geo update                               # 按需下载 geoip/geosite（约 28 MiB）
xm xray route add --domain geosite:openai --to warp
xm xray route add --ip geoip:private --to block
xm xray outbound sub add air https://example.com/sub   # 导入机场订阅为出站 + 负载均衡 air
xm xray route add --domain geosite:netflix --to balancer:air
xm xray route test www.netflix.com               # 某个域名会走哪个出口
xm xray outbound test                            # 各出站连通性与延迟
xm xray dns set 1.1.1.1,https://dns.google/dns-query
xm tools reality-check www.apple.com             # REALITY 目标是否合适；另有 uuid/x25519/mlkem768/ech 等
```

## 运维

- **REALITY 与网站共用 443**：添加 VLESS 节点时会检测本机 Nginx/Caddy 网站并推荐用它伪装；也可
  `xm reality setup 域名`。域名已是本机网站就直接使用（不装 OpenList），否则自动建一个 OpenList 网站。
  之后 `xm reality site add 域名 [--proxy 本机端口]` 继续加网站，手写的 `listen 443 ssl` 站点用
  `xm reality sync` 接入；所有网站域名都可作为 SNI。`xm reality detach` 恢复网站直接监听 443，
  只还原迁移过的 `listen` 行，后来加的网站和修改都保留。`xm mux setup` 另提供 SNI 分流方式。
- **接入已有的中心 Sub-Store**：面板 `16 → 13` 或
  `echo 'https://域名/后端路径' | xm substore remote set - --name jp-aws --tag 主节点库`。本机不装 Sub-Store，
  节点作为中心的一个来源推送过去，之后节点变化时后台自动更新；中心网页上的改名、标签与处理规则保留。
- **Cloudflare Tunnel**、**Sub-Store**、**OpenList**、**Telegram 通知与命令机器人**、健康检查、备份恢复、
  BBR/TCP 调优、测速：见面板对应菜单或 `xm help`。
- **更新**：`xm core update [版本]|policy`（Xray，只保留当前版本；要换回旧版用 `xm core update 版本号`），`xm update`（脚本与 Caddy）。
- **换 IP**：服务器换公网 IP 后每 15 分钟自动检查并更新公网地址、本机的 Cloudflare DNS 记录和分享链接；
  也可立即运行 `xm settings refresh-ip`。证书不受影响。
- **不留垃圾**：文件只放在 `/etc/xray-manager`、`/var/lib/xray-manager`、`/var/log/xray-manager`、
  `/run/xray-manager` 与 `/usr/local/lib/xray-manager`；缓存和日志最长保留约一天，中断操作留下的
  临时文件自动清理。`xm uninstall --purge` 全部移除。

更多：[运维功能](docs/OPERATIONAL_FEATURES.md) · [状态文件](docs/STATE_SCHEMA.md) ·
[协议安全边界](docs/PROTOCOL_SECURITY.md) · [架构](docs/ARCHITECTURE.md)
