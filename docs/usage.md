# Usage Guide

## Creating a microvm guest

### From the web UI

1. Click **Create VM** in Proxmox
2. On the **System** page, select **microvm** as the machine type
3. BIOS, EFI, TPM, and vIOMMU options are automatically hidden
4. Serial console and guest agent are auto-configured
5. Complete the wizard as normal

### From the CLI

```bash
qm create <vmid> \
  --machine microvm \
  --memory <megabytes> \
  --cores <count> \
  --name <name> \
  --net0 virtio,bridge=vmbr0 \
  --serial0 socket \
  --vga serial0 \
  --agent 1 \
  --args '-kernel /usr/share/pve-microvm/vmlinuz -initrd /usr/share/pve-microvm/initrd -append "console=ttyS0 root=/dev/vda rw quiet"'
```

## Using templates (recommended)

Create a template once, clone instantly:

```bash
# Create template from debian:trixie-slim (28 MB, same Debian as PVE 9)
# Includes cloud-init, systemd, networkd, SSH, qemu-guest-agent
pve-microvm-template

# Clone new VMs
qm clone 9000 901 --name agent-sandbox-1 --full
qm clone 9000 902 --name agent-sandbox-2 --full

# Or right-click a microvm template in the web UI → "⚡ Clone microvm"

# Set SSH key and cloud-init options per clone
qm set 901 --sshkeys ~/.ssh/authorized_keys
qm set 901 --ciuser root --ipconfig0 ip=dhcp

# Boot and connect
qm start 901
qm terminal 901
```

The template includes a first-boot setup script (`microvm-setup`) that
installs packages based on the selected profile:
- **minimal**: no services, just `microvm-init` shell
- **standard** (default): cloud-init, SSH, qemu-guest-agent
- **full**: standard + Docker CE

### Template options

| Flag | Default | Purpose |
|---|---|---|
| `--image` | `debian:trixie-slim` | OCI image reference |
| `--vmid` | `9000` | Template VM ID |
| `--name` | `microvm-trixie` | Template name |
| `--storage` | `local-lvm` | PVE storage backend |
| `--disk-size` | `2G` | Root disk size |
| `--memory` | `512` | Memory in MB |
| `--cores` | `1` | CPU cores |
| `--profile` | `standard` | `minimal`, `standard`, or `full` |
| `--no-docker` | — | Skip Docker install (even in full profile) |
| `--no-ssh` | — | Skip SSH server install |
| `--no-agent` | — | Skip guest agent install |
| `--list` | — | List existing microvm templates |
| `--refresh` | — | Re-fetch even if template exists |

## Importing OCI images directly

```bash
pve-oci-import --image <image> --vmid <vmid> --configure
```

Works with Docker Hub, ghcr.io, quay.io, or any OCI registry.

## Console access

microvm has **no VGA display**. Use the serial console:

```bash
# CLI
qm terminal <vmid>
# Disconnect: Ctrl-O

# Web UI: click "Console" — opens xterm.js serial terminal
```

The web UI automatically uses xterm.js when `vga: serial0` is set.

## Networking

Uses `virtio-net-pci-non-transitional` with PCIe on microvm.

```bash
qm set 900 --net0 virtio,bridge=vmbr0              # Single NIC
qm set 900 --net0 virtio,bridge=vmbr0,tag=100       # VLAN
```

DHCP is configured automatically via cloud-init and systemd-networkd.

## Guest agent

Enables graceful `qm shutdown`, IP reporting, and filesystem freeze.
The template configures it automatically with retry on startup.

```bash
qm set 900 --agent 1
```

## Sharing host directories (virtiofs)

Mount a host directory into the guest without networking:

```bash
# On the host: start sharing before VM boot
pve-microvm-share 900 /path/to/workspace

# Start the VM
qm start 900

# Inside the guest:
mkdir -p /mnt/shared
mount -t virtiofs shared /mnt/shared
ls /mnt/shared   # host files visible
```

To stop sharing:
```bash
pve-microvm-share 900 --stop
```

## SSH agent forwarding (via vsock)

Forward your host SSH keys into the guest without exposing them:

```bash
# On the host:
pve-microvm-ssh-agent 900

# Inside the guest:
export SSH_AUTH_SOCK=/tmp/ssh-agent.sock
socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork VSOCK-CONNECT:2:2222 &
ssh-add -l              # lists host keys
git clone git@github.com:org/repo.git  # uses host keys
```

Private keys never enter the guest — only the agent protocol
is forwarded over the vsock channel.

## vsock communication

Each microvm gets a vsock CID (Context ID = VMID + 1000).
Host and guest can communicate without networking:

