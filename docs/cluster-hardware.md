# Cluster Hardware

pve-microvm v0.3.3 is deployed and tested across a 4-node Proxmox VE cluster.

## Nodes

| Node | CPU | Cores | RAM | Storage | Role |
|---|---|---|---|---|---|
| **z83ii** | Intel Atom x5-Z8350 @ 1.44 GHz | 4 | 2 GB | LVM-thin 456 GB, dir 26 GB | Worst-case stability testing |
| **u59** | Intel Celeron N5105 @ 2.00 GHz | 4 | 16 GB | LVM-thin 597 GB, dir 94 GB | Low-mid range validation |
| **tnas** | Intel Core i5-1235U (12th gen) | 12 | 16 GB | ZFS 10.7 TB, dir 795 GB | ZFS storage testing |
| **borg** | Intel Core i7-12700 (12th gen) | 20 | 128 GB | LVM-thin 1.7 TB + 913 GB, dir 94 GB | Performance reference |

## Shared infrastructure

| Component | Details |
|---|---|
| **PVE version** | 9.1.7–9.1.9 (all nodes) |
| **QEMU** | 10.1.2 (all nodes) |
| **Host kernel** | 6.17.13-2-pve (all nodes) |
| **Cluster name** | Home (corosync, 4 votes, quorate) |
| **Shared storage** | CIFS `backup` (5.1 TB on Synology NAS, content: images, backup, ISO, templates) |
| **HA groups** | Intel (z83ii, u59, borg) |

## Storage backends tested

| Backend | Nodes | Notes |
|---|---|---|
| **LVM-thin** | z83ii, u59, borg | Primary microvm storage, supports linked clones |
| **ZFS** | tnas | 10.7 TB pool, supports snapshots natively |
| **dir** | all | Local directory storage |
| **CIFS** | all | Shared NAS, used for HA migration and backups |

## Notes

- **z83ii** is deliberately the primary test node — if microvms boot and run
  well on a 2 GB Atom, they'll work anywhere.
- **borg** serves as the performance reference and migration target.
- **tnas** provides ZFS storage backend testing (the only node with ZFS).
- **u59** validates the mid-range: 4 cores but with 16 GB RAM.
- All nodes share the same CIFS mount for cross-node migration and HA.
- The cluster has been running PVE 9.x since initial release with no
  version skew between nodes.
