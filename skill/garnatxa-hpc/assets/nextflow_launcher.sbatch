#!/bin/bash
# Nextflow master launcher.  Submit with:
#
#   sbatch nextflow_launcher.sbatch ./your_workflow.nf ./your_config.config
#
# The master process stays alive for the WHOLE pipeline duration.  Make sure
# --time outlives the slowest pipeline step, or the entire workflow is killed.

#SBATCH --job-name=nextflowMaster
#SBATCH --output=nextflow_%j.out
#SBATCH --error=nextflow_%j.err
#SBATCH --qos=short                  # raise to medium/long for longer pipelines
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1            # master is light; do NOT over-allocate
#SBATCH --mem=2G
#SBATCH --time=12:00:00              # raise as needed

set -euo pipefail

WORKFLOW=${1:?usage: sbatch nextflow_launcher.sbatch <workflow.nf> <config>}
CONFIG=${2:?usage: sbatch nextflow_launcher.sbatch <workflow.nf> <config>}

module load nextflow

nextflow -C "$CONFIG" run "$WORKFLOW" \
    -resume \
    -with-report report-${SLURM_JOB_ID}.html \
    -with-dag    dag-${SLURM_JOB_ID}.html
