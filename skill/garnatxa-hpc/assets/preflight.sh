#!/bin/bash
# preflight.sh — one-shot operator probe for Garnatxa.
# Run as: ssh garnatxa 'bash -lc ~/garnatxa-hpc/assets/preflight.sh'
# or pipe from local: ssh garnatxa 'bash -l' < preflight.sh
#
# Prints a status block the agent can grep for known good values.

set -u
export TERM=${TERM:-xterm}

echo "=== preflight $(date -Iseconds) ==="
echo "host:        $(hostname)"
echo "user:        $(whoami)"
echo "groups:      $(id -Gn)"

# Fairshare standing (heavy use → demoted priority)
fs=$(sshare -U --noheader -P 2>/dev/null | head -1 | awk -F'|' '{print $5"/"$7}')
echo "fairshare:   ${fs:-unknown}"

# Disk usage on $HOME (which lives on Ceph /storage)
hu=$(du_ -sh "$HOME" 2>/dev/null | awk '{print $1}')
echo "home_used:   ${hu:-unknown}"

# Garnatxa-only tooling — fail loudly if any is missing
for tool in squeue_ sacct_ plotjob du_ checkdiskspace interactive; do
  if command -v "$tool" >/dev/null 2>&1 || type "$tool" >/dev/null 2>&1; then
    echo "$(printf '%-12s' "$tool:") ok"
  else
    echo "$(printf '%-12s' "$tool:") MISSING"
  fi
done

# Module system (sourced via login shell)
if command -v module >/dev/null 2>&1; then
  echo "module:      ok"
else
  echo "module:      MISSING (not a login shell?)"
fi

# Merlot reachability (for any tape work)
if ssh -o BatchMode=yes -o ConnectTimeout=3 merlot true 2>/dev/null; then
  echo "merlot ssh:  ok"
else
  echo "merlot ssh:  FAIL"
fi

# Recent activity — anything queued or running?
n_queued=$(squeue -u "$USER" -h 2>/dev/null | wc -l | tr -d ' ')
echo "jobs queued: $n_queued"

# QoS available to the user (across all assocs)
qos=$(sacctmgr -nP show user "$USER" withassoc format=qos 2>/dev/null | sort -u | head -1)
echo "qos avail:   ${qos:-unknown}"

echo "=== preflight done ==="
