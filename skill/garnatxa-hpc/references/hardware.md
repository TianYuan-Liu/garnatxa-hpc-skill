# Hardware specifications

Garnatxa lives in the I2SysBio Data Center, Burjassot-Paterna (Valencia). The
room is sized for up to 12 racks; currently 6 racks (48 U) plus 6 InRow
cooling units with hot-aisle containment.

## Roles

| Role | Count |
|------|-------|
| Compute nodes | 14 (`cn00-cn13`) — mixed 64/80/128-CPU generations |
| Front-end (login) | 2 (real hostname is `master2`; prompt shows `master`) |
| Interactive nodes | `merlot, subirat` (run the `interactive` partition AND the `tape` partition on `merlot`) |
| Storage management | 3 |
| Service (VPN/LDAP/DHCP/DNS) | 2 |
| Virtualization (VM hosts) | 3 |

## CPUs

| Purpose | Hardware threads |
|---------|------------------|
| Computing (`global` partition) | **1232** |
| Services | ~192 |
| Virtualization | ~288 |

All compute nodes are dual-socket x86_64. The 14 compute nodes are a mix of
80-CPU, 64-CPU, and 128-CPU generations — submitting with `--cpus-per-task=N`
where `N > 80` may force scheduling onto the 128-CPU nodes only.

## Memory

| Pool | Capacity |
|------|----------|
| Computing | **18.3 TB** |
| Services | 4 TB |
| Virtualization | 1.5 TB |

## GPUs

**None.** Garnatxa is a CPU-only cluster. There is no GPU partition, no GPU
node, no GPU-related sbatch flags (`--gres=gpu:...` will not allocate
anything). If the user asks for GPUs, redirect them to another resource — the
docs don't list a Garnatxa GPU option.

## Networking

Cisco Ethernet (Nexus 5696Q + Nexus 2348UPQ). No InfiniBand. Networks are
isolated: storage / compute / management.

| Network | Aggregate bandwidth |
|---------|---------------------|
| Inter-rack uplinks | 40 Gb/s (redundant) |
| Storage network | 50 Gb/s (2 × 25 Gb/s LACP bond) |
| Compute network | 20 Gb/s (2 × 10 GbE LACP bond) |

## Storage

| Item | Value |
|------|-------|
| Filesystem | **Ceph Reef 18.2.1** |
| Storage nodes | 8 JBOD storage cabinets (multipath) |
| Raw capacity | **4.121 PB** (27% NVMe, 73% HDD) |
| Approx. disks | ~332 |
| Metadata (MDS) nodes | 3 |
| Tape library | **IBM TS4300**, 2 drives, 40 LTO-9 slots → **720 TB** online |

## Peak performance

- **20.5 TFLOPS** (HPLinpack 2.3).

## OS / power / cooling

| Item | Value |
|------|-------|
| OS | Rocky Linux 8.10 (Green Obsidian) |
| Job scheduler | SLURM |
| Modules | Lmod |
| UPS | APC Symmetra PX 125 kW (scalable to 500 kW), ~2 h autonomy at high load |
| Cooling | 6 × APC ACRC301S Chilled Water InRow |
| Estimated PUE | 1.49 |
