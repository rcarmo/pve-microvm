# v0.4.2 published-package validation

The published **0.4.2-1** package passed the live resize canary and sequential
installation on five hosts on 10 November 2026. No host or guest restart was
required.

## Release artifact

- Source/tag: `v0.4.2` at `104c142c73d26eefff2e165fdc27a976f3f324e7`.
- [Release workflow 42834869959](https://github.com/rcarmo/pve-microvm/actions/runs/42834869959):
  tests, kernel build, isolated boot, Debian package and GitHub/OCI publication
  all passed.
- Package: `pve-microvm_0.4.2-1_all.deb`.
- SHA-256: `203c503ee4cf63aed0cc200e5370cbadb0b303e8ab2de7c8bc315cb292f5550e`.
- Kernel: Linux `6.12.113`, AppArmor-first LSM configuration unchanged.

The downloaded package matched GitHub's asset digest. Its patcher and file
triggers matched the tagged source. Its effective kernel config matched the
published config. The extracted kernel passed AppArmor enforcement, Landlock,
EROFS and routing/mark boot tests.

## Tests and profiling

The local suite passed **96/96**. Local and tagged-source CI profiling completed
separate CPU and allocation passes, with **1,464 process captures per pass**.
The tagged CI used Valgrind 3.22.0; local profiling used 3.27.1. Raw captures were
removed after analysis.

Repeated Python site-package initialisation in patch transforms was measured
and removed with `python3 -S`. The equivalent single-transform comparison
reduced instructions from 609,101,219 to 75,387,347 (87.6%), allocated bytes from
51,447,728 to 5,086,169 (90.1%), and allocated objects from 16,341 to 2,896
(82.3%). See [measurements and limits](profiling/patch-preflight.md).

CI's largest process entries were regression drivers: Blockdev CPU instructions
1,102,095,952; installer allocations 122,082,508 bytes and 41,180 objects.
These drivers repeatedly launch isolated fixtures and subprocesses. No elapsed
time, guest speedup or persistent-service performance change was measured.

## Live resize canary

After installation from the published package, the Proxmox `qm disk resize`
operation grew a disposable running microVM's root disk from 2 to 3 GiB.

- The task completed without a backend lookup error.
- LVM, QEMU's inserted node and guest `/dev/vda` each reported
  **3,221,225,472 bytes**.
- Stored configuration changed from `size=2G` to `size=3G`.
- Online `resize2fs` completed with 786,432 4 KiB blocks.
- The guest boot ID was unchanged.
- Its persistent HTTP service still returned the expected content, and its
  Docker container retained `docker-default`.

The isolated two-disk QEMU regression separately verifies that root resize
leaves a read-only cloud-init backend and file unchanged. The live canary has
one disk; it does not duplicate that two-disk check.

## Host-by-host rollout

All five hosts upgraded to **0.4.2-1**, one at a time. Installed qemu-server
versions were 9.2.8 and 9.2.10. Checks at each boundary verified:

- No conflicting package process, package recovery state or active PVE task.
- Recovery copies of installed source, affected Perl files and VM configs.
- Unchanged `pvedaemon` and guest PIDs, VM configs and running/stopped states.
- Valid independent `Blockdev.pm` backup checksums and repeat-apply behaviour.
- No new failed host services; clean package state and active `pvedaemon`.
- Workload guest boot IDs, kernel, security labels, IPv4 addresses and container
  health preserved. Root backend lookup succeeded for every running microVM.

Workload disks were not resized. Recovery copies remain on each host. Only the
owned disposable release downloads, extracts, captures and run logs were
removed after use.

Existing partial resizes still need size reconciliation before a retry. The
patch does not grow guest filesystems automatically or validate every storage
backend and guest partition layout.
