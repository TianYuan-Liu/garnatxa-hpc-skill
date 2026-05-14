# Operator loop — how the agent actually runs Garnatxa

This is the canonical guide for **Claude Code acting as an operator** on
Garnatxa, not just answering questions about it. Read this when the user
asks you to do anything on the cluster (check a job, submit work, debug a
failure, archive data, etc.).

The other references describe **what** the cluster looks like; this file
describes **what you do**, in order, end to end, over SSH.

## 0. Hard rules

Always-true facts you should not forget — most have bitten people:

- **`module` is NOT in non-interactive SSH shells.** Wrap every module
  call you do over SSH in `bash -lc`:
  `ssh garnatxa 'bash -lc "module load anaconda && mamba env list"'`.
  Inside an sbatch script `module` works directly (SLURM sources login files).
- **`/scr` is Ceph-shared (not node-local) and is never auto-cleaned.**
  Use `/scr/$USER/` and clean up at end of job. Don't assume `$SCRATCH`
  is set — it isn't.
- **`/tape2` is only mounted on `merlot`.** Tape work always starts with
  `ssh merlot`. `tapecopy -l` works for any user; `ls /tape2/<CODE>` only
  for the owning group.
- **Compute-node SSH (`ssh garnatxa 'ssh cn07 …'`) only works while you
  have a job on that node.** Compute nodes alias `cn00..cn13` → self-identify
  as `osd00..osd13`. Resolve via `scontrol show job <id> | grep NodeList=`.
- **`scontrol show job <id>` only finds running or just-finished jobs.**
  For historical jobs use `sacct -j <id> -P --format=jobid,state,exitcode,workdir%80`.
- **Log filenames are user-defined.** Don't assume `slurm-<id>.out` — read the
  sbatch script for `--output=` or `find <WorkDir>/.. -name "*<id>*"`.
- **`sacct_` / `squeue_` print `tput` warnings under non-interactive SSH.**
  Prepend `TERM=xterm` if you need clean output:
  `ssh garnatxa 'TERM=xterm sacct_ -b -u $USER'`.
- **Never mix `module load <tool>` and `mamba activate <env>` for the same
  tools in the same sbatch.** Pick one source of binaries; the second one
  silently shadows paths and `htslib` etc.
- **Read-only diagnostics need no confirmation.** Destructive or
  shared-impact actions do — see § 5.

## 1. Preflight (run first every session)

Before doing anything else, run the preflight probe so you fail fast on
SSH/VPN/key problems instead of getting weird errors mid-task. The asset
[`assets/preflight.sh`](../assets/preflight.sh) does this in one shot.
Inline form:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 garnatxa '
  echo "host:        $(hostname)"
  echo "user:        $(whoami)"
  echo "groups:      $(id -Gn)"
  echo "fairshare:   $(sshare -U --noheader -P 2>/dev/null | head -1)"
  echo "home_used:   $(du_ -sh ~ 2>/dev/null | awk "{print \$1}")"
  command -v squeue_  >/dev/null && echo "squeue_:     ok" || echo "squeue_:     MISSING"
  command -v tapecopy >/dev/null && echo "tapecopy:    ok" || echo "tapecopy:    MISSING"
  ssh -o BatchMode=yes -o ConnectTimeout=3 merlot true \
      && echo "merlot ssh:  ok" || echo "merlot ssh:  FAIL"
'
```

### When the probe fails

Map the `ssh` exit signature to a recovery — don't loop retries blindly:

| Symptom | Cause | Fix the user must do |
|---|---|---|
| `Permission denied (publickey)` | Key missing on the cluster | `ssh-copy-id garnatxa` (with password). Or add key to GitLab if push-related. |
| `Connection timed out` / `No route to host` | VPN down | Reconnect `i2sysbio.ovpn`. Verify with `ping garnatxa.srv.cpd` after. |
| `Host key verification failed` | Cluster reinstall or MITM | Verify fingerprint matches `SHA256:7fUYLmRdI6b1TMMz92ln3bGFCw8J9mJOv3jniz7Xt8c` from `connecting.md`. If yes, `ssh-keygen -R garnatxa.srv.cpd` then retry. If no — stop, alert user. |
| `Invalid account` / blocked | Account inactive > 1 year | Ticket via <https://garnatxadoc.uv.es/support>. |
| Auth ok but `whoami` says `root` or wrong user | Wrong SSH config | Check `~/.ssh/config` `User` field. |

## 2. Read-only reconnaissance

Run any of these freely without asking. They are the fast path to a
diagnosis:

```bash
ssh garnatxa '
  echo "=== queue ===";              squeue -u $USER --long
  echo "=== live efficiency ===";    TERM=xterm squeue_ -u $USER
  echo "=== last 7d ===";            sacct -u $USER \
                                       --starttime=$(date -d "-7 days" +%F 2>/dev/null || date -v-7d +%F) \
                                       --format=jobid,jobname%20,state,elapsed,reqcpu,reqmem,maxrss,exitcode
  echo "=== finished efficiency ==="; TERM=xterm sacct_ -b -u $USER
  echo "=== fairshare ===";          sshare -U
  echo "=== pending priorities ==="; sprio -u $USER
