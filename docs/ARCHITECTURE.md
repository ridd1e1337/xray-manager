# Architecture

## Data flow

```text
state.json + secrets/ + certs/
        │  validate_state_semantics  (one jq pass: ports, users, files, profiles)
        ▼
xray_render_config  (per-node inbound, content-addressed cache)
        │
        ▼
candidate config.json ──► xray run -test
        │
        ▼
snapshot → atomic install → xm-xray reconcile → health check
                                    └─ failure: restore snapshot
```

`state.json` plus the protected secret and certificate files are the only source of
truth. `generated/config.json` is rebuilt on every change and never parsed back.
Every mutation runs under the manager lock (`with_lock`) as a state transaction:
candidate state → semantic validation → render → `xray -test` → atomic install →
service reconcile; any failure restores the full snapshot (state, secrets,
certificates, subscriptions and service definitions).

## Modules

| Path | Role |
|---|---|
| `xm` | CLI entry point and help |
| `lib/state.sh` | defaults, migrations (`state_normalize`), schema, snapshots, transactions |
| `lib/node.sh` | node/user CLI; builds node objects and secrets |
| `lib/render.sh` | semantic validation, shared jq socket model `SBM_JQ_NODE_KINDS`, candidate pipeline |
| `lib/xray.sh` | Xray inbound renderer, service unit, binary install/switch/prune |
| `lib/vless_config.sh` / `lib/vless_profile.sh` / `libexec/vless_export.jq` | stream protocols (VLESS/VMess/Trojan/SS): transports, TLS/REALITY, client profile derivation and exports |
| `lib/export.sh`, `protocols/*.sh`, `libexec/singbox_to_mihomo.jq` | share links and Xray/mihomo/sing-box/wg-quick client configs |
| `lib/user_limits.sh` | per-user quota, reset day, expiry and online-IP limits via the Stats API |
| `lib/xray_routing.sh` | extra outbounds, WARP, balancers and routing rules |
| `lib/ui.sh` | terminal panel |

Protocol inbounds are built by `xray_protocol_inbound`; VLESS/VMess/Trojan/SS share a
generic stream builder. `--xray-inbound-json` (stored in `nodes[].xray.inbound`) is
deep-merged last; protocol, tag, listen, port and credentials stay manager-owned.

## Performance model

Bash startup is cheap; `jq` process launches dominate. Hot paths therefore use one
jq pass for many nodes (`node list`, `status`, validation, port reservation, panel
header and node picker, traffic table). Two content-addressed caches live under
`/run/xray-manager/vless-cache` (root-only, pruned after a day):

- rendered inbounds, keyed by manager version, certificate directory, the effective
  node JSON and the raw bytes of its secret files;
- profile checks (`.valid`/`.ok` markers), keyed additionally by the Xray build.

Any input change yields a new key, so stale entries are never used.

## Interactive panel

`lib/ui.sh` runs each menu action in a fresh worker process (`__ui-step`) so strict
error handling and locking match the CLI. Menu prompts never act on a bare Enter;
wizard steps pass a recommended default (`ui_menu_choice VAR LABEL MAX DEFAULT`).
The VLESS wizard starts with a one-question REALITY + Vision path. The header caches
the Xray version for the session and resets it after the update menu.

## Services

`xm-xray.service` (systemd) or `/etc/init.d/xm-xray` (OpenRC supervise-daemon) runs
`/usr/local/lib/xray-manager/bin/xray`, a symlink into `cores/xray/<version>/`. On
systemd it runs as the unprivileged `xraymanager` user with only
`CAP_NET_BIND_SERVICE`. Switching versions validates the current config with the
candidate binary first; failure restores the previous link and snapshot. The active
and the newest previous build are kept for `xm core rollback`.

Other units (`xm-cloudflared`, `xm-traffic`, `xm-subscription`, `xm-substore`,
`xm-telegram-bot`, …) are created only when their feature is enabled. Names, ports
(subscription 9081, Sub-Store 3002), the nft table `xm_manager_traffic` and the
service user differ from sb-manager so both managers can run on one host.

## Trust boundaries

- `state.json`: topology and non-secret settings, mode `0600`.
- `secrets/`: user and node credentials, API tokens, extra outbounds, mode `0600` files.
- `generated/config.json`: contains credentials, readable by root and the service group.
- `certs/`: private keys `0640` for the service group.
- `exports/`, backups, subscriptions: `0600`; they contain credentials.
- The Stats API listens only on `127.0.0.1`; ordinary operations never change the
  host firewall (only explicit `xm vps init` / `--init-vps` does).

## Runtime files

Everything lives under `/etc/xray-manager`, `/var/lib/xray-manager`,
`/var/log/xray-manager`, `/run/xray-manager` and `/usr/local/lib/xray-manager`.
Temporary files use `mktemp` inside these directories with traps; scratch files left
by an aborted operation (older than ten minutes) are removed whenever the manager
lock is taken. Logs and caches are kept for about a day. `xm uninstall --purge`
removes all of it.
