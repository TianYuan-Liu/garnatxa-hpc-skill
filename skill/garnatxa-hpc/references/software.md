# Software stack on Garnatxa

## Philosophy

- Garnatxa is shared infrastructure. Develop locally, run stable workflows here.
- Pre-installed tools are exposed through Lmod **modules**.
- For things not pre-installed, use a **mamba/conda env** in your home, or a
  **Singularity container**.
- **Docker is not installed** (the daemon model is unsafe for multi-user HPC).
  Use Podman or Singularity instead.

## Lmod modules

Module naming: `software/version-toolchain`. Tab-completion works on names. If
you omit the version, the **default** marked `D` in `module avail` is loaded.

### Commands

```text
module avail                list available modules
module load NAME[/VERSION]  load a module
module list                 currently loaded
module purge                clear the environment
module spider               every possible module (full search)
module show NAME            inspect what a module sets up
module whatis NAME          one-line description
module help NAME            help text
```

> **Operator note**: `module` is **not in non-interactive SSH shells** —
> Lmod is initialized in `/etc/profile.d/lmod.sh` which only runs in login
> shells. When you (the agent) call modules over SSH, wrap them in
> `bash -lc`:
>
> ```bash
> ssh garnatxa 'bash -lc "module avail | head -20"'
> ssh garnatxa 'bash -lc "module load anaconda && mamba env list"'
> ```
>
> Inside an `sbatch` script `module` works directly — SLURM sources the
> login files for you.

### Switching versions

Loading a new version of an already-loaded module swaps automatically:

```text
[USERNAME@master ~]$ module load R/4.1.2
The following have been reloaded with a version change:
  1) R/4.2.1 => R/4.1.2
```

### Persist modules across sessions

Every fresh SSH session starts empty. Two options:

```bash
module save           # writes ~/.lmod.d/default, auto-loaded next session
```

Or add `module load …` lines to `~/.bashrc`.

### Modules you'll see on Garnatxa

`module avail` shows trees from `/opt/ohpc/pub/modulefiles`,
`/opt/ohpc/pub/moduledeps/gnu9`, and `/storage/apps/modulefiles`. Common ones:

- Compilers / runtimes: `gnu9/9.4.0`, `intel/...`, `openmpi4/4.1.4`,
  `mpich/3.4.2-ucx`, `openblas/0.3.7`, `gsl/2.7`.
- Languages: `python/3.11`, `R/4.1.2`, `R/4.2.1`, `R/4.4.0` (default),
  `matlab/R2022b`, `matlab/R2024a` (default).
- Build tools: `autotools`, `cmake/3.21.3`.
- Containers: `singularity/3.7.1`, `singularity/3.11.1` (default),
  `charliecloud/0.15`.
- Bioinformatics bundle: `biotools/2` (default and only version — `biotools/1`
  has been retired).

### The `biotools` convenience bundle

`module load biotools` (i.e. `biotools/2`) loads, in one go:

| Tool | Version |
|------|---------|
| NCBI-BLAST  | 2.16 |
| samtools    | 1.21 |
| bwa         | 0.7.17 |
| bowtie2     | 2.5.4 |
| fastqc      | 0.12.1 |
| fastp       | 0.24 |
| fastplong   | 0.2.2 |
| BBMap       | 39.14 |
| bedtools    | 2.30.0 |
| mafft       | 7.505 |
| iqtree2     | 2.2.0 |
| SRA Toolkit | 3.0.0 |
| bcftools    | 1.20 |
| KMC         | 3.2.1 |

Or `module load samtools` etc. for individual tools. (Versions drift over time
— `module whatis biotools` and the `module load biotools` output are the
source of truth on the cluster itself.)

### Creating your own modulefile

For software installed in your home or `/storage`.

```bash
mkdir ~/modulefiles
module use $HOME/modulefiles    # do this each session or add to ~/.bashrc
```

Directory layout: `~/modulefiles/<software>/<version>` (Tcl).

```tcl
#%Module1.0
proc ModulesHelp { } {
    puts stderr "This module provides FastANI"
    puts stderr "Version 1.83"
}

module-whatis "Name: FastANI"
module-whatis "Version 1.83"

set version 1.83
always-load gnu9/9.4.0

set BASE_PATH /home/USERNAME/software/fastani
prepend-path PATH $BASE_PATH/bin
```

Then:

```bash
module avail            # should list yours under ~/modulefiles
module load fastani
```

## Mamba / Conda

Anaconda is pre-installed but slow to resolve dependencies. Use **mamba**
(same API as conda; both ship in the `anaconda` module).

