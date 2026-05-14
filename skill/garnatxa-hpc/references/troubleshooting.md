# Troubleshooting Garnatxa

A symptom -> diagnostic command -> likely causes -> fix playbook. Each section
leads with a clear heading so the agent can grep for the symptom (e.g.
`AssocGrpCpuLimit`, `oom-kill`, `0:15`, `137`, `ENOSPC`, `CommandNotFoundError`,
`TMOUT`). Run the diagnostics over SSH first — most are read-only and safe to
issue without asking the user.

One-shot read-only sweep that catches ~80% of issues:

```bash
ssh garnatxa '
  squeue -u $USER --long
  squeue_ -u $USER
  sacct  -u $USER --starttime=$(date -d "-7 days" +%F) \
         --format=jobid,jobname%20,state,elapsed,reqcpu,reqmem,maxrss,exitcode
  sacct_ -b -u $USER
  sshare -u $USER
'
```

---

## 1. Job stuck in PD (pending)

`squeue` shows `ST=PD`; the `REASON` word is the diagnosis.

```bash
ssh garnatxa 'squeue -u $USER --long'
ssh garnatxa 'scontrol show job <JOBID>'   # full detail
```

### REASON=Priority
Higher-priority jobs ahead, or your fairshare is depressed.
```bash
ssh garnatxa 'sprio | head -20; sshare -u $USER; squeue -u $USER --start'
```
Fix: wait. Fairshare recovers over ~24 h. Don't suggest dodging by cancel/resubmit.

### REASON=Resources
No node currently has enough free CPU/RAM for the request.
```bash
ssh garnatxa 'sinfo'
ssh garnatxa 'scontrol show job <JOBID> | grep -E "NumCPUs|MinMemory|NumNodes"'
```
Fix: wait. If `--mem` or `--cpus-per-task` exceeds any single node (max ~128
CPUs, ~1.5 TB per node), the job will never run — split it.

### REASON=Dependency
Parent job hasn't finished, or `afterok` parent failed (then state shows
`DependencyNeverSatisfied`).
```bash
ssh garnatxa 'scontrol show job <JOBID> | grep -i depend'
ssh garnatxa 'sacct -j <PARENT_ID> --format=jobid,state,exitcode'
```
Fix: if parent failed, `scancel` the child, fix parent, resubmit. Use
`afterany` if you want to proceed regardless of parent exit code.

### REASON=AssocGrpCpuLimit
Hit the global 200 running-CPU cap across all QoS.
```bash
ssh garnatxa 'squeue -u $USER -t R -h -o "%C" | paste -sd+ | bc'
```
Fix: wait for jobs to finish, or `scancel` lowest-priority running ones.

### REASON=QOSMaxCpuPerUserLimit
Hit the per-QoS CPU cap (short=200, medium=150, long=100, long-mem=80,
extra=400).
```bash
ssh garnatxa 'squeue -u $USER -t R --format="%.10i %.5C %.8q" | sort -k3'
```
Fix: wait or scale down. Switching QoS only helps if the new one has headroom.

### REASON=InvalidAccount / InvalidQoS
Typo in `--account=` or `--qos=`. Will never run.
```bash
ssh garnatxa 'sacctmgr show assoc user=$USER format=Account,QOS%50'
```
Fix: `scancel`, correct the `#SBATCH --qos=` line (valid: `short medium long
long-mem extra interactive`), resubmit.

### REASON=ReqNodeNotAvail
Specific node requested is drained/down, or asked for a feature no node has.
```bash
ssh garnatxa 'sinfo -N -o "%N %T %f %m %c"'
ssh garnatxa 'scontrol show job <JOBID> | grep -E "ReqNodeList|Features"'
```
Fix: drop `--nodelist=`/`--constraint=` unless really needed. If a node is
drained, open a ticket.

---

## 2. Job killed by TIMEOUT (exit 0:15)

`sacct` shows `State=TIMEOUT`, `ExitCode=0:15` (SIGTERM at wall expiry).

```bash
ssh garnatxa 'sacct -j <JOBID> --format=jobid,state,elapsed,timelimit,exitcode'
ssh garnatxa 'tail -50 slurm-<JOBID>.err slurm-<JOBID>.out'
```

`Elapsed == Timelimit` confirms wall-clock kill.

