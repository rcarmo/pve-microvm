# Quick Start

## Create from the web UI

1. Click **Create µVM** (⚡ button in the header toolbar)
2. Pick an OCI image from the dropdown (or type any image reference)
3. Choose profile, storage, memory, disk size
4. Click Create — a terminal opens to build the template

## Create from CLI

```bash
# Create a template (one-time)
pve-microvm-template --image debian:trixie-slim --vmid 9000

# Clone and boot
qm clone 9000 901 --name my-sandbox --full
qm set 901 --sshkeys ~/.ssh/authorized_keys
qm start 901
qm terminal 901
```

## Choose storage

`local-lvm` is the default, not an automatic selection. The selected storage
must be enabled on the current node, active and support VM disk images. If it
is disabled or unavailable, select a suitable store explicitly:

```bash
pvesm status
pve-microvm-template --image debian:trixie-slim --storage <image-storage>
```

The tool checks storage before downloading an image or removing a template with
`--refresh`, and again before disk import. It verifies the imported backing
volume and attached disk before converting the VM to a template. Import errors
remain visible. After a failed import, inspect the VM's unused disks before
retrying; the tool preserves that VM for diagnosis and does not guess a volume
name or switch storage pools.

## Template options

| Flag | Default | Purpose |
|---|---|---|
| `--image` | `debian:trixie-slim` | OCI image or specialist OS name |
| `--vmid` | `9000` | Template VM ID |
| `--name` | `microvm-trixie` | Template name |
| `--storage` | `local-lvm` | PVE storage backend |
| `--disk-size` | `2G` | Root disk size |
| `--memory` | `512` | Memory in MB |
| `--cores` | `1` | CPU cores |
| `--bridge` | `vmbr0` | PVE network bridge used by every template path |
| `--profile` | `standard` | `minimal`, `standard`, or `full` |
| `--no-docker` | — | Skip Docker install |
| `--no-ssh` | — | Skip SSH server |
| `--no-agent` | — | Skip guest agent |

## Manual creation

```bash
qm create 900 --machine microvm --memory 256 --cores 1 \
  --name my-microvm --net0 virtio,bridge=vmbr0 \
  --serial0 socket --vga serial0 --agent 1 \
  --args '-kernel /usr/share/pve-microvm/vmlinuz \
    -initrd /usr/share/pve-microvm/initrd \
    -append "console=ttyS0 root=/dev/vda rw quiet"'

pve-oci-import --image alpine:3.21 --vmid 900 --configure
qm start 900
qm terminal 900
```

## Console

```bash
# CLI
qm terminal <vmid>     # Disconnect: Ctrl-O

# Web UI: Console tab auto-selects xterm.js for microvm
```

## Shutdown & cleanup

```bash
qm shutdown 900    # Graceful (guest agent)
qm stop 900        # Force stop
qm destroy 900     # Remove VM + disks
```

## Ephemeral VMs

```bash
pve-microvm-run -- uname -a           # Run and destroy
pve-microvm-run -it --image alpine:3.21   # Interactive
pve-microvm-run --no-net -- echo "isolated"
```

## Network configuration

Templates use **systemd-networkd** directly — no cloud-init required.

**DHCP (default)**: works automatically on all ethernet interfaces.

**Static IP**: write `/etc/microvm-static-net` before (or after) first boot:

```bash
# Via guest agent on a running VM:
qm guest exec <vmid> -- bash -c \
  'echo "ADDRESS=10.0.0.5/24 GATEWAY=10.0.0.1 DNS=1.1.1.1" > /etc/microvm-static-net'
qm reboot <vmid>

# Or set the root password and SSH key at creation:
qm clone 9000 901 --name my-vm --full
qm guest exec 901 -- bash -c 'echo "ADDRESS=..." > /etc/microvm-static-net'
qm start 901
```

The `microvm-static-net.service` runs before networkd and generates the
appropriate `.network` file. No MAC address dependency — survives cloning.

## Next steps

- [Supported Guest OS](guests.md) — all 21 distros and specialist OS
- [Networking & Storage](networking.md) — virtiofs, 9p, vsock, SSH agent
- [Web UI](webui.md) — Create µVM dialog, icons, console
- [High Availability](ha.md) — migration and HA relocate
- [Configuration](configuration.md) — all supported options
