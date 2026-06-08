#!/bin/bash
# vpn_connect_macos.sh — bring up an OpenVPN profile on macOS from the CLI.
#
# Credentials are collected through native macOS secure dialogs (osascript),
# so the Garnatxa username/password and the local admin password are never
# echoed to the terminal, the process list, or shell history. Validated
# end-to-end against i2sysbio.ovpn (the Garnatxa VPN).
#
# Usage:
#   ./vpn_connect_macos.sh [/path/to/profile.ovpn]
# Default profile: $HOME/.config/garnatxa/i2sysbio.ovpn
#
# Requires the openvpn CLI:  brew install openvpn
# Disconnect + clean up:     ./vpn_disconnect_macos.sh
#
# Why a script and not `sudo openvpn ./i2sysbio.ovpn`: the bare command needs
# an interactive TTY for three secrets (sudo, VPN user, VPN pass). An agent or
# a one-shot SSH session has no TTY, so the prompts hang or time out. The
# secure-dialog approach lets a human supply secrets without exposing them.
set -uo pipefail

PROFILE="${1:-$HOME/.config/garnatxa/i2sysbio.ovpn}"
OPENVPN="$(command -v openvpn || echo /opt/homebrew/sbin/openvpn)"
RUNDIR="${TMPDIR:-/tmp}/garnatxa-vpn"
AUTH="$RUNDIR/auth"
WORKCFG="$RUNDIR/profile.ovpn"
LOG="$RUNDIR/openvpn.log"
PROBE_IP="10.1.0.6"             # garnatxa.srv.cpd; probe by IP so it works even
                               # when cluster DNS isn't the system resolver
CLUSTER_NET="10.1.0.0"         # I2SysBio internal subnet kept on the VPN
CLUSTER_MASK="255.255.0.0"

# SPLIT-TUNNEL by default. The shipped i2sysbio.ovpn contains
# `redirect-gateway def1`, i.e. it is FULL-tunnel: it forces 100% of your
# traffic through Garnatxa's slow, firewalled egress, which breaks general
# browsing (github times out, ICMP is dropped, everything is slow). Split-tunnel
# sends only the cluster subnet through the VPN and leaves the rest on your
# normal interface. Set VPN_FULL_TUNNEL=1 to restore the original full-tunnel.
FULL_TUNNEL="${VPN_FULL_TUNNEL:-0}"

[ -f "$PROFILE" ]  || { echo "Profile not found: $PROFILE" >&2; exit 1; }
[ -x "$OPENVPN" ]  || { echo "openvpn CLI not found — run: brew install openvpn" >&2; exit 1; }

mkdir -p "$RUNDIR"; chmod 700 "$RUNDIR"; rm -f "$AUTH" "$WORKCFG" "$LOG"

# Secure prompt. $1 = prompt text, $2 = "yes" to mask the input.
# `with timeout of 600 seconds` overrides the ~2 min default AppleEvent timeout
# so the dialog waits for a human instead of erroring with -1712.
ask() {
  VPN_PROMPT="$1" VPN_HIDDEN="$2" osascript <<'OSA'
on run
  set p to (system attribute "VPN_PROMPT")
  set h to (system attribute "VPN_HIDDEN")
  with timeout of 600 seconds
    tell application "System Events"
      activate
      if h is "yes" then
        set r to display dialog p default answer "" with hidden answer with title "Connect Garnatxa VPN" buttons {"Cancel", "OK"} default button "OK"
      else
        set r to display dialog p default answer "" with title "Connect Garnatxa VPN" buttons {"Cancel", "OK"} default button "OK"
      end if
    end tell
  end timeout
  return text returned of r
end run
OSA
}

VPN_USER=$(ask "Garnatxa VPN username:" no)                   || { echo "Cancelled."; exit 2; }
VPN_PASS=$(ask "Garnatxa VPN password:" yes)                  || { echo "Cancelled."; exit 2; }
ADMIN_PW=$(ask "macOS admin password (for VPN routing):" yes) || { echo "Cancelled."; exit 2; }

printf '%s\n%s\n' "$VPN_USER" "$VPN_PASS" > "$AUTH"; chmod 600 "$AUTH"

# Working copy of the profile: read credentials from the auth file (no TTY
# prompt) and, unless full-tunnel was requested, comment out `redirect-gateway`
# so only the cluster subnet (added via --route below) goes through the VPN.
# The original profile is left untouched.
if [ "$FULL_TUNNEL" = "1" ]; then
  sed "s#^auth-user-pass.*#auth-user-pass $AUTH#" "$PROFILE" > "$WORKCFG"
  echo "Mode: FULL-tunnel (all traffic via the VPN) — VPN_FULL_TUNNEL=1."
else
  sed -e "s#^auth-user-pass.*#auth-user-pass $AUTH#" \
      -e 's|^redirect-gateway.*|# redirect-gateway disabled by vpn_connect_macos.sh (split-tunnel)|' \
      "$PROFILE" > "$WORKCFG"
  echo "Mode: split-tunnel (only ${CLUSTER_NET}/16 via the VPN; internet stays direct)."
fi
chmod 600 "$WORKCFG"

# openvpn needs root to create the utun interface and edit routing. --daemon
# forks it to the background after option parsing; the log goes to $LOG.
# --route keeps the cluster subnet on the tunnel even with redirect-gateway off
# (harmless/redundant in full-tunnel mode).
echo "$ADMIN_PW" | sudo -S "$OPENVPN" \
  --config "$WORKCFG" --auth-nocache \
  --route "$CLUSTER_NET" "$CLUSTER_MASK" \
  --connect-timeout 15 --connect-retry-max 3 \
  --log "$LOG" --verb 4 --daemon
rc=$?; unset ADMIN_PW VPN_PASS
[ $rc -eq 0 ] || { echo "openvpn failed to start (sudo rc=$rc)"; exit $rc; }

# Success signal that needs no sudo: $LOG is root-owned (mode 600) and not
# readable here, so verify from the network side instead. The cluster login
# host (10.1.0.6:22) only answers when the tunnel is up, and probing by IP
# avoids depending on cluster DNS under split-tunnel.
echo "Connecting…"
for _ in $(seq 1 20); do
  if nc -z -w3 "$PROBE_IP" 22 >/dev/null 2>&1; then
    dev=$(ifconfig | awk '/^utun/{d=$1} /inet /{if(d!=""){print d" "$2; d=""}}' | tail -1)
    echo "VPN up ✓  cluster ${PROBE_IP}:22 reachable.  ${dev:+interface: $dev}"
    if [ "$FULL_TUNNEL" != "1" ]; then
      echo "Internet stays on your normal interface (split-tunnel)."
      echo "If 'ssh garnatxa' can't resolve garnatxa.srv.cpd, use the IP ${PROBE_IP}."
    fi
    echo "Disconnect with: $(dirname "$0")/vpn_disconnect_macos.sh"
    exit 0
  fi
  sleep 1
done
echo "openvpn started but ${PROBE_IP}:22 did not respond within 20s."
echo "Inspect the log:  sudo tail -n 40 $LOG"
exit 1