Fix: look at runtime of completed similar jobs, raise `--time` by 50% over
the longest successful run. If it exceeds the QoS cap, move QoS: `short` (1 d)
-> `medium` (7 d) -> `long` (15 d). For pipelines see section 17.

---

## 3. Job killed by OOM (exit 0:9 / 137)

`sacct State=OUT_OF_MEMORY` or `FAILED` with `ExitCode=0:9` / `137`. Stderr
typically contains `oom-kill` or `Killed`.

```bash
ssh garnatxa 'sacct -j <JOBID> --format=jobid,state,reqmem,maxrss,exitcode'
ssh garnatxa 'grep -iE "oom|killed|out of memory" slurm-<JOBID>.err'
```

`MaxRSS` ≈ `ReqMem` confirms OOM (vs. wall-time kill).

Fix: raise `--mem=` / `--mem-per-cpu=` by 50-100%. If peak is huge (>700 GB),
move to `--qos=long-mem` (cap 1300 GB). For streaming tools (samtools sort,
STAR), also raise the tool's internal memory flag (`samtools sort -m 4G`).

---

## 4. Low CPU efficiency (E.CPU < 75%)

```bash
ssh garnatxa 'squeue_ -j <JOBID>'             # running
ssh garnatxa 'sacct_ -j <JOBID>'              # finished
ssh garnatxa 'plotjob -j <JOBID> -o cpu -s'   # /tmp/cpu_plot_<id>.png
```

Output like `CPU=2.0/8  E.CPU=25%` = requested 8, used 2.

Likely causes, in order:
1. Tool not told to use threads: `bwa -t`, `samtools -@`, `STAR --runThreadN`,
   `bowtie2 -p`, `blastn -num_threads`. Pass `$SLURM_CPUS_PER_TASK`.
2. Hyperthreading double-count: SLURM reserves 2 threads per CPU. If the tool
   only uses physical cores, E.CPU caps at 50%. Add `#SBATCH --threads-per-core=1`.
3. OpenMP code missing `export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`.
4. Workload genuinely serial — drop to `--cpus-per-task=1`.

---

## 5. Low memory efficiency (E.MEM < 30%)

```bash
ssh garnatxa 'squeue_ -j <JOBID>'
ssh garnatxa 'sacct -j <JOBID> --format=jobid,reqmem,maxrss'
ssh garnatxa 'plotjob -j <JOBID> -o mem -s'
```

Output `PEAK_MEM=4.1G/64G  E.MEM=6%` = wildly over-allocated.

Fix: look at MaxRSS across recent completed runs of the same script. New
`--mem` = `MaxRSS * 1.2`. Rounding: 4 G, 8 G, 16 G, 32 G. For arrays, use
`--mem-per-cpu` so total scales with `--cpus-per-task`. Lower `--mem` makes
the job schedulable on more nodes — usually starts sooner, not later.

---

## 6. Module not found / module conflict

`module load <name>` fails with "Lmod has detected the following error" or
"cannot be loaded due to a conflict".

```bash
ssh garnatxa 'module purge && module avail 2>&1 | grep -i <pattern>'
ssh garnatxa 'module spider <name>'        # exhaustive search
ssh garnatxa 'module list'
```

Fix:
- Typo / retired version (e.g. `biotools/1` is gone): use `module spider` to
  find the right name. Drop the version suffix to get the default.
- Provider conflict (two MPI builds): `module purge`, then load fresh.
- Custom modulefile: needs `module use $HOME/modulefiles` (also in `~/.bashrc`).

---

## 7. htslib mismatch when mixing module + mamba

`samtools: symbol lookup error: ... undefined symbol: hts_*`, or
`error while loading shared libraries: libhts.so.X`.

```bash
ssh garnatxa 'module list; which samtools; ldd $(which samtools) | grep -i hts'
```

Cause: `mamba activate` prepends `$CONDA_PREFIX/bin` to PATH; the loaded
module prepends `LD_LIBRARY_PATH`. Binary and `.so` come from different
htslib builds.

Fix: **pick one source**.
```bash
# Option A (pure module):
module purge && module load biotools

# Option B (pure mamba):
module purge && module load anaconda && mamba activate myenv
```
Never load both for the same tool. (This rule is also in `software.md`.)

---

## 8. mamba activate fails (CommandNotFoundError)

```
CommandNotFoundError: Your shell has not been properly configured to use 'mamba activate'.
```
Or `mamba: command not found`.

