#!/bin/bash
# resubmit_with_bumped_resources.sh — given a finished job ID and its
# original sbatch script, rewrite the resource requests using the actual
# MaxRSS / E.CPU from sacct_ (× 1.5 headroom by default), then submit.
#
# Usage:
#   bash resubmit_with_bumped_resources.sh <ORIGINAL_JOBID> <ORIGINAL_SBATCH> [SAFETY_FACTOR]
#
# - ORIGINAL_JOBID  : the job that hit OOM / TIMEOUT / poor efficiency
# - ORIGINAL_SBATCH : path to the .sh that was sbatched (locally or on cluster)
# - SAFETY_FACTOR   : multiplier on observed peak (default 1.5)
#
# This script asks for confirmation before submitting and never touches
# the original script.  Output is a new sibling file with `.bumped.sh`
# appended.

set -euo pipefail

JOBID="${1:?usage: $0 <jobid> <sbatch_path> [safety_factor]}"
SBATCH="${2:?usage: $0 <jobid> <sbatch_path> [safety_factor]}"
FACTOR="${3:-1.5}"

[ -f "$SBATCH" ] || { echo "no such file: $SBATCH" >&2; exit 1; }

echo "reading actual usage of $JOBID from sacct_..." >&2

# Pull peak RSS (KB) and elapsed seconds from sacct
read -r MAXRSS_KB ELAPSED REQMEM REQCPU < <(ssh garnatxa "
  sacct -j $JOBID.batch -n -X -P \
    --format=maxrss,elapsed,reqmem,reqcpus \
  | head -1 | tr '|' ' '
")

# Normalize MaxRSS to GB
maxrss_gb=$(awk -v kb="${MAXRSS_KB%K}" 'BEGIN { printf "%.1f", kb/1048576 }')
new_mem_gb=$(awk -v m="$maxrss_gb" -v f="$FACTOR" 'BEGIN { printf "%d", (m*f)+1 }')

echo "  observed MaxRSS:    ${maxrss_gb} GB"
echo "  requested mem was:  ${REQMEM}"
echo "  → new --mem:        ${new_mem_gb}G"

# Also: was elapsed close to timelimit? If yes, bump --time.
ELAPSED_S=$(awk -F: '{ if (NF==3) print ($1*3600 + $2*60 + $3); else if (NF==4) {split($1, a, "-"); print (a[1]*86400 + a[2]*3600 + $2*60 + $3)} }' <<< "$ELAPSED")
HOURS=$(awk -v s="$ELAPSED_S" -v f="$FACTOR" 'BEGIN { printf "%.0f", (s*f)/3600 }')
[ "$HOURS" -lt 1 ] && HOURS=1
new_time="$((HOURS+1)):00:00"
echo "  elapsed:            ${ELAPSED} (≈ ${ELAPSED_S}s)"
echo "  → new --time:       ${new_time}"

# Produce the bumped script
OUT="${SBATCH%.sh}.bumped.sh"
cp "$SBATCH" "$OUT"
sed -i.bak -E "s|^#SBATCH\\s+--mem[= ][^[:space:]]+|#SBATCH --mem=${new_mem_gb}G|" "$OUT"
sed -i.bak -E "s|^#SBATCH\\s+--time[= ][^[:space:]]+|#SBATCH --time=${new_time}|" "$OUT"
rm -f "$OUT.bak"

echo
echo "wrote bumped sbatch to: $OUT"
echo
echo "diff vs original:"
diff -u "$SBATCH" "$OUT" || true
echo

read -rp "submit it? [y/N] " ok
case "$ok" in
  y|Y|yes) ;;
  *) echo "not submitted."; exit 0 ;;
esac

NEW=$(ssh garnatxa "cd $(dirname "$OUT") && sbatch --parsable $(basename "$OUT")")
echo "submitted: $NEW"
