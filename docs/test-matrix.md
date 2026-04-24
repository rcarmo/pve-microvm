# Test Matrix

## Linux distributions

| Image | Size | Pkg mgr | Template | Boot (z83ii) | Boot (borg) |
|---|---|---|---|---|---|
| `alpine:3.21` | 3 MB | apk | ✅ | ✅ | — |
| `redhat/ubi9-micro` | 6 MB | microdnf | ✅ | ✅ | — |
| `photon:5.0` | 15 MB | tdnf | ✅ | ✅ | — |
| `debian:trixie-slim` | 28 MB | apt | ✅ | ✅ | — |
| `ubuntu:24.04` | 28 MB | apt | ✅ | ✅ | — |
| `azurelinux/base/core:3.0` | 30 MB | tdnf | ✅ | ✅ | — |
| `almalinux:9-minimal` | 34 MB | dnf | ✅ | ✅ | — |
| `redhat/ubi9-minimal` | 38 MB | microdnf | ✅ | ✅ | — |
| `rockylinux:9-minimal` | 44 MB | dnf | ✅ | ✅ | — |
| `oraclelinux:9-slim` | 45 MB | dnf | ✅ | ✅ | — |
| `amazonlinux:2023` | 52 MB | dnf | ✅ | ✅ | — |
| `fedora:41` | 57 MB | dnf | ✅ | ✅ | — |

## Non-Linux / specialist OS

| Image | Type | Size | Template | Boot (z83ii) | Boot (borg) |
|---|---|---|---|---|---|
| `9front` | Plan 9 | 239 MB | ✅ | ✅ | — |
| `osv` | Unikernel | 2.5 MB | ✅ | ✅ | — |
| `gokrazy` | Go appliance | varies | instructions | — | — |
| Firecracker rootfs | ext4 | varies | `qm importdisk` | ✅ (compat) | — |

## Features

| Feature | z83ii | borg |
|---|---|---|
| `qm create/start/stop/destroy` | ✅ | ✅ (installed) |
| Serial console (`qm terminal`) | ✅ | — |
| PVE web UI (xterm.js) | ✅ | — |
| Cloud-init (hostname, DHCP, SSH keys) | ✅ | — |
| Guest agent | ✅ | — |
| Graceful shutdown | ✅ | — |
| Networking (DHCP) | ✅ | — |
| Linked clones | ✅ | — |
| Disk resize | ✅ | — |
| Snapshots | ✅ | — |
| vzdump backup | ✅ | — |
| vsock (`/dev/vsock`) | ✅ | — |
| virtiofs | code ready | — |
| SSH agent forwarding | code ready | — |
| Template profiles | ✅ | — |
| GUI (panel hiding, clone) | ✅ | — |

## Test hardware

| Node | CPU | RAM | Storage | PVE | QEMU | pve-microvm |
|---|---|---|---|---|---|---|
| z83ii | Atom x5-Z8350 @ 1.44 GHz | 2 GB | LVM-thin | 9.1.7 | 10.1.2 | v0.3.0 |
| borg | i7-12700 @ 4.9 GHz, 20 cores | 128 GB | LVM-thin | 9.1.7 | 10.1.2 | v0.3.0 |

## Legend

- ✅ — tested and confirmed working
- — — not yet tested
- `code ready` — implemented but awaiting hardware test
- `instructions` — prints build steps (requires external toolchain)
- `compat` — compatible format, tested via manual import
