# SLURM on Garnatxa

The full SLURM reference: partitions, QoS, sbatch flags, job templates, monitoring,
canceling, dependencies, arrays, MPI, OpenMP, and the Garnatxa-only efficiency
tools `squeue_`, `sacct_`, `plotjob`.

## Golden rules

- **Never run real work on the login node.** Wrap everything in `sbatch` or use
  the `interactive` command. Processes that exceed ~30 min or ~8 GB on the
  login node may be killed.
- **A job that is not parallel will not run faster by requesting more CPUs or
  memory.** SLURM never swaps to disk, so extra RAM doesn't speed anything up.
- **Always set `--time` and `--mem`** (or `--mem-per-cpu`) explicitly — defaults
  will silently kill long jobs.
- **Hyperthreading is on.** Each physical core has 2 logical threads. When you
  request 1 CPU, SLURM reserves 2 threads. Whether your code uses both is up to
  the parallelism flag you pass to it.
- **Email comes after every job** showing actual usage; iterate until
  CPU efficiency and memory efficiency are ≥ 75%.
- **Don't run expensive `find`/`ls`/`du`** over directories with > ~10 000 files.
  Use `du_` and `checkdiskspace` instead of `du`.

## Partitions

| Partition | Use for | Time limit | Default time | Default mem | Memory cap | Nodes |
|-----------|---------|------------|--------------|-------------|------------|-------|
| `interactive` | Interactive shells, file transfer, compilation | 1 d | 12 h | 4 GB | 30 GB | `merlot, subirat` |
| `global`      | Batch jobs (`sbatch`)                          | 15 d | 6 h | 2 GB | per QoS | `cn[00-13]` (14 nodes) |
| `tape`        | Tape transfers (auto-submitted by `tapecopy` on `merlot`) | 7 d | – | – | – | `merlot` |

## QoS table

| QoS         | Max time | Default time | Max mem (user) | Max CPU (user) | Priority |
|-------------|----------|--------------|----------------|----------------|----------|
| `interactive` | 1 d   | 12 h | 30 GB    | 20  | 1000 |
| `short`       | 1 d   | 6 h  | 1300 GB  | 200 | 1000 |
| `medium`      | 7 d   | 6 h  | 700 GB   | 150 | 750  |
| `long`        | 15 d  | 6 h  | 360 GB   | 100 | 500  |
| `long-mem`    | 15 d  | 6 h  | 1300 GB  | 80  | 250  |
| `extra`       | 15 d  | 6 h  | 2800 GB   | 400 | 1000 (open ticket — same priority as short) |
| `tape`        | 7 d   | –    | –         | –   | 1000 (used by `tapecopy`; not for normal submissions) |

Per-user totals: **1000 running jobs**, **5000 array tasks max**. Per-QoS CPU
and RAM caps in the table above are enforced individually — pick the right
QoS, don't try to dodge by switching mid-batch.

If a job is pending with reason `AssocGrpCpuLimit` or `QOSMaxCpuPerUserLimit`,
the user has hit one of these caps.

## Priority

```
Job priority = AGE + FAIRSHARE + JOB SIZE + QOS PRIORITY
```

- AGE grows the longer the job waits.
- FAIRSHARE drops for users with heavy recent usage; helps balance the cluster.
- JOB SIZE depends on CPU + memory request.
- QOS PRIORITY is static — see table above.

`sprio` shows the current priority breakdown. Priorities change continuously;
backfilling can start a small job ahead of a larger waiting one.

## Resource request rules

- Request what you'll actually use, plus ~10–20 % headroom.
- Serial code: `--cpus-per-task=1`. Check the tool's docs for the right
  parallelism flag — most apps need an explicit `-t`, `-@`, `--threads`,
  `--runThreadN`, or similar to use more than one core.
- Choose `--mem=<TOTAL>` (per node) OR `--mem-per-cpu=<PER_CPU>`. Don't mix.
- Hyperthreading: SLURM rounds up to even thread counts. If you only need 1
  thread, set `--threads-per-core=1` or `--hint=nomultithread`.

## sbatch flag reference

