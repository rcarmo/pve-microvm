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
  --args '-kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw"'
```

**Key points:**
- `--args` with `-kernel` is **required** (no BIOS/UEFI boot)
- `--serial0 socket` enables `qm terminal`
- `--vga serial0` makes PVE web UI open xterm.js serial console

## Using templates (recommended)

The fastest way to get started — create a template once, clone instantly:

```bash
# Create template from debian:trixie-slim (28 MB, same Debian as PVE 9)
# Includes cloud-init drive for SSH key injection
pve-microvm-template

# Clone new VMs in seconds
qm clone 9000 901 --name agent-sandbox-1 --full
qm clone 9000 902 --name agent-sandbox-2 --full

# Set SSH key and other cloud-init options per clone
qm set 901 --sshkeys ~/.ssh/authorized_keys
qm set 901 --ciuser root --ipconfig0 ip=dhcp

# Boot and connect
qm start 901
qm terminal 901
```

The template includes a first-boot setup script (`microvm-setup`) that
automatically installs:
- **cloud-init** — reads PVE cloud-init config drive for SSH keys, hostname, networking
- **qemu-guest-agent** — enables `qm shutdown`, IP reporting, filesystem freeze
- **Docker CE** — full container runtime inside the microvm

First boot takes ~60s for package installation. Subsequent boots are instant.

### Template options

| Flag | Default | Purpose |
|---|---|---|
| `--image` | `debian:trixie-slim` | OCI image reference |
| `--vmid` | `9000` | Template VM ID |
| `--name` | `microvm-trixie` | Template name |
| `--storage` | `local-lvm` | PVE storage backend |
| `--disk-size` | `1G` | Root disk size |
| `--list` | — | List existing microvm templates |
| `--refresh` | — | Re-fetch even if template exists |

## Importing OCI images directly

For one-off VMs without templates:

```bash
pve-oci-import --image <image> --vmid <vmid> --configure
```

Works with Docker Hub, ghcr.io, quay.io, or any OCI registry:

```bash
pve-oci-import --image alpine:latest --vmid 900 --configure
pve-oci-import --image python:3.12-alpine --vmid 901 --configure
pve-oci-import --image ghcr.io/myorg/myapp:v1.2 --vmid 902 --size 4G --configure
```

## Console access

microvm has **no VGA display**. Use the serial console:

```bash
# CLI
qm terminal <vmid>
# Disconnect: Ctrl-O

# Web UI
# Click "Console" on the VM — opens xterm.js serial terminal
# (requires vga: serial0 in config)
```

## Networking

Uses `virtio-net-device` (virtio-mmio). Works identically to standard virtio NICs.

```bash
# Single NIC
qm set 900 --net0 virtio,bridge=vmbr0

# With VLAN tag
qm set 900 --net0 virtio,bridge=vmbr0,tag=100

# Inside the guest
udhcpc -i eth0          # Alpine
dhclient eth0           # Debian
ip addr add 10.0.0.100/24 dev eth0  # Static
```

Proxmox firewall rules on the bridge still apply.

## Guest agent

```bash
qm set 900 --agent 1

# Inside guest (Alpine)
apk add qemu-guest-agent

# Inside guest (Debian)
apt install qemu-guest-agent
```

Enables graceful shutdown, IP reporting, and filesystem freeze.

## Shutdown

microvm has no ACPI, so `qm shutdown` needs the guest agent:

```bash
qm shutdown 900    # Graceful (needs guest agent)
qm stop 900        # Force stop
qm destroy 900     # Remove VM and disks
```
