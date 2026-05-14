#!/bin/bash
# Orchestrator: submit a one-off setup job, then an array job that only runs
# if the setup succeeds.  Run this on the login node:
#
#   bash launcher_dependency.sh
#
# Adapt the names of the two sbatch scripts as needed.

set -euo pipefail

# Step 1: setup (e.g. build an index, download a reference). One job.
jobid_setup=$(sbatch --parsable setup.sh)
echo "Setup job:  $jobid_setup"

# Step 2: array job that runs once per input file.  Gated on setup success.
jobid_array=$(sbatch --parsable -d afterok:$jobid_setup job_array.sh)
echo "Array job:  $jobid_array (waits on $jobid_setup)"

# Step 3 (optional): a final aggregation job that runs after the whole array.
# jobid_final=$(sbatch --parsable -d afterok:$jobid_array aggregate.sh)
# echo "Final job:  $jobid_final"
