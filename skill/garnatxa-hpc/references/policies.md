# Usage policies

## Who can use Garnatxa

- I2SysBio research groups — **free of charge**.
- External entities (private companies or institutions outside I2SysBio) —
  either by **economic contribution** (initial deposit converted to CPU-hours
  and storage; topped up as needed) or by **equipment purchase** (≥ 64 cores
  and 100 TB of storage; contributor keeps 70% of bought storage and 95% of
  bought CPUs guaranteed; agreement valid for 5 years with 3-year warranty).
- New research groups: open a ticket under topic
  `Cluster GarnatxaHPC / General Support`.
- New user accounts inside an existing group: opened by the **PI (or delegate)**
  under topic `Cluster Garnatxa HPC / New Account Request`. The PI is
  responsible for providing each user's official email and for reporting
  changes; emails are added to the Garnatxa distribution list.

## Account inactivity

Accounts that haven't been used for **more than 1 year** are blocked. The PI
is notified and must request reactivation or deletion.

## Compute fairness

- All CPUs are shared.
- Jobs go through SLURM partitions (`interactive`, `global`) and time-based
  queues (`short`, `medium`, `long`, `long-mem`), plus the special `tape`
  queue.
- The scheduler uses four factors:
  - **Queue type** — shorter-time queues get higher score.
  - **Age** — longer waits raise the score.
  - **Fairshare** — heavy users in the last ~24 h get a lower score so other
    users get a turn.
  - **Job size** — smaller resource requests get a higher score.
- Going over the per-queue or global per-user cap is not "abuse" — your jobs
  just stay queued until resources free up.

### Group-contributed nodes

- Each contributing group gives up **5% of its acquired CPUs** to maintain
  the global filesystem.
- A dedicated queue is configured for the contributed node.
- Non-owner I2SysBio members can use that queue for up to **24 hours** per
  job.
- Owning-group members have **unlimited execution time and priority** on
  that queue.

## Per-user limits (across all QoS)

| Limit | Value |
|-------|-------|
| Max running CPUs | 200 |
| Max running RAM | 1300 GB |
| Max simultaneous running jobs | 1000 |
| Max array size | 5000 |

QoS-specific caps are in `slurm.md`.

## Storage fairness

- Primary storage = Ceph, ~4.1 PB raw. Each group gets `/storage/<GROUP>`
  with per-user subdirs.
- Full capacity is open to everyone while global usage stays under the 80%
  critical mark.
- Above 80%, dynamic quotas kick in automatically — see `storage.md`.
- Quotas reflect each group's voluntary contribution to the storage pool.
- **No backups** — every user is responsible for off-cluster copies of
  anything irreplaceable.
- Old/obsolete data should be moved to tape (`ssh merlot`, `tapecopy`) to
  free up `/storage`. Tapes are bought by groups (~€100 per LTO-9 tape).

## Virtualization (IaaS)

Garnatxa hosts internal VMs for the docs site, ticketing, GitLab, courses,
and web hosting.

- Any I2SysBio group can request a VM and network access through the ticket
  platform.
- Approval depends on requested CPU, memory, disk.
- After approval, CPD staff start the VM and hand over credentials.
- **The requesting group is responsible** for managing and updating the
  virtualized service.

## Acknowledgment in publications

If Garnatxa contributed to a published result (paper, conference, dataset),
include this acknowledgment text:

> The computations/simulations/[OR SIMILAR] were performed on the HPC cluster
> Garnatxa at Institute for Integrative Systems Biology (I2SysBio). I2SysBio
> is a mixed research centre formed by University of Valencia (UV) and Spanish
> National Research Council (CSIC).

And email a copy of the publication to **`i2sysbiohpc@uv.es`**.

The same wording appears verbatim in the Terms of Use page.

## Rates (external groups)

| Service | Units | Public | External |
|---------|-------|--------|----------|
| Computing | 1 h / CPU | 0.07 € | 0.08 € |
| Online storage | 1 TB / day | 0.32 € | 0.35 € |
| Tape storage | 1 TB / day | 0.04 € | 0.05 € |
| Advice & support | 1 h | 47.76 € | 52.31 € |

Notes:

- **Computing**: pay per use, billed monthly in cores × hours. Each core
  delivers two non-shared hyperthreads.
- **Storage**: billed monthly per TB-day of cumulative residency. Disk types
  available: SSD, NVMe, SAS.
- **Tape**: customer pays for tapes themselves; minimum is 1 tape + 1 year's
  rental.
- **Advice & support**: deployment, pipeline optimization, SLURM scripting.

I2SysBio members do not pay any of these.