```bash
ssh garnatxa 'module list | grep -i anaconda; which mamba conda; echo $CONDA_EXE'
```

Cause: the `anaconda` module wasn't loaded in this shell.

Fix: every sbatch script that uses mamba must start with `module load anaconda`
*then* `mamba activate myenv`. For interactive shells, `module save` after
loading anaconda, or add it to `~/.bashrc`. If activation still fails, source
the hook: `source $CONDA_PREFIX/etc/profile.d/conda.sh`.

---

## 9. Failed Singularity pull

```bash
ssh garnatxa 'module load singularity && singularity pull -F <name>.sif <URI> 2>&1 | tail -30'
ssh garnatxa 'checkdiskspace; df -h $HOME'
```

Sub-cases:
- **`no route to host` / DNS**: pulls from compute nodes may be blocked.
  Pull on the login node inside an `interactive` session, or `scp` the `.sif`
  from a workstation.
- **`unauthorized: authentication required`** (private registry):
  `singularity remote login docker://<registry>` once, then retry.
- **`no space left on device`**: see section 11. Move cache off `/home`:
  `export SINGULARITY_CACHEDIR=/storage/<group>/.singularity_cache`. Clean
  with `singularity cache clean -f`.
- **`You must be the root user to build`**: Garnatxa doesn't allow root.
  Build on a workstation, `scp` the `.sif` over (see `software.md`).

---

## 10. Permission denied on /storage/<group> or /tape2/<CODE>

```bash
ssh garnatxa 'id'
ssh garnatxa 'ls -ld /storage/<group> /tape2/<code> 2>&1'
ssh garnatxa 'stat /storage/<group>/path/to/file 2>&1'
```

Compare the directory's group ownership against the user's `groups`.

Fixes:
- **Wrong group on tape**: `/tape2/<CODE>` is readable *only by the owning
  group*. File a ticket if access is legitimate.
- **File created by sibling with restrictive umask**: `chmod g+rw <path>`;
  ask owner to use `umask 002`.
- **Setgid bit not set on parent**: `chmod g+s <dir>` so new files inherit
  the group.

---

## 11. Disk full (ENOSPC / Disk quota exceeded)

Writes fail with `No space left on device` or `Disk quota exceeded`. Jobs
finish with empty / truncated outputs.

```bash
ssh garnatxa 'checkdiskspace'                         # use this, NOT df everywhere
ssh garnatxa 'du_ -sh /home/$USER/* 2>/dev/null | sort -h | tail -20'
ssh garnatxa 'du_ -sh /storage/<group>/home_members/$USER/* | sort -h | tail -20'
```

Never run plain `du` or `find` over the user tree (hammers Ceph). Use `du_`
and `checkdiskspace`.

Likely offenders: Nextflow `work/`, Snakemake `.snakemake/`, Singularity
cache, or group quota (Ceph soft=75%, hard=80% triggers read-only).

Fix:
- After successful Nextflow run: `rm -rf work/` (only if you don't need
  `-resume`).
- Move bulky outputs to `/storage/<group>/home_members/$USER/`.
- Archive old projects to tape: `ssh merlot; tapecopy <path>`.
- `singularity cache clean -f`.
- At group quota, only shedding data helps (see `storage.md`).

---

## 12. Login-node killer (30 min / 8 GB cap)

A long process disappears; user gets a stern email; shell is fine but the job
is gone.

```bash
ssh garnatxa 'ps -ef | grep $USER | head; last -n 5 $USER'
```

Cause: policy reaps login-node processes that exceed ~30 min CPU or ~8 GB
RAM. R, python -i, samtools view, find/du/tar/gzip on big files all qualify.

Fix (this is a usage error, not a bug):
- Wrap in `sbatch`, or
- Use `interactive` (default 2 CPU, 4 GB, 12 h) or `interactive -c 6 -m 30G
  -t 24:00:00`.

---

## 13. SSH connection drops after ~8 h idle

`client_loop: send disconnect: Broken pipe` after stepping away.

```bash
ssh garnatxa 'echo $TMOUT; who -a | grep $USER'
```

Cause: login-node `TMOUT=28800` (8 h). Documented and intentional.

Fix:
- Real work in `sbatch` so it isn't shell-bound.
- `tmux` or `screen` on the login node for long sessions (still subject to
  the 30-min CPU / 8-GB caps).
