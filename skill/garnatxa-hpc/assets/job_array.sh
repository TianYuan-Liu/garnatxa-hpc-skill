#!/bin/bash
# Array job: one SLURM task per input file under data/
# Max array size on Garnatxa: 5000.
#
# Concurrency cap (the `%N` after the range) — pick `N` so
#   N × cpus-per-task ≤ your QoS user-CPU cap
# (short=200, medium=150, long=100, long-mem=80 per `slurm.md`).
# E.g. cpus-per-task=8 + short → use %25 (25 × 8 = 200).

#SBATCH --job-name=<JOB_NAME>
#SBATCH --output=<JOB_NAME>_%A_%a.out
#SBATCH --error=<JOB_NAME>_%A_%a.err
#SBATCH --qos=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=02:00:00
#SBATCH --array=0-19%50              # %50 = at most 50 tasks running at once
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=<YOU@example.org>

set -euo pipefail

module load <YOUR_MODULE>

# Optional: use /scr/$USER as a per-job working directory.  /scr is Ceph-shared
# (same backend as /home and /storage, NOT node-local) and not auto-cleaned,
# so always tidy up at end of script.  This pattern keeps transient outputs
# out of your group's /storage quota.
#
#   WORKDIR=/scr/$USER/$SLURM_ARRAY_JOB_ID/${SLURM_ARRAY_TASK_ID}
#   mkdir -p "$WORKDIR" && cd "$WORKDIR"
#   trap 'cd / && rm -rf "$WORKDIR"' EXIT

# One option: glob the data directory and pick by index.
FILES=(data/*)
INPUT=${FILES[$SLURM_ARRAY_TASK_ID]}
NAME=$(basename "$INPUT" .fq)

# Another option (uncomment): read the Nth line of a manifest file.
# INPUT=$(sed -n "${SLURM_ARRAY_TASK_ID}p" inputs.txt)

mkdir -p out
srun <your_command> "$INPUT" > "out/${NAME}.result"

# Reminder: any one-shot setup (e.g. building an index) should NOT live here
# — it would re-run once per array task. Put it in a separate sbatch and
# launch this array with `-d afterok:<setup_jobid>` (see launcher_dependency.sh).
