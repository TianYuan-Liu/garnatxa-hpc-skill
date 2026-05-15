# garnatxa-hpc-skill

[![lint](https://github.com/TianYuan-Liu/garnatxa-hpc-skill/actions/workflows/lint.yml/badge.svg)](https://github.com/TianYuan-Liu/garnatxa-hpc-skill/actions/workflows/lint.yml)

**Your agent is the HPC user. You're just the scientist.**

Tell your coding agent — [Claude Code](https://claude.com/claude-code),
[Codex CLI](https://developers.openai.com/codex), or
[Gemini CLI](https://github.com/google-gemini/gemini-cli) — what you want
done. It finds your data on the cluster, loads the right modules, writes
the right sbatch, picks the right QoS, submits to the right partition,
waits for it to finish, reads the efficiency numbers, diagnoses failures,
and ships the results back to your machine.

No sbatch headers. No `squeue` refreshing in the other terminal. No `ssh
merlot` to remember. No "wait, what was the right partition again."

---

## A normal afternoon

```text
> The latest basecalls just landed for run 42. Should be ~50 paired-end
  FASTQ files somewhere under /storage/gge/Tian/seq/. Align them to hg38
  with bwa and put the BAMs somewhere reasonable. Ping me when done.

  • garnatxa ssh: 50 FASTQs in /storage/gge/Tian/seq/basecalls-2/  (1.4 TB)
  • fairshare 0.45 — picking --qos=short
  • writing 50-task array, --cpus-per-task=4 --mem=16G --time=2:00:00,
    --array=1-50%50  (50 × 4 = 200 ≤ short cap of 200 CPUs/user)
    module load biotools (samtools 1.21, bwa 0.7.17)
  • submitted as job 2810123. polling every 30 s.
  …
  • 38 min later — all 50 tasks COMPLETED.
    mean CPU 81%, mean mem 62%, both above the 75% / 30% target
  • 50 BAMs in /storage/gge/projects/run42/bams/  (280 GB)
  • cleaned up /scr/tyuan/2810123/

  Want me to run `samtools flagstat` on each and rsync the summary to your
  laptop?

> yes, into ~/Desktop/run42_qc.tsv
```

That's the loop. The skill knows your cluster: the right modules, the right
QoS, where scratch lives, how to read `sacct_` for efficiency, why a job is
pending. So you don't have to.

---

## You'll also want it for…

**Finding out what just failed.**

```text
> jobs 2792866_11 through _15 died last night, look into it.

  • pulled slurm-2792866_11.err:  ModuleNotFoundError: 'encodings'
  • diagnosis: PYTHONHOME from a previous mamba env leaked in
  • patched the sbatch: `module purge` before `mamba activate`
  • resubmitted only the failed indices: sbatch --array=11-15 …
  • ETA ~30 min — will notify
```

**Realizing you've been wasting allocation.**

```text
> am i using the cluster well?

  • last 3 jobs: 1/16 CPU (4%), 5/16 (31%), 6/32 (19%)
  • you ask for ~5× the cores and 30× the RAM you actually use
  • that's why your fairshare is 0.995 — future jobs queue longer
  • drop-in template tuned to your real MaxRSS:
    --cpus-per-task=8  --mem=8G  --time=12:00:00
```

**Archiving a finished project.**

```text
> we're done with /storage/gge/Tian/2024-fiberseq, archive it.

  • size 4.8 TB / 14 232 files — fits one LTO-9 (NCR001L9, 16 TB free)
  • sha-256 manifest → /home/tyuan/manifests/2024-fiberseq.sha256
  • ssh merlot; tapecopy submitted; monitoring jobtape_20260514….out
  • 3 h later — tape COMPLETED. sample-verified 10 random files.
  • waiting for your "yes, delete the original" before rm.
```

**Launching a pipeline.** You say "run my Nextflow pipeline on the new samples
with the GRCh38 reference"; the agent picks the master QoS so it outlives the
slowest child, sets `clusterOptions = '--qos=short'`, watches the master log,
cleans `work/` on success, and saves the HTML report to your laptop.

**Setting up a brand-new account.** "I just got my Garnatxa credentials" →
walks you through VPN config, key install, password rotation, `module save`
of a sensible default environment, and an initial GitLab repo with the right
`.gitignore`.

---

## What makes this different

This isn't a chat wrapper over `man sbatch`. The skill encodes everything
that's *specifically Garnatxa* — and the agent reaches into the cluster over
SSH to do the work for real:

- The right QoS for the time you asked for (`short` ≤ 1 d, `medium` ≤ 7 d,
  `long` ≤ 15 d, `long-mem` for the big-RAM stuff).
- The right modules — `biotools/2` for most bio work, `nextflow/25.10.2`,
  the `anaconda` module to get `mamba`.
- The 200 / 1300 / 100 / 80 per-QoS CPU caps so it doesn't blow your
  fairshare.
- That `/scr` is Ceph-shared and isn't auto-cleaned. That `/tape2` is only
  on `merlot`. That `module` isn't in non-interactive SSH (the agent uses
  `bash -lc`).  That `scontrol show job` only sees recent jobs and old ones
  need `sacct -P --format=workdir%80`.
- The htslib mismatch trap when you mix `module load samtools` with a
  `mamba` env that has bcftools.

Every one of these facts was verified against the live cluster the day this
skill was published.

---

## Install

You need:

- A working `ssh garnatxa` (i.e. VPN connected, key registered).
- One of [Claude Code](https://claude.com/claude-code),
  [Codex CLI](https://developers.openai.com/codex), or
  [Gemini CLI](https://github.com/google-gemini/gemini-cli).

The skill follows the [Agent Skills](https://www.agensi.io/learn/agent-skills-open-standard)
open standard — the same `SKILL.md` file works in every agent that
supports it. Pick the symlink target for the agent(s) you use:

```sh
git clone https://github.com/TianYuan-Liu/garnatxa-hpc-skill.git
SRC="$PWD/garnatxa-hpc-skill/skill/garnatxa-hpc"

# Claude Code (personal skills directory)
mkdir -p ~/.claude/skills && ln -sfn "$SRC" ~/.claude/skills/garnatxa-hpc

# Codex CLI (canonical) + Gemini CLI (via the .agents/ alias)
mkdir -p ~/.agents/skills && ln -sfn "$SRC" ~/.agents/skills/garnatxa-hpc
```

If you only use Gemini CLI and prefer its native path, symlink into
`~/.gemini/skills/` instead — Gemini picks up either location.

Open a new agent session anywhere. It auto-loads when the conversation
touches Garnatxa. If `ssh garnatxa` isn't set up yet, just open your
agent and say *"set me up to use the Garnatxa cluster from this laptop"*
— it'll walk you through it.

---

## Safety

The agent treats your cluster account like a production system:

- **Read-only diagnostics** (`squeue`, `sacct`, `sinfo`, `scontrol show`,
  tailing slurm logs, `du`) — runs freely.
- **Small sbatch submissions** — runs if you clearly asked.
- **`scancel`, big submissions, `rm -rf`, tape writes, shell-config or
  `~/.ssh/` edits, GitLab pushes** — confirms before doing.

These rules live in [`skill/garnatxa-hpc/SKILL.md`](skill/garnatxa-hpc/SKILL.md)
and apply to any agent that loads the skill.

---

## What's in it

```
skill/garnatxa-hpc/
├── SKILL.md                  # entry: cluster facts, routing, operator gotchas
├── references/
│   ├── operator-loop.md         # how the agent drives the cluster end-to-end
│   ├── troubleshooting.md       # ~20 failure modes: symptom → diagnostic → fix
│   ├── scenarios.md             # 14 step-by-step playbooks
│   ├── connecting.md            # SSH, VPN, firewall, first login
│   ├── slurm.md                 # full SLURM reference + templates
│   ├── software.md              # modules, mamba, Singularity, biotools
│   ├── pipelines.md             # Nextflow + Snakemake on the SLURM executor
│   ├── storage.md               # /home, /storage, /scr, tape
│   ├── policies.md              # QoS, quotas, acknowledgment
│   ├── gitlab-vscode.md         # GitLab + rsync-on-save workflow
│   └── hardware.md              # nodes, CPUs, Ceph, tape library
└── assets/
    ├── preflight.sh                       # 1-shot SSH/VPN/tooling probe
    ├── wait_for_job.sh                    # local poll-until-done helper
    ├── resubmit_with_bumped_resources.sh  # right-size from sacct, confirm, submit
    ├── cleanup_pipeline.sh                # kill children → master → optional work/ purge
    ├── ssh_config.template                # ControlMaster + ProxyJump merlot
    └── job_*.sh / *_launcher.sbatch / *.config / *.yaml
                                          # ready-to-edit job & pipeline templates
```

Source of truth: the official I2SysBio docs at <https://garnatxadoc.uv.es/>.
Open an issue if you spot drift.

---

## Contributing

Drift updates and additional playbooks are welcome — open an issue or a PR.
Mention the actual cluster output you ran to confirm the new fact; that's
the most useful kind of contribution as the cluster evolves.

## Licence

[MIT](LICENSE). The I2SysBio docs at <https://garnatxadoc.uv.es/> are
© I2SysBio and are not redistributed here.

## Acknowledgment

If you publish results obtained on Garnatxa, please use the official text
(see [`skill/garnatxa-hpc/references/policies.md`](skill/garnatxa-hpc/references/policies.md))
and email a copy of the paper to `i2sysbiohpc@uv.es`.
