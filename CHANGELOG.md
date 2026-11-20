# Changelog

xray-manager 由 sb-manager 0.1.0-alpha.82 拆分而来，此后独立编号；之前的历史见 sb-manager 仓库。

## Unreleased

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
