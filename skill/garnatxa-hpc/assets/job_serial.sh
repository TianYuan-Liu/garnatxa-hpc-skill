#!/bin/bash
# Single-CPU serial job on Garnatxa.
# Edit the placeholders marked <...> and the actual command at the bottom.

#SBATCH --job-name=<JOB_NAME>
#SBATCH --output=<JOB_NAME>_%j.out
#SBATCH --error=<JOB_NAME>_%j.err
#SBATCH --qos=short                  # short | medium | long | long-mem
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G                     # request what you'll actually use
#SBATCH --time=06:00:00              # HH:MM:SS or D-HH:MM:SS
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=<YOU@example.org>

set -euo pipefail

module load <YOUR_MODULE>

srun <your_command> <args>
