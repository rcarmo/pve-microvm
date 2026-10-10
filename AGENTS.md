<!-- RUI-PROFILE-LIFECYCLE-20261005 -->
## Current profiling and cleanup rule — supersedes older text below

Rui's explicit rule: **profile and tune during pre-release tests; remove profiling data immediately after analysis/use.** Ordinary development tests do not require profiling on every run. Targeted diagnostic profiling is optional when useful and follows the same disposal rule.

- During pre-release verification, capture CPU and heap/allocation behaviour, analyse hotspots and tune avoidable allocations/repeated work. Compare equivalent workloads without weakening correctness/security/numerical contracts. For Go, inspect CPU, alloc_space and alloc_objects; coverage alone is not profiling.
- Keep captures and matching artifacts only while the current analysis needs them. Once used, immediately delete raw profiles, traces, matching test binaries, temporary fixtures and disposable logs, including failed/probe artifacts after diagnosis. Retain only concise conclusions and important measurements/limitations. Do not keep indefinite raw archives or copy them into exports/reports/evidence to evade cleanup.
- Remove all completed disposable cache/build/test/run data promptly. Never delete files still in use: finish or safely pause the owning job and clean at a safe boundary. Preserve source, installed toolchains, durable datasets/checkpoints and intentional release assets. Minimise disk usage; no random exports or redundant snapshots.
- This rule overrides **every conflicting older paragraph in this file and linked local guidance**, including “profile every test”, “unprofiled tests prohibited”, “retain all raw evidence”, “never delete profiles” and cleanup exclusions based only on an evidence/profiles directory name. Update helper/CI cleanup behaviour accordingly; do not weaken pre-release analysis.
- Existing no-agent-contact and execution-pause rules remain unchanged. This policy grants no unsolicited coordination or automatic job restart.
<!-- /RUI-PROFILE-LIFECYCLE-20261005 -->



# pve-microvm Agent Notes

These notes capture the working process for developing, testing, and releasing `pve-microvm`. They are intentionally generic: replace hostnames, node IPs, storage names, VMIDs, and template IDs with values from your own Proxmox VE cluster.

## Project shape

`pve-microvm` is a Debian package that adds QEMU `microvm` machine type support to Proxmox VE by:

* Installing `PVE::QemuServer::MicroVM` as a delegated command builder.
* Patching PVE's `Machine.pm` and `QemuServer.pm` for microVM dispatch, plus `BlockJob.pm` so unversioned microVMs use drive-mirror for running full clones.
* Shipping a minimal kernel/initrd pair for direct kernel boot.
* Adding CLI helpers, template creation from OCI images, filesystem sharing, vsock support, and web UI integration.

The patching model is invasive by design, so every change must be reversible, idempotent, and tested against the current PVE `qemu-server` package.

## Git and release workflow

* Work on `main` unless explicitly creating a long-running branch.
* Do not rebase published history.
* Keep commits outcome-focused: one logical fix or feature per commit.
* For release builds, update `debian/changelog`, tag `vX.Y.Z`, push the commit and tag, then let GitHub Actions publish assets.
* Installation instructions should not hardcode package versions. Prefer commands that resolve the latest release asset dynamically.
* After a release asset is published, test on one non-critical node first before pushing to the rest of the cluster.

Typical release sequence:

```bash
# after committing changelog and code changes
git tag -a v0.3.X -m "v0.3.X — short release description"
git push
git push origin v0.3.X

# wait for GitHub release assets, then on a test PVE node:
curl -sLO $(curl -s https://api.github.com/repos/rcarmo/pve-microvm/releases/latest \
  | grep browser_download_url | grep '.deb' | cut -d'"' -f4)
dpkg -i pve-microvm_*.deb
apt-get install -f
```

## Project-owned caches and disposable output (2026-10-05)

The canonical project name is `pve-microvm`. Resolve the root once, before
changing `TMPDIR`, with the packaged `tools/lib/project-tmp.sh` resolver:

