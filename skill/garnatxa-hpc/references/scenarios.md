# Operational scenarios — end-to-end playbooks

End-to-end recipes for the agent acting on the user's behalf on Garnatxa.
Each scenario: trigger, steps with exact commands, confirmation points,
done criteria. Use `Ctrl-F` / `grep` to jump:

- `setup` — Scenario 1, first-time setup audit
- `single-sample` — Scenario 2, run one alignment
- `array` — Scenario 3, N-sample alignment array
- `debug` / `failed` — Scenario 4, debug a failed array
- `right-size` / `efficiency` — Scenario 5, right-size a wasteful job
- `nextflow` — Scenario 6, launch a Nextflow pipeline
- `snakemake` — Scenario 7, launch a Snakemake pipeline
- `archive` / `tape` — Scenario 8, archive a finished project to tape
- `recall` — Scenario 9, recall data from tape
- `move` / `rsync` — Scenario 10, move data on/off the cluster
- `first time` / `bootstrap` — Scenario 11, set up Nextflow/Snakemake first time
- `password` / `vpn` — Scenario 12, rotate password and update VPN
- `queued` / `pending` — Scenario 13, investigate why everything is queued
- `reset` / `cancel everything` — Scenario 14, stop everything and reset

Conventions:

- All commands assume `ssh garnatxa` works without a password.
- `$USER` inside `ssh garnatxa '...'` is the cluster username.
- "Confirm with user" = pause, summarize, wait for explicit "yes" before any
  destructive or shared-impact action: submission > 100 CPUs, `scancel -u`,
  `rm -rf`, `tapecopy`, `passwd`, writes outside `$HOME` / `/storage/<group>`.
- A blended prompt (e.g. "my array is stuck") may pull two scenarios — start
  with the read-only diagnostic loop from `SKILL.md`.

---

## Scenario 1 — First-time setup audit

**Trigger.** "I just installed the skill", "check my setup", "am I configured
correctly". Also run proactively the first time the agent talks to a user
about Garnatxa in a fresh session.

### Steps

