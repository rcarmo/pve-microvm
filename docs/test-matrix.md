# Test Matrix

Last updated: 2026-04-24

Tested on a 4-node cluster. This matrix shows the smallest (z83ii) and
largest (borg) nodes. See [Cluster Hardware](cluster-hardware.md) for
all node specs.

## Linux distributions

| Image | Size | Pkg mgr | Template | Boot (z83ii) | Boot (borg) |
|---|---|---|---|---|---|
| `alpine:3.21` | 3 MB | apk | ✅ | ✅ | ✅ |
| `redhat/ubi9-micro` | 6 MB | microdnf | ✅ | ✅ | ✅ |
| `photon:5.0` | 15 MB | tdnf | ✅ | ✅ | ✅ |
| `debian:trixie-slim` | 28 MB | apt | ✅ | ✅ | ✅ |
| `ubuntu:24.04` | 28 MB | apt | ✅ | ✅ | ✅ |
| `azurelinux/base/core:3.0` | 30 MB | tdnf | ✅ | ✅ | ✅ |
| `almalinux:9-minimal` | 34 MB | dnf | ✅ | ✅ | ✅ |
| `redhat/ubi9-minimal` | 38 MB | microdnf | ✅ | ✅ | ✅ |
| `rockylinux:9-minimal` | 44 MB | dnf | ✅ | ✅ | ✅ |
| `oraclelinux:9-slim` | 45 MB | dnf | ✅ | ✅ | ✅ |
| `amazonlinux:2023` | 52 MB | dnf | ✅ | ✅ | ✅ |
| `fedora:41` | 57 MB | dnf | ✅ | ✅ | ✅ |

## Non-Linux / specialist OS

| Image | Type | Size | Template | Boot (z83ii) | Boot (borg) |
|---|---|---|---|---|---|
| `9front` | Plan 9 | 239 MB | ✅ | ✅ | — |
| `osv` | Unikernel | 2.5 MB | ✅ | ✅ | — |
| `gokrazy` | Go appliance | varies | instructions | — | — |
| Firecracker rootfs | ext4 | varies | `qm importdisk` | ✅ (compat) | — |
| `openwrt` | Router OS | 13 MB | ✅ | ✅ | — |
| `opnsense` | Firewall (FreeBSD) | 500 MB | ✅ | — | ✅ |

## Features

| Feature | z83ii | borg |
|---|---|---|
| `qm create/start/stop/destroy` | ✅ | ✅ |
| Serial console (`qm terminal`) | ✅ | ✅ |
| PVE web UI (xterm.js) | ✅ | ✅ |
| Cloud-init (hostname, DHCP, SSH keys) | ✅ | ✅ |
| Guest agent | ✅ | ✅ |
| Graceful shutdown | ✅ | ✅ |
| Networking (DHCP) | ✅ | ✅ |
| Linked clones | ✅ | ✅ |
| Disk resize | ✅ | — |
| Snapshots | ✅ | — |
| vzdump backup | ✅ | — |
| vsock (`/dev/vsock`) | ✅ | — |
| virtiofs | ✅ | — |
| 9p filesystem sharing | ✅ (QEMU args) | — |
| SSH agent forwarding | ✅ | — |
| Template profiles | ✅ | ✅ |
| Offline migration | ✅ z83ii→borg | ✅ borg→z83ii |
| HA (ha-manager) | ✅ | ✅ |
| HA relocate | ✅ | ✅ |
| GUI (panel hiding, clone, icon) | ✅ | ✅ |

## Test hardware (boundary nodes)

| Node | CPU | Cores | RAM | Storage | PVE | QEMU |
|---|---|---|---|---|---|---|
| z83ii | Atom x5-Z8350 @ 1.44 GHz | 4 | 2 GB | LVM-thin 456 GB | 9.1.9 (qemu-server 9.1.8) | 10.1.2 |
| borg | i7-12700 @ 4.9 GHz | 20 | 128 GB | LVM-thin 2.6 TB | 9.1.7 (qemu-server 9.1.6) | 10.1.2 |

Full cluster: 4 nodes (z83ii, u59, tnas, borg) — see [Cluster Hardware](cluster-hardware.md).

## Legend

- ✅ — tested and confirmed working
- — — not yet tested