| Type | Flag | Description |
|------|------|-------------|
| Job name | `--job-name=NAME` (`-J`) | Identify the job in `squeue` |
| Account | `--account=ALLOC` | Bill the named allocation |
| QoS | `--qos=QOS` | `short`, `medium`, `long`, `long-mem`, `interactive`, `extra` |
| Partition | `--partition=NAME` (`-p`) | `global` or `interactive` |
| Nodes | `--nodes=N` or `--nodes=MIN-MAX` (`-N`) | Number of nodes (or range) |
| Tasks | `--ntasks=N` (`-n`) | Total processes (MPI ranks) |
| Tasks per node | `--ntasks-per-node=N` | Distribute tasks |
| CPUs per task | `--cpus-per-task=N` (`-c`) | CPUs per process (threads) |
| Total memory | `--mem=MEM` | Per-node total (K/M/G/T, default M) |
| Memory per CPU | `--mem-per-cpu=MEM` | Per allocated CPU |
| Wall time | `--time=HH:MM:SS` or `D-HH:MM:SS` (`-t`) | Max runtime |
| Stdout | `--output=PATH` (`-o`) | `%j`→jobid, `%A`→array id, `%a`→task idx |
| Stderr | `--error=PATH` (`-e`) | Separate stderr file |
| Email events | `--mail-type=TYPE` | `BEGIN`, `END`, `FAIL`, `ALL` |
| Email | `--mail-user=ADDR` | Notification target |
| Array | `--array=RANGE` (`-a`) | `1-20`, `1,3,5,7`, `1-7:2`, `0-15%4` |
| Dependency | `--dependency=TYPE:JOBID` (`-d`) | `afterok`, `afterany`, `afternotok`, `after`, `aftercorr`, `singleton`, … |
| One thread / core | `--hint=nomultithread` or `--threads-per-core=1` | Disable HT |
| Parsable | `--parsable` | Returns only the jobid (useful for chaining) |
| Wait | `--wait` | sbatch blocks until the job ends |

## Useful environment variables inside the script

| Variable | Meaning |
|----------|---------|
| `$SLURM_JOB_ID` | Job ID |
| `$SLURM_SUBMIT_DIR` | Where `sbatch` was called |
| `$SLURM_JOB_NODELIST` | Allocated nodes |
| `$SLURM_CPUS_PER_TASK` | Value of `--cpus-per-task` |
| `$SLURM_NTASKS` | `--ntasks` |
| `$SLURM_NNODES` | Allocated node count |
| `$SLURM_MEM_PER_CPU` | Value of `--mem-per-cpu` |
| `$SLURM_MEM_PER_NODE` | Value of `--mem` |
| `$SLURM_ARRAY_JOB_ID` | Array master id |
| `$SLURM_ARRAY_TASK_ID` | Array task index |
| `$SLURM_ARRAY_TASK_COUNT` | Number of array tasks |

## sbatch vs srun

- `sbatch` submits a **batch script**. The `#SBATCH` directives at the top
  configure resources; the rest runs as a single implicit job step in the
  background once SLURM grants resources.
- `srun` runs **synchronously** — it blocks until that step finishes. Use it:
  - Inside an sbatch script to launch a job step (good practice but optional
    for a single command).
  - On the login node, to start an interactive session.

Submit:

```bash
sbatch myjob.sh
# Submitted batch job 6757
```

## Interactive jobs

Default — 2 CPUs, 4 GB, 12 h:

```bash
interactive
# srun: job 5745 queued and waiting for resources
# srun: job 5745 has been allocated resources
```

Custom resources:

```bash
interactive -c 6 -m 30G -t 24:00:00
```

Full `srun` form (advanced):

```bash
srun --partition=interactive --qos=interactive --nodes=1 --ntasks=1 \
     --cpus-per-task=2 --mem=30G --time=12:00:00 \
     --pty --export=ALL /bin/bash
```

Cap: 30 GB RAM, 20 CPUs, 1 day max.

## Monitoring

