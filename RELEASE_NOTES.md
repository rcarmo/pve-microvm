# v0.4.3 — template storage validation

Template creation now rejects disabled, unavailable or unsuitable storage before
building an image or removing an existing template with `--refresh`.

The selected storage must be enabled on the current node, active and support
VM disk images. `local-lvm` remains the default. If it is disabled, select a
suitable pool with `--storage`; the tool does not enable it or switch pools.

Disk-import errors are printed. Successful imports must register one new unused
volume on the selected storage, owned by the template VM, with a non-empty
backing volume. The tool verifies attachment before converting the VM to a
template. OCI and specialist disk-image imports share these checks. Failed
imports preserve the VM for inspection; existing partial creations are not
repaired automatically.

The local suite passes **97/97**, including storage/import failure cases and
existing patch, resize, security and isolation checks. Real Proxmox checks
reject disabled/non-image storage, preserve a template during a rejected refresh,
and verify import/attachment/template conversion in a disposable stopped VM.
Separate CPU/allocation passes passed; no guest restart was needed. See
[issue #25](https://github.com/rcarmo/pve-microvm/issues/25), the
[cause and coverage](docs/rca-issue-25.md),
[published-package validation](docs/release-0.4.3-validation.md) and
[storage selection](docs/usage.md#choose-storage).

GitHub bug-report forms now require Proxmox VE and pve-microvm versions,
reproduction steps and error output. Storage reports request sanitised storage
status and configuration. A separate form collects feature requests.

Linux remains **6.12.113**, with AppArmor selected by default. Install
`pve-microvm_0.4.3-1_all.deb` on the Proxmox host; guest restarts are not required
for this template-tool fix.