1. **Confirm SSH works at all.**

   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=8 garnatxa 'echo ok; hostname; whoami'
   ```

   Expected: `ok`, `master`, the cluster username. If it fails with
   `Permission denied` / `Connection refused` / timeout → jump to Scenario 12.

2. **Cluster-side identity and state in one round-trip.** All read-only.

   ```bash
   ssh garnatxa '
     echo "=== identity ===";          id -un; id -gn; groups
     echo "=== home, group storage ==="; ls -ld $HOME; ls -ld /storage/* 2>/dev/null | head
     echo "=== default modules ===";   module list 2>&1 || true
     echo "=== saved collection ===";  ls ~/.lmod.d/ 2>/dev/null || echo "(none)"
     echo "=== mamba envs ===";        ls ~/.conda/envs 2>/dev/null || echo "(none)"
     echo "=== SLURM assoc ===";       sacctmgr -n show assoc user=$USER format=account,qos%40 2>/dev/null
     echo "=== fairshare ===";         sshare -U
     echo "=== last 7d jobs ===";      sacct -u $USER --starttime=$(date -d "-7 days" +%F) \
        --format=jobid%12,jobname%20,qos,state,elapsed,reqcpu,reqmem,maxrss,exitcode
   '
   ```

3. **Interpret.**
   - `module list` empty → suggest `module save` after they pick their stack.
   - `~/.conda/envs` empty → fine; Scenario 11 covers setup.
   - `sacct` empty → never submitted; recommend a tiny smoke test (Scenario 2).
   - `sshare -U` `LevelFS<0.5` and big `RawUsage` → heavy recent use; mention
     Scenario 13.

4. **Verify VPN/firewall basics.** Local to the user's machine — ASK, don't
   guess: VPN profile in use (`i2sysbio.ovpn` / `vpn_uv_es.ovpn`), local
   firewall on with inbound blocked.

### Confirm with user

Nothing to confirm — all read-only. If you later want to push an SSH key to
GitLab or save modules, that's Scenario 11.

### Done looks like

Short summary: username, group, default account; modules autoloaded (or
"none"); mamba envs; fairshare standing; last-7-days job count + % failed;
one concrete next step.

---

## Scenario 2 — Run a single-sample alignment

**Trigger.** "Run STAR on sample X", "align one FASTQ with BWA", "map this
BAM" — anything with **one sample** as input.

### Steps

1. **Gather parameters before writing anything.** Aligner + version, reference
   path, reads (PE/SE), output dir, expected wall time, CPUs, RAM. The
   `biotools/2` bundle covers `bwa`, `bowtie2`, `samtools`, `fastp`, etc.

2. **Pick QoS from stated time** (not the other way around):

   | Stated time      | QoS         |
   |------------------|-------------|
   | ≤ 1 d            | `short`     |
   | ≤ 7 d            | `medium`    |
   | ≤ 15 d           | `long`      |
   | needs > 360 GB RAM | `long-mem` |
   | urgent + justified | `extra` (ticket only) |

3. **Adapt `assets/job_threaded.sh`** — STAR/BWA are multi-threaded,
   single-node. Example BWA-MEM, paired-end:

   ```bash
   #!/bin/bash
   #SBATCH --job-name=bwa_sampleX
   #SBATCH --output=bwa_sampleX_%j.out
   #SBATCH --error=bwa_sampleX_%j.err
   #SBATCH --qos=short
   #SBATCH --nodes=1
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=12
   #SBATCH --mem=24G
   #SBATCH --time=08:00:00
   #SBATCH --mail-type=END,FAIL
   #SBATCH --mail-user=you@uv.es

   set -euo pipefail
   export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
   module load biotools

   REF=/storage/<GROUP>/refs/hg38/bwa/hg38
   R1=/storage/<GROUP>/raw/sampleX_R1.fq.gz
   R2=/storage/<GROUP>/raw/sampleX_R2.fq.gz
   OUT=/storage/<GROUP>/aln/sampleX.bam

   srun bwa mem -t $SLURM_CPUS_PER_TASK "$REF" "$R1" "$R2" \
     | srun samtools sort -@ $SLURM_CPUS_PER_TASK -o "$OUT" -
   srun samtools index -@ $SLURM_CPUS_PER_TASK "$OUT"
   ```

   For STAR: `STAR --runThreadN $SLURM_CPUS_PER_TASK --genomeDir …
   --readFilesIn …` and bump memory to ≥32 GB for human.

4. **Submit** (after confirming if non-trivial — see below):

   ```bash
   ssh garnatxa 'cd /storage/<GROUP>/jobs && sbatch align_sampleX.sh'
   # Submitted batch job 2792999
   ```

5. **Watch.** Once a minute is plenty.

   ```bash
   ssh garnatxa 'squeue -j 2792999 --long; echo; squeue_ -j 2792999 2>/dev/null'
   ```

6. **On finish, pull efficiency.**

   ```bash
   ssh garnatxa '
     sacct  -j 2792999 --format=jobid,jobname,state,elapsed,reqcpu,reqmem,maxrss,exitcode
     sacct_ -j 2792999
   '
   ```

7. **Suggest tuning.**
   - CPU eff < 75% → drop `--cpus-per-task`, or confirm tool actually uses
     `$SLURM_CPUS_PER_TASK`.
   - MEM eff < 30% → cut `--mem` to `MaxRSS × 1.2`.
   - TIMEOUT → bump `--time` and recheck QoS.
   - Ran in < 5% of `--time` on `medium` → move to `short`.

### Confirm with user

Before submitting if **any** of: `--time` > 1 day, `--cpus-per-task` > 50,
`--mem` > 100 GB, or output path is outside `/home/<USER>` or `/storage/<GROUP>`.

### Done looks like

> Job 2792999 `COMPLETED` in 2h47m on cn08. CPU eff 88%, MEM eff 64% (MaxRSS
> 15.3 GB of 24 GB). BAM at `/storage/<GROUP>/aln/sampleX.bam`, indexed.
> Next time `--mem=20G` is enough.

---

## Scenario 3 — Run an N-sample alignment array

**Trigger.** "Align these 96 samples", "20 FASTQs in `data/`, run STAR on
each", "map the whole batch".

Same as Scenario 2 but as an **array** with a separate setup-then-array
dependency.

### Steps

1. **Enumerate inputs.**

   ```bash
   ssh garnatxa 'ls /storage/<GROUP>/raw/ | wc -l;
                 ls /storage/<GROUP>/raw/ | head'
   ```

2. **Write a manifest.** Array index → one line of `samples.txt`.

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/jobs
     ls /storage/<GROUP>/raw/*_R1.fq.gz | sort > samples.txt
     wc -l samples.txt
   '
   ```

3. **Split setup from per-sample work.** The reference index must NOT be
   rebuilt 96 times. Use the `assets/launcher_dependency.sh` pattern:

   - `setup.sh` — index build, once.
   - `align_array.sh` — `--array=1-N`, reads line `$SLURM_ARRAY_TASK_ID`.
   - `launcher.sh` (run on login node, not via sbatch):

     ```bash
     #!/bin/bash
     set -euo pipefail
     jobid_setup=$(sbatch --parsable setup.sh)
     echo "Setup:  $jobid_setup"
     jobid_array=$(sbatch --parsable -d afterok:$jobid_setup align_array.sh)
     echo "Array:  $jobid_array (waits on $jobid_setup)"
     ```

4. **`align_array.sh`** — adapt `assets/job_array.sh`. `--array=1-N%K` caps
   concurrency (K × `cpus-per-task` ≤ QoS CPU cap, e.g. 200 for `short`):

   ```bash
   #!/bin/bash
   #SBATCH --job-name=bwa_array
   #SBATCH --output=logs/bwa_%A_%a.out
   #SBATCH --error=logs/bwa_%A_%a.err
   #SBATCH --qos=short
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=8
   #SBATCH --mem=20G
   #SBATCH --time=06:00:00
   #SBATCH --array=1-96%20            # 20 concurrent × 8 CPU = 160 ≤ 200

   set -euo pipefail
   mkdir -p logs out
   export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
   module load biotools

   R1=$(sed -n "${SLURM_ARRAY_TASK_ID}p" samples.txt)
   R2=${R1/_R1./_R2.}
   NAME=$(basename "$R1" _R1.fq.gz)

   srun bwa mem -t $SLURM_CPUS_PER_TASK ref/hg38 "$R1" "$R2" \
     | srun samtools sort -@ $SLURM_CPUS_PER_TASK -o out/${NAME}.bam -
   srun samtools index -@ $SLURM_CPUS_PER_TASK out/${NAME}.bam
   ```

5. **Submit after confirm.**

   ```bash
   ssh garnatxa 'cd /storage/<GROUP>/jobs && bash launcher.sh'
   ```

6. **Monitor both stages.**

   ```bash
   ssh garnatxa '
     squeue -u $USER --long
     squeue -u $USER --start | head
   '
   ```

   While the array runs:

   ```bash
   ssh garnatxa '
     squeue -u $USER --long | head -20
     echo "Outputs so far:"
     ls /storage/<GROUP>/jobs/out/*.bam 2>/dev/null | wc -l
   '
   ```

7. **Summarize at the end.**

   ```bash
   ssh garnatxa '
     sacct -j <ARRAY_JOB_ID> \
       --format=jobid%18,state,elapsed,maxrss,exitcode \
       --noheader | sort -u
   '
   ```

   Count COMPLETED / FAILED / TIMEOUT / OUT_OF_MEMORY.

### Confirm with user

- Before submission if total concurrency × CPUs > 100, or total wall > 24 h.
- Before re-running failed tasks (Scenario 4).

### Done looks like

> Array 2793077 finished. 94/96 `COMPLETED`, 2 `FAILED` (tasks 17, 63). Wall
> 5h12m. CPU eff median 81%, MEM eff median 72%. Want me to investigate the
> two failures?

---

## Scenario 4 — Debug a failed array (mix of completed + failed)

**Trigger.** "Array 2792866 had failures", "tasks 17 and 63 failed", "what
happened to task 22".

### Steps

1. **Full sacct table** — state + exit code per task.

   ```bash
   ssh garnatxa '
     sacct -j 2792866 \
       --format=jobid%20,jobname%18,state,exitcode,elapsed,reqmem,maxrss,nodelist \
       --noheader | grep -v "\.batch\|\.extern\|\.0"
   '
   ```

   Patterns:
   - `OUT_OF_MEMORY` / exit `0:125` → bump `--mem`.
   - state `TIMEOUT` → bump `--time` and/or QoS.
   - `FAILED` exit `1:0` → app error; read the log.
   - `NODE_FAIL` → not user's fault; resubmit those tasks.
   - `CANCELLED+` → user or admin cancelled.

2. **Extract failed indices.**

   ```bash
   ssh garnatxa '
     sacct -j 2792866 --format=jobid,state --noheader \
       | awk "/_[0-9]+ +FAILED|_[0-9]+ +TIMEOUT|_[0-9]+ +OUT_OF_MEMORY/ {print \$1}" \
       | sed "s/.*_//"
   '
   ```

3. **Read 1–2 `.err` files** to confirm cause. Failures usually share a root
   cause; don't read all 96.

   ```bash
   ssh garnatxa '
     for t in 17 63; do
       echo "=== task $t ==="
       tail -50 /storage/<GROUP>/jobs/logs/bwa_2792866_${t}.err
     done
   '
   ```

4. **Diagnose.**

   | Symptom | Cause | Fix |
   |---|---|---|
   | `slurmstepd: error: Detected ... oom-kill` | OOM | `--mem = MaxRSS × 1.5` |
   | `CANCELLED ... DUE TO TIME LIMIT` | TIMEOUT | bump `--time`, reconsider QoS |
   | `no such file or directory` on one input | manifest typo | fix and resubmit those indices |
   | `bwa: Could not open index` on one node | index path wrong, partial write, or setup job didn't finish | confirm with `ls -la <prefix>.amb …`; rerun setup if missing files; verify setup job `COMPLETED` |
   | `Disk quota exceeded` | group quota hit | Scenario 8 (archive) or delete |
   | `NODE_FAIL` | hardware blip | resubmit those tasks |

5. **Plan rerun — failed indices only.** SLURM array specs accept comma lists.

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/jobs
     # If OOM: bump --mem in align_array.sh first.
     sbatch --array=17,63 align_array.sh
   '
   ```

   If setup itself failed, fix setup, rerun setup, then failed indices.

### Confirm with user

- Before resubmitting if `--mem` / `--time` changed materially — show the diff.
- Before deleting partial output from failed tasks.

### Done looks like

> 94 of 96 completed; 2 OOM'd (MaxRSS 18.4 GB vs `--mem=20G`). Bumped to
> `--mem=28G` and resubmitted `--array=17,63` as job 2793021.

---

## Scenario 5 — Right-size a wasteful job from history

**Trigger.** "Am I wasting cluster time?", "audit my recent jobs", "I keep
getting efficiency emails". Also run proactively after Scenarios 2/3 if
efficiencies are bad.

### Steps

1. **Pull brief efficiency report.**

   ```bash
   ssh garnatxa '
     sacct_ -b -u $USER \
       --starttime=$(date -d "-30 days" +%F) --endtime=now 2>/dev/null
   '
   ```

2. **Find offenders.** `E.CPU < 75%` (over-CPU), `E.MEM < 30%` (over-RAM).

3. **Cross-check with cputime / MaxRSS** for the worst few:

   ```bash
   ssh garnatxa '
     sacct -j <BADID1>,<BADID2> \
       --format=jobid%18,jobname%20,reqcpu,ncpus,reqmem,maxrss,cputime,elapsed,state
   '
   ```

   Right-sizes:
   - **CPUs**: smallest `N` such that `cputime / N ≈ elapsed`. If
     `cputime/elapsed ≈ 3` despite requesting 16, recommend `--cpus-per-task=4`.
   - **Memory**: `--mem = MaxRSS × 1.2`, rounded up to next GB.

4. **Format as a diff.**

   ```diff
   -#SBATCH --cpus-per-task=16
   -#SBATCH --mem=64G
   +#SBATCH --cpus-per-task=4
   +#SBATCH --mem=10G
   ```

   Cite the cluster's stated rule (≥ 75% CPU eff, ≥ 75% MEM eff) — not
   arbitrary.

### Confirm with user

Nothing destructive — just a recommendation. If they ask to edit scripts in
place, confirm exact paths first; never overwrite shared scripts under
`/storage/<GROUP>` without explicit OK.

### Done looks like

> In 30 days you ran 47 jobs. 12 had CPU eff < 50%, 8 had MEM eff < 20%:
> - `bwa_align.sh` — drop `--cpus-per-task` 16→8, `--mem` 32G→18G (~12
>   CPU-h saved per run).
> - `gatk_hc.sh` — drop `--mem` 64G→16G (MaxRSS was 11 GB).
> Want me to write the patched scripts?

---

## Scenario 6 — Launch a Nextflow pipeline

**Trigger.** "Run my Nextflow workflow", "submit `main.nf`", "launch
nf-core/rnaseq", or anything mentioning `.nf` / `nextflow.config`.

### Steps

1. **Prereqs.**

   ```bash
   ssh garnatxa '
     module avail nextflow 2>&1 | head
     ls -la ~/.nextflow 2>/dev/null | head
   '
   ```

2. **Locate the project files.** Garnatxa convention: `NextflowJob.nf`
   (or `main.nf`), `NextflowJob.config`, `NextflowLauncher.sbatch`. If any
   missing, generate from `assets/` (or build locally and scp up).

3. **Sanity-check `*.config`:**
   - `executor = 'slurm'` (not local).
   - `queue = 'global'` (the **partition**, not the QoS).
   - QoS via `clusterOptions = '--qos=short'`.
   - Each process uses `$task.cpus` inside `script:`, not hardcoded `-t 8`.
   - `publishDir` set on every process whose output the user wants — otherwise
     it stays in `work/<hash>/`.

4. **Master `--time` must outlive the slowest child job.** Typical omics:
   `--time=2-00:00:00`, `--qos=medium`.

5. **Confirm with user, then submit.**

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/project
     sbatch NextflowLauncher.sbatch ./NextflowJob.nf ./NextflowJob.config
   '
   # Submitted batch job 2793077
   ```

6. **Monitor in two layers.**

   ```bash
   # Master log
   ssh garnatxa 'tail -40 /storage/<GROUP>/project/nextflow_2793077.out'
   # Child jobs on SLURM
   ssh garnatxa 'squeue -u $USER --long'
   # Master state
   ssh garnatxa 'sacct -j 2793077 --format=jobid,state,elapsed'
   ```

   Poll every 5–10 min. The master is named `nextflowMaster`; children are
   `nf-PROCESS_*`.

7. **On success, clean up.** `work/` for omics is often hundreds of GB.

   ```bash
   ssh garnatxa '
     ls -la /storage/<GROUP>/project/out/
     du_ -sh /storage/<GROUP>/project/work
   '
   ```

   **After explicit user confirm:**

   ```bash
   ssh garnatxa 'rm -rf /storage/<GROUP>/project/work'
   ```

   Keep `work/` if they might want `-resume`.

8. **Save report locally:**

   ```bash
   scp garnatxa:/storage/<GROUP>/project/report-2793077.html ./
   scp garnatxa:/storage/<GROUP>/project/dag-2793077.html ./
   ```

### Confirm with user

- Before submitting if estimated runtime > 1 day.
- Before `rm -rf work/`.
- Before pulling the report locally if > 50 MB.

### Done looks like

> Master 2793077 `COMPLETED` after 17 h. 312 child jobs, 0 failures. Outputs
> in `/storage/<GROUP>/project/out/`. Pulled `report-2793077.html` and
> `dag-2793077.html` locally. `work/` is 287 GB — delete it? You won't be
> able to `-resume` after.

---

## Scenario 7 — Launch a Snakemake pipeline

**Trigger.** "Run my Snakefile on the cluster", "snakemake on Garnatxa", "I
have a Snakefile + Snakeconfig.yaml".

### Steps

1. **Check the per-user mamba env.** Snakemake is **not** a system module.

   ```bash
   ssh garnatxa '
     module load anaconda 2>/dev/null
     mamba env list 2>/dev/null | head
   '
   ```

   If no `snakemake` env → Scenario 11 (snakemake section) first.

2. **Project files**: `Snakefile`, `Snakeconfig.yaml`,
   `SnakemakeLauncher.sbatch`. Generate from `assets/` if missing.

3. **Sanity-check `Snakeconfig.yaml`:**
   - `slurm_extra: "' -q short '"` — outer YAML double quotes, inner literal
     single quotes. Anything else and `sbatch` gets it wrong.
   - Each `set-threads:` entry must match an actual rule name; a typo
     silently defaults to `--cpus-per-task=1`.

4. **Master `--time`** in `SnakemakeLauncher.sbatch` must outlive the
   slowest rule. Default in the asset: `2-00:00:00` on `--qos=medium`.

5. **Confirm, submit.**

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/project
     sbatch SnakemakeLauncher.sbatch
   '
   # Submitted batch job 2793104
   ```

6. **Monitor.**

   ```bash
   # Master log
   ssh garnatxa 'tail -60 /storage/<GROUP>/project/snakemake_2793104.out'

   # Snakemake's own logs
   ssh garnatxa '
     cd /storage/<GROUP>/project/.snakemake/log
     latest=$(ls -t | head -1); echo "$latest"; tail -100 "$latest"
   '

   # Child SLURM jobs
   ssh garnatxa 'squeue -u $USER --long | head -20'
   ```

7. **Identify the bottleneck rule** from per-rule timings:

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/project/.snakemake/log
     latest=$(ls -t | head -1)
     grep -E "^\[|^rule |Finished job|wildcards" "$latest" | tail -50
   '
   ```

   Or via child sacct rows (job names start with `smk-`).

8. **No `work/` to clean.** Snakemake writes directly to each rule's
   `output:`. Keep `.snakemake/` — it's small and useful for re-runs.

### Confirm with user

- Before submitting if estimated runtime > 1 day, or `jobs:` > 100 in
  `Snakeconfig.yaml`.
- Before `snakemake --forceall` — destroys caching.

### Done looks like

> Master 2793104 `COMPLETED`. 47 rule instances; bottleneck `star_align` at
> 2h31m mean per sample (8 samples → ~20 h total). BAMs in `out/`.
> Per-rule timings in `.snakemake/log/<latest>.snakemake.log`.

---

## Scenario 8 — Archive a finished project to tape

**Trigger.** "Archive `project_2024_rnaseq/` to tape", "put this to LTO",
"move to long-term storage", "tapecopy this directory". The word "archive"
is the signal.

### Steps

1. **Pre-flight size + file count.** Never `du` / `find` blind on a big tree;
   use `du_` and `checkdiskspace`.

   ```bash
   ssh garnatxa '
     checkdiskspace /storage/<GROUP>/project_2024_rnaseq 2>/dev/null \
       || du_ -sh /storage/<GROUP>/project_2024_rnaseq
     find /storage/<GROUP>/project_2024_rnaseq -type f 2>/dev/null | wc -l
   '
   ```

2. **Tape strategy.** LTO-9 = 16 TB each. Check what tapes the group owns:

   ```bash
   ssh garnatxa 'ssh merlot tapecopy -l'
   ```

   - Payload fits comfortably (< 14 TB on a tape with that much free) → submit.
   - Tight fit → ask user: use this tape (nothing else will fit) or buy
     another?
   - Doesn't fit any single tape → split first, OR rely on automatic
     spillover (only works if **multiple group tapes are already mounted in
     `/tape2`**; otherwise `tapecopy` aborts without copying). Open a
     support ticket to mount a second tape if needed.

3. **Generate sha256 manifest.** `tapecopy` does not do this — you want one
   for later verification. Submit as an sbatch (don't hash big trees on the
   login node):

   ```bash
   ssh garnatxa '
     cat > /tmp/manifest.sh <<'\''EOF'\''
     #!/bin/bash
     #SBATCH --job-name=manifest
     #SBATCH --output=manifest_%j.out
     #SBATCH --qos=short --cpus-per-task=8 --mem=4G --time=06:00:00
     set -euo pipefail
     cd /storage/<GROUP>/project_2024_rnaseq
     find . -type f -print0 \
       | xargs -0 -n 32 -P $SLURM_CPUS_PER_TASK sha256sum \
       | sort -k2 > MANIFEST.sha256
     wc -l MANIFEST.sha256
     EOF
     sbatch /tmp/manifest.sh
   '
   ```

4. **Confirm with user — key checkpoint.** Show:
   - Total size + file count.
   - Tape (or "automatic spillover across N tapes").
   - ETA (LTO-9 sustained ~250 MB/s → 1 TB ≈ 1 h; lots of small files much
     slower).
   - That originals will NOT be deleted until they confirm again post-verify.

   Wait for explicit "yes, archive it".

5. **Submit `tapecopy` from `merlot`.**

   ```bash
   ssh garnatxa 'ssh merlot "
     cd /storage/<GROUP>
     tapecopy project_2024_rnaseq
   "'
   ```

   This submits a SLURM job on the `tape` partition; log goes to
   `jobtape_<TS>.out` in cwd.

6. **Monitor the tape job.** Poll every 15–30 min, not minute-by-minute.

   ```bash
   ssh garnatxa 'squeue -u $USER --partitions=tape'
   ssh garnatxa 'ls -lt /storage/<GROUP>/jobtape_*.out | head -3'
   ssh garnatxa 'tail -40 /storage/<GROUP>/jobtape_<TS>.out'
   ```

7. **Verify with a sample restore.** A few files, not the whole archive.

   ```bash
   ssh garnatxa '
     TAPE_CODE=$(grep -oE "/tape2/[A-Z0-9]+L9" jobtape_*.out | head -1)
     mkdir -p /tmp/verify_restore
     for f in $(awk "{print \$2}" project_2024_rnaseq/MANIFEST.sha256 | shuf -n 3); do
       cp "$TAPE_CODE/storage/<GROUP>/project_2024_rnaseq/$f" /tmp/verify_restore/
     done
     cd /tmp/verify_restore
     for f in *; do
       want=$(grep " $f\$" /storage/<GROUP>/project_2024_rnaseq/MANIFEST.sha256 | awk "{print \$1}")
       got=$(sha256sum "$f" | awk "{print \$1}")
       [ "$want" = "$got" ] && echo "OK  $f" || echo "MISMATCH $f"
     done
   '
   ```

   All "OK" → archive verified.

8. **CRITICAL — confirm DELETE.** Only after explicit "yes, delete originals":

   ```bash
   ssh garnatxa '
     du_ -sh /storage/<GROUP>/project_2024_rnaseq
     ls /storage/<GROUP>/project_2024_rnaseq | head
   '
   ssh garnatxa 'rm -rf /storage/<GROUP>/project_2024_rnaseq'
   ```

   Keep `MANIFEST.sha256` somewhere safe (e.g.
   `/storage/<GROUP>/_archive_manifests/`). Suggest the user maintain a
   `/storage/<GROUP>/ARCHIVE_INDEX.md` with tape code, date, manifest path.

### Confirm with user

- Before `tapecopy` — show size, tape choice, ETA.
- Before `rm -rf` of originals — show what's about to go.

### Done looks like

> Archived `project_2024_rnaseq` (4.7 TB, 312k files) to tape `GRP0017L9`.
> Manifest at `/storage/<GROUP>/_archive_manifests/2024_rnaseq.sha256`. 3
> random files restore-verified. Originals deleted on your confirm. Recall:
> `/tape2/GRP0017L9/storage/<GROUP>/project_2024_rnaseq/`.

---

## Scenario 9 — Recall data from tape

**Trigger.** "Get `<file>` back from tape", "restore my 2023 project", "pull
`out/foo.bam` off LTO".

### Steps

1. **Determine tape ownership.**

   ```bash
   ssh garnatxa 'ls /tape2 2>&1 | head'
   ```

   - Can `ls /tape2/<CODE>/` → group owns it; continue.
   - `Permission denied` → not their tape. They must open a ticket at
     <https://garnatxadoc.uv.es/support> under `Garnatxa HPC`. The agent
     cannot escalate via SSH.

2. **Locate the file.** Use the manifest if you have it (Scenario 8).
   Otherwise:

   ```bash
   ssh garnatxa 'find /tape2/<TAPE_CODE> -name "<filename>" 2>/dev/null | head'
   ```

   Tape is sequential — large finds are slow.

3. **Copy back.** Small (< 1 GB single file) — inline:

   ```bash
   ssh garnatxa '
     mkdir -p /storage/<GROUP>/recalled
     cp /tape2/<TAPE_CODE>/storage/<GROUP>/project_2024_rnaseq/out/foo.bam \
        /storage/<GROUP>/recalled/
   '
   ```

   Large (> 50 GB) — wrap in an sbatch (e.g. `--qos=short --time=12:00:00`),
   don't tie up the login node.

4. **Discourage in-job tape reads.** Possible but very slow (sequential
   media) and can stall other tape ops. If the user wants this, explain
   the cost and confirm.

5. **Verify checksums if a manifest exists.** Same approach as Scenario 8
   step 7.

### Confirm with user

- Before submitting a big recall — show ETA and size.
- Before writing into `/storage/<GROUP>` if `checkdiskspace` is tight.

### Done looks like

> Restored 3 files from `/tape2/GRP0017L9` to `/storage/<GROUP>/recalled/`.
> Checksums match. 12 GB, ~3 min.

---

## Scenario 10 — Move data on/off the cluster

**Trigger.** "Upload these FASTQs", "download my results", "copy between
nodes", "move data from `/scr` to `/storage`".

Distinguish direction first.

### A. Local → cluster (upload)

1. Confirm size and destination disk:

   ```bash
   du -sh <local_path>
   ssh garnatxa 'checkdiskspace /storage/<GROUP>'
   ```

2. **`rsync`** for anything > a few GB. Resume-friendly:

   ```bash
   rsync --inplace --progress --partial --append-verify -av \
     ./big_data/ USER@garnatxa.srv.cpd:/storage/<GROUP>/raw/
   ```

3. For one-off bulk where rsync is slow, `tar | ssh`:

   ```bash
   tar c big_data | pv | ssh garnatxa 'cd /storage/<GROUP>/raw && tar x'
   ```

### B. Cluster → local (download)

```bash
rsync --inplace --progress --partial --append-verify -av \
  USER@garnatxa.srv.cpd:/storage/<GROUP>/results/ ./local_results/
```

Single file: `scp -O USER@garnatxa.srv.cpd:/path/file .`. `-O` selects the
legacy SCP protocol — more compatible across OpenSSH versions.

### C. Within the cluster (`/scr` lifecycle)

`/scr` is **shared scratch on the same CephFS as `/home` and `/storage`** —
verified against the live cluster (all three mounts share `fsid` and the
same 888 T available pool). It is **NOT node-local** and is **NOT
auto-cleaned**. Files persist forever until you delete them. Per-user
subdir: `/scr/$USER/` (create if missing).

Pattern inside an sbatch — useful when you want a tidy per-job working
directory or when your group `/storage` quota is tight:

```bash
mkdir -p /scr/$USER/$SLURM_JOB_ID
cd /scr/$USER/$SLURM_JOB_ID
# ... heavy I/O on /scr ...
cp -av results/ /storage/<GROUP>/results/job_${SLURM_JOB_ID}/
cd / && rm -rf /scr/$USER/$SLURM_JOB_ID
```

Because all three filesystems are the same Ceph backend, **`/scr` is not
faster than `/storage`**. The reason to use it is organisational
(transient outputs that don't bloat group quota) and convention (everyone
can `mkdir /scr/$USER`).

`$SCRATCH` and `$XDG_CACHE_HOME` are **not** set in Garnatxa job environments
— resolve scratch explicitly as `/scr/$USER`.

### Confirm with user

- Before > 100 GB — confirm direction, dest, ETA, receiving-side disk space.
- Before deleting source files post-transfer.
- Before any `/scr` cleanup, confirm results are persisted to `/home` or
  `/storage`.

### Done looks like

> Uploaded 47 GB across 192 files from `~/Desktop/seq_run_2024_05/` to
> `/storage/<GROUP>/raw/run_2024_05/` in 38 min (rsync resumed once after a
> blip). Sha256 checksums match.

---

## Scenario 11 — Set up Nextflow/Snakemake first time + GitLab bootstrap

**Trigger.** "Start using Snakemake on Garnatxa", "first-time Nextflow setup",
"set up GitLab for this project", "set up my workflow from scratch".

### Steps

1. **Snakemake mamba env (one-time).**

   ```bash
   ssh garnatxa '
     module load anaconda
     mamba env list | grep -q "^snakemake " \
       && echo "snakemake env already exists" \
       || mamba create -y -n snakemake -c bioconda snakemake
     mamba activate snakemake
     snakemake --version
   '
   ```

2. **Optional: graphviz for DAG rendering.**

   ```bash
   ssh garnatxa '
     module load anaconda && mamba activate snakemake
     mamba install -y -c conda-forge graphviz
   '
   ```

3. **Save default module collection** — only after user confirms what they
   want autoloaded. Typical bio stack:

   ```bash
   ssh garnatxa '
     module purge
     module load gnu9/9.4.0 openmpi4 biotools anaconda
     module list
     module save
   '
   ```

   `module save` writes `~/.lmod.d/default` and changes every future
   session — confirm first.

4. **GitLab SSH key from inside Garnatxa.**

   ```bash
   ssh garnatxa '
     [ -f ~/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
     cat ~/.ssh/id_rsa.pub
   '
   ```

   Print the pubkey; tell user: "paste at <https://garnatxadoc.uv.es/gitlab>
   → avatar → Preferences → SSH Keys → Add key". After they confirm:

   ```bash
   ssh garnatxa 'ssh -T git@garnatxagitlab.uv.es 2>&1 | head'
   # Welcome to GitLab, @<username>!
   ```

5. **Create the project repo.** Either init locally:

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/projects
     mkdir myproject && cd myproject
     git init -b main
     git config user.name "<NAME>"; git config user.email "<EMAIL>"
   '
   ```

   …or clone an empty GitLab project the user already made:

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/projects
     git clone git@garnatxagitlab.uv.es:<USER>/myproject.git
   '
   ```

6. **Drop in the standard `.gitignore`** (10 MB push limit, source-only):

   ```gitignore
   data/*
   data_extra/*
   out/*
   ref/*
   work/                # Nextflow
   .snakemake/          # Snakemake
   *.sif                # Singularity
   *.sam
   *.bam
   *.fq
   *.fastq
   *.fq.gz
   *.fastq.gz
   ```

7. **Copy in engine-specific assets** (Nextflow: `nextflow.config`,
   `nextflow_launcher.sbatch`, empty `main.nf`. Snakemake:
   `snakemake_profile.yaml` → `Snakeconfig.yaml`, `snakemake_launcher.sbatch`,
   empty `Snakefile`).

8. **First commit + push.**

   ```bash
   ssh garnatxa '
     cd /storage/<GROUP>/projects/myproject
     git add . && git commit -m "Initial scaffolding"
     git push -u origin main
   '
   ```

   If push fails with "too large" → user added data; `git rm --cached
   <file>`, fix `.gitignore`, recommit.

### Confirm with user

- Before `module save` (changes default shell env).
- Before pushing to GitLab if diff includes anything > 5 MB.
- Before generating a keypair if `~/.ssh/id_rsa` already exists — don't
  clobber.

### Done looks like

> Snakemake env (snakemake 8.x, graphviz). Default modules saved:
> `gnu9/openmpi4/biotools/anaconda`. SSH key added to GitLab. Created
> `/storage/<GROUP>/projects/myproject` with standard `.gitignore` and the
> Snakemake assets, pushed to
> <https://garnatxadoc.uv.es/gitlab/<user>/myproject>.

---

## Scenario 12 — Rotate password and update VPN

**Trigger.** "Changed Garnatxa password, VPN won't connect", "VPN says auth
failed but SSH works", "password expired", or agent detects SSH works while
the user reports VPN broken.

### Steps

1. **Confirm SSH still works.**

   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=8 garnatxa 'echo SSH ok'
   ```

   - `ok` → password good, VPN profile stale → continue.
   - Fails → different problem; point them to
     <https://garnatxadoc.uv.es/support>.

2. **VPN client refresh** — the agent can't act here; give exact OS steps.

   **macOS (OpenVPN Connect 3.x)**: Open the app → `i2sysbio` profile →
   trash icon → re-import `i2sysbio.ovpn` (File tab → Browse) → Connect with
   username + new password.

   **Windows (OpenVPN GUI 2.5)**: tray icon → right-click → `i2sysbio` →
   delete profile (or Edit Config) → re-import `i2sysbio.ovpn` → Connect.

   **Linux GUI**: Network Settings → VPN → `i2sysbio` → delete → re-import.
   Re-tick **IPv4 → "Use this connection only for resources on its
   network"** (otherwise general internet breaks while connected).

   **Linux CLI**: `sudo openvpn ./i2sysbio.ovpn` — sudo pw, then Garnatxa
   user, then **new** password.

3. **If the user is changing the password now**, walk them through:

   ```bash
   ssh garnatxa
   # on the cluster:
   passwd
   # Old: ...
   # New: ... (≥8 chars, ≥1 special, ≥1 digit)
   ```

   Remind them: **VPN credential = same as Garnatxa SSH credential.**
   Change one, update the other in the VPN client.

4. **Verify after reconnect.**

   ```bash
   ssh -o BatchMode=yes garnatxa 'echo "VPN+SSH ok"'
   ```

### Confirm with user

- The agent should NOT issue `passwd` directly — the user types their own
  passwords. Don't record them.

### Done looks like

> SSH works on new password. VPN was caching the old one. Walked you
> through deleting and re-importing `i2sysbio.ovpn` on macOS; you
> reconnected successfully. Update your password manager.

---

## Scenario 13 — Investigate why everything is queued

**Trigger.** "Why is my job stuck?", "everything is PENDING", "submitted
hours ago and nothing has started", or expressed frustration about queue
times.

### Steps

1. **User's queue + REASON.**

   ```bash
   ssh garnatxa 'squeue -u $USER --long'
   ```

   | Reason | Meaning | Fix |
   |---|---|---|
   | `Priority` | higher-priority jobs ahead | wait; or higher-priority QoS |
   | `Resources` | no free CPUs/RAM | wait; or shrink request |
   | `Dependency` | waiting on parent | check parent state |
   | `AssocGrpCpuLimit` | user 200-CPU cap | wait for own jobs to drain |
   | `QOSMaxCpuPerUserLimit` | QoS cap | move some to another QoS |
   | `AssocMaxJobsLimit` | 1000-job cap | wait, or `scancel` some |
   | `InvalidAccount` / `InvalidQoS` | misconfig | cancel and resubmit |

2. **ETA.**

   ```bash
   ssh garnatxa 'squeue -u $USER --start'
   ```

   `START_TIME = N/A` → SLURM can't see a slot yet.

3. **Fairshare.**

   ```bash
   ssh garnatxa 'sshare -U'
   ```

   `LevelFS`: > 1.0 = under-using, ≈ 1.0 = equilibrium, < 0.5 = heavy recent
   use (long waits), 0.0 = fully depressed.

4. **Cluster-wide load.**

   ```bash
   ssh garnatxa '
     echo "=== whole queue ===";   squeue -a --long | head -30
     echo "=== nodes ===";         sinfo
     echo "=== priorities ===";    sprio | head -20
   '
   ```

   Nodes `down/drain/mix*` → possible hardware outage; if multiple, email
   `i2sysbiohpc@uv.es`.

5. **Suggest based on findings.**
   - `Priority` + low fairshare → wait, or split a big job into smaller
     ones (better backfill).
   - `Resources` + cluster full → wait; consider smaller
     `--cpus-per-task` to fit a backfill window.
   - `QOSMaxCpuPerUserLimit` on `short` → user is hitting their own cap;
     let some drain, or split into `medium`.
   - RAM cap on `long-mem` → tighten `--mem` (Scenario 5), or `extra` via
     ticket.
   - `Dependency` → if parent FAILED, children will never start; cancel
     them.

6. **Be honest.** If priority is genuinely low and the cluster is full, "wait
   ~2 hours" is the right answer — don't move things uselessly.

### Confirm with user

- Before scancel-ing anything (even a job stuck on a dead dependency).
- Before moving jobs between QoS — cancel+resubmit loses queue position;
  almost always cheaper to wait if < 2 h.

### Done looks like

> All 96 array tasks `PD` with `QOSMaxCpuPerUserLimit` on `short`. You
> already have 24 running using 192 of the 200 CPU cap. As tasks finish the
> queue drains. SLURM ETA for the last task: ~3h40m. Fairshare healthy
> (`LevelFS=0.91`). Nothing to fix; do something else.

---

## Scenario 14 — Stop everything and reset

**Trigger.** "Cancel all my jobs", "stop everything", "reset, I made a mess",
"kill it". Usually said in frustration — confirm, then act decisively.

### Steps

1. **Show what's about to die.**

   ```bash
   ssh garnatxa '
     echo "=== running ==="; squeue -u $USER -t R --long
     echo "=== pending ==="; squeue -u $USER -t PD --long
     echo "=== total ===";   squeue -u $USER -h | wc -l
   '
   ```

2. **Explicit CONFIRM.** The agent must hear "yes cancel everything" (or
   equivalent) before running `scancel -u`. Running jobs lose their
   un-flushed output.

3. **Cancel.**

   ```bash
   ssh garnatxa 'scancel -u $USER'
   ssh garnatxa 'squeue -u $USER'   # should be empty within ~30s
   ```

4. **Show cleanup targets.**

   ```bash
   ssh garnatxa '
     echo "=== Nextflow work/ ==="
     find /storage/<GROUP>/ -maxdepth 3 -name "work" -type d 2>/dev/null \
       | while read d; do du_ -sh "$d"; done
     echo "=== Snakemake .snakemake/ ==="
     find /storage/<GROUP>/ -maxdepth 3 -name ".snakemake" -type d 2>/dev/null
     echo "=== /scr ==="
     du_ -sh /scr/$USER 2>/dev/null
     echo "=== totals ==="
     du_ -sh $HOME 2>/dev/null
     checkdiskspace /storage/<GROUP> 2>/dev/null
   '
   ```

5. **Per-target confirm, then delete.** Never batch them into one question.

   ```bash
   ssh garnatxa 'rm -rf /storage/<GROUP>/project_X/work'
   ssh garnatxa 'rm -rf /storage/<GROUP>/project_X/.snakemake'
   ssh garnatxa 'rm -rf /scr/$USER'
   ```

   Don't auto-`rm` partial result dirs the user might want to inspect.

6. **Final disk report.**

   ```bash
   ssh garnatxa '
     squeue -u $USER
     du_ -sh $HOME 2>/dev/null
     checkdiskspace /storage/<GROUP> 2>/dev/null
   '
   ```

### Confirm with user

- **Always** before `scancel -u`.
- **Always** before each `rm -rf` — one explicit yes per target.

### Done looks like

> Cancelled 187 jobs (1 R, 186 PD). Deleted `/storage/<GROUP>/project_X/work/`
> (412 GB) and `/scr/<user>` (84 GB) on your confirm. Left `.snakemake/` and
> the partial `out/` in place — you said you wanted to inspect those. Group
> storage now 71% of quota, queue empty.

---

## Cross-cutting notes

### Polling cadence

- Diagnostic round-trip (1, 4, 5, 13): once, repeat only if state plausibly
  changed.
- Watching a running job (2, 3, 6, 7): 60 s minimum, 5–10 min plenty for
  anything > 10 min long.
- Watching a tape job (8): 15–30 min. Tape is slow; spamming `squeue` adds
  nothing.
- Never poll faster than 30 s on the login node — it's shared.

### When to break out and ask

- Any destructive command: `scancel -u`, `rm -rf` outside obvious tempdirs,
  `tapecopy`, `passwd`, `git push --force`, writes to `~/.bashrc` /
  `~/.lmod.d/default` / `~/.ssh/`.
- Submissions > 100 concurrent CPUs, > 100 GB RAM, or > 1 day wall.
- Operations touching shared `/storage/<GROUP>/` paths (not just the user's
  subdir).
- Anything the user might not be expecting (e.g. mid-task you realize an
  index needs rebuilding).

### When NOT to ask — just do it

- Read-only diagnostics: `squeue`, `sacct`, `sshare`, `sprio`, `sinfo`,
  `module list`, `ls`, `du_`, `checkdiskspace`.
- Tailing the user's own `slurm-*.out` / `slurm-*.err`.
- Reading their own `~/jobs/*.sh` to understand what they ran.
- Cleaning the agent's own scratch (e.g. a `/tmp/manifest.sh` it wrote and
  submitted).

### Always end with a status line

The "Done looks like" message is the deliverable. Concrete:

- Job IDs created, final state, elapsed.
- File paths created or deleted (absolute).
- One concrete next step, or "no action needed".

A vague "done!" wastes the round-trip. "Array 2793077 `COMPLETED` in 4h12m,
96 BAMs in `/storage/<GROUP>/aln/`, want me to clean `work/`?" gives the
user everything to react or move on.