> **Operator notes for the agent**:
>
> - `sacct_` and `squeue_` (the Garnatxa efficiency tools) emit
>   `tput: No value for $TERM` warnings under non-interactive SSH. Prepend
>   `TERM=xterm` for clean output: `ssh garnatxa 'TERM=xterm sacct_ -b -u $USER'`.
> - `scontrol show job <id>` only works for **running or just-finished**
>   jobs (the scheduler purges historical state quickly). For older jobs
>   use `sacct -j <id> -P --format=jobid,state,exitcode,workdir%80`.
> - **Log filenames are user-defined.** The sbatch script's `--output=`
>   directive controls it. Don't assume `slurm-<id>.out` — read the
>   script, or `find $(sacct -j <id> -P --format=workdir%120 | tail -1) -name "*<id>*"`.

### `squeue` — currently queued or running

```bash
squeue -u $USER
squeue -u $USER --long           # non-abbreviated
squeue -u $USER --start          # estimated start time
squeue -u $USER --iterate=5      # repeat every 5 s (Ctrl-C to stop)
squeue -j JOBID
```

Job states (ST column): `R` running, `PD` pending, `CG` completing, `CD`
completed, `F` failed, `S` suspended, `ST` stopped, `PR` preempted.

Common pending reasons:

| Reason | Meaning |
|--------|---------|
| `Priority` | Higher-priority jobs ahead |
| `Resources` | Waiting for CPUs/mem |
| `Dependency` | Waiting on a parent job |
| `AssocGrpCpuLimit` | User CPU cap exceeded (200) |
| `QOSMaxCpuPerUserLimit` | QoS-level CPU cap exceeded |
| `AssocMaxJobsLimit` | Per-user job count cap exceeded |
| `InvalidAccount` / `InvalidQoS` | Wrong account or QoS — cancel and fix |

### `sacct` — historical (finished) jobs

Default shows today only — use `--starttime`:

```bash
sacct -u $USER --starttime=2026-05-01
sacct -u $USER --starttime=2026-05-01 --long
sacct -u $USER --format=jobid,jobname,state,elapsed,reqcpu,reqmem,maxrss,exitcode
```

Useful `--format` fields: `jobid`, `jobname`, `state`, `elapsed`, `cputime`,
`reqcpu`, `reqmem`, `maxrss` (peak RAM), `maxdiskread`, `maxdiskwrite`,
`ncpus`, `nnodes`, `priority`, `qos`, `exitcode`.

### `squeue_` — running-job efficiency (Garnatxa-specific)

```bash
squeue_ -u $USER
squeue_ -j JOBID
```

Output adds `CPU E.CPU` (used/requested + percent) and `PEAK_MEM E.MEM`.
Anything below ~75 % is wasted allocation; tighten the next submission.

### `sacct_` — finished-job efficiency (Garnatxa-specific)

```bash
sacct_ -j JOBID
sacct_ -u $USER
sacct_ -b -u $USER     # brief: efficiencies only, no step rows
```

### `plotjob` — efficiency over time

Needs X11 forwarding (`ssh -X`). Or save to PNG for off-cluster viewing.

```bash
ssh -X $USER@garnatxa.srv.cpd
plotjob -j JOBID -o cpu     # CPU usage over time
plotjob -j JOBID -o mem     # memory usage over time
plotjob -h                  # help

# Save without X11
plotjob -j JOBID -o mem -s  # writes /tmp/mem_plot_<jobid>.png
scp /tmp/mem_plot_*.png you@elsewhere:/tmp/
```

Gray regions = idle / wasted resources.

### `scontrol` — control running/pending jobs

```bash
scontrol show job JOBID                # detailed info
scontrol show job JOBID | grep Time
scontrol suspend JOBID                 # stop running job (resumable)
scontrol resume JOBID
scontrol hold JOBID                    # lower a PD job's priority to 0
scontrol release JOBID
```

### `sinfo` — node and partition state

```bash
sinfo
```

### `sprio` — pending job priorities

```bash
sprio
```

## Cancelling

```bash
scancel JOBID
scancel JOBID1 JOBID2 JOBID3
scancel -u $USER            # cancel ALL your jobs — careful
```

## Job script templates

The cluster ships sample scripts under `/doc/test/`. Copy and adapt:

```bash
cp -pr /doc/test/ .
cd test
ls            # ArrayJob.sh FileJob.sh MPIJob.sh OpenMPJob.sh SequentialJob.sh ...
```