'
```

From that one round-trip you can answer 80 % of "what's going on?" questions:

- Jobs stuck `PD` → look at `REASON` (see `troubleshooting.md` § 1).
- Low `E.CPU` or `E.MEM` from `sacct_` → user is wasting allocation, suggest
  right-sized resubmit.
- Fairshare close to 1.0 → group has been heavy; expect longer queue waits.
- TIMEOUT pattern → next submission needs higher QoS or `--time` headroom.

## 3. Acting on the cluster — the submit/wait/diagnose loop

The canonical operator pattern for a single job:

```bash
# 1. SUBMIT
JID=$(ssh garnatxa 'cd ~/work && sbatch --parsable myjob.sh')
echo "submitted $JID"

# 2. WAIT — poll, do NOT block ssh for hours. Sleep on the local side.
#    The 8-hour SSH idle timeout (TMOUT=28800) breaks naive `sbatch --wait`.
while :; do
  STATE=$(ssh garnatxa "sacct -j $JID -X -n -P --format=state" | head -1 | tr -d ' ')
  case "$STATE" in
    COMPLETED) echo "done"; break ;;
    FAILED|TIMEOUT|CANCELLED|OUT_OF_MEMORY|NODE_FAIL) echo "$STATE"; break ;;
    "") echo "(scheduler not aware yet)"; sleep 10 ;;
    *) sleep 30 ;;
  esac
done

# 3. DIAGNOSE
ssh garnatxa "TERM=xterm sacct_ -j $JID"
ssh garnatxa "scontrol show job $JID 2>/dev/null | grep -E 'StdOut|StdErr|WorkDir' \
              || sacct -j $JID -P --format=workdir%120 | tail -1"
```

The asset [`assets/wait_for_job.sh`](../assets/wait_for_job.sh) bundles
this loop. Use it (or inline the pattern) whenever a downstream step
depends on a job finishing.

### Polling cadence

- **Short jobs (≤ 5 min expected)**: poll every 10 s.
- **Medium (≤ 1 h)**: every 30 s.
- **Long (hours+)**: every 1–2 min. Never poll faster than 30 s when the
  job is long-running — it adds noise to the login node.

### Reading the log while it runs

```bash
ssh garnatxa "scontrol show job $JID | awk -F= '/StdOut/{print \$2}'"
# Then:
ssh garnatxa "tail -f /storage/<group>/.../slurm-$JID.out"
```

For historical jobs (where `scontrol` errors out), the path lives in
`sacct -j $JID -P --format=workdir%120` — but the **filename** depends on
what the sbatch script wrote into `--output`, which means you may have to:

```bash
ssh garnatxa "find $(sacct -j $JID -P --format=workdir%120 | tail -1) \
              -maxdepth 2 -name \"*$JID*\""
```

## 4. Pipeline mode (Nextflow / Snakemake)

A pipeline is a long-lived **master** job that submits **child** jobs.
Operating it adds two wrinkles:

1. **Master wall time must outlive the longest child.** If the master is
   killed (TIMEOUT or `scancel`), children orphan.
2. **Don't `scancel` the master alone.** Kill the children first, then
   the master, then clean `work/` (Nextflow) or `.snakemake/` (Snakemake)
   if the user explicitly OKs it.

The asset [`assets/cleanup_pipeline.sh`](../assets/cleanup_pipeline.sh)
does that ordering for you. Inline form:

```bash
# 1. Find all jobs for this pipeline (master + children share a prefix)
ssh garnatxa "squeue -u $USER -h -o '%i %j' | grep -E 'nf-|snakemake_'"

# 2. Cancel children first
ssh garnatxa "scancel --user=$USER --name=nf-ALIGN_PROCESS"  # or by jobid

# 3. Then the master
ssh garnatxa "scancel $MASTER_JID"

