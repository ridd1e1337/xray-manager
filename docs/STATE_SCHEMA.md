# State schema v2

`/etc/xray-manager/state.json` holds topology and non-secret settings. Credentials
live in protected files under `secrets/`. `generated/config.json` is derived and is
never parsed back into state. States copied from sb-manager are normalized on load:
sing-box-only fields (`api`, `realm`, DNS settings, `core_channel`, Hysteria2
Realm/Gecko/BBR/Chrome options) are removed.

Simplified example:

```json
{
  "schema_version": 2,
  "manager_version": "0.1.0-alpha.17",
  "settings": {
    "log_level": "warn",
    "default_server_address": "",
    "default_server_address_source": "auto",
    "public_ipv4": "203.0.113.7",
    "public_ipv6": "",
    "outbound_ip_strategy": "prefer_ipv4",
    "core_update_policy": "notify",
    "cloudflared_update_policy": "notify",
    "manager_auto_update": true,
    "manager_update_minute": 47,
    "xray_api_port": 10085
  },
  "tunnel": {"mode": "none"},
  "nginx_stream": {"enabled": false, "backend": "nginx", "listen": "::", "port": 443, "routes": []},
  "notifications": {"enabled": false, "provider": "none", "traffic_thresholds": [80, 90, 100]},
  "health": {"enabled": false, "certificate_warn_days": 21, "resources": {}},
  "certificates": [],
  "node_templates": [],
  "nodes": [
    {
      "id": "vless-22ce8165",
      "name": "VLESS Reality",
      "protocol": "vless",
      "enabled": true,
      "listen": "::",
      "port": 8443,
      "domain": "www.apple.com",
      "security": "reality",
      "flow": "xtls-rprx-vision",
      "handshake_server": "www.apple.com",
      "handshake_port": 443,
      "server_address": "203.0.113.7",
      "server_address_source": "auto",
      "metadata": {"remark": "", "region": "", "purpose": "", "line": "", "tags": []},
      "traffic": {"configured": false, "enabled": false, "quota_bytes": null, "quota_mode": "total",
                  "reset_day": 1, "upload_rate_bps": null, "download_rate_bps": null},
      "xray": {"inbound": {}, "outbound": {}},
      "singbox": {"outbound": {}},
      "users": [
        {"id": "default", "name": "VLESS Reality", "enabled": true,
         "limits": {"quota_bytes": 107374182400, "reset_day": 1, "expires_at": 1798761600,
                    "ip_limit": 2, "suspended": null, "suspended_until": null, "resume_enabled": false}}
      ]
    }
  ]
}
```

## Nodes

Common fields: `id` (`^[a-z0-9][a-z0-9._-]{0,47}$`), `name`, `protocol`, `enabled`,
`listen`, `port`, `server_address` (what clients connect to; `server_address_source`
`auto` follows `xm settings detect-ip`), `metadata`, `traffic`, `users`, `xray`.

| protocol | extra fields | user secret | node secret |
|---|---|---|---|
| `vless` | `security` none/tls/reality, `flow`, `domain`, `handshake_server/port` | `uuid` | REALITY keys, short id |
| `vmess` | `security` none/tls, `domain` | `uuid` | — |
| `vmess-ws-cf` | `ws_path`, `client_address` (Cloudflare Tunnel) | `uuid` | — |
| `trojan` | `security` tls/reality, `domain`, `handshake_*` | `password` | REALITY keys |
| `shadowsocks` | `method` (2022 or AEAD), `network` tcp/udp, `credential_mode` legacy/multi | `password` | `server_password` (2022 multi) |
| `hysteria2` | `domain`, `obfs.type` ""/salamander, `masquerade` | `password` | `obfs_password` |
| `wireguard` | `subnet` 10.x.y.0/24, `mtu` | `private_key`, `public_key`, `address` | server key pair |
| `masque` | `domain`, `subnet`, `mtu` (≥1280) | `password` | — |
| `tunnel` | `target_address`, `target_port`, `network`, `follow_redirect` | — | — |
| `socks`/`http`/`mixed` | (default listen 127.0.0.1) | `username`, `password` | — |

The transport and TLS/REALITY parameters of VLESS/VMess/Trojan/SS live in
`xray.inbound.streamSettings`, written by `--transport`, `--security`, `--path`,
`--sniffing`, `--sockopt-json`, etc. Structured 3x-ui flags such as
`--udp-idle-timeout`, `--quic-*`, `--allow-transparent` and `--port-map` are stored
as fragments of the same object. `xray.inbound` is deep-merged into the generated
inbound last; `protocol`, `tag`, `listen`, `port` and credentials always come from
the manager. `xray.outbound` customizes the Xray client export; `singbox.outbound`
customizes the sing-box client export.

