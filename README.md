# pve-microvm

A Debian package that adds QEMU `microvm` machine type support to Proxmox VE.

microvm guests boot in under 200 ms, use virtio-mmio devices instead of PCI,
and provide full KVM hardware isolation with a minimal attack surface — all
managed through the standard `qm` CLI and (in future releases) the Proxmox web UI.

---

## Table of contents

- [Why microvm](#why-microvm)
- [Prior art](#prior-art)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Usage guide](#usage-guide)
  - [Creating a microvm guest](#creating-a-microvm-guest)
  - [Importing OCI images](#importing-oci-images)
  - [Console access](#console-access)
  - [Networking](#networking)
  - [Guest agent](#guest-agent)
  - [Shutdown and lifecycle](#shutdown-and-lifecycle)
- [Configuration reference](#configuration-reference)
- [Architecture](#architecture)
- [Patch management](#patch-management)
- [Kernel guide](#kernel-guide)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Development](#development)
- [References](#references)
- [License](#license)

---

## Why microvm

QEMU ships a `microvm` machine type on every Proxmox node. It is a minimal
virtual machine model inspired by Firecracker:

| Property | Standard VM (`pc`/`q35`) | `microvm` |
|---|---|---|
| Boot time | 2–10 s | < 200 ms |
| BIOS/UEFI | SeaBIOS or OVMF | None (direct kernel boot) |
| PCI bus | Full PCI/PCIe topology | None |
| Device model | PCI-attached virtio | virtio-mmio |
| ACPI | Full ACPI tables | None |
| VGA/display | VGA, QXL, virtio-gpu | None (serial only) |
| USB | UHCI/EHCI/xHCI | None |
| Attack surface | Broad | Minimal |
| KVM isolation | Full hardware VM | Full hardware VM |

microvm is ideal for:

- **Sandboxing untrusted code** with hardware isolation
- **Ephemeral build/CI runners** that start and stop in milliseconds
- **Edge workloads** where memory and boot time matter
- **Running OCI container images** with VM-level isolation
- **Per-request or per-task VMs** in automation pipelines

Proxmox does not support the `microvm` machine type out of the box.
`qemu-server` explicitly blocks it in its machine type validation regex.
This package removes that limitation.

---

## Prior art

As of April 2026, **nobody has done this before**:

- No Proxmox patches, PRs, or mailing list threads for `microvm`
- No Debian packages that add the `microvm` guest type to PVE
- No GitHub repositories implementing this integration
- Ubuntu ships `qemu-system-x86-microvm` (a stripped QEMU build) but that is
  not a Proxmox integration
- `linuxdevel/firecracker-farm` provides shell scripts for Firecracker on
  Proxmox hosts, but it runs alongside PVE rather than integrating as a guest type

---

## Requirements

- **Proxmox VE 8.x** (Debian Bookworm based)
- **`qemu-server` ≥ 9.0** (ships with PVE 8)
- **`pve-qemu-kvm` ≥ 9.0** (the PVE-patched QEMU, which includes microvm)
- **KVM support** (`/dev/kvm` available on the host)
- **`skopeo`** — for pulling OCI images (used by `pve-oci-import`)
- **`umoci`** — for unpacking OCI images to a rootfs
- **`qemu-utils`** — for `qemu-img` (disk conversion)
- **A microvm-compatible Linux kernel** — see [Kernel guide](#kernel-guide)

---

## Installation

### From .deb package

```bash
# Build the package (on a build host with debhelper)
cd pve-microvm
dpkg-buildpackage -us -uc -b

# Install on your Proxmox node
dpkg -i ../pve-microvm_0.1.0-1_all.deb
apt-get install -f   # resolve any missing dependencies
```

### Manual installation (development)

```bash
# Copy files
make install DESTDIR=/

# Apply patches manually
/usr/share/pve-microvm/pve-microvm-patch apply
```

### Verify installation

```bash
# Check patch status
/usr/share/pve-microvm/pve-microvm-patch status
# Expected output: applied (2026-04-18T13:00:00+00:00)

# Verify microvm is accepted as a machine type
qm create 999 --machine microvm --memory 128 --name test-microvm
qm destroy 999
```

### Uninstallation

```bash
# Via dpkg (automatically reverts patches)
apt remove pve-microvm

# Or manually
/usr/share/pve-microvm/pve-microvm-patch revert
```

The `prerm` hook restores the original `qemu-server` files from backup.
No data or existing VMs are affected.

---

## Quick start

```bash
# 1. Create a microvm guest
qm create 900 --machine microvm --memory 256 --cores 1 \
  --name my-microvm \
  --net0 virtio,bridge=vmbr0

# 2. Import an OCI image as the root disk
pve-oci-import --image alpine:latest --vmid 900 --configure

# 3. Start and connect
qm start 900
qm terminal 900

# 4. Inside the guest
/ # uname -a
Linux microvm 6.x.x ...
/ # ip addr
...
/ # exit

# 5. Stop and clean up
qm stop 900
qm destroy 900
```

---

## Usage guide

### Creating a microvm guest

microvm guests are created with `qm create` using `--machine microvm`:

```bash
qm create <vmid> \
  --machine microvm \
  --memory <megabytes> \
  --cores <count> \
  --name <name> \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 <storage>:<size_gb> \
  --args '-kernel /path/to/vmlinuz -append "console=ttyS0 root=/dev/vda rw"'
```

The `--args` parameter is **required** and must include at least `-kernel`.
microvm does not use BIOS or UEFI — the kernel is loaded directly by QEMU.

#### Minimal example (raw disk, no OCI)

```bash
# Create a 2GB raw disk image with an Alpine rootfs
qm create 900 --machine microvm --memory 256 --cores 1 \
  --name alpine-microvm \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:2 \
  --args '-kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw quiet"'
```

#### With initrd

```bash
qm create 901 --machine microvm --memory 512 --cores 2 \
  --name ubuntu-microvm \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:4 \
  --args '-kernel /boot/vmlinuz-microvm -initrd /boot/initrd-microvm.img -append "console=ttyS0 root=/dev/vda rw"'
```

### Importing OCI images

`pve-oci-import` converts any OCI container image into a bootable microvm disk:

```bash
pve-oci-import --image <image> --vmid <vmid> [options]
```

#### Options

| Flag | Default | Description |
|---|---|---|
| `--image IMAGE` | *(required)* | OCI image reference (e.g. `alpine:latest`) |
| `--vmid VMID` | *(required)* | Proxmox VM ID |
| `--storage STORE` | `local-lvm` | PVE storage target |
| `--size SIZE` | `2G` | Disk image size |
| `--kernel PATH` | `/usr/share/pve-microvm/vmlinuz` | Kernel for boot |
| `--init CMD` | auto-detect | Override init command in guest |
| `--configure` | off | Also set VM machine type and kernel args |

#### Examples

```bash
# Alpine Linux — smallest, fastest boot
pve-oci-import --image alpine:latest --vmid 900 --configure

# Ubuntu 22.04 with a larger disk
pve-oci-import --image ubuntu:22.04 --vmid 901 --size 4G --configure

# Python runtime
pve-oci-import --image python:3.12-alpine --vmid 902 --configure

# Node.js runtime
pve-oci-import --image node:20-alpine --vmid 903 --configure

# Custom registry image
pve-oci-import --image ghcr.io/myorg/myapp:v1.2 --vmid 904 --storage ceph-pool --configure
```

#### What it does

1. **Pulls** the OCI image via `skopeo` (supports Docker Hub, ghcr.io, quay.io,
   and any OCI registry)
2. **Unpacks** the image layers to a rootfs via `umoci`
3. **Prepares** the rootfs for VM boot:
   - creates `/proc`, `/sys`, `/dev`, `/run`, `/tmp` mount points
   - generates a minimal `/etc/inittab` (for busybox-based images like Alpine)
   - creates a fallback `/sbin/microvm-init` if no init system exists
   - sets a default `/etc/resolv.conf`
4. **Creates** a raw ext4 disk image populated with the rootfs
5. **Converts** to qcow2 for storage efficiency
6. **Imports** into PVE storage via `qm importdisk`
7. **Configures** the VM (if `--configure` is passed)

### Console access

microvm guests have **no VGA display**. All interaction is via serial console:

```bash
# Connect to the serial console
qm terminal <vmid>

# Disconnect: press Ctrl-O (not Ctrl-C)
```

The serial console is exposed as a Unix socket at
`/var/run/qemu-server/<vmid>.serial0`.

You can also configure a serial port in the guest config:

```
serial0: socket
```

### Networking

microvm uses `virtio-net-device` (virtio-mmio) instead of PCI-attached virtio-net.
From the guest's perspective, the network interface appears as `eth0` (or similar)
and works identically to a standard virtio NIC.

```bash
# Single NIC on vmbr0
qm set 900 --net0 virtio,bridge=vmbr0

# With a specific MAC address
qm set 900 --net0 virtio,bridge=vmbr0,macaddr=BC:24:11:00:00:01

# VLAN tagged
qm set 900 --net0 virtio,bridge=vmbr0,tag=100

# Multiple NICs (up to 6)
qm set 900 --net0 virtio,bridge=vmbr0
qm set 900 --net1 virtio,bridge=vmbr1
```

**Inside the guest**, configure networking as usual:

```bash
# DHCP (if your bridge has a DHCP server)
udhcpc -i eth0

# Static IP
ip addr add 10.0.0.100/24 dev eth0
ip route add default via 10.0.0.1
```

**Firewall**: Proxmox firewall rules on the bridge still apply to microvm
guests. The tap device (`tap<vmid>i<n>`) is created by the standard PVE
bridge scripts.

### Guest agent

The QEMU guest agent can be used with microvm for:

- Filesystem freeze/thaw (for consistent backups)
- IP address reporting
- Graceful shutdown

```bash
# Enable guest agent
qm set 900 --agent 1

# Inside the guest, install and start qemu-ga
apk add qemu-guest-agent    # Alpine
systemctl start qemu-guest-agent  # systemd-based
```

The agent communicates over a `virtio-serial-device` (virtio-mmio) channel.
The host socket is at the standard PVE path for guest agent sockets.

### Shutdown and lifecycle

microvm has **no ACPI**, so the standard `qm shutdown` (which sends an ACPI
power button event) will not work unless the guest agent is installed.

```bash
# Preferred: graceful shutdown via guest agent
qm shutdown 900

# Force stop (immediate, like pulling the power cord)
qm stop 900

# Via QMP directly
qm monitor 900 <<< 'quit'

# Destroy (removes config and disks)
qm destroy 900
```

**With guest agent enabled**, `qm shutdown` sends a shutdown command through the
agent channel, which is the cleanest approach.

**Without guest agent**, use `qm stop` (hard stop) or arrange for the guest
to shut itself down (e.g., via a command sent over serial or SSH).

---

## Configuration reference

### Supported `qm` options

| Option | Supported | Notes |
|---|---|---|
| `machine` | ✅ | Must be `microvm` |
| `memory` | ✅ | Static allocation (MiB) |
| `cores` | ✅ | Number of vCPUs per socket |
| `sockets` | ✅ | Number of CPU sockets |
| `vcpus` | ✅ | Visible vCPUs (hotplug not supported) |
| `cpu` | ✅ | CPU model (default: `host` with KVM) |
| `name` | ✅ | Guest name |
| `onboot` | ✅ | Start on host boot |
| `startup` | ✅ | Startup/shutdown order |
| `args` | ✅ **required** | Must include `-kernel`; optionally `-initrd`, `-append` |
| `kvm` | ✅ | Hardware virtualization (default: on) |
| `agent` | ✅ | Guest agent support |
| `affinity` | ✅ | CPU affinity (taskset) |
| `net0`–`net5` | ✅ | virtio only; bridge, MAC, VLAN tag |
| `scsi0`–`scsi30` | ✅ | Block devices via virtio-blk-device (mmio) |
| `ide0`–`ide3` | ✅ | Mapped to virtio-blk-device |
| `virtio0`–`virtio15` | ✅ | Mapped to virtio-blk-device |
| `serial0` | ✅ | Serial console socket |
| `protection` | ✅ | Prevent accidental removal |
| `description` | ✅ | Metadata |
| `tags` | ✅ | Metadata |

### Unsupported options (will error)

| Option | Reason |
|---|---|
| `bios` | No BIOS/UEFI — direct kernel boot only |
| `efidisk0` | No UEFI |
| `vga` | No display hardware |
| `tablet` | No USB bus |
| `audio0` | No audio hardware |
| `usb0`–`usb9` | No USB bus |
| `hostpci0`–`hostpci3` | No PCI bus |
| `tpmstate0` | No TPM |
| `vmgenid` | No ACPI |
| `rng0` | No PCI bus for virtio-rng-pci |
| `parallel0`–`parallel2` | No ISA parallel port in microvm mode |

### Example VM config file

`/etc/pve/qemu-server/900.conf`:

```ini
machine: microvm
name: alpine-sandbox
memory: 256
cores: 2
sockets: 1
kvm: 1
agent: 1
net0: virtio=BC:24:11:00:00:01,bridge=vmbr0
scsi0: local-lvm:vm-900-disk-0,size=2G
args: -kernel /usr/share/pve-microvm/vmlinuz -append "console=ttyS0 root=/dev/vda rw quiet"
```

---

## Architecture

### How it works

pve-microvm modifies two files in `qemu-server` and adds one new Perl module:

```
┌─────────────────────────────────────────────┐
│  qm create 900 --machine microvm ...        │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  PVE::QemuServer::Machine  (Machine.pm)     │
│  ─ regex now accepts 'microvm'              │
│  ─ machine_base_type() returns 'microvm'    │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  PVE::QemuServer  (QemuServer.pm)           │
│  ─ config_to_command() checks is_microvm()  │
│  ─ if true, delegates to MicroVM module     │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  PVE::QemuServer::MicroVM  (MicroVM.pm)     │  ← NEW
│  ─ validates config (rejects unsupported)   │
│  ─ generates stripped-down QEMU command:    │
│    · -M microvm,x-option-roms=off,...       │
│    · -device virtio-blk-device (mmio)       │
│    · -device virtio-net-device (mmio)       │
│    · -serial chardev:serial0                │
│    · -kernel ... -append ...                │
│    · no PCI, no VGA, no ACPI, no USB        │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  /usr/bin/qemu-system-x86_64 -M microvm ... │
│  (standard PVE QEMU binary)                 │
└─────────────────────────────────────────────┘
```

### Files modified

| File | Change |
|---|---|
| `/usr/share/perl5/PVE/QemuServer/Machine.pm` | Regex + base type + flags |
| `/usr/share/perl5/PVE/QemuServer.pm` | `use` statement + delegation in `config_to_command` |
| `/usr/share/perl5/PVE/QemuServer/MicroVM.pm` | New file (installed, not patched) |

### QEMU command line generated

For a minimal microvm guest, the generated QEMU command looks like:

```bash
/usr/bin/qemu-system-x86_64 \
  -id 900 \
  -name alpine-sandbox,debug-threads=on \
  -M microvm,x-option-roms=off,pit=off,pic=off,isa-serial=on,rtc=on \
  -no-shutdown -nodefaults -no-user-config -nographic \
  -enable-kvm \
  -chardev socket,id=qmp,path=/var/run/qemu-server/900.qmp,server=on,wait=off \
  -mon chardev=qmp,mode=control \
  -pidfile /var/run/qemu-server/900.pid \
  -daemonize \
  -smp 2,sockets=1,cores=2,maxcpus=2 \
  -cpu host \
  -m 256M \
  -chardev socket,id=serial0,path=/var/run/qemu-server/900.serial0,server=on,wait=off \
  -serial chardev:serial0 \
  -drive file=/dev/pve/vm-900-disk-0,id=drive-scsi0,if=none,format=raw,cache=none,detect-zeroes=on,aio=io_uring \
  -device virtio-blk-device,drive=drive-scsi0 \
  -netdev tap,id=netdev0,ifname=tap900i0,script=/var/lib/qemu-server/pve-bridge,downscript=/var/lib/qemu-server/pve-bridgedown \
  -device virtio-net-device,netdev=netdev0,mac=BC:24:11:00:00:01 \
  -kernel /usr/share/pve-microvm/vmlinuz \
  -append "console=ttyS0 root=/dev/vda rw quiet"
```

### Key differences from standard VM command line

| Feature | Standard VM | microvm |
|---|---|---|
| Machine | `-M pc-i440fx-9.0+pve1` | `-M microvm,x-option-roms=off,pit=off,pic=off,isa-serial=on,rtc=on` |
| Boot | SeaBIOS/OVMF from disk | `-kernel` + `-append` (direct) |
| Block devices | `virtio-blk-pci` | `virtio-blk-device` (mmio) |
| Network | `virtio-net-pci` | `virtio-net-device` (mmio) |
| Display | `-vnc unix:...` | `-nographic` |
| ACPI | enabled | absent |
| SMBIOS | `-smbios type=1,...` | absent |
| USB | EHCI/xHCI controllers | absent |
| Boot splash | `-boot menu=on,...` | absent |
| PCI bridges | dynamically allocated | absent |
| Serial | `isa-serial` on ISA bus | `-serial chardev:serial0` |
| Guest agent | `virtio-serial` (PCI) | `virtio-serial-device` (mmio) |

---

## Patch management

### How patches are applied

The `pve-microvm-patch` tool performs targeted Perl-based text transformations
on the installed `qemu-server` files. It is **not** a blind `patch(1)` — it
uses pattern matching to locate the exact code points.

```bash
# Check current status
/usr/share/pve-microvm/pve-microvm-patch status

# Apply patches (done automatically on package install)
/usr/share/pve-microvm/pve-microvm-patch apply

# Revert patches (done automatically on package removal)
/usr/share/pve-microvm/pve-microvm-patch revert
```

### Safety

- **Backup before patch**: originals are saved to `/usr/share/pve-microvm/backup/`
- **Idempotent**: applying twice is safe (checks a stamp file)
- **Clean revert**: restoring the backup returns files to their exact original state
- **No data loss**: no VM configs, disks, or PVE state is touched
- **Stamp file**: `/usr/share/pve-microvm/.applied` records when patches were applied

### After `qemu-server` upgrades

When Proxmox upgrades `qemu-server`, the patched files may be overwritten.
To re-apply:

```bash
# Check if patches are still applied
/usr/share/pve-microvm/pve-microvm-patch status

# If "not applied", re-apply
/usr/share/pve-microvm/pve-microvm-patch revert   # clear stale stamp if needed
/usr/share/pve-microvm/pve-microvm-patch apply
```

A future version may include a dpkg trigger to detect `qemu-server` upgrades
and re-apply automatically.

---

## Kernel guide

microvm boots via direct kernel loading (`-kernel`), so you need a Linux
kernel binary (`vmlinuz`) that:

1. Has virtio-mmio support compiled in (not as a module)
2. Has ext4 (or your rootfs filesystem) compiled in
3. Has basic networking drivers compiled in

### Option 1: Use the host kernel

The simplest approach — use the Proxmox node's own kernel:

```bash
qm set 900 --args '-kernel /boot/vmlinuz-$(uname -r) -append "console=ttyS0 root=/dev/vda rw"'
```

This works but the host kernel is large and includes many drivers the microvm
doesn't need. Boot will be slower than with a minimal kernel.

### Option 2: Build a minimal microvm kernel

For fastest boot times, build a stripped-down kernel:

```bash
# Start from a minimal config
make tinyconfig

# Enable required features
scripts/config --enable CONFIG_VIRTIO_MMIO
scripts/config --enable CONFIG_VIRTIO_BLK
scripts/config --enable CONFIG_VIRTIO_NET
scripts/config --enable CONFIG_VIRTIO_CONSOLE
scripts/config --enable CONFIG_HW_RANDOM_VIRTIO
scripts/config --enable CONFIG_EXT4_FS
scripts/config --enable CONFIG_SERIAL_8250
scripts/config --enable CONFIG_SERIAL_8250_CONSOLE
scripts/config --enable CONFIG_NET
scripts/config --enable CONFIG_INET
scripts/config --enable CONFIG_NETDEVICES
scripts/config --enable CONFIG_NET_CORE
scripts/config --enable CONFIG_DEVTMPFS
scripts/config --enable CONFIG_DEVTMPFS_MOUNT
scripts/config --enable CONFIG_TMPFS
scripts/config --enable CONFIG_PROC_FS
scripts/config --enable CONFIG_SYSFS
scripts/config --enable CONFIG_PRINTK
scripts/config --enable CONFIG_BLK_DEV
scripts/config --enable CONFIG_TTY
scripts/config --enable CONFIG_UNIX
scripts/config --enable CONFIG_BINFMT_ELF
scripts/config --enable CONFIG_BINFMT_SCRIPT

# Build
make -j$(nproc) vmlinux
# or for compressed:
make -j$(nproc) bzImage
```

A minimal microvm kernel can be under 5 MB and boot in ~50 ms.

### Option 3: Use a Firecracker-compatible kernel

The [Firecracker project](https://github.com/firecracker-microvm/firecracker/blob/main/resources/guest_configs/)
maintains minimal kernel configs that work well with microvm since the machine
model is similar. Download their config and build against the desired kernel
version.

### Option 4: Use the Alpine Linux `virt` kernel

Alpine's `linux-virt` package provides a small kernel with virtio support:

```bash
# Inside an Alpine VM or container
apk add linux-virt
ls /boot/vmlinuz-virt
```

Copy the resulting `vmlinuz-virt` to your Proxmox node.

### Recommended kernel command line

```
console=ttyS0 root=/dev/vda rw quiet panic=1
```

| Parameter | Purpose |
|---|---|
| `console=ttyS0` | Direct output to serial (only console on microvm) |
| `root=/dev/vda` | Root filesystem on the first virtio-blk disk |
| `rw` | Mount root read-write |
| `quiet` | Suppress kernel boot messages (faster perceived boot) |
| `panic=1` | Reboot after 1 second on kernel panic |

---

## Limitations

### No display

microvm has no VGA, QXL, or virtio-gpu. There is no VNC/noVNC/SPICE console
in the Proxmox web UI. All interaction is via serial console (`qm terminal`)
or SSH (once the guest has networking).

### No PCI bus

There is no PCI topology at all. This means:

- No PCI passthrough (`hostpci0`, etc.)
- No PCI-attached devices
- All devices use virtio-mmio

The maximum number of virtio-mmio devices is limited by QEMU (typically 8–32
depending on the QEMU version and microvm configuration).

### No ACPI

- `qm shutdown` requires the guest agent to work
- No ACPI power button
- No S3/S4 sleep states
- The host can force-stop via `qm stop` (sends SIGTERM to QEMU)

### No USB

No USB controllers of any kind. USB passthrough is not possible.

### No UEFI / Secure Boot

microvm uses direct kernel boot. There is no firmware, no EFI variables,
no Secure Boot chain.

### Boot requires a kernel

Unlike standard VMs that boot from disk via BIOS/UEFI, microvm **always**
requires `-kernel` to be specified. The kernel must be accessible on the
Proxmox host filesystem.

### CD-ROM / ISO boot not supported

microvm cannot boot from ISO images. Use `pve-oci-import` or prepare disk
images directly.

### Migration untested

Live migration of microvm guests has not been tested. The reduced device model
may simplify migration state, but this is unverified.

### Backup (vzdump)

vzdump behavior with microvm guests has not been validated. Filesystem-level
backup via the guest agent (fsfreeze) should work if the agent is installed.
Snapshot-based backup may need testing.

### Limited to 6 NICs

The current implementation supports up to 6 network interfaces per microvm
guest. This can be increased in `MicroVM.pm` if needed.

---

## Troubleshooting

### "option 'X' is not supported with microvm machine type"

You have set a configuration option that microvm does not support. Remove it:

```bash
qm set <vmid> --delete <option>
```

Common ones: `vga`, `bios`, `efidisk0`, `usb0`, `hostpci0`.

### "microvm requires a kernel"

You must specify a kernel via `--args`:

```bash
qm set <vmid> --args '-kernel /boot/vmlinuz-$(uname -r) -append "console=ttyS0 root=/dev/vda rw"'
```

### VM starts but no console output

1. Verify the kernel command line includes `console=ttyS0`
2. Verify the kernel has serial console support compiled in
3. Connect via `qm terminal <vmid>` (not the noVNC console)
4. Try pressing Enter — the shell may be waiting for input

### VM starts but kernel panics

1. Check that the root device path is correct (`root=/dev/vda`)
2. Check that the rootfs filesystem (ext4) is compiled into the kernel
3. Check that virtio-mmio is compiled in (not as a module)
4. Try adding `rdinit=/bin/sh` to the kernel command line to get a shell
   before init

### Network not working in guest

1. Verify the bridge exists on the host: `brctl show`
2. Check that the tap device was created: `ip link show tap<vmid>i0`
3. Inside the guest, check `ip link` — the interface may need manual
   configuration or DHCP
4. Try `udhcpc -i eth0` (Alpine) or `dhclient eth0` (Debian/Ubuntu)

### "KVM virtualisation configured, but not available"

KVM is not accessible. Check:

```bash
ls -la /dev/kvm
# If missing, load the module:
modprobe kvm_intel  # or kvm_amd
```

If running inside a VM (nested), ensure nested virtualization is enabled on
the outer hypervisor.

### Patches not applied after qemu-server upgrade

```bash
/usr/share/pve-microvm/pve-microvm-patch revert
/usr/share/pve-microvm/pve-microvm-patch apply
```

### pve-oci-import fails with "required tool not found"

Install the missing dependencies:

```bash
apt update
apt install skopeo umoci qemu-utils
```

### pve-oci-import fails with "failed to import disk"

The VM must exist before importing a disk:

```bash
qm create <vmid> --machine microvm --memory 256
pve-oci-import --image alpine:latest --vmid <vmid>
```

---

## Roadmap

### v0.1 — MVP (current)

- [x] Machine type regex patch
- [x] MicroVM.pm command builder
- [x] Config validation
- [x] `qm create/start/stop/destroy` support
- [x] Serial console via `qm terminal`
- [x] `pve-oci-import` helper
- [x] Debian package scaffolding
- [ ] Testing on real Proxmox VE node

### v0.2 — UI + kernel

- [ ] `pve-manager` UI patches (machine type dropdown)
- [ ] Conditional panel hiding for microvm guests
- [ ] Ship a pre-built microvm kernel
- [ ] Cloud-init or Ignition support

### v0.3 — Production hardening

- [ ] vzdump backup validation
- [ ] Resource accounting / cgroup verification
- [ ] dpkg trigger for automatic re-patching after `qemu-server` upgrades
- [ ] Metrics and monitoring integration
- [ ] Performance benchmarking and documentation

### Future

- [ ] Memory ballooning (virtio-balloon-device on mmio)
- [ ] CPU hotplug testing
- [ ] Disk hotplug testing
- [ ] Upstream proposal to Proxmox (RFC patch series)

---

## Development

### Repository structure

```
pve-microvm/
├── Makefile                          # Build and install targets
├── README.md                         # This file
├── debian/
│   ├── changelog                     # Package version history
│   ├── compat                        # Debhelper compatibility level
│   ├── control                       # Package metadata and dependencies
│   ├── patches/
│   │   ├── series                    # Patch application order
│   │   ├── 01-machine-type-regex.patch
│   │   └── 02-microvm-command-builder.patch
│   ├── pve-microvm.postinst          # Post-install hook (applies patches)
│   ├── pve-microvm.prerm             # Pre-remove hook (reverts patches)
│   └── rules                         # Debian build rules
├── doc/
│   └── microvm-defaults.conf         # Example/default configuration
├── kernel/                           # (placeholder for kernel config/binary)
└── tools/
    ├── MicroVM.pm                    # Perl module — microvm QEMU command generation
    ├── pve-microvm-patch             # Patch apply/revert/status tool
    └── pve-oci-import                # OCI image → microvm disk converter
```

### Building the .deb

```bash
cd pve-microvm
dpkg-buildpackage -us -uc -b
ls ../pve-microvm_*.deb
```

### Testing patches locally

```bash
# On a test Proxmox node, apply patches without the .deb
sudo cp tools/MicroVM.pm /usr/share/perl5/PVE/QemuServer/MicroVM.pm
sudo /path/to/tools/pve-microvm-patch apply

# Test
qm create 999 --machine microvm --memory 128 --name test
qm destroy 999

# Revert
sudo /path/to/tools/pve-microvm-patch revert
```

### Running the upstream qemu-server tests

```bash
cd /path/to/qemu-server
make test
```

Ensure microvm patches do not break existing tests.

### Key source references

- `qemu-server/src/PVE/QemuServer/Machine.pm` — machine type definitions
- `qemu-server/src/PVE/QemuServer.pm` — `config_to_command()` main entry
- `qemu-server/src/PVE/QemuServer/Cfg2Cmd.pm` — flag generation
- [QEMU microvm source](https://gitlab.com/qemu-project/qemu/-/blob/master/hw/i386/microvm.c)

---

## References

- [QEMU microvm documentation](https://www.qemu.org/docs/master/system/i386/microvm.html)
- [Ubuntu Server — QEMU microvm](https://ubuntu.com/server/docs/explanation/virtualisation/qemu-microvm/)
- [Proxmox `qemu-server` source](https://git.proxmox.com/git/qemu-server.git)
- [Proxmox `pve-manager` source](https://git.proxmox.com/git/pve-manager.git)
- [Proxmox Developer Documentation](https://pve.proxmox.com/wiki/Developer_Documentation)
- [Firecracker kernel configs](https://github.com/firecracker-microvm/firecracker/tree/main/resources/guest_configs)
- [virtio-mmio specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html)

---

## License

Apache-2.0
