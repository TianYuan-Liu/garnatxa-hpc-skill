# Nextflow and Snakemake on Garnatxa

Both engines use SLURM as their executor. A long-lived **master job** stays in
the queue for the whole pipeline duration; it submits each pipeline step as
its own SLURM job and tracks dependencies. The master only needs 1 CPU and
1–2 GB RAM — don't over-allocate it, but **give it enough wall time to outlive
the slowest pipeline step.**

## Nextflow

### Install / availability

Nextflow is a system module — no per-user install:

```bash
module load nextflow
```

### Files

A Garnatxa-style Nextflow project has three files:

- `NextflowJob.config` — executor and per-process resource profiles.
- `NextflowJob.nf` — DSL2 workflow (channels, processes, the `workflow {}` block).
- `NextflowLauncher.sbatch` — the SLURM launcher for the master process.

### `NextflowJob.config` — recommended skeleton

```groovy
executor {
    queueSize = 200
}

process {
    executor = 'slurm'
    queue = 'global'
    maxRetries = 5
    errorStrategy = 'retry'
}

process {
    withLabel: SHORT_PROCESS {
        memory = { 1.GB * task.attempt }
        time = { 5.minute * task.attempt }
        cpus = 2
        clusterOptions = '--qos=short'
    }

    withLabel: GENERIC_PROCESS {
        memory = { 5.GB * task.attempt }
        time = { 1.day * task.attempt }
        cpus = 8
        clusterOptions = '--qos=medium'
        errorStrategy = { task.exitStatus >= 1 ? 'retry' : 'terminate' }
    }
}
```

Notes:

- `executor = 'slurm'` — submit each task with `sbatch`.
- `queue = 'global'` is the **partition**, not the QoS. Set the QoS via
  `clusterOptions = '--qos=short'`.
- `{ 1.GB * task.attempt }` scales memory/time on each retry — combined with
  `errorStrategy = 'retry'` this gives self-healing resource bumps.
- `queueSize = 200` caps concurrent jobs. Garnatxa's per-user SLURM caps still
  apply — anything beyond stays `PD`.
- `withLabel: NAME { ... }` binds resource profiles to processes that declare
  `label 'NAME'` in the `.nf` file.

### `NextflowJob.nf` — process example

```groovy
#!/usr/bin/env nextflow

params.reads  = "$projectDir/data/reads_*.fq"
params.genome = "$projectDir/ref/chr8.fa"
params.ref    = "$projectDir/ref"
params.outdir = "$projectDir/out"

process INDEX {
    label 'SHORT_PROCESS'
    publishDir params.ref, mode: 'copy'

    input:
    path genome

    output:
    path 'chr8_ref.*'

    script:
    """
    module load biotools
    bwa index $genome -p chr8_ref
    """
}

process ALIGN {
    label 'GENERIC_PROCESS'
    publishDir params.outdir, mode: 'copy'

    input:
    path genome_indexed
    path read

    output:
    path '*_aln.sai'

    script:
    """
    module load biotools
    bwa aln -I -t $task.cpus chr8_ref $read > ${read.baseName}_aln.sai
    """
}

workflow {
    reads_ch  = Channel.fromPath(params.reads)
    index_ch  = INDEX(params.genome)
    align_ch  = ALIGN(index_ch, reads_ch)
    align_ch.view()
}
```

Conventions:

- Inside each process, load tool modules **inside the `script:` block**.
- Use `$task.cpus` so the tool actually uses the cores SLURM reserved.
- `publishDir` copies final outputs out of Nextflow's `work/<hash>/` temp dir
  to the directory you specify. Without it, outputs aren't visible to you.

### `NextflowLauncher.sbatch`

```bash
#!/bin/bash
#SBATCH --qos=short
#SBATCH --mem=2G
#SBATCH --cpus-per-task=1
#SBATCH --time=12:00:00

WORKFLOW=$1
CONFIG=$2

module load nextflow
nextflow -C ${CONFIG} run ${WORKFLOW} -resume -with-report -with-dag
```

Submit:

```bash
sbatch NextflowLauncher.sbatch ./NextflowJob.nf ./NextflowJob.config
```

- `-resume` reuses cached results from a previous run.
- `-with-report` writes an HTML CPU/memory report after the run.
- `-with-dag` writes a DAG file.
- Increase `--time` for longer pipelines — the master must outlive the
  slowest child job, otherwise the whole workflow is killed.

### After the run

Nextflow keeps every task's intermediate files in `work/<hash>/`. This blows up
fast for omics. Once you've verified outputs landed via `publishDir`:

```bash
rm -rf work
```