User secrets live in `secrets/users/<node>/<user>.json`, node secrets in
`secrets/nodes/<node>.json` (mode 0600). The Xray client `email` (Stats key) is
`<node>:<user>`, or `<node>@<user>` for MASQUE, which rejects `:`.

## User limits

`users[].limits` is optional. `expires_at` (epoch seconds), `quota_bytes`,
`reset_day` (1–28, null = lifetime) and `ip_limit` apply to every protocol except
socks/http/mixed/tunnel; counters come from the loopback Stats API on
`settings.xray_api_port`. `suspended` is `null`, `quota`, `expired` or `ip`; while
suspended the user has `enabled:false` and `resume_enabled` stores the state to
restore. Per-user counters live in `/var/lib/xray-manager/user-usage.json`.

## Routing

`xray_routing` holds `outbounds[{tag,protocol,via}]`,
`balancers[{tag,selectors,strategy,fallback}]`,
`rules[{node?,user?,domain?,ip?,network?,port?,outbound|balancer}]` and `default`.
The outbound objects themselves (including WARP keys) are in
`secrets/xray-outbounds.json`. Reserved tags: `direct`, `block`, `api`.

## Traffic accounting

Every node has a normalized `traffic` object. `configured` distinguishes a never
configured node from a disabled policy; `enabled` controls runtime nft rules.
`quota_bytes` and directional rates (bit/s) may be `null` for unlimited;
`quota_mode` is `total` or `download`; `reset_day` is 1–28 in UTC. Counters live in
`/var/lib/xray-manager/traffic-usage.json`. `traffic_groups[{id,nodes,quota_bytes,
quota_mode,reset_day}]` share one quota; `shaping:{enabled,interface,capacity_bps}`
configures optional tc download shaping.

## TCP/SNI sharing of 443

`nginx_stream` keeps its historical key. `backend` is `nginx`, `caddy` or
`nginx-site` (states from sb-manager with `sing-box` become `nginx`).
`routes[{node_id,sni,backend_port}]` render each routed node on
`127.0.0.1:<backend_port>` while exports use the public port. Node IDs, SNI values
and backend ports are unique. `nginx_stream.website` (when `managed:true`) records an
operator website integrated by `xm mux setup`; original files and hashes are
journaled under `var/website-mux/` so `xm mux detach` can restore them.

`reality_site` records the VLESS REALITY + Vision listener that shares TCP/443 with a
real HTTPS site (`node_id`, `domain`, `server`, `binary`, `config`, `backend_port`,
`journal`). Overrides are refused for that node; detach restores the site and
disables the node while keeping credentials.

## Other components

- `tunnel`: `mode` none/quick/fixed/managed; managed adds `tunnel_id` and
  `routes[{id,hostname,service,path}]`; credentials in `secrets/cloudflared-credentials.json`.
- `notifications`: provider and thresholds; tokens/URLs in `secrets/notifications.json`.
  `notifications.bot:{enabled,admins}` enables the Telegram command bot.
- `health`: certificate warning days and resource thresholds.
- `substore:{enabled,port,version,frontend_version}`; its API path is a secret.
- `openlist.sites[{domain,server,binary,config,port}]`; OpenList data lives in
  `/var/lib/xm-openlist` and is not part of manager backups.
- `caddy` / `caddy_apt`: explicit Caddy program lifecycle enrollment (mutually exclusive).
- `node_templates`: non-secret defaults captured from nodes; credentials are always
  regenerated.
- `certificates[]`: issued certificates; Cloudflare credentials are in
  `secrets/dns-cloudflare.env`. DNS records created for an operation are journaled so
  a failed operation deletes only its own records.

## Subscriptions

Live subscriptions keep authorization metadata in
`subscriptions/<token-sha256>.meta.json`; `subscriptions/live.json` is a derived
bundle regenerated after changes. Per-user subscriptions return
`Subscription-Userinfo` from the user limits above.

## Settings

`manager_auto_update` defaults to `true` only when missing; `manager_update_minute`
(0–179) is the minute after 03:00 local time for the daily manager/Caddy update.
`core_update_policy` (Xray) and `cloudflared_update_policy` are `manual`, `notify`,
`patch` (same year.month for Xray) or `stable`. Update attempts are recorded under
`var/updates/`, not in state.

Existing v1 installations migrate once, before rendering, with a pre-migration
snapshot. Future changes must use explicit one-way migrations.
