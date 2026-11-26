# Changelog

xray-manager 由 sb-manager 0.1.0-alpha.82 拆分而来，此后独立编号；之前的历史见 sb-manager 仓库。

## Unreleased

## 0.1.0-alpha.49

- `xm node schema`：新增「FinalMask」分节（VLESS / VMess / Trojan / Shadowsocks），同一份设置写入服务端入站和客户端出站：
  - TCP 伪装（RAW、WebSocket、gRPC、HTTPUpgrade、XHTTP；TLS 或无安全层）：分片、Sudoku、自定义头部、Minecraft 伪装（xmc）、来源过滤。
  - UDP 伪装（mKCP、Hysteria 传输）：Salamander（含 Gecko 分片）、mKCP 旧式头部 / 种子、Sudoku、噪声、自定义头部、来源过滤。
  - Hysteria 传输的 QUIC 参数：拥塞控制、BBR 档位、Brutal 带宽、空闲超时、保活、并发流、接收窗口、路径 MTU 探测与 GSO 开关。
  - 字段类型新增 `blocks`（每项选一种类型，`variants` 给出该类型的字段）。xdns、xicmp、realm、udphop 需要额外的网络环境，仍用命令行 JSON 设置。
- 上一版与本版的表单选项已用 Xray 26.11.9 逐项验证（配置校验加真实流量）。Reality 与 TCP 分片同时使用时无法连通，表单在 Reality 下不提供 TCP 伪装。

## 0.1.0-alpha.48

- `xm node schema`：按 3x-ui「添加入站」补齐 VLESS / VMess / Trojan / Shadowsocks 的细项，全部是结构化字段，写入节点的 Xray 入站 / 出站扩展
  （顶层新增 `json_flags`、`ext_from`）：
  - 传输：RAW 的 HTTP 伪装（路径、Host）；mKCP 的 MTU、TTI、上下行容量、CWND 倍数、发送窗口；WebSocket 的心跳与请求头；HTTPUpgrade 请求头；
    gRPC 的 Authority 与 Multi Mode；XHTTP 的请求头、填充（含混淆模式）、会话 ID、序号、上行数据位置、上传大小与间隔、SSE / gRPC 头开关；
    VLESS 新增 Hysteria 传输（认证密码、UDP 空闲超时）。
  - TLS：最低 / 最高版本、加密套件、密钥交换曲线、拒绝未知 SNI、禁用系统根证书、会话恢复、ECH、证书指纹固定、按名称校验证书。
  - Reality：ML-DSA-65、Xver、SpiderX、最大时间差、客户端版本范围、回落限速、调试输出。
  - Sockopt（新分节）：mark、TCP 保活 / 最大分段 / 用户超时 / 窗口上限、拥塞控制、透明代理、多路径 TCP、Penetrate、仅 IPv6、信任的转发头。
  - 嗅探：仅用元数据、排除域名、排除 IP。回落改为多条（SNI、ALPN、路径、目标、Xver），取代原来的单个回落目标。
  - Shadowsocks 可选传输与 TLS。
- 新增 `--reality-mldsa65 true|false`（自动生成 ML-DSA-65 密钥）与 `--ech 域名|none`（自动生成 ECH 密钥，客户端配置写入出站扩展）。
- 表单描述新增字段类型 `pairs`（名称 → 值）、`rows`（多行表格，`columns`），以及 `join`、`from_match`。

## 0.1.0-alpha.47

- `xm node add vless` / `xm node set` 新增 `--vless-auth x25519|mlkem768|none`：自动生成配对的 VLESS Encryption 密钥并写入服务端
  decryption 与客户端 encryption，`none` 关闭；不能与 `--vless-encryption` / `--vless-decryption` 同时使用。
- `xm node schema`：VLESS 新增「VLESS 加密」（不启用 / X25519 / ML-KEM-768），网页面板添加和编辑节点时可直接选择，不需要填写密钥。
  字段新增 `from_match`（按正则把现有值换成选项值）。

## 0.1.0-alpha.46

- `xm node schema`：每个字段标明现有节点里对应的值在哪里（`from`）、创建后能否修改（`edit`、`create_only`），并给出修改命令（顶层 `edit`），
  网页面板据此用同一张表单编辑节点，只提交改动过的项。
- `xm panel schema` 新增页面：隧道（Cloudflare Tunnel、多域名路由、cloudflared 程序）、网站与端口（443 端口复用、与现有网站共用 443、
  Reality 伪装站、OpenList）；流量页新增流量分组，系统页新增健康检查阈值、备份与清理。状态值带中文说明（`map`），令牌类字段标记为 `secret`，
  节点下拉可按协议筛选（`source.filter`），节点列表可点选（`tags` + `source`）。去掉节点菜单里的简易「编辑」。

