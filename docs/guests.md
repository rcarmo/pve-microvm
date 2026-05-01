# Supported Guest OS

## Linux distributions

| Image | Size | Pkg mgr | Profile support |
|---|---|---|---|
| `debian:trixie-slim` | 28 MB | apt | full |
| `ubuntu:24.04` | 28 MB | apt | full |
| `alpine:3.21` | 3 MB | apk | full |
| `fedora:41` | 57 MB | dnf | full |
| `rockylinux:9-minimal` | 44 MB | dnf | full |
| `almalinux:9-minimal` | 34 MB | dnf | full |
| `amazonlinux:2023` | 52 MB | dnf | full |
| `oraclelinux:9-slim` | 45 MB | dnf | full |
| `redhat/ubi9-minimal` | 38 MB | microdnf | full |
| `redhat/ubi9-micro` | 6 MB | microdnf | full |
| `photon:5.0` | 15 MB | tdnf | full |
| `mcr.microsoft.com/azurelinux/base/core:3.0` | 30 MB | tdnf | full |

Any OCI image with apt, apk, dnf, microdnf, tdnf, or yum is supported.

## Specialist OS

| System | Type | Command | Boot time | Notes |
|---|---|---|---|---|
| **SmolBSD** | NetBSD | `--image smolbsd` | 31 ms | virtio-mmio, 64 MB RAM |
| **OpenWrt** | Router | `--image openwrt` | ~5 s | q35/BIOS, 13 MB |
| **OPNsense** | Firewall | `--image opnsense` | ~90 s | q35/BIOS, FreeBSD, >= 1 GB |
| **9Front** | Plan 9 | `--image 9front` | ~3 s | q35/BIOS, 239 MB |
| **OSv** | Unikernel | `--image osv` | ~1 s | q35, needs app image |
| **gokrazy** | Go appliance | `--image gokrazy` | — | Prints build instructions |
| **Firecracker** | Any | `qm importdisk` | — | Direct ext4 rootfs import |

## Template profiles

| Profile | Installs | Use case |
|---|---|---|
| `--profile minimal` | Nothing (microvm-init shell) | Fastest boot, scripted workloads |
| `--profile standard` | SSH, cloud-init, guest agent | General use (default) |
| `--profile full` | Standard + Docker CE | Container workloads |

Additional flags: `--no-docker`, `--no-ssh`, `--no-agent`

## Creating templates

```bash
# Linux (from OCI image)
pve-microvm-template --image debian:trixie-slim --vmid 9000
pve-microvm-template --image alpine:3.21 --vmid 9001 --profile minimal

# Specialist OS
pve-microvm-template --image smolbsd --vmid 9002
pve-microvm-template --image openwrt --vmid 9003
pve-microvm-template --image opnsense --vmid 9004

# Template options
pve-microvm-template --image <image> --vmid <id> \
  --name <name> --storage <store> --disk-size <size> \
  --profile <minimal|standard|full> --cores <n> --memory <mb>
```