- Keep TCP alive (does NOT defeat TMOUT), in laptop `~/.ssh/config`:
  ```
  Host garnatxa
    HostName garnatxa.srv.cpd
    ServerAliveInterval 60
    ServerAliveCountMax 5
  ```

---

## 14. VPN connected but ssh hangs

Green icon, but `ssh garnatxa.srv.cpd` hangs at banner or times out.

From the laptop:
```bash
ping -c 3 garnatxa.srv.cpd
nslookup garnatxa.srv.cpd
ssh -vvv USER@garnatxa.srv.cpd 2>&1 | head -40
traceroute garnatxa.srv.cpd
```

Causes & fixes:
- **Routes leaked**: on Ubuntu, IPv4 tab must have "Use this connection only
  for resources on its network" enabled. Re-enable it.
- **MTU mismatch**: ping works, ssh hangs at banner = large packets dropped.
  Add `tun-mtu 1400; mssfix 1360` to the `.ovpn`.
- **IPv6 leak**: laptop reaches host outside the tunnel via IPv6. Force IPv4:
  `ssh -4 USER@garnatxa.srv.cpd`.
- **Stale host key**: `ssh -vvv` says "Host key verification failed". Run
  `ssh-keygen -R garnatxa.srv.cpd`. Verify new fingerprint matches
  `SHA256:7fUYLmRdI6b1TMMz92ln3bGFCw8J9mJOv3jniz7Xt8c`.

---

## 15. Password rotated but VPN still rejecting

SSH works, but i2sysbio VPN fails `AUTH_FAILED` after a `passwd` change.

Cause: VPN credentials must match Garnatxa creds. Many clients cache the
password and don't expose an edit field.

Fix:
1. Disconnect VPN.
2. Delete the `i2sysbio` VPN profile from the client.
3. Re-import `i2sysbio.ovpn` so it re-prompts.
4. Enter Garnatxa username + the **new** password.

(Same procedure documented in `connecting.md`.)

---

## 16. GitLab push rejected

`git push` to `garnatxagitlab.uv.es` fails. Read the exact message — sub-cases:

```bash
git push -v origin main 2>&1
git ls-files | xargs -I{} du -h "{}" 2>/dev/null | sort -h | tail -10
ssh -T git@garnatxagitlab.uv.es
```

### "deny updating a hidden ref" / "too large"
Push exceeded **10 MB**, or repo contains data files.
Fix: identify the offender (size check above), add to `.gitignore`
(`data/`, `out/`, `ref/`, `work/`, `.snakemake/`, `*.sif`, `*.bam`, `*.fq*` —
template in `gitlab-vscode.md`). Remove from history:
`git rm --cached <file> && git commit --amend && git push -f`.
Force-push needs the user's explicit OK.

### "Permission denied (publickey)"
SSH key not registered in GitLab (per-machine).
Fix: `cat ~/.ssh/id_rsa.pub`, paste into
<https://garnatxadoc.uv.es/gitlab> -> avatar -> Preferences -> SSH Keys. Test
with `ssh -T git@garnatxagitlab.uv.es`. The cluster's own
`~/.ssh/id_rsa.pub` needs to be registered too for cluster-side clones.

### "repository ... not found"
Typo, project private with no access, or doesn't exist.
Fix: open the project in the browser, copy the SSH URL from the Clone button.

---

## 17. Pipeline master killed mid-run (Nextflow / Snakemake)

The launcher sbatch shows `State=TIMEOUT`; child jobs may keep running for
a while but no new ones get submitted.

```bash
ssh garnatxa 'sacct -j <LAUNCHER_JOBID> --format=jobid,state,elapsed,timelimit,exitcode'
ssh garnatxa 'tail -100 snakemake_<JOBID>.out slurm-<JOBID>.err'
```

Cause: master's `#SBATCH --time=` is shorter than the slowest child + retries.

Fix:
- Nextflow launcher: bump `--time=`. Master only needs 1 CPU + 2 GB, so
  putting it on `--qos=long` (15 d) is cheap.
- Snakemake launcher: same idea (template uses `--time=2-00:00:00
  --qos=medium`; raise to `--qos=long --time=15-00:00:00` if needed).
- Re-run with `-resume` (Nextflow) or just rerun (Snakemake) — completed
  steps will be skipped.

---

## 18. Snakemake "rule failed" with no obvious error