* `PROJECT_TMP_BASE` selects `<base>/pve-microvm`. Compatible
  `PROJECT_TMP_ROOT` selects the complete root; if both are supplied they must
  agree. Invalid/relative/empty/conflicting overrides fail. `PVE_MICROVM_TMP_ROOT`
  is a legacy alias only when the generic root is absent.
* Snapshot inherited `TMPDIR` once as `PROJECT_ORIGINAL_TMPDIR`. CI chooses
  `$RUNNER_TEMP/pve-microvm`, then original `$TMPDIR/pve-microvm`, then platform
  temp, even if a workspace mount exists. Local hosts choose usable
  `/workspace/tmp/pve-microvm`, then platform temp. On the supported Linux/Bash
  toolchain system temp is `/tmp/pve-microvm`; there is no bare/home cache root.
  The resolved root is exported once, so subprocesses keep the same hierarchy.
  Ownership/symlink checks remain; `/workspace` is the known mount alias.
* `cache/kernel/` holds Linux tarballs; `cache/{xdg,bun,npm,python}/` holds tool
  caches. `build/kernel/` holds kernel/initrd outputs; isolated kernel compilation
  and Debian staging/artifacts live under `build/`. Stable `tests/` and `logs/`
  directories are available for disposable isolation/output; profiling captures are temporary and deleted after analysis. The helper exports
  `TMPDIR`/`TMP`/`TEMP` to an existing `runs/<purpose>/run.XXXXXX/tmp/`, plus
  `XDG_CACHE_HOME`, `BUN_INSTALL_CACHE_DIR`, `npm_config_cache`,
  `PYTHONPYCACHEPREFIX` and `PYTHONDONTWRITEBYTECODE`.
* Use `make test`, `make kernel`, `make deb`; direct tools use the same helper.
  `make deb` builds a copy under `build/deb/run.XXXXXX` rather than writing
  generated Debian files into source. `PVE_MICROVM_KERNEL_DIR` must be beneath
  the resolved `build/`; packaging consumes that path.
* CI explicitly sets `PROJECT_TMP_ROOT=$RUNNER_TEMP/pve-microvm`. The resolver
  is vendored into the repository/package: CI does not depend on the host's
  `/workspace/Makefile`. Artifact staging and publisher auth use the same tree.
* Installed tools have the portable fallback too. No remote host changes are
  authorised by this policy update; coordinate rollout/path mapping before
  deploying. Existing jobs, model/data assets and legacy paths are untouched.
* Guest `/tmp` tmpfs mounts and in-image package paths are guest runtime state,
  not host build scratch. Do not replace them with workspace paths.
* Pre-release profiling scratch uses `runs/tests/<run-id>/profiles/`, which
  is disposable and separate from source. `make test` captures
  Callgrind CPU instructions and Memcheck allocation trees in paired equivalent
  full-suite passes (Valgrind cannot combine these tools). Both are analysed
  then deleted after a run; instruction counts are not wall-clock latency samples.
* `make clean CONFIRM_IDLE=yes` removes only the resolved root's `cache`,
  `build`, `tests`, `logs`, `runs` after jobs stop and concise conclusions are recorded. Never migrate/delete
  another project's files or durable source/data/release assets without authorisation; raw profiles are deleted after use.

## Development checks before committing

Run the checks that are meaningful in the current environment:

* Shell syntax for scripts:

```bash
bash -n tools/pve-microvm-template
bash -n tools/pve-microvm-patch
bash -n kernel/build-kernel.sh
```

* Perl syntax for `MicroVM.pm` is best checked on a PVE host, not on a generic development machine, because it imports PVE Perl modules:

```bash
perl -c /usr/share/pve-microvm/MicroVM.pm
perl -e 'use PVE::QemuServer; use PVE::QemuServer::MicroVM; print "OK\n"'
```

* Verify patches are idempotent:

```bash
pve-microvm-patch status
pve-microvm-patch apply
pve-microvm-patch apply
pve-microvm-patch status
```

The second `apply` must not duplicate imports or delegation blocks.

## PVE node testing process

Use a staged rollout:

