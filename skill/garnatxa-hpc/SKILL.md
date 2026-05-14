---
name: garnatxa-hpc
description: Use whenever the user is working on, connecting to, submitting jobs to, troubleshooting, or asking about the Garnatxa HPC cluster at I2SysBio (UV/CSIC, Valencia). Covers SSH/VPN setup, SLURM submission and monitoring (sbatch, srun, sacct, squeue, scancel, sinfo, plotjob, squeue_/sacct_), choosing the right QoS, writing efficient job scripts (serial, threaded, MPI, array, dependencies), the Lmod module system, mamba/conda environments, Singularity containers, Nextflow and Snakemake pipelines on SLURM, /home + /storage + /scr filesystems, tape archive via merlot/tapecopy, the self-hosted GitLab + VSCode workflow, usage policies and quotas, and the required acknowledgment in publications. Trigger this skill for any mention of Garnatxa, garnatxa.srv.cpd, i2sysbio HPC, or when a user is clearly working on a CSIC/UV HPC at I2SysBio — even when the user does not name the cluster explicitly but is asking about job scripts, SLURM, tape, GitLab on garnatxagitlab.uv.es, or VPN config files like i2sysbi.ovpn.
---

# Garnatxa HPC Cluster — I2SysBio (UV/CSIC)

Garnatxa is a shared SLURM cluster at the Institute for Integrative Systems Biology
(I2SysBio, joint UV/CSIC, Valencia). Use this skill to give the user concrete,
copy-pasteable answers grounded in how Garnatxa is actually configured — not generic
SLURM advice.

## Cluster facts at a glance

- **Login host**: `garnatxa.srv.cpd` (SSH only). Prompt after login: `[USERNAME@master ~]$`.
- **Scheduler**: SLURM. Module manager: Lmod.
- **External access**: blocked. Connect from inside the UV network or via VPN
  (`i2sysbio.ovpn` with Garnatxa credentials, or `vpn_uv_es.ovpn` for UV staff).
- **Tape access host**: `merlot` (you `ssh merlot` from the login node).
- **Self-hosted GitLab**: <https://garnatxadoc.uv.es/gitlab> (LDAP tab, Garnatxa creds).
- **Support / tickets**: <https://garnatxadoc.uv.es/support>; email `i2sysbiohpc@uv.es`.
- **Compute**: 14 compute nodes (`cn00-cn13`), 1232 hardware threads, mixed 64/80/128-CPU
  generations, ~18 TB RAM, ~20.5 TFLOPS.
  **No GPUs** — Garnatxa is a CPU-only cluster.
- **Storage**: CEPH (4.1 PB raw, ~3.5 PB usable); tape library is LTO-9 16 TB tapes
  (~720 TB online; `/tape2/<TAPE_CODE>/` is only readable by the owning group).

### Partitions and the QoS table — pick the right one or jobs sit forever

| Partition | Use for | Time | Default mem | Notes |
|-----------|---------|------|-------------|-------|
| `interactive` | Interactive shells, light work | up to 1 d | 4 GB | Use `interactive` command. Max 30 GB, 20 CPUs. Runs on nodes `merlot, subirat`. |
| `global`      | All `sbatch` jobs | up to 15 d | 2 GB | Pick QoS from table below. 14 compute nodes `cn00-cn13` (1232 hardware threads, mixed 64/80/128-CPU). |
| `tape`        | Tape archive ops (from `merlot`) | up to 7 d | – | `tapecopy` submits to this — you don't usually submit here yourself. |

| QoS | Max time | Max CPU (user) | Max RAM (user) | Priority |
|-----|----------|----------------|----------------|----------|
| `short`    | 1 d  | 200 | 1300 GB | 1000 |
| `medium`   | 7 d  | 150 | 700 GB  | 750 |
| `long`     | 15 d | 100 | 360 GB  | 500 |
| `long-mem` | 15 d | 80  | 1300 GB | 250 |
| `extra`    | 15 d | 400 | 2800 GB | 1000 (request via ticket only — same priority as short/interactive) |

