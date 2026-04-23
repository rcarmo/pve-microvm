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
installs cloud-init, qemu-guest-agent, Docker CE, and SSH.

### Template options

| Flag | Default | Purpose |
|---|---|---|
| `--image` | `debian:trixie-slim` | OCI image reference |
| `--vmid` | `9000` | Template VM ID |
| `--name` | `microvm-trixie` | Template name |
| `--storage` | `local-lvm` | PVE storage backend |
| `--disk-size` | `2G` | Root disk size |
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

When a VM uses `machine: microvm`:

- **Hardware view**: USB, PCI passthrough, BIOS, EFI, TPM, audio rows are hidden
- **Add hardware menu**: unsupported device types are disabled
- **Machine edit**: vIOMMU and version options are hidden
- **Console button**: opens xterm.js serial terminal (via `vga: serial0`)
- **Resource tree**: microvm-tagged VMs show a ⚡ bolt icon in purple
- **Template context menu**: right-click → "⚡ Clone microvm" for one-click cloning

## Ephemeral VMs

Run a command in a disposable microvm that's destroyed after exit:

```bash
# Run a command
pve-microvm-run -- uname -a

# Interactive shell
pve-microvm-run -it --image alpine:latest

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
pve-microvm-template --image alpine:latest --vmid 9001 --name microvm-alpine
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
| `alpine:latest` | apk | busybox/OpenRC | full |
| `fedora:41` | dnf | systemd | full |
| `rockylinux:9-minimal` | dnf/microdnf | systemd | full |
| `almalinux:9-minimal` | dnf/microdnf | systemd | full |
| `amazonlinux:2023` | dnf | systemd | full |
| `oraclelinux:9-slim` | dnf | systemd | full |
| `redhat/ubi9-minimal` | microdnf | systemd | full |
| `redhat/ubi9-micro` | microdnf | minimal | full |
| `photon:5.0` | tdnf | systemd | full |
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
