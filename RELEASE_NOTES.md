# v0.3.29

Full clones from a running microVM could fail before disk mirroring because PVE
passed the unversioned `microvm` machine name into its machine-version parser.
This release fixes [#22](https://github.com/rcarmo/pve-microvm/issues/22) with an
exact-machine guard in `PVE::QemuServer::BlockJob::mirror`.

The microVM command builder uses `-drive`, so exact `microvm` uses the existing
`qemu_drive_mirror` branch. Conventional machines keep their previous version
check and drive/blockdev selection. No arbitrary unversioned machine is accepted
and no global machine-version parser behaviour is changed.

`BlockJob.pm` participates in patch preflight, idempotency, replacement triggers
and independently verified rollback originals. Unsupported layouts fail before
upstream files are edited. Legacy installations still refuse rollback if their
historical Machine/QemuServer backups lack verified provenance.

Validation: **91 tests pass**, including mirror dispatch, layout rejection,
fresh/legacy upgrades, repeated apply, upstream file replacement and rollback.
A disposable running microVM on z83ii reproduced the old version-check failure.
After candidate installation its full clone completed, the source stayed running
and responsive, and the destination booted with the expected on-disk marker.
Both disposable VMs were removed; existing workloads were not rebooted.

The guest kernel is unchanged from v0.3.28. Package hooks gracefully refresh
pvedaemon so new clone requests see the fix without a host or guest reboot.