1. Pick a non-critical PVE node that has local storage and at least one disposable test VM/template.
2. Install the new `.deb`.
3. Restart `pvedaemon` and verify it still starts.
4. Create or restart a microVM.
5. Verify the QEMU command line uses `-M microvm` and virtio-only devices.
6. Verify the guest boots, mounts root as `/dev/vda`, has networking, and the QEMU guest agent responds if enabled.
7. Only then deploy to the remaining nodes.

Useful checks on a PVE node:

```bash
systemctl restart pvedaemon
systemctl is-active pvedaemon

qm config <vmid> | grep '^machine: microvm'
qm start <vmid>
PID=$(pgrep -f "kvm.*-id <vmid>")
tr '\0' '\n' < /proc/$PID/cmdline | grep -A1 '^-machine$'
tr '\0' '\n' < /proc/$PID/cmdline | grep -E 'virtio-blk|virtio-net|balloon|scsi-hd'

qm agent <vmid> ping
qm guest exec <vmid> -- bash -c 'hostname; df -h /; ip -brief addr'
```

Expected microVM signs:

* Machine line contains `microvm,x-option-roms=off,...,pcie=on`.
* Block devices are `virtio-blk-pci-non-transitional`, not `scsi-hd`.
* Network devices are virtio PCI devices.
* Root filesystem is mounted from `/dev/vda` for Linux guests.

## Testing existing microVM workloads

When upgrading a node that already runs microVMs:

* Record the VMIDs and expected services before stopping anything.
* Restart one microVM at a time unless the host itself must reboot.
* After restart, check the guest agent, root filesystem, and service health.
* For web services, test from both inside the guest and from the host/network.

Example pattern:

```bash
qm stop <vmid>; sleep 3; qm start <vmid>
sleep 15
qm agent <vmid> ping
qm guest exec <vmid> -- bash -c 'hostname; df -h /; systemctl --failed --no-pager'
```

For HTTP services:

```bash
IP=$(qm guest exec <vmid> -- bash -c 'hostname -I' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("out-data","").split()[0])')
curl -I http://$IP:<port>/
```

## Auto-start and boot-order hazards

`onboot: 1` VMs expose ordering bugs. If PVE starts VMs before `pve-microvm` patches are active, `machine: microvm` may be rejected or stripped during config parsing/migration, and the VM can start as a standard PC. The disk will then appear as `/dev/sda` instead of `/dev/vda`, which looks like a lost root filesystem.

Required safeguards:

* `pve-microvm-early.service` must be enabled on every node.
* It must run before `pvedaemon.service` and `pve-guests.service`.
* The patch script must be idempotent.

Check:

```bash
systemctl is-enabled pve-microvm-early.service
systemctl show pve-microvm-early.service | grep -E 'Before=|After='
systemctl status pve-microvm-early.service --no-pager
```

Expected ordering includes:

```text
Before=pvedaemon.service pve-guests.service
```

After any host reboot, verify at least one auto-started microVM actually launched as `microvm` and not `pc+pve0`/`q35`.

## Updating Proxmox VE packages safely

Avoid partial PVE upgrades. PVE Perl modules are tightly coupled, and mismatched versions can break `pvedaemon`, `qm`, and config parsing. Prefer full upgrades:

```bash
apt-get update
apt-get dist-upgrade
```

Then:

```bash
dpkg --configure -a
apt-get install -f
pve-microvm-patch apply
systemctl restart pvedaemon
```

Watch for these failure modes:

* `unknown file 'sdn/...cfg'` from `PVE::Cluster` usually means PVE package version skew.
* `parse_guest_agent` or similar Perl API errors usually mean `qemu-server` changed an internal function signature; update `MicroVM.pm` compatibility code.
* Duplicate `use PVE::QemuServer::MicroVM;` or duplicate delegation blocks mean patch idempotency regressed.

If a PVE package upgrade replaces patched files, the dpkg trigger and early-boot service should re-apply patches. Still verify explicitly:

```bash
grep -n 'PVE::QemuServer::MicroVM\|is_microvm' /usr/share/perl5/PVE/QemuServer.pm
perl -e 'use PVE::QemuServer; print "OK\n"'
```

