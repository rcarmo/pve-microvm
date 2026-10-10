# Running microVM full clone failure (#22)

## Cause

PVE's `BlockJob::mirror` decides between legacy drive mirroring and the newer
blockdev path using `Machine::is_machine_version_at_least($machine_type, 10, 0)`.
The microVM machine name is the unversioned string `microvm`, so version parsing
fails before a mirror job starts. On the tested qemu-server 9.2.8 the error was
`cannot check version of invalid string '10'`; the report describes another
version-parser error at the same call site.

The microVM command builder creates `-drive` devices. Its live clone must use
PVE's existing `qemu_drive_mirror` path; interpreting `microvm` as a synthetic
version or selecting `blockdev_mirror` would choose the wrong device API.

## Fix

The patch in version 0.3.29 guards the version check with an exact
`$machine_type ne 'microvm'` test. Short-circuiting sends exact `microvm` to the
existing drive-mirror branch. Conventional machines retain their original
version validation and mirror selection. Unrecognised unversioned strings
still fail; no global parser behaviour is changed.

`BlockJob.pm` is included in the patcher's preflight and stamped fast path,
package replacement triggers and status checks. Its pristine original and
patched file are checked independently on rollback. An upstream replacement of
only BlockJob leaves the fast path and receives the current patch. Previously
verified Machine/QemuServer originals keep their provenance after this repair;
unverified legacy backups remain unverified. All rollback checks run before any
file is restored.

## Verification

Executable regressions cover stock and manually guarded layouts, dry-run without
writes, repeat application, unsupported/ambiguous layouts, exact-machine
short-circuiting, conventional drive/blockdev selection and mirror arguments.
Isolated filesystem tests exercise pristine installs, stamped legacy upgrades,
BlockJob replacement and refusal of changed files/backups before rollback.

The development suite passes **91/91**. An isolated running
Debian microVM reproduced the version-check failure before mirror start. After
installing the candidate package, its full clone completed on LVM-thin using
drive-mirror. The source stayed running and guest-agent responsive; the
new destination booted and read the expected flushed on-disk marker. Both
disposable VMs were purged. PVE used its graceful daemon reload to refresh
cached Perl modules.

A running full clone is a point-in-time operation with PVE's existing consistency
semantics. This fix does not promise application-level consistency or replace
backups, guest quiescence or recovery testing.

[Issue #22](https://github.com/rcarmo/pve-microvm/issues/22).
