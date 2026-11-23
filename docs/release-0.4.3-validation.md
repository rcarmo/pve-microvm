# v0.4.3 published-package validation

The published **0.4.3-1** package passed artifact checks and disabled-storage
preflight on Proxmox on 23 November 2026. The fix and issue forms are available
in [v0.4.3](https://github.com/rcarmo/pve-microvm/releases/tag/v0.4.3).

## Artifact and tests

- Source/tag: `v0.4.3` at `f0ebc449a5f656f6b3147eaaf2285d769155bf87`.
- [Release workflow 45263267552](https://github.com/rcarmo/pve-microvm/actions/runs/45263267552):
  tests/profiling, kernel build, isolated boot, Debian package and GitHub/OCI
  publication all passed. Ordinary CI also passed.
- Package: `pve-microvm_0.4.3-1_all.deb`.
- SHA-256: `29bc8fef7d3d192932d650bbd435a907a7299a9eeea9bcfef7490273c99e703a`.
- Kernel: Linux `6.12.113`, AppArmor-first configuration retained.

The downloaded package matched GitHub's asset digest. Its template tool matched
the tagged source, and its effective kernel config matched the published
config. The extracted kernel passed AppArmor enforcement, Landlock, EROFS and
routing/mark boot tests.

The regression suite passed **97/97**, including isolated storage/import
failures, existing patch lifecycle and live QMP resize checks. GitHub form YAML
parsed successfully; the bug form requires Proxmox VE and pve-microvm versions,
and its field IDs are unique. Bug and feature-request forms are present on
`main`; blank issues are disabled.

## Profiling

Local and tagged-source CI each completed separate CPU and allocation passes,
with **1,554 process profiles per pass**. Local Valgrind was 3.27.1; CI used
3.22.0. CPU annotations for the new storage regression driver show Python
import/evaluation work. It repeatedly launches isolated mocked commands for
failure cases. The installed config parser retains `python3 -S`, and storage
checks use the native PVE Perl API.

CI's largest process entries were Blockdev regression instructions
(1,102,302,552) and installer regression allocations (122,084,556 bytes;
41,181 objects). These are test-driver measurements. No elapsed-time, guest
speedup or persistent-service performance change was measured. No material new
persistent-runtime outlier was identified in this workload. Raw captures were
removed after analysis; different test suites were not compared as evidence of
an improvement.

## Real Proxmox checks

On a host with qemu-server 9.2.8 and QEMU 11.0.3:

- Native storage checks rejected a disabled store and a store without image
  content. An enabled image store passed.
- The actual helpers imported a 16 MiB sparse raw image into a disposable
  stopped VM. The registered volume was verified, attached and converted to a
  template. The owned template and its backing volume were then removed.
- The full tool rejected a refresh against disabled storage before deleting
  the existing template, pulling an image or importing a disk. The template's
  configuration and running canary's PID were unchanged.
- The extracted published tool repeated that full disabled-storage refresh
  check successfully. It matched the source used for the earlier live import.

No fleet package upgrade or workload guest restart was performed. Storage
configuration was not changed. The valid-import test covers LVM-thin; other
storage backends and complete specialist image downloads were not live-tested.
The disabled-storage check stops before the OCI build, so a full OCI build was
not repeated. Failed-import diagnostics and ambiguous/missing disk cases were
covered with isolated mocks.

## Existing partial templates

The fix does not repair old partial creations. Select enabled image storage
explicitly with `--storage`. Inspect an existing VM and its unused disks before
retrying or deleting it; the tool does not guess volume names for cleanup.
