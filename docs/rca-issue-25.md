# Template creation with disabled storage

Template creation could download and build an image, create a VM and then fail
at import because the default `local-lvm` storage was disabled. The import error
was captured without being printed. Issue
[#25](https://github.com/rcarmo/pve-microvm/issues/25) reported this on
pve-microvm 0.4.2-1 and Proxmox VE 9.2.32.

## Cause and fix

The template tool accepted its configured/default storage without checking
whether it was enabled on the current node, active or permitted VM images.
Several import paths also tried to parse human-readable progress output and
substituted a guessed disk name when that parsing failed.

The tool now checks the selected storage through `PVE::Storage` before image
download/build and before deleting an existing template with `--refresh`. It
checks again before import because storage can change during a build. It
retains `local-lvm` as the default; users select another pool with `--storage`.
It does not enable storage or silently choose a different pool.

Disk import errors are printed and stop template conversion. On success, the
tool reads the new unused disk from `qm config`, verifies its storage, VM
ownership and non-empty backing volume, attaches it and checks the resulting
device configuration. It refuses missing/ambiguous results and changes to
pre-existing unused disks. OCI, 9Front, OpenWrt, OPNsense and SmolBSD use the same
helpers. Diskless OSv and the gokrazy instructions do not require disk storage.

Failed imports preserve the newly created VM and any unused disks for manual
inspection. No cleanup deletes volumes based on guessed names. Existing
partial template creations are not repaired automatically.

## Regression coverage

`tests/test-template-storage.py` executes the actual helpers against isolated
PVE mocks. It covers disabled/missing/node-excluded storage, wrong content,
inactive storage, failed import diagnostics, localised progress output,
missing/ambiguous volumes, wrong storage/owner, empty backing volume,
pre-existing unused disks and failed attachment verification. It also checks
that all disk-import paths use the shared helper and storage preflight precedes
refresh deletion.

The published 0.4.3-1 tool passed disabled-storage refresh preflight on a real
Proxmox host without changing its existing template or running canary. The
same source helpers verified a valid import, attachment and template conversion
on LVM-thin. See [published-package validation](release-0.4.3-validation.md)
for evidence and limits.

GitHub bug reports now require Proxmox VE and pve-microvm versions, reproduction
steps and error output. Storage failures request sanitised storage status and
configuration. A separate feature-request form collects the use case and
proposed behaviour.
