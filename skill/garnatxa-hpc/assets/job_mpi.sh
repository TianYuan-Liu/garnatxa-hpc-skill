#!/bin/bash
# MPI job across multiple nodes on Garnatxa.
# Load the same MPI module that was used at build time (openmpi4 here).

#SBATCH --job-name=<JOB_NAME>
#SBATCH --output=<JOB_NAME>_%j.out
#SBATCH --error=<JOB_NAME>_%j.err
#SBATCH --qos=short
#SBATCH --nodes=2                    # request multiple nodes
#SBATCH --ntasks=80                  # total MPI ranks
#SBATCH --cpus-per-task=1            # threads per rank (>=2 for hybrid MPI+OpenMP)
#SBATCH --mem-per-cpu=2G             # total = ntasks * cpus-per-task * mem-per-cpu
#SBATCH --time=01:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=<YOU@example.org>

set -euo pipefail

module load openmpi4                 # must match the MPI used to build the binary

mpirun -np $SLURM_NTASKS <your_mpi_binary> <args>