## 0.1.0-alpha.45

- `xm node schema` 升到 version 3：字段按 3x-ui「添加入站」的顺序和分节重排（启用、备注、协议、监听、端口、总流量、流量重置、到期时间，
  然后是客户端、协议设置、传输、安全、嗅探、高级）。新增字段类型 `radio`（按钮组）、`tags`（多选），以及 `random`、`generate`、`auto`、
  `value`、`suffix`、`invert`、`readonly`、`top` 和 `post`（节点创建后接着执行的命令，如流量额度、到期时间）。

## 0.1.0-alpha.44

- `xm node add` 新增 `--uuid`、`--password`、`--short-id`：指定首个用户的 UUID / 密码和 Reality Short ID（默认仍自动生成），
  便于沿用其他面板的凭据，也供网页面板在表单里显示和重新生成。Shadowsocks 2022、ShadowTLS、Snell 的密钥有固定格式，不能指定。

## 0.1.0-alpha.43

- `xm panel schema` 的「系统」页去掉「卸载」：卸载改由网页面板内置提供（在脚本页顶部和机器设置里），对任何版本的脚本都可用。

## 0.1.0-alpha.42

- `xm panel schema` 的「系统」页新增「卸载」：在网页面板里卸载本脚本及其管理的核心，可选择同时删除全部数据。

## 0.1.0-alpha.41

- 新增 `xm panel schema`（来源 `schemas/panel.json`）：描述网页面板的功能页——用户、流量、出站与分流、系统，
  以及节点的编辑、到期、复制、轮换——每页显示哪些状态和表格、有哪些操作、操作对应的命令和参数。
  面板据此生成界面，脚本的功能与网页保持一致；新增或修改命令时须同步更新该文件。

## 0.1.0-alpha.40

- 新增 `xm substore remote status --json`：输出是否已连接中心 Sub-Store、来源名、显示名、标签、上次推送时间和最近一次失败原因
  （不包含后端地址），供网页面板显示同步状态。

## 0.1.0-alpha.39

- 修复 `xm cert status` 在 jq 1.6 上报语法错误（`label` 是 jq 的保留字）。

## 0.1.0-alpha.38

- 证书的 DNS-01 验证新增三家服务商：阿里云、腾讯云 DNSPod、NameSilo（原有 Cloudflare 不变）。
  `xm cert setup <cloudflare|aliyun|dnspod|namesilo> --email EMAIL --stdin` 配置凭据，凭据从标准输入读取，不进入进程列表；
  `xm cert status` 以 JSON 输出当前服务商。签发、每日自动续期和部署到节点沿用原有流程。
  只有 Cloudflare 会自动创建节点域名的 A/AAAA 记录；其他三家只用于证书验证，域名解析需自行指向本机。
  NameSilo 的记录生效较慢，签发时会等待 15 分钟。

## 0.1.0-alpha.37

- `xm node schema` 不再包含任何 JSON 输入字段，也去掉了「专家」分组：面板的添加节点表单里不会出现需要手写 JSON 的地方。
  原始配置片段仍可通过命令行参数使用。

## 0.1.0-alpha.36

- `xm node schema` 升级为第 2 版：字段带分组（基础 / Reality / 传输 / TLS / 性能与混淆 / 高级 / 备注与标签 / 专家）、
  显示条件（例如选了 WebSocket 才出现路径和 Host）和更明确的选项文字，供面板生成类似 3x-ui 的分步表单。

## 0.1.0-alpha.35

- Debian/Ubuntu 安装依赖时只处理确实缺少的软件包：依赖已齐全时不再运行 `apt-get update`，
  软件源索引刷新失败时改用现有索引继续安装。此前任意一个第三方软件源异常或 apt 锁被占用，都会让安装和升级在第一步失败。

## 0.1.0-alpha.34

- 新增 `xm node schema`：以 JSON 输出 `xm node add` 支持的协议、每个协议的参数、输入类型和可选值
  （来源 `schemas/node-form.json`）。网页面板据此生成添加节点的表单，脚本新增参数后面板无需改动。
  新增或修改 `node add` 参数时须同步更新该文件。

## 0.1.0-alpha.33

- 添加/修改节点时，“客户端连接地址”改为选项：有域名时 1 域名（默认）、2 自动获取的本机公网 IP、3 手动输入；
  没有域名时 1 本机公网 IP（默认）、2 手动输入。

## 0.1.0-alpha.32