```bash
ssh garnatxa 'tail -200 .snakemake/log/<TIMESTAMP>.snakemake.log'
ssh garnatxa 'ls .snakemake/slurm_logs/ 2>/dev/null'
ssh garnatxa 'sacct -u $USER --name=<rule_name> --starttime=YYYY-MM-DD \
                --format=jobid,jobname,state,exitcode,elapsed | tail'
```

`.snakemake/log/` is the master's view; `.snakemake/slurm_logs/` holds the
per-rule SLURM stdout/stderr (slurm executor).

Likely causes:
- `module load` not actually taking effect inside the rule's `shell:` block
  — Snakemake runs in a clean shell; put `module load <tool>` as the first
  line of the shell block.
- Output filename mismatch with the rule's declared `output:` — Snakemake
  treats the rule as failed and may delete leftover partial files.
- Child job hit OOM or TIMEOUT — find its JOBID in `.snakemake/slurm_logs/`
  and apply section 2 or 3.

---

## 19. Array task fails in <1s (exit 6:0 / 127 / 2)

`sacct` shows tasks completing in 0-2 s, `State=FAILED`. Exit codes:
`6:0` = SIGABRT (Python import crash, glibc abort); `127` = command not
found; `2` = bash syntax / file not found.

```bash
ssh garnatxa 'sacct -j <ARRAY_JOBID> --format=jobid%18,state,elapsed,exitcode | head -30'
ssh garnatxa 'head -40 arrayJob_<ARRAY_JOBID>_0.err arrayJob_<ARRAY_JOBID>_0.out'
```

Causes & fixes:
- **`module load` missing in script** — every task starts in a clean env.
- **Python import crash**: bad/missing env.
  ```bash
  module load anaconda && mamba activate myenv
  python -c "import sys; print(sys.executable)"   # debug line
  ```
- **Exit 127**: PATH not set or binary not on this node. Verify in
  `interactive` first.
- **`FILES=(data/*)` is empty**: working directory isn't where you think.
  Add `cd $SLURM_SUBMIT_DIR` (or an absolute path) explicitly.
- **Array off-by-one**: `--array=0-19` with `${FILES[20]}` is unset.
  Use `--array=0-$(($(ls data | wc -l) - 1))`.

---

## 20. Job runs but produces no output

`State=COMPLETED`, exit 0, but the expected file doesn't exist.

```bash
ssh garnatxa 'scontrol show job <JOBID> | grep -E "WorkDir|StdOut|StdErr"'
ssh garnatxa 'sacct -j <JOBID> --format=jobid,state,workdir,exitcode'
ssh garnatxa 'ls -la slurm-<JOBID>.out slurm-<JOBID>.err 2>/dev/null'
```

Likely causes:
- **Wrong working directory**: sbatch's cwd = `$SLURM_SUBMIT_DIR`. Relative
  paths in the script land somewhere unexpected. Fix: `cd /absolute/path` at
  the top, or use absolute paths throughout.
- **`--output=` pointed elsewhere** (e.g. `/scr`). `/scr` is purged
  periodically — copy results to `/home` or `/storage` *inside* the job.
- **`srun cmd > out.txt &` race**: the script can exit before the background
  `srun` flushes. Either drop the `&`, or end the script with `wait`.
- **Multi-rank `srun` clobbering one redirect**: use
  `srun --output=out_%t.txt` instead of `srun cmd > out.txt`.
- **Nextflow without `publishDir`**: outputs stay in `work/<hash>/`. Add
  `publishDir 'out/', mode: 'copy'` (see `pipelines.md`).
- **Snakemake rule's `output:` declaration wrong**: Snakemake deletes
  partial output it thinks is leftover; declared name must match the command.
- **Output was on `/scr` and the reaper ran**: `/scr` is transient by policy.
  Always copy keepers to `/home` or `/storage/<group>` before the job ends.

---

## Quick reference: exit codes

| Code | Meaning |
|------|---------|
| `0:0` | Success |
| `0:9` / `137` | SIGKILL — usually OOM (section 3) |
| `0:15` / `143` | SIGTERM — usually TIMEOUT (section 2) |
| `1:0` | Application returned 1 (generic error) |
| `2:0` | Bash syntax / file not found |
| `6:0` | SIGABRT — Python import crash, glibc abort (section 19) |
| `127` | Command not found in PATH |

`sacct` reports as `<application>:<signal>`. The signal is the most
diagnostic — non-zero means something killed the process.