(Keep `work/` if you might want to `-resume`.)

### Nextflow → SLURM mapping

| Nextflow directive | SLURM equivalent |
|--------------------|------------------|
| `executor = 'slurm'` | submits with `sbatch`-style scheduling |
| `queue = 'global'` | `--partition=global` |
| `memory = { 1.GB * task.attempt }` | `--mem=…` (scales on retry) |
| `time = { 5.minute * task.attempt }` | `--time=…` (scales on retry) |
| `cpus = N` | `--cpus-per-task=N`, available as `$task.cpus` |
| `clusterOptions = '--qos=short'` | raw extra sbatch flags |
| `errorStrategy = 'retry'` + `maxRetries` | re-submit on failure |
| `label 'X'` in `.nf` | resolves to `withLabel: X` in config |

### Pitfalls

- Forgetting `publishDir` → outputs invisible after the run.
- Not using `$task.cpus` inside `script:` → tool runs single-threaded despite
  SLURM reserving more.
- Underestimating master wall time → whole pipeline killed.
- Over-allocating master resources → wastes capacity; child jobs do the work.
- Mixing partition and QoS: `queue` is partition, QoS goes through
  `clusterOptions`.

### Recovering from a killed master

If the master is `scancel`-led or hits TIMEOUT, its child jobs **continue
in the queue** until they finish naturally or hit their own walltime.
**Don't `scancel` the master alone** — kill children first, then the
master. [`assets/cleanup_pipeline.sh`](../assets/cleanup_pipeline.sh)
implements the right ordering:

```bash
# 1. List children (Nextflow names them nf-PROCESS_NAME)
ssh garnatxa "squeue -u $USER -h -o '%i %j' | grep '^[0-9]* nf-'"

# 2. Cancel children by name pattern, then master
ssh garnatxa "squeue -u $USER -h -o '%i %j' | awk '\$2 ~ /^nf-/ {print \$1}' | xargs -r scancel"
ssh garnatxa "scancel <MASTER_JID>"

# 3. To resume: leave `work/` alone, just rerun with -resume
sbatch nextflow_launcher.sbatch ./NextflowJob.nf ./NextflowJob.config
```

---

## Snakemake

### Install (per user)

Snakemake is **not** a system module — confirmed against the cluster
(`module avail snakemake` returns nothing). Each user installs it once via
mamba. You also need the SLURM **executor plugin** (Snakemake 8+ split
SLURM out into a separate package):

```bash
module load anaconda
mamba create -n snakemake -c bioconda -c conda-forge snakemake snakemake-executor-plugin-slurm
mamba activate snakemake
```

Activate the env in every session before using `snakemake`.

### Files

- `Snakefile` — rules and the `all` target (Python-based DSL).
- `Snakeconfig.yaml` — Snakemake profile: executor, partitions, threads,
  memory, runtime, extra SLURM args per rule.
- `SnakemakeLauncher.sbatch` — SLURM launcher for the master.

### `Snakeconfig.yaml` — recommended skeleton

```yaml
executor: slurm
jobs: 200

default-resources:
    slurm_partition: "global"

set-threads:
    bwa_index: 1
    bwa_align: 8
    bwa_samse: 1

set-resources:
    bwa_index:
        slurm_partition: "global"
        mem_mb: 5000
        slurm_extra: "' -q short '"
        runtime: "10h"
    bwa_align:
        slurm_partition: "global"
        mem_mb: 2000
        slurm_extra: "' -q medium '"
        runtime: "5m"
    bwa_samse:
        slurm_partition: "global"
        mem_mb: 2000
        slurm_extra: "' -q short '"
        runtime: "10m"
```

Notes:

- Quote `slurm_extra` exactly as `"' -q short '"` — outer YAML double quotes,
  inner literal single quotes so the value is forwarded verbatim.
- `set-threads` controls `--cpus-per-task` and the `{threads}` placeholder
  used inside rules.
- `jobs: 200` caps concurrent SLURM jobs at the Snakemake level.

### `Snakefile` example