```bash
module load anaconda                 # activates (base)
mamba create -n myenv python=3       # always pin the Python major version
mamba activate myenv
mamba install -c bioconda samtools
mamba deactivate
mamba env list                       # all envs (yours + system)
mamba env remove -n myenv            # delete
```

Envs land under `/home/USERNAME/.conda/envs/<name>`.

### Export and replicate an env

```bash
mamba activate myenv
mamba env export --file environment.yml
# Edit environment.yml — change the `name:` line first if you want a new name
mamba env create -f environment.yml
```

### Never mix modules and conda in the same job

> If you use a conda environment, install everything you require for that job
> inside that environment. Mixing modules from the system with packages inside
> conda will fail or cause major issues.

Inside an `sbatch` script choose **one** of `module load …` or
`mamba activate …` for the tools you're calling — not both.

**The single most common silent failure** this causes is an **htslib
version mismatch**. Concretely: you `module load samtools` (samtools 1.21
plus its bundled htslib), then `mamba activate myenv` which has its own
`bcftools` + `htslib` on `PATH`/`LD_LIBRARY_PATH`. Calls to `bcftools`
then load samtools' htslib at runtime, producing cryptic CRAM resolution
errors or silently-wrong results on edge cases. If you need samtools AND
bcftools together, install both in the same mamba env, or load both from
the `biotools` bundle which already pins compatible versions.

## Singularity

`module load singularity` exposes Singularity 3.x. It runs containers in user
space (no daemon), supports Docker images, and uses single-file `.sif`
images.

### Pulling images

```bash
# Singularity Hub
singularity pull hello-world.sif shub://vsoch/hello-world

# Docker Hub
singularity pull python-3.9.6.sif docker://python:3.9.6-slim-buster

# HTTPS (Galaxy / Bioconda mirrors)
singularity pull --name fastqc-0.11.9--0.sif \
  https://depot.galaxyproject.org/singularity/fastqc:0.11.9--0

# OCI/ORAS registries (e.g. INRAE Forgemia)
singularity pull bwa_v0.7.17.sif \
  oras://registry.forgemia.inra.fr/gafl/singularity/bwa/bwa:latest
```

### Inspect

```bash
singularity inspect fastqc-0.11.9--0.sif
```

### Run

- `singularity run IMAGE` — runs the default `runscript` baked into the image.
- `singularity exec IMAGE CMD` — runs `CMD` inside the container, ignoring the
  default.

```bash
singularity exec fastqc-0.11.9--0.sif fastqc -h
```

### Bind mounts

Singularity 3.6.x auto-mounts `$HOME`, `/tmp`, `/var/tmp`, `/sys`, `/proc`,
`/etc/resolv.conf`, `/etc/passwd`, and `$PWD`. Anything else needs explicit
`-B host:container`:

```bash
singularity shell -B /storage/group/shared hello-world.sif
```

Writes inside the container are limited to `$HOME` / `/home/<USER>`.
X11 sessions don't work inside containers.

### Running a container in an sbatch job

```bash
#!/bin/bash
#SBATCH --job-name=singularityTest
#SBATCH --output=singularityTest_%j.out
#SBATCH --ntasks=1 --cpus-per-task=1 --mem=10G --time=00:05:00 --qos=short

module load singularity

srun singularity run bwa_v0.7.17.sif index ref/chr8.fa -p ref/chr8_ref
srun singularity run bwa_v0.7.17.sif aln -I -t 1 ref/chr8_ref data/reads_00.fq > out/example_aln.sai
```

### Building your own `.sif`

You **cannot** build on Garnatxa — it needs root. Build on a workstation, then
`scp` the `.sif` to the cluster.

```bash
# On a workstation with root:
singularity build --sandbox python_sandbox docker://python:3.7.3-stretch
singularity exec --writable python_sandbox pip3 install --upgrade pip
singularity exec --writable python_sandbox pip3 install bwa
singularity build python_sandbox.sif python_sandbox

scp python_sandbox.sif USER@garnatxa.srv.cpd:~/containers/
```

## Quick decision table

| Need                                       | Use |
|--------------------------------------------|-----|
| Use a pre-installed bio tool               | `module avail` → `module load <name>` |
| Install something not in modules           | `module load anaconda` → `mamba create -n …` → `mamba install …` |
| Run a pre-built tool reproducibly          | `module load singularity` → `singularity pull docker://…` → `singularity exec …` |
| Build a custom container                   | Build on your laptop with root, `scp` the `.sif` to Garnatxa |
| Resolve "conflict" between two modules     | `module load <other-version>` (Lmod swaps automatically) or `module purge` |
| Avoid retyping `module load`               | `module save` (writes `~/.lmod.d/default`) or add to `~/.bashrc` |
