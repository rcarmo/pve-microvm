# v0.3.25

This release fixes unsafe cleanup and refresh paths, preserves command failures,
and honours read-only disk settings. Template cleanup now keeps the build directory
when bind mounts remain or mount inspection fails; refresh refuses ordinary or
running VMs and checks prerequisites before deletion.

Patch application validates both upstream Perl layouts before changing either file.
Rollback verifies the saved originals and patched files rather than restoring stale
PVE code. **Legacy installations without verified backup provenance refuse automatic
removal**; reconcile backups with the installed qemu-server package before removing
pve-microvm. Upgrades remain supported.

The ephemeral runner cleans up after configuration failures and preserves guest exit
codes. OCI imports retain failure diagnostics and abort on failed disk attachment.
Required kernel configuration checks now fail the build instead of just logging errors.
The missing 9Front download has also been restored.

Validation: 88 tests pass; the Debian candidate installed on borg and z83ii, repeated
patch application was idempotent, and isolated Debian guest boots passed on both.
z83ii also built a fresh Debian template. Existing borg VM IDs and process IDs were
unchanged. Candidate tests used the deployed kernel/initrd; release CI rebuilds them.

See [the audit report](docs/audit-2026-09-05.md) for test boundaries and remaining limitations.
