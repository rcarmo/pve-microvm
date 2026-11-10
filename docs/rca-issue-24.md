# Live disk resize could not resolve the microVM backend

A live microVM resize could grow the backing volume and then fail before QEMU
or the stored VM configuration received the new size. Issue
[#24](https://github.com/rcarmo/pve-microvm/issues/24) reported:

```text
no block node inserted for drive 'scsi0'
```

## Cause

`MicroVM.pm` creates legacy `-drive` backends with IDs such as `drive-scsi0`.
It attaches virtio devices without explicit device IDs. QEMU reports those
devices with anonymous paths such as
`/machine/peripheral-anon/device[0]/virtio-backend`.

Proxmox's `Blockdev::get_block_info()` indexes its QMP `query-block` results by
virtio device ID. It cannot derive the configuration key `scsi0` from an
anonymous path. `Blockdev::resize()` grows the storage volume before consulting
that index, so a failed lookup leaves the operation partly applied.

The upstream routines used for regression tests come from
[`proxmox/qemu-server` at `27e51213d75e`](https://github.com/proxmox/qemu-server/blob/27e51213d75e9fdf067153c8008794e84d69af8a/src/PVE/QemuServer/Blockdev.pm).
The test fixture retains its upstream licence and copyright notice.

## Fix

The installer patches `Blockdev::get_block_info()` to use the stable legacy
backend ID when all these conditions hold:

- The virtio device ID is missing or has a recognised anonymous path.
- The backend ID is exactly `drive-` followed by a supported disk key.
- The running machine type is exactly `microvm`.

The mapping retains QEMU's full block information, including the inserted node
name and read-only state. It refuses duplicate backend keys. Named devices and
conventional VMs keep the upstream mapping. Resize still targets the inserted
node, preserving Proxmox's top-throttle-node behaviour, size rounding and QMP
timeout. Stopped-VM resize sends no QMP command.

The package registers a file trigger for `Blockdev.pm`. Installation validates
all transforms before changing upstream files. Rollback requires an independent
checksum manifest for the live file and its original; missing or changed
provenance prevents every restore.

## Validation

The local regression suite passes **96/96**. Tests cover:

- The failure with the unmodified upstream routine and success with the patch.
- Missing and anonymous device IDs, all supported disk-key families, malformed
  backend IDs, duplicate keys and exact-machine matching.
- Conventional VM node mapping and top-throttle-node resize.
- Fresh installation, stamped upgrade, repeat application, unsupported-layout
  refusal, upstream file replacement and verified rollback.
- An isolated, paused QEMU 8.2.2 microVM with two sparse raw disks. The actual
  patched resize routine supplies the QMP arguments. The root backend grows
  from 1,048,576 to 2,098,176 bytes; the separate read-only cloud-init backend
  and backing file remain at 1,048,576 bytes.

The full upstream `Blockdev.pm` also passes transform preflight. The isolated
QEMU test has no guest OS or network. A live Proxmox task, guest filesystem grow
and published-package installation still need validation; SSH access to the
managed host was unavailable during this fix. The issue's installed package
revision is unknown.

## Existing partial resizes

Check backing storage, QEMU's inserted-node size and the stored configuration
before retrying a failed resize. An additive retry can grow the volume again.
Use an absolute target after verifying the intended disk and current sizes.
Guest partition and filesystem growth remain separate steps. The patch does
not repair an earlier partial resize automatically.