### Skeleton

```bash
#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=00:05:00

module load package/version

cd /path/to/work
binary [arguments]
```

### Single-CPU serial job

```bash
#!/bin/bash
#SBATCH --job-name=seqJobTest
#SBATCH --output=seqJobTest_%j.out
#SBATCH --qos=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=01:00:00

module load biotools

srun bwa index ref/chr8.fa -p ref/chr8_ref
srun bwa aln -I -t 1 ref/chr8_ref data/reads_00.fq > out/example_aln.sai
srun bwa samse ref/chr8_ref out/example_aln.sai data/reads_00.fq > out/reads_00.sam
```

Submit and watch:

```bash
sbatch SequentialJob.sh        # -> Submitted batch job 6757
squeue -u $USER
squeue_ -u $USER
```

### Passing parameters

`$1`, `$2`, … from the command line work as normal Bash arguments:

```bash
sbatch SequentialJob.sh 150       # 150 becomes $1 inside the script
```

### Multi-threaded SMP / OpenMP job

For shared-memory parallelism, stay on **one node**: `--ntasks=1` and raise
`--cpus-per-task`.

```bash
#!/bin/bash
#SBATCH --job-name=multiThreadJob
#SBATCH --output=OpenMPJob_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=1G
#SBATCH --time=01:00:00
#SBATCH --qos=short

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK     # for OpenMP code

module load biotools

srun bwa index ref/chr8.fa -p ref/chr8_ref
srun bwa aln -I -t $SLURM_CPUS_PER_TASK ref/chr8_ref data/reads_00.fq > out/example_aln.sai
srun bwa samse ref/chr8_ref out/example_aln.sai data/reads_00.fq > out/reads_00.sam
```

For tools with thread flags, always pass `$SLURM_CPUS_PER_TASK` (e.g.
`bwa -t`, `samtools -@`, `STAR --runThreadN`).

### MPI job (multiple nodes)

```bash
#!/bin/bash
#SBATCH --job-name=MPIJob
#SBATCH --nodes=2
#SBATCH --ntasks=80
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --qos=short
#SBATCH --output=MPIJob_%j.log

module load openmpi4         # must match the MPI used at build time

mpirun -np $SLURM_NTASKS ./mpi_hello_world
```

Notes:

- 80 tasks × 1 CPU > 1 node (40 cores/node), so `--nodes=2`. You may omit
  `--nodes` to let SLURM decide.
- `--mem=1G` is per node. With `--mem-per-cpu`, total = `ntasks * cpus-per-task * mem-per-cpu`.

### Array job — same command, many input files

```bash
#!/bin/bash
#SBATCH --job-name=ArrayJob
#SBATCH --output=arrayJob_%A_%a.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --mem-per-cpu=1G
#SBATCH --array=0-19
#SBATCH --qos=short

module load biotools

FILES=(data/*)
INPUTFILE=${FILES[$SLURM_ARRAY_TASK_ID]}
OUTPUTFILE=$(basename ${FILES[$SLURM_ARRAY_TASK_ID]} .fq)

srun bwa aln -I -t 1 ref/chr8_ref $INPUTFILE  > out/${OUTPUTFILE}.sai
srun bwa samse ref/chr8_ref out/${OUTPUTFILE}.sai $INPUTFILE > out/${OUTPUTFILE}.sam
```

Array spec variants:

- `--array=1-20` — tasks 1…20.
- `--array=1,3,5,7` — explicit list.
- `--array=1-7:2` — step 2 (1, 3, 5, 7).
- `--array=0-15%4` — cap concurrency at 4 simultaneous tasks.

Max array size: **5000**.

Dynamic array range:

```bash
sbatch --array=0-$(ls data | wc -l) ArrayJob.sh
```

**Caveat — shared setup belongs outside the array.** If every task runs `bwa
index`, you'll waste compute and risk corrupted index files. Split into a setup
job + array with a dependency (next section).

### Dependencies

`-d TYPE:JOBID` (or `--dependency=TYPE:JOBID`):

