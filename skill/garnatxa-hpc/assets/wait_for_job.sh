#!/bin/bash
# wait_for_job.sh — poll a SLURM job to completion and exit with a code
# that reflects its final state.  Run locally, not on the login node:
#
#   bash wait_for_job.sh <JOBID> [INTERVAL_SECONDS]
#
# Exit codes:
#   0   — job ended COMPLETED
#   1   — job ended FAILED / TIMEOUT / CANCELLED / OUT_OF_MEMORY / NODE_FAIL
#   2   — could not reach the cluster
#
# Uses `ssh garnatxa` (assumes the host alias is configured).  Polling
# happens locally so the 8-hour SSH idle timeout (TMOUT=28800) doesn't
# kill the watch.

set -u

JOBID="${1:?usage: $0 <jobid> [interval_seconds]}"
INTERVAL="${2:-30}"

# Cap polling frequency
if [ "$INTERVAL" -lt 10 ]; then INTERVAL=10; fi

echo "waiting for job $JOBID (poll every ${INTERVAL}s)" >&2

while :; do
  STATE=$(ssh garnatxa "sacct -j $JOBID -X -n -P --format=state 2>/dev/null" \
          | head -1 | tr -d ' ')

  case "$STATE" in
    "")
      # Scheduler hasn't picked it up yet (or job doesn't exist)
      echo "$(date +%H:%M:%S)  $JOBID  (no state yet)" >&2
      ;;
    PENDING|RUNNING|CONFIGURING|COMPLETING|RESIZING|REQUEUED)
      echo "$(date +%H:%M:%S)  $JOBID  $STATE" >&2
      ;;
    COMPLETED)
      echo "$(date +%H:%M:%S)  $JOBID  COMPLETED" >&2
      ssh garnatxa "TERM=xterm sacct_ -j $JOBID 2>/dev/null"
      exit 0
      ;;
    FAILED|TIMEOUT|CANCELLED|OUT_OF_MEMORY|NODE_FAIL|BOOT_FAIL|DEADLINE|PREEMPTED)
      echo "$(date +%H:%M:%S)  $JOBID  $STATE" >&2
      ssh garnatxa "TERM=xterm sacct_ -j $JOBID 2>/dev/null"
      # Try to show the tail of stderr if we can find it
      ssh garnatxa "
        wd=\$(sacct -j $JOBID -P --format=workdir%120 | tail -1 | tr -d ' ')
        if [ -n \"\$wd\" ]; then
          find \"\$wd\" -maxdepth 2 -name '*$JOBID*err*' -print -exec tail -30 {} \\;
        fi
      " 2>/dev/null
      exit 1
      ;;
    *)
      echo "$(date +%H:%M:%S)  $JOBID  $STATE (unfamiliar)" >&2
      ;;
  esac

  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 garnatxa true 2>/dev/null; then
    echo "lost connection to garnatxa" >&2
    exit 2
  fi

  sleep "$INTERVAL"
done