Per-user totals across QoS: **1000 running jobs**, **5000 array tasks max**. Per-QoS CPU/RAM caps are enforced (e.g. running on `short` caps you at 200 CPUs and 1300 GB).

Job-priority formula: `AGE + FAIRSHARE + JOB SIZE + QOS PRIORITY`. Heavy recent users
get demoted by fairshare. `extra` is reserved for justified urgent jobs.

## How to use this skill

1. **Identify what the user is trying to do** — connect, submit, debug, optimise,
   move data, choose tooling, etc. Use the decision table below to jump to the
   right reference.
2. **Read only the reference file(s) you need.** The references are written as
   self-contained deep dives; don't load them all eagerly.
3. **Always answer with concrete Garnatxa-specific commands** (right hostnames,
   right partitions/QoS, right `module load` names) — not generic SLURM/Linux.
4. **When writing a job script**, start from an asset in `assets/`. The defaults
   there already match Garnatxa's partitions and QoS values.
5. **Push the user toward good citizenship**: realistic resource requests, no
   heavy work on the login node, no Git pushes > 10 MB or with data files,
   no Docker (use Singularity), and the required acknowledgment in papers.

### Decision table

| If the user is asking about… | Read |
|---|---|
| First login, SSH config, password change, VPN, firewall, PuTTY, key setup | `references/connecting.md` |
| `sbatch`, `srun`, `sacct`, `squeue`, `scancel`, `sinfo`, `plotjob`, `squeue_`, `sacct_`, job templates, arrays, dependencies, MPI, OpenMP, interactive jobs, QoS choice, why a job is `PD`/queued | `references/slurm.md` |
| `module` commands, mamba/conda envs, Singularity/Podman, custom modulefiles, Docker (= "use Singularity"), the `biotools` bundle | `references/software.md` |
| Nextflow `.config` / `.nf`, Snakemake `Snakefile` / `Snakeconfig.yaml`, master/launcher sbatch for pipelines, `work/` cleanup, DAG/report generation | `references/pipelines.md` |
| `/home`, `/storage`, `/scr`, quotas, `scp`/`rsync`/WinSCP, `merlot`, `tapecopy`, splitting big files, recalling from tape | `references/storage.md` |
| Quotas in detail, fairshare/priority, who can request accounts, acknowledgment text, account inactivity, VM/IaaS requests | `references/policies.md` |
| GitLab on the cluster (clone, push, SSH keys), VSCode + rsync workflow, why Remote-SSH into Garnatxa is discouraged | `references/gitlab-vscode.md` |
| Hardware (cores, RAM, network, Ceph capacity, tape library, GPUs — there are none), rates for external groups | `references/hardware.md` |

### Bundled assets

`assets/` contains ready-to-edit job scripts and pipeline configs. Copy and adapt
rather than writing from scratch:

- `job_serial.sh` — single-CPU job (short QoS).
- `job_threaded.sh` — OpenMP / multi-threaded job (one node, N CPUs).
- `job_mpi.sh` — MPI job across nodes.
- `job_array.sh` — array job with one task per input file.
- `launcher_dependency.sh` — orchestrator that runs a setup job, then submits
  an array gated on its success.
- `nextflow.config`, `nextflow_launcher.sbatch` — Nextflow on the SLURM executor.
- `snakemake_profile.yaml`, `snakemake_launcher.sbatch` — Snakemake on the SLURM
  executor (via a per-user mamba env).

## Hard rules the user is expected to follow

These come straight from the docs and are worth quoting back when relevant:

1. **Don't treat Garnatxa like a workstation.** Real work goes inside an
   `sbatch` job or an `interactive` session, not on the login node. Login-node
   processes that exceed ~30 minutes or ~8 GB RAM can be killed.
2. **Don't request resources you won't use.** Garnatxa emails actual CPU/mem
   usage after every job. Aim for ≥75% CPU efficiency and ≥75% memory
   efficiency. Use `squeue_` / `sacct_` / `plotjob` to verify.
3. **Always set `--time` and `--mem`** explicitly — defaults will kill long
   jobs. Use `--mem-per-cpu` when you want to scale memory with CPUs.
