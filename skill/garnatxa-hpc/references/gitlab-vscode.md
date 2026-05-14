# GitLab and VSCode workflow

## Self-hosted GitLab

- **URL**: <https://garnatxadoc.uv.es/gitlab>
- **Login**: use the **LDAP** tab with your Garnatxa username and password.
- **What lives here**: **source code only**. Don't push binaries, archives,
  databases, FASTA/FASTQ, etc. — they may be rejected.
- **Push size limit**: 10 MB per push.

### Add an SSH key to GitLab

You need one key per machine you push from (your laptop AND your Garnatxa
account for cluster-side clones).

```bash
# On your machine — generate if you don't have one
ssh-keygen -t rsa

# Show the public key
cat ~/.ssh/id_rsa.pub
```

Then in GitLab: top-right avatar → **Preferences** → **SSH Keys** → paste the
key → **Add key**. Repeat from inside Garnatxa with
`~/.ssh/id_rsa.pub` on the cluster to enable `git clone` / `git push` from
there too.

### Create a project

1. Sign in (LDAP tab).
2. **Project → New project → Create blank project.**
3. Fill in name + URL slug. Choose visibility:
   - **Private** — you (and shared-group members) only.
   - **Internal** — any logged-in GitLab user.
   - **Public** — anyone on the internet.
4. **Uncheck** "Initialize repository with a README" if you'll push existing
   code into the repo.
5. **Create project**. Copy the SSH clone URL — looks like
   `git@garnatxagitlab.uv.es:<USER>/<PROJECT>.git`.

### One-time global git config

```bash
git config --global init.defaultBranch main
git config --global user.name  "Your Name"
git config --global user.email you@example.org
```

### Push an existing project up

```bash
cd MY_PROJECT
git init
git remote add origin git@garnatxagitlab.uv.es:USER/myproject.git

git add .
git commit -m "First commit"

git branch -m main          # ensure branch is `main` (older git defaults to master)
git push -u origin main
```

Verify:

```bash
git status
# On branch main
# Your branch is up to date with 'origin/main'.
# nothing to commit, working tree clean
```

### Clone from inside Garnatxa

Make sure you added the cluster's `~/.ssh/id_rsa.pub` to GitLab first.

```bash
git clone git@garnatxagitlab.uv.es:USER/myproject.git
```

### Daily git commands

| Command | Purpose |
|---------|---------|
| `git init` | New local repo (run once). |
| `git status` | What's modified / staged / untracked. |
| `git log` | Commit history. `--graph` for branches. `--pretty=oneline` for compact. |
| `git show` | Diff for a commit. |
| `git add .` | Stage changes. |
| `git commit -m '...'` | Snapshot staged changes. |
| `git push -u origin main` | Upload. `-u` only the first time. |
| `git tag -a v1.0 -m '...' <commit>` | Tag a commit. Then `git push origin --tags`. |
| `git checkout <branch>\|<commit>\|<tag>` | Switch the working tree. |
| `git rm <file>` | Remove a tracked file. `--cached` to keep the local copy. |
| `git mv <src> <dst>` | Move/rename a tracked file. |
| `git restore <file>` | Restore a file (deleted or modified). |

### `.gitignore` template for a Garnatxa project

Keep the 10 MB push limit (and the "source code only" rule) by ignoring data
directories from the start:

```gitignore
data/*
data_extra/*
out/*
ref/*
work/                # Nextflow temp dir
.snakemake/          # Snakemake bookkeeping
*.sif                # Singularity images
*.sam
*.bam
*.fq
*.fastq
*.fq.gz
*.fastq.gz
```

## VSCode workflow — develop locally, run on Garnatxa

### The cluster's strong recommendation: don't VSCode-Remote-SSH into Garnatxa

> Using VS Code remotely to Garnatxa is discouraged. Administrators could
> disable the use of VS Code if you fail to comply with the basic rules.

The reasons are real:

- VSCode's **FileWatcher** stats every file in the open workspace continuously,
  which hammers the login node's CPU, memory, and Ceph metadata service.
- Opening `/home/<USER>` as the workspace root is especially bad.
- TypeScript / JavaScript language services and recursive search can stall
  the login node for other users.
- VSCode often leaves **orphan processes** that keep consuming resources
  even after you close the window.

If you *must* connect via Remote-SSH:

- Never open `/home/<USER>` as workspace root — only the specific project
  folder.
- Don't use VSCode as a file explorer or transfer tool.
- Use **SSH connection status (bottom-left) → Close Remote Connection** when
  done, not just the X on the window.

### Option 1: VSCode + Git (simple)

1. Edit locally in VSCode.
2. Commit + push to Garnatxa GitLab.
3. On Garnatxa: `git clone <URL>` once, then `git pull` for every run.

### Option 2 (recommended): VSCode + rsync-on-save + Git for releases

Use Git only for stable releases. For day-to-day iteration, put the project
on a cloud-synced disk and let a VSCode plugin rsync every save to Garnatxa.

Cloud-disk options mentioned in the docs:

- Google Drive / Nextcloud / private NAS.
- **CSIC staff**: [SACO](https://saco.csic.es).
- **UV staff**: [UV virtual disk](https://www.uv.es/uv-teaching/en/teaching-organisation/-teaching-tools/storage/storage.html).

#### Setup

1. Set up passwordless SSH to Garnatxa once: `ssh-copy-id USER@garnatxa.srv.cpd`.
2. Copy the project to your cloud-mounted disk:

   ```bash
   rsync -av --progress USER@garnatxa.srv.cpd:/doc/test /cloudisk
   ```

3. In VSCode: **File → Add folder to workspace** → `/cloudisk/test` → **Add**.
4. **File → Save Workspace As…** → e.g. `test.code-workspace`.
5. Install the **Save and Run** extension. Then replace your workspace file
   contents with:

   ```json
   {
       "folders": [{ "path": "." }],
       "settings": {
           "sync-rsync.sites": [
               {
                   "localPath": "/home/user/cloudisk/test",
                   "remotePath": "USER@garnatxa.srv.cpd:/home/USER"
               }
           ],
           "sync-rsync.onSaveIndividual": true,
           "sync-rsync.autoShowOutput": true,
           "sync-rsync.notification": true,
           "sync-rsync.onSave": true,
           "saveAndRun": {
               "commands": [
                   {
                       "cmd": "rsync -av --progress /home/user/cloudisk/test USER@garnatxa.srv.cpd:/home/USER",
                       "isAsync": true
                   }
               ]
           }
       }
   }
   ```

6. Connect VSCode's Source Control panel to GitLab: **Git icon → Initialize
   Repository** → **⋯ → Remote → Add Remote** → paste your GitLab SSH URL
   (e.g. `git@garnatxagitlab.uv.es:USER/test.git`) → name it `test`.

#### Result

- Edit in VSCode → `Ctrl+S` → instant rsync to Garnatxa.
- Same project syncs from any laptop you log in from (cloud disk does the
  heavy lifting).
- Run the synced code directly on the cluster — no manual transfer.
- When code stabilizes, **Commit & Push** in VSCode → GitLab gets the
  versioned release.
