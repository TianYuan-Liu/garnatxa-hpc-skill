#!/bin/bash
# Snakemake master launcher.  Submit with:
#
#   sbatch snakemake_launcher.sbatch
#
# The master process stays alive for the WHOLE pipeline duration.  Pick a QoS
# whose time limit safely outlasts the longest expected pipeline step.

#SBATCH --job-name=snakemakeMaster
#SBATCH --output=snakemake_%j.out
#SBATCH --error=snakemake_%j.err
#SBATCH --qos=medium                 # raise to long for multi-day pipelines
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1            # master is light; do NOT over-allocate
#SBATCH --mem=1G
#SBATCH --time=2-00:00:00            # 2 days; raise as needed

set -euo pipefail

# Snakemake is installed per-user via mamba.  See references/pipelines.md.
module load anaconda
mamba activate snakemake

snakemake \
    --slurm-jobname-prefix snakemake \
    --profile ./Snakeconfig.yaml
