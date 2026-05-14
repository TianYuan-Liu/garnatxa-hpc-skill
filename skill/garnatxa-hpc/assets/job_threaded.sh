#!/bin/bash
# Multi-threaded (OpenMP / pthreads / single-node parallel) job on Garnatxa.
# Single node, single MPI task, N threads.

#SBATCH --job-name=<JOB_NAME>
#SBATCH --output=<JOB_NAME>_%j.out
#SBATCH --error=<JOB_NAME>_%j.err
#SBATCH --qos=medium
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8            # threads per task
#SBATCH --mem=16G                    # total memory for the job
#SBATCH --time=1-00:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=<YOU@example.org>

set -euo pipefail

# Forward the thread count to OpenMP-style tools.
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

module load <YOUR_MODULE>

# Pass $SLURM_CPUS_PER_TASK to whatever -t / -@ / --threads flag the tool uses.
srun <your_command> -t $SLURM_CPUS_PER_TASK <args>
