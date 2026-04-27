# Networking & Storage Sharing

## Network interfaces

Uses `virtio-net-pci-non-transitional` with PCIe.

```bash
qm set 900 --net0 virtio,bridge=vmbr0              # Single NIC
qm set 900 --net0 virtio,bridge=vmbr0,tag=100       # VLAN
```

DHCP is configured via cloud-init and systemd-networkd (or dhclient fallback).

## Sharing host directories

### virtiofs (high performance, needs daemon)

```bash
# Host: start sharing before VM boot
pve-microvm-share 900 /path/to/workspace

# Start the VM, then inside guest:
mount -t virtiofs shared /mnt/shared

# Stop sharing:
pve-microvm-share 900 --stop
```

### 9p (simpler, no daemon)

```bash
# Host: configure before VM boot
pve-microvm-9p 900 /srv/data mytag

# Start VM, then inside guest:
mount -t 9p mytag /mnt/data -o trans=virtio,version=9p2000.L

# Management:
pve-microvm-9p 900 --list
pve-microvm-9p 900 --remove mytag
pve-microvm-9p 900 --clear
```

### Comparison

| | virtiofs | 9p |
|---|---|---|
| Daemon | virtiofsd required | None (QEMU built-in) |
| Performance | Better for large I/O | Good for most uses |
| Setup | More complex | Simpler |
| Hot-add | No (before boot) | No (before boot) |

## SSH agent forwarding (vsock)

Forward host SSH keys into the guest without exposing them:

```bash
# Host:
pve-microvm-ssh-agent 900

# Guest:
export SSH_AUTH_SOCK=/tmp/ssh-agent.sock
socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork VSOCK-CONNECT:2:2222 &
ssh-add -l              # lists host keys
git clone git@github.com:org/repo.git
```

## vsock communication

Each microvm gets a vsock CID (VMID + 1000). Host and guest communicate
without networking:

```bash
# Host → Guest:
socat - VSOCK-CONNECT:<cid>:<port>

# Guest → Host (CID 2 = host):
socat - VSOCK-CONNECT:2:<port>
```