```bash
# Host → Guest:
socat - VSOCK-CONNECT:<cid>:<port>

# Guest → Host (CID 2 = host):
socat - VSOCK-CONNECT:2:<port>
```

## Shutdown

```bash
qm shutdown 900    # Graceful (via guest agent)
qm stop 900        # Force stop
qm destroy 900     # Remove VM and disks
```

## Web UI features

### Create µVM button

The PVE header toolbar has a **Create µVM** button (⚡ bolt icon) next to
Create VM and Create CT. It opens a dedicated dialog with:
- OCI image selector (12 pre-configured distros + freeform entry)
- Profile picker (minimal / standard / full)
- Storage, memory, cores, disk size fields
- Auto-populated VM ID from the cluster

The same option appears in the node right-click context menu.

### Microvm VM features

When a VM uses `machine: microvm`:

- **Hardware view**: USB, PCI passthrough, BIOS, EFI, TPM, audio rows are hidden
- **Add hardware menu**: unsupported device types are disabled
- **Machine edit**: vIOMMU and version options are hidden
- **Console button**: opens xterm.js serial terminal (via `vga: serial0`)
- **Resource tree**: microvm-tagged VMs show a ⚡ bolt icon in amber
- **Template context menu**: right-click → "⚡ Clone microvm" for one-click cloning

## Ephemeral VMs

Run a command in a disposable microvm that's destroyed after exit:

```bash
# Run a command
pve-microvm-run -- uname -a

# Interactive shell
pve-microvm-run -it --image alpine:3.21

# Without network (sandbox)
pve-microvm-run --no-net -- echo "isolated"

# Custom resources
pve-microvm-run --memory 512 --cores 2 -- make -j2
```

The VM is cloned from a template, started, command executed via the
guest agent, then destroyed automatically.

## Alpine templates

Alpine Linux works out of the box:

```bash
pve-microvm-template --image alpine:3.21 --vmid 9001 --name microvm-alpine
```

Alpine templates use busybox init + inittab (no systemd). The chroot
step installs `openssh`, `qemu-guest-agent`, `dhclient`, and `socat`
via `apk`.

## Benchmarking

Measure boot time and resource overhead:

```bash
pve-microvm-bench
```

Outputs: boot time to serial socket, boot time to shell prompt,
host memory usage, QEMU RSS, kernel/initrd sizes.

## 9Front / Plan 9 templates

Boot Plan 9 (9Front) as a microvm guest:

```bash
pve-microvm-template --image 9front --vmid 9002 --name microvm-9front
qm clone 9002 950 --name my-9front --full
qm start 950
qm terminal 950
```

Note: 9Front uses q35 machine type (boots from disk via BIOS, not `-kernel`).
At the boot prompt, serial console is enabled automatically.

9Front provides:
- ~3 MB kernel, sub-second boot
- Native 9P file sharing
- Different security model (per-process namespaces)
- `rc` shell, `mk` build tool, `sam`/`acme` editors

> **⚠️ Experimental.** 9Front support is a proof-of-concept for running
> non-Linux guests as microvms. It demonstrates that pve-microvm can host
> alternative operating systems beyond Linux — a stepping stone toward
> supporting specialist microkernels used in telco (e.g., PikeOS, QNX),
> real-time systems (e.g., Zephyr, seL4), and research OS platforms.

## Supported distributions

| Image | Package manager | Init | Profile support |
|---|---|---|---|
| `debian:trixie-slim` | apt | systemd | full |
| `ubuntu:24.04` | apt | systemd | full |
| `alpine:3.21` | apk | busybox/OpenRC | full |
| `fedora:41` | dnf | systemd | full |
| `rockylinux:9-minimal` | dnf/microdnf | systemd | full |
| `almalinux:9-minimal` | dnf/microdnf | systemd | full |
| `amazonlinux:2023` | dnf | systemd | full |
| `oraclelinux:9-slim` | dnf | systemd | full |
| `redhat/ubi9-minimal` | microdnf | systemd | full |
| `redhat/ubi9-micro` | microdnf | minimal | full |
| `photon:5.0` | tdnf | systemd | full |
| `mcr.microsoft.com/azurelinux/base/core:3.0` | tdnf | minimal | full |
| `9front` | n/a | Plan 9 | boot only |

Any OCI image from Docker Hub, ghcr.io, or other registries can be used.
The template tool auto-detects the package manager (`apt`, `apk`, `dnf`/`yum`)
and installs the appropriate packages.

## Unikernels and specialist OS

### OSv

OSv is a unikernel that runs a single application per VM with minimal overhead:

