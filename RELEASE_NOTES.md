# v0.4.2 — live microVM disk resize

This patch fixes live disk resize for microVMs whose virtio devices have
anonymous QEMU device IDs. Linux stays at **6.12.113**, with AppArmor selected
by default.

## Disk resize

Proxmox could grow the backing volume and then fail with:

```text
no block node inserted for drive 'scsi0'
```

The block-info lookup now resolves missing or anonymous virtio device IDs
through the stable legacy backend ID, such as `drive-scsi0`, for exact `microvm`
guests. Conventional VMs keep the upstream mapping and top-throttle-node resize
behaviour. The installer handles `Blockdev.pm` file replacement and requires
independently verified backups for rollback.

The regression suite passes **96/96**. An isolated QEMU microVM test uses the
patched Proxmox resize routine to grow the root disk. The separate read-only
cloud-init disk stays unchanged. Tests also cover stopped-VM behaviour, size
rounding, repeat installation, upgrades and rollback refusal. The published
package also passed a live Proxmox resize from 2 to 3 GiB, online filesystem
growth and sequential installation on five hosts without guest restarts. See
[published-package validation](docs/release-0.4.2-validation.md).

See [issue #24](https://github.com/rcarmo/pve-microvm/issues/24) and the
[cause and validation notes](docs/rca-issue-24.md).

## Existing partial resizes

The patch does not repair earlier partial resizes. Check the backing volume,
QEMU node and stored configuration sizes before retrying. An additive retry
can grow storage again; use a verified absolute target. Guest partition and
filesystem growth remain separate steps.

## Installation

Install `pve-microvm_0.4.2-1_all.deb` on each Proxmox host. Installation reloads
`pvedaemon` to refresh its Perl code. Guest restarts are not required for this
host-side fix. Custom kernel paths and existing guest network files are
preserved.