- 彻底卸载（`xm uninstall --purge` / 面板“删除程序及全部数据”）时，列出本脚本在 Cloudflare 创建的 A/AAAA 记录并询问是否一并删除。
  只按创建时打上的标记识别，手动创建或仅被复用的记录不会删除；Cloudflare 不可达时只提示，卸载继续。普通卸载不动 DNS。

## 0.1.0-alpha.31

- 服务器换公网 IP（域名不变）后的处理：
  - `xm settings refresh-ip` 与面板“核心通用设置 → 服务器换了 IP”：重新探测公网 IP，把使用旧 IP 的默认地址和节点连接地址
    换成新 IP，更新本机在 Cloudflare 上的 A/AAAA 记录，并刷新分享链接、订阅和中心 Sub-Store 来源；
  - 每 15 分钟的维护任务自动检查：两个独立服务报告相同的新 IPv4 时自动执行同样的更新；DNS 未更新成功会在后续检查中重试；
  - 只改“属于本机”的 DNS 记录：带本管理器标记的，或仍指向本机旧 IP 的；指向其他服务器、开启橙云的记录不动；
  - 申请证书/接入域名时，遇到仍指向本机旧 IP 的记录会自动改指，不再报“已有指向其他地址的记录”。
  证书按域名签发，换 IP 后继续有效，无需重新申请。
- 新增 `xm cert delete 域名` 与证书菜单“删除证书”：删除证书文件并停止续签；仍被节点或网站使用时拒绝并列出使用者。

## 0.1.0-alpha.30

- 移除核心回滚：`xm core rollback` 与面板中的回滚项。磁盘上只保留正在使用的 Xray 核心；升级成功后旧版本立即删除，升级失败时不留下未使用的版本。
  需要旧版时用 `xm core update 版本号`。升级时先用新核心校验配置、启动失败自动切回的保护不变。

## 0.1.0-alpha.29

- 不留垃圾：删除节点或用户时同时删除其导出的客户端文件（含凭据）；定期维护会清掉已不存在的节点/用户的导出目录。

## 0.1.0-alpha.28

- 性能：单节点分享的客户端文件（sing-box/Xray/mihomo 配置）按内容缓存。节点、凭据、共享设置或核心程序未变化时
  直接复用，不再重新生成；任一变化即失效。导出文件与终端输出和之前逐字节一致。

## 0.1.0-alpha.27

- 稳定性：排查全部“管道读端提前关闭”的写法（与 alpha 上一版 Sub-Store 菜单退出码 141 同类）。管道末端的
  `grep -q` 改为读完整个输入的 `pipe_has`，`head`/带 `exit` 的 awk 改为不提前退出的等价写法，避免 pipefail 下
  把“已匹配”误判为失败（例如 UFW 状态、端口占用、版本校验）或中止操作。
- 性能：分享链接按内容缓存（节点、凭据、公网入口设置任一变化即失效，带警告的结果不缓存）。`share all`、
  Sub-Store 链接导出、订阅刷新和中心 Sub-Store 推送在节点未变化时不再为每条链接重复运行约 30 次 jq；
  `share all` 不再把每条链接生成两遍。输出与之前逐字节一致。

## 0.1.0-alpha.26

- 修复：已接入中心 Sub-Store 时打开“Sub-Store 订阅管理”菜单直接中止（退出码 141）。菜单顶部的状态改用单行函数，
  不再经管道截取多行输出。
- 重新连接或更换中心 Sub-Store 时，来源名和显示名默认沿用当前值；提示改名会在中心新建来源。

## 0.1.0-alpha.25

- 移除故障诊断与修复：面板入口、`xm doctor`、`xm repair`、`xm probe` 及只为它们服务的检查函数。运行状态、
  运行日志、健康监控和操作时的配置校验与自动回滚不变。
- “VPS 与网站运维”从 10 项整理为 5 项：1 新 VPS 一键初始化（含组件状态）、2 防火墙与 SSH 防护、
  3 网站与 443 共用（REALITY 与本机网站 / 多节点 SNI 分流 / OpenList）、4 网络调优与测速、
  5 程序与缓存维护（Caddy、缓存与日志、支持的系统）。
- 彻底卸载改为 y/N 确认，不再要求输入 DELETE。
- 主菜单其后各项前移：10 运行日志、11 核心通用设置、12 VPS 与网站运维、13 节点流量与限速、14 通知与健康监控、
  15 卸载管理器、16 Sub-Store 订阅管理。

## 0.1.0-alpha.24

- 移除“完整客户端配置”：主菜单第 5 项、节点创建后“生成完整客户端配置”入口与 `xm export config`。每个节点的分享链接、
  二维码、客户端文件（主菜单 4）和动态订阅不受影响，`xm export outbounds` 保留。
