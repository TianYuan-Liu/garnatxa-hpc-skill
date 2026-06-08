#!/bin/bash
# vpn_disconnect_macos.sh — tear down the tunnel started by
# vpn_connect_macos.sh and shred the temporary credential/config files.
#
# Usage:  ./vpn_disconnect_macos.sh
set -uo pipefail

RUNDIR="${TMPDIR:-/tmp}/garnatxa-vpn"
WORKCFG="$RUNDIR/profile.ovpn"

ask() {  # hidden secure prompt
  VPN_PROMPT="$1" osascript <<'OSA'
on run
  set p to (system attribute "VPN_PROMPT")
  with timeout of 600 seconds
    tell application "System Events"
      activate
      set r to display dialog p default answer "" with hidden answer with title "Disconnect Garnatxa VPN" buttons {"Cancel", "OK"} default button "OK"
    end tell
  end timeout
  return text returned of r
end run
OSA
}

if ! pgrep -f "openvpn --config $WORKCFG" >/dev/null 2>&1; then
  echo "No tunnel started by vpn_connect_macos.sh appears to be running."
  rm -f "$RUNDIR/auth" "$WORKCFG" "$RUNDIR/openvpn.log"
  exit 0
fi

ADMIN_PW=$(ask "macOS admin password (to stop the VPN):") || { echo "Cancelled."; exit 2; }
echo "$ADMIN_PW" | sudo -S pkill -f "openvpn --config $WORKCFG" 2>/dev/null
unset ADMIN_PW

rm -f "$RUNDIR/auth" "$WORKCFG" "$RUNDIR/openvpn.log"
echo "VPN stopped and temporary files removed."
