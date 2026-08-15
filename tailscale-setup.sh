#!/bin/sh
# tailscale-setup.sh — one-shot setup for Tailscale on OpenWrt 25.12.4 with LAN bridging.
#
# What it does:
#   - creates 'tailscale0' network interface
#   - creates a dedicated 'tailscale' firewall zone
#   - allows bidirectional forwarding between LAN and tailscale
#   - enables IPv4 forwarding
#   - restarts network + firewall
#   - prints status
#
# Tested on: OpenWrt 25.12.4 (x86_64, ramips/mt7621 also reported working)
# Author:   <your-name>
# License:  MIT

set -eu

# --- pretty output ---
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; NC='\033[0m'
say()   { printf "${GRN}==>${NC} %s\n" "$*"; }
warn()  { printf "${YEL}!!  ${NC} %s\n" "$*" >&2; }
err()   { printf "${RED}xx  ${NC} %s\n" "$*" >&2; exit 1; }

# --- preflight ---
[ "$(id -u)" -eq 0 ] || err "must run as root (ssh root@<router>)"
command -v uci >/dev/null 2>&1 || err "uci not found — this does not look like OpenWrt"

if ! command -v tailscale >/dev/null 2>&1; then
  err "tailscale binary not found. Install it first:
  opkg update && opkg install tailscale"
fi

say "preflight OK"

# --- 1. network.tailscale ---
say "[1/5] configuring network.tailscale"
uci -q delete network.tailscale
uci set network.tailscale='interface'
uci set network.tailscale.proto='none'
uci set network.tailscale.device='tailscale0'

# --- 2. firewall.tailscale zone ---
say "[2/5] configuring firewall zone 'tailscale'"
uci -q delete firewall.tailscale
uci set firewall.tailscale='zone'
uci set firewall.tailscale.name='tailscale'
uci set firewall.tailscale.input='ACCEPT'
uci set firewall.tailscale.output='ACCEPT'
uci set firewall.tailscale.forward='ACCEPT'
uci add_list firewall.tailscale.network='tailscale'

# --- 3. firewall forwardings (idempotent) ---
say "[3/5] adding forwarding lan <-> tailscale"
# remove existing forwardings in either direction to keep things clean
for fw in $(uci show firewall 2>/dev/null | awk -F'=' '/=forwarding$/{print $1}'); do
  idx="${fw#firewall.@forwarding[}"
  idx="${idx%]}"
  src=$(uci get "firewall.@forwarding[$idx].src" 2>/dev/null || true)
  dst=$(uci get "firewall.@forwarding[$idx].dest" 2>/dev/null || true)
  case "${src}:${dst}" in
    "lan:tailscale"|"tailscale:lan")
      uci delete "firewall.@forwarding[$idx]"
      ;;
  esac
done

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'

# --- 4. ip_forward ---
say "[4/5] enabling IPv4 forwarding"
uci set system.@system[0].ip_forward='1'

# --- 5. commit + restart ---
say "[5/5] committing and restarting network/firewall"
uci commit network
uci commit firewall
uci commit system

/etc/init.d/network restart
/etc/init.d/firewall restart

# --- status ---
echo ""
say "Tailscale interface"
ip -br addr show tailscale0 2>/dev/null || warn "tailscale0 not up yet (authenticate first)"

echo ""
say "Tailscale status"
tailscale status || warn "tailscale not running — try: /etc/init.d/tailscale enable && /etc/init.d/tailscale start"

echo ""
say "Done. Authenticate with:"
echo "    tailscale up"
echo "If you want exit-node routing through this router:"
echo "    tailscale up --advertise-exit-node"
echo "If you want subnet routes from LAN (advanced):"
echo "    tailscale up --advertise-routes=192.168.1.0/24"
