<div align="center">

# openwrt-tailscale-oneliner

<br>

[![GitHub](https://img.shields.io/badge/GITHUB-repo-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/ASoba17/openwrt-tailscale-oneliner)
[![OpenWrt](https://img.shields.io/badge/OPENWRT-25.12.4-00B5E2?style=for-the-badge&logo=openwrt&logoColor=white)](https://openwrt.org/)
[![Tailscale](https://img.shields.io/badge/TAILSCALE-mesh-1B6EE8?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com/)
[![License](https://img.shields.io/badge/LICENSE-MIT-21B517?style=for-the-badge&logo=mit&logoColor=white)](./LICENSE)
[![Shell](https://img.shields.io/badge/SHELL-POSIX_`sh`-2E2E2E?style=for-the-badge&logo=gnu-bash&logoColor=white)](#)

<br>

_Single SSH paste — Tailscale up on OpenWrt 25.12.4 and bridged with your LAN._

<br>

</div>

---

## 🔗 <a id="description"></a> Description

This script configures [Tailscale](https://tailscale.com/) on [OpenWrt 25.12.4](https://openwrt.org/) so that the router's LAN and your Tailscale mesh can talk to each other.

Why: an OpenWrt router is a great Tailscale edge node — already wired to your ISP, already on the LAN, always on. This script makes the configuration **reproducible** in a single paste.

Properties:

- **Idempotent** — re-running won't duplicate forwardings or break config
- **Atomic** — UCI commits fully; no half-applied state if interrupted
- **Minimal surface** — only UCI + `network`/`firewall`/system, no extra daemons
- **Visible status** — `tailscale0` and `tailscale status` printed at the end

---

## 🔗 <a id="prerequisites"></a> Prerequisites

| Requirement | Why |
|---|---|
| OpenWrt **25.12.4** | primary target; other recent builds should also work (see compatibility table) |
| `tailscale` package | the binary + init scripts |
| SSH access as **root** | needed for UCI and service restarts |

Install Tailscale once before running:

```sh
apk update
apk add tailscale
```

---

## 🔗 <a id="what-it-does"></a> What it does

Five steps, each atomic and visible in the output:

| Step | Action                                                 |
|------|--------------------------------------------------------|
| 1/5  | Creates a `tailscale0` network interface                |
| 2/5  | Creates a `tailscale` firewall zone (`input=ACCEPT`)    |
| 3/5  | Adds bidirectional forwarding `lan ↔ tailscale`         |
| 4/5  | Enables IPv4 forwarding (`ip_forward=1`)                |
| 5/5  | Commits and restarts `network` + `firewall`             |

Topology after running:

```
       ┌───────────────────────────┐
       │      OpenWrt router       │
       │                           │
       │  [lan zone] ⇄ [tailscale zone] │
       │       ▲             ▲     │
       │       │             │     │
       └───┬───┘         ┌───┴─────┘
           │             │
       LAN (192.168.x/24)   tailscale0 (100.x/32)
                                │
                                ▼  WireGuard/QUIC
                          Tailscale mesh
```

---

## 🔗 <a id="install"></a> Install

### Option A: one-liner via your router's network

```sh
ssh root@192.168.1.1 -- sh -c "$(curl -fsSL https://raw.githubusercontent.com/ASoba17/openwrt-tailscale-oneliner/main/tailscale-setup.sh)"
```

### Option B: paste manually

1. `cat tailscale-setup.sh` on your laptop
2. Copy the whole file
3. `ssh root@192.168.1.1`
4. Paste into the SSH session and press Enter

### Authenticate

```sh
tailscale up
```

> A browser window will pop up at `https://login.tailscale.com/...` to confirm the node.

---

## 🔗 <a id="usage"></a> Usage

Useful `tailscale up` flags:

```sh
# Make this router a Tailscale exit node
tailscale up --advertise-exit-node

# Advertise the LAN subnet so other tailnet nodes can reach it
tailscale up --advertise-routes=192.168.1.0/24
```

Approve the routes / exit-node in the [Tailscale admin panel](https://login.tailscale.com/admin/machines) — they won't activate otherwise.

---

## 🔗 <a id="verify"></a> Verify

```sh
# interface should be UP
ip -br addr show tailscale0

# zone + two forwardings
uci show firewall | grep -E 'zone|forwarding'

# ip_forward
uci get system.@system[0].ip_forward   # → 1

# Tailscale itself
tailscale status
tailscale ping <any-other-tailnet-peer>
```

---

## 🔗 <a id="rollback"></a> Rollback

```sh
uci -q delete network.tailscale
uci -q delete firewall.tailscale
for fw in $(uci show firewall | awk -F'=' '/=forwarding$/{print $1}'); do
  idx="${fw#firewall.@forwarding[}"; idx="${idx%]}"
  src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
  dst=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
  case "${src}:${dst}" in
    "lan:tailscale"|"tailscale:lan") uci delete firewall.@forwarding[$idx] ;;
  esac
done
uci set system.@system[0].ip_forward='0'
uci commit network firewall system
/etc/init.d/network restart
/etc/init.d/firewall restart
```

---

## 🔗 <a id="compatibility"></a> Compatibility

| OpenWrt   | Status | Comment |
|-----------|--------|---------|
| 25.12.4   | ✅ primary target | developed and tested here |
| 24.10.x   | ✅ should work | `uci` API stable |
| 23.05+    | ⚠️ should work | minor `/etc/init.d/` differences possible |
| < 22.03   | ❓ untested | open an issue with logs |

The Tailscale package requires a supported architecture (`x86_64`, `aarch64`, `mipsel`/`mips` for many SOHO routers). Check the [package feed](https://github.com/adyanth/openwrt-tailscale) for your device.

---

## 🔗 <a id="security"></a> Security

- The `tailscale` zone is created with `input=ACCEPT`. That's the standard pattern but may be **too permissive** for some threat models. To tighten: change `input`/`forward` to `REJECT`/`DROP` and add specific rules.
- The script does **not** configure Tailscale ACL — handle that in the [Tailscale admin panel](https://login.tailscale.com/access).
- `tailscale0` only comes up after the first `tailscale up`. The script applies UCI regardless; that's intentional.
- Do not expose the OpenWrt admin UI (`http://192.168.1.1`) to the public internet — keep it LAN-only.

Security disclosures: use [GitHub Security Advisories](../../security/advisories/new).

---

## 🔗 <a id="disclaimer"></a> Disclaimer

The materials in this repository are published for educational and entertainment purposes. Use at your own risk and comply with the laws of your country and the rules of any network you connect to. The author is not responsible for misuse.

---

## 🔗 <a id="license"></a> License

[MIT](./LICENSE) — do whatever you want, no warranty.

<br>

<div align="center">

<sub>made so OpenWrt+Tailscale boots with one paste 🐉</sub>

</div>
