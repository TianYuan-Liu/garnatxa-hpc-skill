# garnatxa-hpc-skill

[![lint](https://github.com/TianYuan-Liu/garnatxa-hpc-skill/actions/workflows/lint.yml/badge.svg)](https://github.com/TianYuan-Liu/garnatxa-hpc-skill/actions/workflows/lint.yml)

A [Claude Code](https://claude.com/claude-code) skill that turns Claude Code
into a **hands-on operator** for the **Garnatxa HPC cluster** at
[I2SysBio](https://www.uv.es/institute-integrative-systems-biology-i2sysbio/en/)
(UV / CSIC, Valencia).

Once installed, Claude Code can directly **SSH into the cluster, inspect your
jobs, diagnose failures, right-size resource requests, and act on the cluster
on your behalf** — not just answer questions in the abstract. The skill
encodes the Garnatxa-specific details (hostnames, partitions, QoS limits,
modules, tape system, GitLab, VPN) so the agent uses the right commands
instead of generic SLURM advice.

## What the agent can do for you

With your SSH config already in place (i.e. `ssh garnatxa` works), Claude
Code will reach into the cluster directly to:

- Check what's queued / running / finished — `squeue`, `squeue_`, `sacct`,
  `sacct_`
- Diagnose stuck `PD` jobs and `AssocGrpCpuLimit` / `QOSMaxCpuPerUserLimit`
  reasons
- Pull CPU and memory efficiency for finished jobs and propose right-sized
  replacements (Garnatxa's policy: ≥ 75 % CPU and memory efficiency)
- Read your `slurm-<jobid>.out`/`.err` to find the actual error
- Write complete, copy-pasteable sbatch scripts that target the right QoS
  (`short` / `medium` / `long` / `long-mem`)
- Build Nextflow / Snakemake configs for the Garnatxa SLURM executor
- Walk you through `ssh merlot` + `tapecopy` for archiving to LTO-9 tape
- Resolve VPN / SSH / firewall / password-rotation issues
- Set up the GitLab + VSCode-rsync workflow

The agent **runs read-only diagnostic commands without asking** (they're
safe) but **confirms before anything destructive or shared-impact** —
`scancel -u $USER`, large `sbatch` submissions, `rm -rf`, tape writes of
TBs, shell-config edits.

### Example session

```
> Can you check on my running jobs and any way to improve them?

Claude reaches into Garnatxa, runs:
  ssh garnatxa 'squeue -u $USER --long ; squeue_ -u $USER ; sacct_ -b -u $USER'

…and replies with:
  • Your last 3 jobs used only 1-6 CPUs out of the 16-32 you requested
  • Memory efficiency was 2-3% on two of them
  • Two earlier jobs hit TIMEOUT — try medium QoS
  • Here's a drop-in template tuned to your actual usage…
```

## Install

Prerequisites: a working `ssh garnatxa` (via VPN if you're off-network) and
[Claude Code](https://claude.com/claude-code).

```sh
git clone https://github.com/TianYuan-Liu/garnatxa-hpc-skill.git
ln -sfn "$PWD/garnatxa-hpc-skill/skill/garnatxa-hpc" ~/.claude/skills/garnatxa-hpc
```

Open a new Claude Code session in any directory — the skill auto-loads when
the conversation touches anything Garnatxa-related. Try:

```
> How do I submit a STAR alignment with 12 threads and 30 GB RAM on Garnatxa?
> My job 2792866_11 just failed — what happened and how do I fix it?
> Archive /storage/mygroup/projectX/ to tape, but check sizes first.
```

If you don't already have `ssh garnatxa` configured, see
[`skill/garnatxa-hpc/references/connecting.md`](skill/garnatxa-hpc/references/connecting.md)
— it walks the agent (and you) through VPN setup, key install, and password
rotation.

## What's in the skill

```
skill/garnatxa-hpc/
├── SKILL.md                  # entry — cluster facts, QoS table, decision routing,
│                             #   operating mode (read-only freely, confirm before
│                             #   destructive)
├── references/               # deep dives loaded on demand by the agent
│   ├── connecting.md           # SSH, VPN, firewall, first login
│   ├── slurm.md                # full SLURM reference + templates
│   ├── software.md             # modules, mamba, Singularity, biotools bundle
│   ├── pipelines.md            # Nextflow + Snakemake on the SLURM executor
│   ├── storage.md              # /home, /storage, /scr, tape
│   ├── policies.md             # QoS, quotas, acknowledgment
│   ├── gitlab-vscode.md        # GitLab + rsync-on-save workflow
│   └── hardware.md             # nodes, CPUs, Ceph, tape library
└── assets/                   # ready-to-edit templates
    ├── job_serial.sh,  job_threaded.sh,  job_mpi.sh,  job_array.sh
    ├── launcher_dependency.sh
    ├── nextflow.config,        nextflow_launcher.sbatch
    └── snakemake_profile.yaml, snakemake_launcher.sbatch
```

## Safety model

The agent treats the cluster like any other production system:

- **Read-only diagnostics** (squeue, sacct, sinfo, scontrol show, cat
  slurm-*.out, sshare, sprio, module avail, ls, df, du_, checkdiskspace) —
  no confirmation needed.
- **Submitting a small sbatch job** (≤ 1 CPU, low memory, short QoS) — usually
  no confirmation needed if it directly answers the user's request.
- **Submitting a large job, `scancel`-ing, writing to tape, deleting files,
  modifying shell config, force-pushing** — confirmation required first.

These rules live in `SKILL.md` and apply to any agent that loads the skill.

## Source of truth

The official documentation at <https://garnatxadoc.uv.es/>. Every cluster
fact in this skill was verified against the live cluster
(`sinfo`, `sacctmgr show qos`, `module avail`, etc.) at the time of writing.
Clusters drift — when in doubt, ask the agent to run the relevant check or
open an issue here.

## Contributing

Drift updates and additional reference docs are welcome — open an issue or a
PR. Mention the cluster command output you ran to confirm the new fact;
that's the most useful kind of contribution as the cluster evolves.

## Licence

[MIT](LICENSE). The I2SysBio documentation at <https://garnatxadoc.uv.es/>
is © I2SysBio and is **not** redistributed here.

## Acknowledgment

If you publish results obtained on Garnatxa, please use the official
acknowledgment text (see
[`skill/garnatxa-hpc/references/policies.md`](skill/garnatxa-hpc/references/policies.md))
and email a copy of the paper to `i2sysbiohpc@uv.es`.
