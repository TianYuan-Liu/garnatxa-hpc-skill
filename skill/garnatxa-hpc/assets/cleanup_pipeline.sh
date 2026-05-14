#!/bin/bash
# cleanup_pipeline.sh — cancel a Nextflow / Snakemake pipeline cleanly,
# children first then the master, and OPTIONALLY clean its work directory.
#
# Usage:
#   bash cleanup_pipeline.sh <MASTER_JOBID> [--purge-work <work_dir>]
#
# Why children first: if you scancel the master before its children, the
# children are orphaned in the queue until they finish or hit their own
# wall time.

set -euo pipefail

MASTER="${1:?usage: $0 <master_jobid> [--purge-work <work_dir>]}"
PURGE_DIR=""
if [ "${2:-}" = "--purge-work" ]; then PURGE_DIR="${3:?--purge-work needs a directory}"; fi

# Sanity — verify master belongs to current user
OWNER=$(ssh garnatxa "sacct -j $MASTER -X -P -n --format=user" | head -1 | tr -d ' ')
if [ "$OWNER" != "$USER" ]; then
  echo "job $MASTER belongs to user '$OWNER', not '$USER' — refusing." >&2
  exit 1
fi

echo "finding pipeline children of $MASTER..."
ssh garnatxa "
  master_name=\$(sacct -j $MASTER -X -P -n --format=jobname | head -1 | tr -d ' ')
  echo \"master name: \$master_name\"

  # Nextflow names children nf-PROCESSNAME, Snakemake names them snakemake_<runid>
  if [[ \"\$master_name\" =~ ^(nextflow|snakemake) ]] || [[ \"\$master_name\" == *Launcher* ]]; then
    echo \"=== children currently in queue ===\"
    squeue -u $USER -h -o '%i %j' | grep -E '^[0-9]+ (nf-|snakemake_)'
  else
    echo \"WARNING: master name '\$master_name' doesn't look like a Nextflow/Snakemake launcher.\"
    echo \"will only cancel the master itself.\"
  fi
"

echo
read -rp "scancel children listed above THEN master $MASTER? [y/N] " ok
case "$ok" in
  y|Y|yes) ;;
  *) echo "aborted, no scancel issued."; exit 0 ;;
esac

ssh garnatxa "
  master_name=\$(sacct -j $MASTER -X -P -n --format=jobname | head -1 | tr -d ' ')
  # Cancel children by name pattern
  squeue -u $USER -h -o '%i %j' | awk '\$2 ~ /^(nf-|snakemake_)/ {print \$1}' \
    | xargs -r scancel
  scancel $MASTER
"
echo "scancel issued. let SLURM settle..."
sleep 5
ssh garnatxa "squeue -u $USER"

if [ -n "$PURGE_DIR" ]; then
  echo
  echo "DANGEROUS: about to rm -rf $PURGE_DIR on garnatxa."
  echo "make sure nothing depends on -resume from this directory."
  read -rp "type 'PURGE' to confirm: " confirm
  if [ "$confirm" = "PURGE" ]; then
    ssh garnatxa "rm -rf $PURGE_DIR"
    echo "purged."
  else
    echo "not purged."
  fi
fi
