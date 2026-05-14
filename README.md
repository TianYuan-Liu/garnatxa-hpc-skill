# garnatxa-hpc-skill

A [Claude Code](https://claude.com/claude-code) skill for the **Garnatxa HPC
cluster** at [I2SysBio](https://www.uv.es/institute-integrative-systems-biology-i2sysbio/en/)
(UV / CSIC, Valencia).

Gives Claude Code concrete, copy-pasteable answers about Garnatxa instead of
generic SLURM advice — right hostnames, right partitions and QoS, right
`module load` names, the cluster-specific tooling (`squeue_`, `sacct_`,
`plotjob`, `interactive`, `tapecopy` / `ssh merlot`), and the published usage
policies.

## What it covers

- SSH / VPN setup (`i2sysbio.ovpn`, UV VPN) and firewall expectations
- SLURM submission and monitoring — sbatch, srun, sacct, squeue, scancel,
  sinfo, plus the Garnatxa-only `squeue_` / `sacct_` / `plotjob` efficiency
  tools
- Choosing the right QoS (`short` / `medium` / `long` / `long-mem` / `extra` /
  `tape`)
- Job-script patterns — serial, threaded, MPI, array, dependencies
- The Lmod module system, mamba / conda environments, Singularity containers
- Nextflow and Snakemake pipelines on the SLURM executor
- `/home`, `/storage`, `/scr` filesystem layout and quotas
- Tape archive via `ssh merlot` + `tapecopy`
- Self-hosted GitLab + VSCode-rsync workflow
- Usage policies and the required publication acknowledgment

## Install

```sh
git clone https://github.com/TianYuan-Liu/garnatxa-hpc-skill.git
ln -sfn "$PWD/garnatxa-hpc-skill/skill/garnatxa-hpc" ~/.claude/skills/garnatxa-hpc
```

Open a new Claude Code session in any directory. The skill auto-loads when
the conversation touches anything Garnatxa-related. Try:

```
> How do I submit a STAR alignment with 12 threads and 30 GB RAM on Garnatxa?
> My job is stuck in PD with reason AssocGrpCpuLimit, what does that mean?
> How do I archive a directory to tape?
```

## Layout

```
skill/garnatxa-hpc/
├── SKILL.md                  # entry — cluster facts, QoS table, decision routing
├── references/               # deep dives loaded on demand
│   ├── connecting.md           # SSH, VPN, firewall
│   ├── slurm.md                # full SLURM reference + templates
│   ├── software.md             # modules, mamba, Singularity, biotools
│   ├── pipelines.md            # Nextflow + Snakemake on SLURM
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

## Source of truth

The official documentation at <https://garnatxadoc.uv.es/>. Every
cluster-specific claim in this skill was verified against the live cluster
(`sinfo`, `sacctmgr show qos`, `module avail`, etc.) at the time of writing.
Things drift — when in doubt, check the live docs or open an issue.

## Contributing

Drift updates and additional reference docs are welcome — open an issue or a
PR. Mention the cluster command output you ran to confirm the new fact;
that's the most useful kind of contribution as the cluster evolves.

## Licence

[MIT](LICENSE). The I2SysBio documentation at <https://garnatxadoc.uv.es/>
is © I2SysBio and is **not** redistributed here.

## Acknowledgment

If you publish results obtained on Garnatxa, please use the official
acknowledgment text (see [`skill/garnatxa-hpc/references/policies.md`](skill/garnatxa-hpc/references/policies.md))
and email a copy of the paper to `i2sysbiohpc@uv.es`.