| Type | Behavior |
|------|----------|
| `after:ID[+m]` | Start after the job starts/is cancelled (optionally +m minutes later). |
| `afterany:ID` | Start after termination, any state. **Default if no type.** |
| `afterok:ID`  | Start only if the parent exited 0. |
| `afternotok:ID` | Start only if the parent failed. |
| `aftercorr:ID` | Array task `i` waits for parent's array task `i`. |
| `singleton`   | Only one job with the same name + user runs at a time. |

#### Setup + array launcher pattern

`indexSequence.sh` (one-off):

```bash
#!/bin/bash
#SBATCH --job-name=indexSequence
#SBATCH --output=indexSequence_%j.out
#SBATCH --ntasks=1 --cpus-per-task=1 --mem=1G --time=01:00:00 --qos=short

module load biotools
srun bwa index ref/chr8.fa -p ref/chr8_ref
```

`launcherArrayJob.sh`:

```bash
#!/bin/bash
jobid_index=$(sbatch --parsable indexSequence.sh)
sbatch -d afterok:$jobid_index ArrayJob.sh
```

`squeue` while it runs:

```
JOBID            NAME           QOS    STATE  TIME  REASON
2390042_[0-19]   ArrayJob       short  PD     0:00  Dependency
2390041          indexSequence  short  R      0:08  None
```

#### Multi-step pipeline

```bash
jid1=$(sbatch --parsable preprocess.sh)
jid2=$(sbatch --parsable -d afterok:$jid1 analyze.sh)
jid3=$(sbatch --parsable -d afterok:$jid2 postprocess.sh)
echo "Submitted $jid1 -> $jid2 -> $jid3"
```

### File of commands + array

`list_of_cmd.txt`:

```
bwa aln -I -t 1 ref/chr8_ref data/reads_00.fq > out/example_ali_reads_00.sai
bwa aln -I -t 1 ref/chr8_ref data/reads_01.fq > out/example_ali_reads_01.sai
...
```

`ArrayJob_List.sh`:

```bash
#!/bin/bash
#SBATCH --array=0-20
#SBATCH --ntasks=1 --cpus-per-task=1 --time=00:30:00 --mem-per-cpu=1G --qos=short
#SBATCH --output=arrayJob_List_%A_%a.out

module load biotools

readarray -t CMDS < list_of_cmd.txt
eval srun ${CMDS[$SLURM_ARRAY_TASK_ID]}
```

`eval` is needed so `>` and other shell metachars are interpreted.

### Background `srun` (NOT RECOMMENDED)

If arrays + dependencies don't fit, you can fan out with backgrounded `srun`
inside one job. It's inefficient and limited to **5000 background srun
processes** before the system kills them.

```bash
#!/bin/bash
#SBATCH --job-name=FileJob
#SBATCH --ntasks=20
#SBATCH --cpus-per-task=2          # must be even on Garnatxa for background mode
#SBATCH --time=00:30:00
#SBATCH --mem-per-cpu=1G
#SBATCH --qos=short

module load biotools

srun -n 1 -c 1 bwa index ref/chr8.fa -p ref/chr8_ref     # one-off setup

for file in data/*; do
  srun -n 1 -c 2 -Q --exclusive bwa aln -I -t 1 ref/chr8_ref $file > out/$(basename $file .fq).sai &
done
wait
```

Notes: `-Q --exclusive` per inner `srun`, even `--cpus-per-task`, end with
`wait`.

## Pre-submit checklist

- [ ] QoS fits the time you're requesting (short ≤ 1 d, medium ≤ 7 d, long ≤ 15 d).
- [ ] `--time` and `--mem` are set, with ~10–20 % headroom.
- [ ] `--ntasks` and `--cpus-per-task` match the actual parallelism of your code.
- [ ] `--output` uses `%j` or `%A_%a` to avoid clobbering.
- [ ] For arrays: `--array=…` plus optional `%N` concurrency cap.
- [ ] Loaded the right `module` for the tool and (for MPI) the matching MPI build.
- [ ] Multi-step pipelines use `-d afterok:…` not "rerun setup inside every task".
- [ ] Plan to verify with `squeue_`, `sacct_`, `plotjob` afterwards.
