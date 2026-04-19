# Usage Guide

## Creating a microvm guest

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

**Key points:**
- `-kernel` + `-initrd` are **required** — the initrd loads virtio modules
- `--serial0 socket` enables `qm terminal`
- `--vga serial0` makes PVE web UI open xterm.js serial console
- `--agent 1` enables the guest agent channel

## Using templates (recommended)

Create a template once, clone instantly:

```bash
# Create template from debian:trixie-slim (28 MB, same Debian as PVE 9)
# Includes cloud-init drive, systemd, networkd, SSH, qemu-guest-agent
pve-microvm-template

# Clone new VMs
qm clone 9000 901 --name agent-sandbox-1 --full
qm clone 9000 902 --name agent-sandbox-2 --full

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
# (requires vga: serial0 in config)
```

## Networking

Uses `virtio-net-pci-non-transitional` with PCIe on microvm.
Works identically to standard virtio NICs.

```bash
qm set 900 --net0 virtio,bridge=vmbr0              # Single NIC
qm set 900 --net0 virtio,bridge=vmbr0,tag=100       # VLAN
```

Inside the guest, configure via cloud-init or manually:
```bash
ip link set eth0 up
dhclient eth0
```

## Guest agent

Enables graceful `qm shutdown`, IP reporting, and filesystem freeze:

```bash
qm set 900 --agent 1
# Agent starts automatically if installed in the template
```

## Shutdown

```bash
qm shutdown 900    # Graceful (needs guest agent)
qm stop 900        # Force stop
qm destroy 900     # Remove VM and disks
```

## Architecture

microvm with PCIe uses `virtio-*-pci-non-transitional` devices:

| Device | Type |
|---|---|
| Block | `virtio-blk-pci-non-transitional` |
| Network | `virtio-net-pci-non-transitional` |
| Serial/Agent | `virtio-serial-pci-non-transitional` |
| Balloon | `virtio-balloon-pci-non-transitional` |
| Console | ISA serial (`isa-serial=on`) |

Boot flow: kernel → initrd (loads virtio modules) → switch_root → systemd

## Sharing host directories (virtiofs)

Mount a host directory into the guest:

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