- 主菜单去掉“节点与客户端 / 维护与扩展”分组标题，成为连续列表：5 TLS 域名证书、6 CF Tunnel、7 更新管理器与核心、
  8 Xray 出站、WARP 与分流、9 Xray 流量统计、10 运行日志、11 故障诊断与修复、12 核心通用设置、13 VPS 与网站运维、14 节点流量与限速、
  15 通知与健康监控、16 卸载管理器、17 Sub-Store 订阅管理。文档中的面板路径同步更新。

## 0.1.0-alpha.23

- 新增 `xm substore remote set|push|status|disable` 与面板 `18 → 13`：接入已有的中心 Sub-Store，与 sb-manager 相同。
  本机节点作为中心的一个本地来源推送；首次创建时设置显示名和标签，之后只更新节点内容；每次成功的修改后按指纹判断，
  有变化才在后台推送；中心不可达只记录并在状态中提示。
- 修复：Sub-Store 链接导出会为无法表达的节点写入空行。

## 0.1.0-alpha.22

- 移除节点模板与批量操作：面板“节点模板与批量操作”、`xm node template list|save|delete|add`、
  `xm node enable-all|disable-all`；状态中的 `node_templates` 自动删除。`xm node clone` 保留。
- 主菜单其后各项前移：17 卸载管理器、18 Sub-Store 订阅管理。

## 0.1.0-alpha.21

- 移除备份与恢复功能：`xm backup`、`xm restore`、面板“13. 备份与恢复”、Telegram `/backup` 与
  `xm notify bot backup on|off`（状态中的 `notifications.bot.backup` 自动删除）。操作失败时的自动回滚快照不受影响；
  `xm substore backup|restore` 仍可备份 Sub-Store 数据。
- 主菜单 13 之后的各项前移一位：13 核心通用设置、14 VPS 与网站运维、15 节点流量与限速、16 通知与健康监控、
  17 节点模板与批量操作、18 卸载管理器、19 Sub-Store 订阅管理；旧的 21 入口移除。
- 子菜单输入超出范围时提示“先输入 0 返回上一级”，避免把主菜单编号输在子菜单里。

## 0.1.0-alpha.20

- REALITY 与本机网站共用 443：
  - `xm reality setup` 的域名已是本机 Nginx/Caddy 的 HTTPS 网站时直接使用，不再强制安装 OpenList；
  - 添加 VLESS 节点时检测本机网站并推荐“借用本机网站伪装并共用 443”，Reality 菜单可直接选择本机网站；
  - 新增 `xm reality sites`、`sync`、`site add DOMAIN [--proxy 端口]`、`site remove DOMAIN`，共存后继续添加
    OpenList 或反代网站、接入手写的 443 网站；`xm openlist setup/detach` 在共存时自动走这条路径；
  - 所有网站域名都写入 Xray `serverNames`；
  - `detach` 改为按迁移标记还原 `listen`，保留共存期间添加或修改的网站（旧版本迁移的配置同样可还原）；
  - 重新接入同一网站时复用上次停用的节点，`detach` 不留下空目录。
- 修复：所有回滚都会误报“自动恢复未完成”。trap 中调用的函数里，裸 `return` 继承的是触发回滚的失败状态；
  现统一改为 `return $?`。
- 修复：xm 自己生成的备份无法恢复（`var/user-usage.json` 不在恢复白名单中）。

## 0.1.0-alpha.19

- `xm update` 的前置检查同样接受“链接丢失但核心已下载”的情况，让 alpha.17 及更早版本更新后丢失 `bin/xray` 的机器可以直接修复。

## 0.1.0-alpha.18

- 修复 `xm update` 失败（`--keep-core 需要已有 Xray 核心`）：更新脚本时连同 `bin/xray` 链接一起删除。现在保留 `bin/`，
  链接已丢失时自动指向已下载的最新核心。

## 0.1.0-alpha.17

- 修复 Xray 服务启动失败（`203/EXEC Permission denied`）：`/usr/local/lib/xray-manager/bin` 在 `umask 027` 下被创建为 0750，
  非 root 的服务用户无法进入。现以 0755 创建，权限修复也覆盖该目录，已安装的机器下次操作时自动修正。
- 添加/修改 VLESS 节点时，监听地址改为带说明的选项（公网 IPv4+IPv6、仅 IPv4、仅本机、指定网卡 IP）。
- 客户端 TLS 指纹改为选项：chrome、firefox、safari、ios、android、edge、360、qq、random、randomized、randomizednoalpn，或手动输入。

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
