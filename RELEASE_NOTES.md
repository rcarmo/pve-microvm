# pve-microvm v0.1.19

All virtio devices confirmed working. Major milestone release.

## Confirmed on z83ii (PVE 9.1.7, QEMU 10.1.2, 256 MB RAM)

- ✅ `eth0` — networking via virtio-net-pci
- ✅ `/dev/vport1p1` — guest agent serial port
- ✅ `/dev/ttyS0` — serial console with interactive shell
- ✅ `/dev/vda` — root disk via virtio-blk-pci
- ✅ Balloon device for memory reporting
- ✅ Linked clones (instant LVM snapshot)
- ✅ Disk resize
- ✅ Snapshots
- ✅ vzdump backup (stop-mode, 8s)
- ✅ dpkg trigger for auto-repatching

## Key architecture

- Kernel: 6.12.22 from native `x86_64_defconfig`
- Transport: PCIe with non-transitional virtio devices
- Boot: kernel + initrd (1.2 MB, loads virtio modules)
- Init: busybox (static) or systemd from OCI image
