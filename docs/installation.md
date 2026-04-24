# Installation

## From GitHub Release

Download the latest `.deb` from the [releases page](https://github.com/rcarmo/pve-microvm/releases):

```bash
# Download and install
wget https://github.com/rcarmo/pve-microvm/releases/download/v0.1.4/pve-microvm_0.3.0-1_all.deb
dpkg -i pve-microvm_0.3.0-1_all.deb
apt-get install -f   # resolve any missing dependencies
```

## From source

```bash
git clone https://github.com/rcarmo/pve-microvm.git
cd pve-microvm
dpkg-buildpackage -us -uc -b
dpkg -i ../pve-microvm_*_all.deb
```

## Manual (development)

```bash
make install DESTDIR=/
/usr/share/pve-microvm/pve-microvm-patch apply
```

## Verify

```bash
/usr/share/pve-microvm/pve-microvm-patch status
# Expected: applied (2026-04-18T...)

qm create 999 --machine microvm --memory 128 --name test-microvm
qm destroy 999
```

## Uninstall

```bash
apt remove pve-microvm
```

The `prerm` hook automatically reverts all patches and restores the original
`qemu-server` files from backup. No VMs or data are affected.

## Requirements

| Component | Version | Notes |
|---|---|---|
| **Proxmox VE** | 9.0+ | Debian Trixie based |
| **`qemu-server`** | 9.1.x | Patched by this package |
| **`pve-qemu-kvm`** | 10.x | QEMU with microvm support |
| **Host kernel** | 6.14+ | PVE 9 default |

### Tested nodes

| Node | CPU | RAM | Notes |
|---|---|---|---|
| **z83ii** | Intel Atom x5-Z8350 @ 1.44 GHz | 2 GB | Low-end stability testing |
| **borg** | Intel Core i7-12700 @ 4.9 GHz, 20 cores | 125 GB | Performance reference |

### Dependencies

- `skopeo` — OCI image pulling
- `umoci` — OCI image unpacking
- `qemu-utils` — disk conversion
- KVM — `/dev/kvm` available