```python
genome = "ref/chr8.fa"
SAMPLES, = glob_wildcards("data/{sample}.fq")

rule all:
    input:
        expand("out/{sample}.sam", sample=SAMPLES)

rule bwa_index:
    input:
        genome
    output:
        idx = multiext("ref/chr8_ref", ".amb", ".ann", ".bwt", ".pac", ".sa")
    log:
        "logs/bwa_index.log"
    shell:
        """
        module load bwa
        bwa index {input} -p ref/chr8_ref 2> {log}
        """

rule bwa_align:
    input:
        read_sample = "data/{sample}.fq",
        idx = "ref/chr8_ref.bwt"            # forces bwa_index to run first
    log:
        "logs/bwa_align_{sample}.log"
    output:
        "out/{sample}.sai"
    shell:
        """
        module load bwa
        bwa aln -I -t {threads} ref/chr8_ref {input.read_sample} > {output} 2> {log}
        """

rule bwa_samse:
    input:
        "out/{sample}.sai",
        "data/{sample}.fq"
    log:
        "logs/bwa_samse_{sample}.log"
    output:
        "out/{sample}.sam"
    shell:
        """
        module load bwa
        bwa samse ref/chr8_ref {input} {genome} > {output} 2> {log}
        """
```

Inputs gate execution: a rule won't start until every input file exists, which
is how cross-rule ordering is enforced (e.g. `bwa_align` requires
`ref/chr8_ref.bwt`, forcing `bwa_index` to run first).

### `SnakemakeLauncher.sbatch`

```bash
#!/bin/bash
#SBATCH --job-name=snakemakeLauncher
#SBATCH --output=snakemake_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=2-00:00:00
#SBATCH --qos=medium

module load anaconda
mamba activate snakemake

snakemake --slurm-jobname-prefix snakemake --profile ./Snakeconfig.yaml
```

Submit:

```bash
sbatch SnakemakeLauncher.sbatch
```

If the `Snakefile` is named something else, add `-s path/to/file`.

### Snakemake → SLURM mapping

| YAML key (under `set-resources`) | SLURM equivalent |
|----------------------------------|------------------|
| `slurm_partition: "global"` | `--partition=global` |
| `mem_mb: 5000` | `--mem=5000M` |
| `runtime: "10h"` | `--time=…` |
| `slurm_extra: "' -q short '"` | extra raw sbatch flags (here `-q`) |
| `set-threads: <rule>: N` | `--cpus-per-task=N` and `{threads}` placeholder |
| `default-resources:` | fallback values for any rule that doesn't override |
| `jobs: 200` (top level) | max concurrent SLURM jobs Snakemake submits |

### DAG / rule graph

Graphviz must be installed in the env (`mamba install graphviz`):

```bash
snakemake --profile ./Snakeconfig.yaml --dag       | dot -Tpng > dag.png
snakemake --profile ./Snakeconfig.yaml --rulegraph | dot -Tpng > rulegraph.png
```

`--dag` shows one node per wildcard instance; `--rulegraph` shows just
abstract rule-to-rule dependencies.

### Pitfalls

- Forgetting an input declaration → no implicit dependency → race conditions.
- Master sbatch `--time` too short → Snakemake kills mid-pipeline.
- `Snakefile` missing or named differently — pass `-s path` or rename it.
- Running Snakemake directly on the login node violates cluster policy; the
  Garnatxa docs explicitly recommend wrapping it in `sbatch`.

---

## Side-by-side cheat sheet

| Concern | Nextflow | Snakemake |
|---------|----------|-----------|
| Install | `module load nextflow` | `mamba create -n snakemake && mamba install -c bioconda snakemake` |
| Config | `NextflowJob.config` (Groovy) | `Snakeconfig.yaml` (YAML profile) |
| Workflow | `NextflowJob.nf` (DSL2) | `Snakefile` (Python DSL) |
| Executor | `process { executor = 'slurm' }` | `executor: slurm` |
| Partition | `queue = 'global'` | `slurm_partition: "global"` |
| QoS | `clusterOptions = '--qos=short'` | `slurm_extra: "' -q short '"` |
| CPUs | `cpus = N`; use `$task.cpus` in script | `set-threads: <rule>: N`; use `{threads}` |
| Memory | `memory = { 1.GB * task.attempt }` | `mem_mb: 5000` |
| Time | `time = { 5.minute * task.attempt }` | `runtime: "10h"` |
| Concurrent cap | `executor { queueSize = 200 }` | `jobs: 200` |
| Retries | `errorStrategy = 'retry'` + `maxRetries = 5` | not shown; pass `--retries N` |
| Master wall time | `#SBATCH --time=12:00:00` (`--qos=short`) | `#SBATCH --time=2-00:00:00` (`--qos=medium`) |
| Final outputs | `publishDir <path>, mode: 'copy'` | written directly to each rule's `output:` |
| Workdir to clean | `rm -rf work` after success | no `work/`; `.snakemake/` holds logs |
| Reports | `-with-report` (HTML) | `--report report.html` (upstream feature) |
| DAG | `-with-dag` | `--dag` / `--rulegraph` piped to `dot` |