## Kernel and EFI partition maintenance

Kernel upgrades can fail if the EFI system partition is full, especially on small appliances. Symptoms include `No space left on device` while copying `initrd.img-*` into `/boot/efi/...`.

Check before/after upgrades:

```bash
df -h /boot /boot/efi
dpkg -l 'proxmox-kernel-*-pve-signed' | awk '/^ii/{print $2, $3}'
uname -r
```

Remove old kernels, keeping the currently running kernel and one known-good fallback:

```bash
apt-get remove proxmox-kernel-<old-version>-pve-signed
apt-get autoremove
```

If the bootloader selected an unwanted kernel, pin the intended version:

```bash
proxmox-boot-tool kernel pin <version>-pve
update-grub
```

Reboot only after `dpkg --configure -a` is clean and `/boot/efi` has enough free space.

## Memory management testing

Current memory features include:

* `free-page-reporting=on` on virtio-balloon.
* `deflate-on-oom=on` on virtio-balloon.
* PVE active ballooning via `balloon` config.
* Optional `virtio-mem-pci` with a memory backend.

Check a running VM command line:

```bash
PID=$(pgrep -f "kvm.*-id <vmid>")
tr '\0' '\n' < /proc/$PID/cmdline | grep balloon
```

Expected balloon flags:

```text
virtio-balloon-pci-non-transitional,id=balloon0,free-page-reporting=on,deflate-on-oom=on
```

QMP balloon query:

```bash
(echo '{"execute":"qmp_capabilities"}'; sleep 0.5; echo '{"execute":"query-balloon"}') \
  | socat - UNIX-CONNECT:/var/run/qemu-server/<vmid>.qmp
```

Inside a Linux guest, `dmesg` should show free page reporting if the kernel supports it:

```bash
dmesg | grep -i 'free page\|balloon'
```

`virtio-mem` is currently QMP/CLI-only; there is no PVE web UI control yet. Grow/shrink live by setting `requested-size` on the `vmem0` object. Avoid combining active ballooning and virtio-mem for the same VM unless specifically testing QEMU behaviour; the two mechanisms can fight over the same memory.

## Web UI changes

The UI extension is injected into PVE's `index.html.tpl` and adds microVM-specific affordances. Test it after package upgrades because PVE frontend internals can change.

Minimum checks:

* PVE web UI loads without JavaScript errors.
* Create µVM wizard opens.
* The wizard-generated command matches supported `pve-microvm-template` flags.
* Machine type dropdown accepts `microvm`.
* xterm.js console opens for serial console guests.

When adding wizard fields, also add matching CLI flags or post-create `qm set` commands. Do not let the GUI generate unsupported arguments.

## Recovery notes

If a microVM appears to have lost its filesystem after a reboot:

1. Check whether the VM started as standard PC instead of microVM:

```bash
PID=$(pgrep -f "kvm.*-id <vmid>")
tr '\0' '\n' < /proc/$PID/cmdline | grep -A1 '^-machine$'
tr '\0' '\n' < /proc/$PID/cmdline | grep -E 'scsi-hd|virtio-blk'
```

2. Check whether `machine: microvm` is still present:

```bash
grep '^machine:' /etc/pve/qemu-server/<vmid>.conf
```

3. Restore it if missing:

```bash
qm set <vmid> --machine microvm
pve-microvm-patch apply
systemctl restart pvedaemon
qm stop <vmid>; qm start <vmid>
```

The data is usually intact; the guest simply saw the root disk as a different device path.

## Documentation expectations

When behaviour changes, update docs in the same commit or immediately after:

* `README.md` for quick-start, feature list, and roadmap.
* `docs/installation.md` for install/update process.
* `docs/configuration.md` for VM config options.
* `docs/architecture.md` for command-line/device model changes.
* `docs/known-issues.md` or `docs/troubleshooting.md` for sharp edges and recovery steps.

Keep docs version-agnostic where possible. If a feature depends on a minimum release, state it in prose rather than embedding stale package filenames.
