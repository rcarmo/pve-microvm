# Firecracker image compatibility

pve-microvm can run Firecracker rootfs images directly — no conversion needed.

## How Firecracker images work

Firecracker VMs use two files:

- **`vmlinux`** — an uncompressed Linux kernel
- **`rootfs.ext4`** — a raw ext4 filesystem image containing the OS

The rootfs is just a standard ext4 file. It's the same format that
`pve-oci-import` and `pve-microvm-template` produce from OCI container
images. Any Firecracker rootfs can be imported into Proxmox and booted
as a microvm.

## Importing a Firecracker rootfs

```bash
# Create the VM
qm create 900 --machine microvm --memory 256 --cores 1 \
  --serial0 socket --vga serial0 --agent 1 --tags microvm

# Import the Firecracker rootfs (ext4 image)
qm importdisk 900 /path/to/firecracker-rootfs.ext4 local-lvm

# Attach the disk
qm set 900 --scsi0 local-lvm:vm-900-disk-0

# Set kernel args (use OUR kernel, not Firecracker's vmlinux)
qm set 900 --args '-kernel /usr/share/pve-microvm/vmlinuz \
  -initrd /usr/share/pve-microvm/initrd \
  -append "console=ttyS0 root=LABEL=microvm-root rw"'

# Boot
qm start 900
qm terminal 900
```

## What's different from native Firecracker

| | Firecracker | pve-microvm |
|---|---|---|
| VMM | Firecracker VMM | QEMU microvm |
| Kernel | Firecracker's `vmlinux` | Our 6.12.22 kernel + initrd |
| Rootfs | ext4 image | Same ext4 image (compatible) |
| Network | Firecracker TAP | Proxmox bridge via virtio |
| Management | Firecracker API | `qm` CLI + PVE web UI |
| Storage | Local files | Any PVE storage backend |
| Backup | None | `vzdump`, snapshots |

The rootfs is interchangeable. The kernel and VMM are different but the
guest OS doesn't care — it's the same Linux userspace either way.

## Where to find Firecracker rootfs images

There's no central registry. Common sources:

- **AWS S3** (`spec.ccfc.min` bucket) — Firecracker CI test images
- **Docker export** — `docker export container > rootfs.tar && virt-make-fs rootfs.tar rootfs.ext4`
- **debootstrap** — `debootstrap trixie rootfs && mkfs.ext4 -d rootfs rootfs.ext4`
- **Our tools** — `pve-oci-import` produces the same ext4 format from any OCI image

Since Firecracker rootfs images are just ext4 files containing a Linux
filesystem, anything that produces an ext4 image works — including our
`pve-microvm-template` which creates them from OCI images automatically.

## Can I use Firecracker's kernel?

Firecracker ships `vmlinux` (uncompressed ELF) while we use `bzImage` +
initrd. You could theoretically use Firecracker's kernel with
`-kernel /path/to/vmlinux`, but our kernel includes virtio module loading
via the initrd which is required for QEMU microvm's PCIe device discovery.
Stick with our shipped kernel for reliability.