# 4. Confirm with the user before deleting `work/`. It's also the
#    file that lets you -resume; deleting it is a one-way commit.
```

### Resuming a killed pipeline

For Nextflow, `nextflow run … -resume` from the same `work/` directory
picks up where it left off. For Snakemake, just rerun — it recomputes the
DAG and skips completed outputs.

## 5. When to confirm with the user

Read-only diagnostics (everything in § 2) → just do it. The user expects
the agent to know the state of their cluster without 17 round-trips.

**Confirm first** for any of these, even if the user asked you to:

- Submitting an sbatch that requests > 50 CPUs or > 100 GB RAM
- `scancel JOBID` of jobs the user did not explicitly name
- `scancel -u $USER` (kill ALL the user's jobs)
- `rm -rf` of anything not in `/tmp` or a folder you just created
- `tapecopy` of multi-TB payloads (it's irreversible-ish; deleting files
  from a tape doesn't reclaim space, only reformatting does)
- Writing or modifying `~/.bashrc`, `~/.lmod.d/`, `~/.ssh/`
- `passwd` / password rotation
- Pushing to GitLab on behalf of the user
- Anything on `/storage/<other-group>/` even if you have read access

The pattern is: **describe what you're about to do, list the exact
commands, ask for "yes"**. Then proceed.

## 6. Failure recovery patterns

### 6.1 Job hit OOM → resubmit with more memory

Read the actual `MaxRSS` from `sacct_`, multiply by 1.5, regenerate the
sbatch with the new value. Don't double blindly — that wastes the
allocation again. See
[`assets/resubmit_with_bumped_resources.sh`](../assets/resubmit_with_bumped_resources.sh).

### 6.2 Job hit TIMEOUT → bump QoS or add headroom

`sacct -j <id> --format=elapsed,timelimit` shows what it ran for vs what
you asked. If `elapsed ≈ timelimit`, the job needed more wall time. If
`elapsed << timelimit`, the job hung — investigate the slurm-*.err.

QoS step-up table (recap from `slurm.md`):

| Needed wall time | QoS |
|---|---|
| ≤ 1 d | `short` |
| ≤ 7 d | `medium` |
| ≤ 15 d | `long` |
| > 15 d | not possible — checkpoint and resubmit |

### 6.3 Array job with mixed completed + failed tasks

```bash
# Which tasks failed?
ssh garnatxa "sacct -j $ARRAY_JID -X -P --format=jobid,state,exitcode | grep -v COMPLETED"

# Read one failed task's log
ssh garnatxa "find $(sacct -j ${ARRAY_JID}_$FAILED_IDX -P --format=workdir%120 | tail -1) \
              -name '*${ARRAY_JID}_${FAILED_IDX}*'"

# Common causes: bad input file for that index, race on a shared write,
# env not activated on a node, exit 6:0 = SIGABRT typically Python /
# encodings or missing C library.
```

Resubmit just the failed indices with `sbatch --array=10,11,15,...`.

### 6.4 Corrupted mamba env

Symptoms: `mamba activate myenv` fails with import errors, or your job
runs but tools crash with `htslib` version errors. Usually means the env
was built mixing channels or a stale install. Fix:

```bash
ssh garnatxa 'bash -lc "
  mamba env export -n myenv --file ~/myenv.lock.yaml
  mamba env remove -n myenv -y
  mamba env create -n myenv -f ~/myenv.lock.yaml
"'
```

## 7. The minimal session script

For a quick "check the user's state, suggest something" interaction, this
is the entire flow:

```bash
# 1. Preflight (asset)
ssh garnatxa 'bash -lc ~/garnatxa-hpc/assets/preflight.sh' \
  || { echo "preflight failed — see above for cause"; exit 1; }

# 2. Reconnaissance
ssh garnatxa '
  squeue -u $USER --long
  TERM=xterm squeue_ -u $USER
  sacct -u $USER --starttime=$(date -d "-7 days" +%F) \
    --format=jobid,jobname%20,state,elapsed,reqcpu,reqmem,maxrss,exitcode
  TERM=xterm sacct_ -b -u $USER
  sshare -U
'

# 3. (Optional) Act based on user request.
# 4. Always end with: report status + next step.
```

## 8. Cross-references

| If the agent needs… | Read |
|---|---|
| Symptom → diagnostic → fix for ~20 failure modes | [`troubleshooting.md`](troubleshooting.md) |
| End-to-end playbooks for 14 common operations | [`scenarios.md`](scenarios.md) |
| Full SLURM flag and command reference | [`slurm.md`](slurm.md) |
| Filesystem / quota / tape details | [`storage.md`](storage.md) |
| Modules / mamba / Singularity | [`software.md`](software.md) |
| Nextflow / Snakemake configs | [`pipelines.md`](pipelines.md) |
| VPN / SSH / firewall setup | [`connecting.md`](connecting.md) |