```bash
pve-microvm-template --image osv --vmid 9003 --name microvm-osv
```

Downloads the OSv loader (2.5 MB) and creates a template. Use OSv's
`capstan` or `ops` tools to build application images, then import as
disks for cloned VMs.

### gokrazy

gokrazy turns Go programs into appliance images. QEMU x86_64 is supported:

```bash
pve-microvm-template --image gokrazy --vmid 9004
# Prints instructions for building with gok CLI
```

### Other supported specialist OS

| System | Type | Template command | Notes |
|---|---|---|---|
| 9Front | Plan 9 OS | `--image 9front` | Pre-built qcow2, q35 boot |
| OSv | Unikernel | `--image osv` | ELF kernel, needs app image |
| gokrazy | Go appliance | `--image gokrazy` | Instructions only, needs `gok` |
| OpenWrt | Router OS | `--image openwrt` | x86-64 combined image, q35 boot |
| OPNsense | Firewall (FreeBSD) | `--image opnsense` | Serial image, q35 boot, >= 1 GB RAM |

## High Availability

Microvms support HA via offline migration on shared storage. Live migration
is not supported (QEMU microvm machine type limitation).

### Requirements

- Shared storage with `content images` (CIFS, NFS, etc.)
- VM disks on the shared storage
- pve-microvm installed on all target nodes

### Setup

```bash
# Create VM on shared storage
pve-microvm-template --image alpine:3.21 --vmid 9010 --storage backup

# Clone and add to HA
qm clone 9010 9011 --name ha-vm --full
ha-manager add vm:9011 --group Intel --state started

# Relocate to another node (stops, migrates, restarts)
ha-manager relocate vm:9011 borg
```

### Tested flow

| Step | Result |
|---|---|
| Create on z83ii (shared CIFS) | ✅ |
| Offline migrate z83ii → borg | ✅ (2 seconds) |
| Start on borg | ✅ |
| HA add + started | ✅ |
| HA relocate borg → z83ii | ✅ |
| VM running after relocate | ✅ |

> **Note**: Live migration (`--online`) is not supported for the microvm
> machine type. HA relocate performs a stop-migrate-start cycle automatically.

## 9p filesystem sharing

9p is a simpler alternative to virtiofs — no daemon required. QEMU handles
the filesystem export natively.

### Setup

```bash
# Add a 9p share (VM must be stopped)
pve-microvm-9p 900 /srv/data mydata

# Start the VM
qm start 900

# Inside the guest
mount -t 9p mydata /mnt/mydata -o trans=virtio,version=9p2000.L
```

### Management

```bash
pve-microvm-9p 900 --list              # list shares
pve-microvm-9p 900 --remove mydata     # remove a share
pve-microvm-9p 900 --clear             # remove all shares
```

### 9p vs virtiofs

| | 9p (`pve-microvm-9p`) | virtiofs (`pve-microvm-share`) |
|---|---|---|
| Daemon | None (QEMU built-in) | virtiofsd required |
| Setup | Simpler | More complex |
| Performance | Good for most use cases | Better for large file I/O |
| Hot-add | No (configure before boot) | No (configure before boot) |
| Guest support | Needs `CONFIG_9P_FS` | Needs `CONFIG_FUSE` |

> **Note**: 9p requires the microvm kernel to include `CONFIG_9P_FS=y`.
> This is included in the kernel overlay config but requires a kernel
> rebuild to take effect. The next release kernel will include 9p support.

## OpenWrt templates

OpenWrt runs as a q35 guest (boots from disk via BIOS, not microvm):

```bash
pve-microvm-template --image openwrt --vmid 9005 --name microvm-openwrt
```

Downloads the OpenWrt x86-64 combined image (~13 MB compressed) and creates
a template. Boots with its own kernel, serial console active by default.

OpenWrt features:
- ~120 MB disk image, boots in ~5 seconds
- Full firewall/routing stack (nftables, dnsmasq, opkg)
- LuCI web interface (if network configured)
- Serial console on ttyS0

> **Note**: Uses q35 machine type (BIOS boot), not microvm.

## OPNsense templates

OPNsense (FreeBSD-based) runs as a q35 guest:

```bash
pve-microvm-template --image opnsense --vmid 9006 --name microvm-opnsense
```

Downloads the OPNsense serial image (~500 MB compressed) and creates
a template. Needs at least 1 GB RAM.

OPNsense features:
- Full firewall/router OS (pf, Suricata, HAProxy, WireGuard)
- Web UI on HTTPS
- SSH enabled by default
- Serial console on ttyu0

> **Note**: Uses q35 machine type. FreeBSD-based — not Linux.
> Default credentials: root / opnsense