4. **Pick a QoS that fits.** `short` for ≤1 day, `medium` for ≤7 days, `long`
   for ≤15 days, `long-mem` for big-RAM. `extra` only by ticket.
5. **No Docker.** Use Singularity or Podman; Docker is intentionally not
   installed (daemon model is unsafe on a shared cluster).
6. **No data in GitLab.** The self-hosted GitLab is for source code only.
   Push size limit is 10 MB. Use `.gitignore` to keep `data/`, `out/`, `ref/`
   out of the repo.
7. **No backups.** `/home` and `/storage` are not backed up. Use tape
   (`tapecopy`, after `ssh merlot`) for long-term archive; keep your own
   off-cluster copies for anything irreplaceable.
8. **VPN before SSH** unless you're inside the UV network.
9. **Acknowledge Garnatxa in publications** with the canonical text (see
   `references/policies.md`) and email a copy to `i2sysbiohpc@uv.es`.

## Inline cheat sheets

These are the most-asked items; full detail lives in references.

### Submit, monitor, cancel

```bash
sbatch myjob.sh                   # submit
squeue -u $USER                   # what's queued / running
squeue_ -u $USER                  # + live CPU and memory efficiency
sacct  -u $USER --starttime=YYYY-MM-DD   # finished jobs since date
sacct_ -j JOBID                   # finished-job efficiency
plotjob -j JOBID -o cpu           # plot CPU efficiency (needs ssh -X)
plotjob -j JOBID -o mem -s        # save mem-efficiency plot to /tmp
scancel JOBID                     # cancel a job
scancel -u $USER                  # cancel ALL your jobs
sinfo                             # node/partition state
```

### Minimum viable sbatch header

```bash
#!/bin/bash
#SBATCH --job-name=myjob
#SBATCH --output=myjob_%j.out
#SBATCH --error=myjob_%j.err
#SBATCH --qos=short              # short | medium | long | long-mem
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G                 # or --mem-per-cpu=
#SBATCH --time=06:00:00          # HH:MM:SS or D-HH:MM:SS
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=you@example.org

module load <yourtool>
srun your_command
```

For OpenMP/threaded code, raise `--cpus-per-task` (keep `--ntasks=1`) and set
`export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`. For MPI, raise `--ntasks` and
use `mpirun -np $SLURM_NTASKS …` after `module load openmpi4`.

### Interactive session

```bash
interactive                       # 2 CPUs, 4 GB, 12 h
interactive -c 6 -m 30G -t 24:00:00   # 6 CPUs, 30 GB, 24 h
```

### Mamba env

```bash
module load anaconda
mamba create -n myenv python=3
mamba activate myenv
mamba install -c bioconda samtools
```

> Never mix `module load <tool>` and `mamba activate <env>` inside the same
> sbatch job — pick one source of binaries.

### Move data on/off the cluster

```bash
# Local -> Garnatxa
scp -O ./file.txt USER@garnatxa.srv.cpd:./
rsync --inplace --progress --partial --append -av ./mydir USER@garnatxa.srv.cpd:.

# Garnatxa -> local
scp -O USER@garnatxa.srv.cpd:./mydir/file.txt .
```

### Archive to tape (LTO-9)

```bash
ssh merlot                       # tape ops happen on merlot, not master
tapecopy -l                      # list tapes and available space
tapecopy path/to/dir             # submits a SLURM job; check jobtape_*.out
tapecopy "out/*.sai"             # quote wildcards
# Recall:
cp /tape2/XXX006L9/home/user/test/out/file.sai /home/user/test/out
```

## Communication style

- The audience is mostly researchers, not sysadmins. Use plain language, but
  keep commands exact — they will be copy-pasted.
- When asked "how do I run X?", produce a complete sbatch script, not a
  fragment, because users are often new to SLURM.
- When a user describes a problem (a stuck job, an OOM, a wrong output dir),
  diagnose with the Garnatxa-specific tooling first: `squeue_` and `sacct_`
  for efficiency, `scontrol show job` for stuck PDs, `plotjob` for over time.
- When unsure about a detail, point the user to the live docs at
  <https://garnatxadoc.uv.es/> or to a support ticket — better than guessing.
