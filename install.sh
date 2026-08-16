#!/bin/sh
# install.sh — auto-detect your OpenWrt router's gateway and run tailscale-setup.sh on it via SSH.
# Run this on your **local machine** (laptop/desktop that is on the same LAN as the router).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ASoba17/openwrt-tailscale-oneliner/main/install.sh | sh
#
# Environment overrides:
#   ROUTER=<ip>          skip detection, use this address explicitly (e.g. 192.168.10.1)
#   SSH_USER=<name>      default: root
#   SSH_PORT=<port>      default: 22
#   SETUP_URL=<url>      default: this repo's tailscale-setup.sh@main
#
# Works on Linux (Debian, Ubuntu, Arch, Alpine…) and macOS.

set -eu

# --- pretty output ---
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; NC='\033[0m'
say()  { printf "${GRN}==>${NC} %s\n" "$*"; }
warn() { printf "${YEL}!!  ${NC} %s\n" "$*" >&2; }
err()  { printf "${RED}xx  ${NC} %s\n" "$*" >&2; exit 1; }

# --- preflight on the local machine ---
command -v ssh   >/dev/null 2>&1 || err "ssh not found; install OpenSSH client (apt install openssh-client / brew install openssh)"
command -v curl  >/dev/null 2>&1 || err "curl not found; install curl"

SETUP_URL="${SETUP_URL:-https://raw.githubusercontent.com/ASoba17/openwrt-tailscale-oneliner/main/tailscale-setup.sh}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"

# --- detect router IP ---
detect_gw() {
  # 1) explicit override
  if [ -n "${ROUTER:-}" ]; then
    echo "$ROUTER"
    return
  fi

  # 2) ip route on Linux (most reliable)
  if command -v ip >/dev/null 2>&1; then
    gw=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
    [ -n "$gw" ] && { echo "$gw"; return; }
  fi

  # 3) route on macOS / BSD
  if command -v route >/dev/null 2>&1; then
    gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')
    [ -n "$gw" ] && { echo "$gw"; return; }
    gw=$(netstat -rn 2>/dev/null | awk '$2=="default"{print $1; exit}')
    [ -n "$gw" ] && { echo "$gw"; return; }
  fi

  # 4) fallback — try common OpenWrt defaults
  for ip in 192.168.1.1 192.168.10.1 192.168.0.1 192.168.2.1 10.0.0.1 10.1.1.1; do
    # -W only on busybox/coreutils; ignore failure here
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1 \
    || ping -c 1 -t 1 "$ip" >/dev/null 2>&1; then
      echo "$ip"
      return
    fi
  done

  return 1
}

ROUTER_IP=$(detect_gw) || err "could not auto-detect router gateway.
Set ROUTER=<ip> explicitly and run again, e.g.:
  ROUTER=192.168.10.1 curl -fsSL <this-url> | sh"

say "router detected: ${SSH_USER}@${ROUTER_IP}"

# --- optional SSH reachability check (non-blocking — auth may still succeed later) ---
if command -v nc >/dev/null 2>&1; then
  if ! nc -z -G 3 "$ROUTER_IP" "$SSH_PORT" 2>/dev/null \
  && ! nc -z -w 3 "$ROUTER_IP" "$SSH_PORT" 2>/dev/null; then
    warn "port $SSH_PORT on $ROUTER_IP doesn't respond — SSH may fail."
  fi
fi

# --- download setup script locally, then pass to remote sh over SSH ---
SETUP="$(curl -fsSL "$SETUP_URL")" || err "failed to download $SETUP_URL"
say "running tailscale-setup on ${ROUTER_IP}…"

# shellcheck disable=SC2086
ssh -p "$SSH_PORT" "${SSH_USER}@${ROUTER_IP}" -- sh -c "$SETUP"
