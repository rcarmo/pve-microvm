# v0.3.29 validation and AgentsInTheCloud relocation

On 2026-10-10, v0.3.29 was published with the running microVM full-clone fix for
[#22](https://github.com/rcarmo/pve-microvm/issues/22). The exact published package
is installed on z83ii and radxax4. Other fleet nodes were not upgraded in this
operation. The fix is described in [the RCA](rca-issue-22.md).

## Source, tests and release

* Commit `3daba93` and tag `v0.3.29` contain the exact-machine BlockJob guard,
  patch preflight, idempotency, package replacement trigger and independently
  verified rollback originals. Conventional machine version/dispatch behaviour
  is unchanged.
* Development tests passed **91/91**. Regression cases cover pristine and
  stamped legacy upgrades, repeated application, upstream BlockJob replacement,
  manual guard normalisation, unsupported layouts and changed-file/backup refusal.
* Local paired profiling passed but tests were extended during that job, giving
  different process counts. It is not an equivalent-workload performance
  comparison. Immutable release CI ran both passes against the committed source:
  **975 CPU captures and 975 allocation captures**, both successful. Python
  interpreter/import work dominates the mock suite. No PVE runtime performance
  improvement is claimed. Raw captures were analysed and disposed after use.
* [Release CI](https://github.com/rcarmo/pve-microvm/actions/runs/38033674776)
  passed tests, kernel rebuild, booted Landlock/EROFS checks, Debian packaging and
  publication. Published Debian asset SHA256:
  `fa020ef8b677e47ac068777e431b56f636a9c38ae97e86d934a8d6ffeb19b37a`.

## Live clone verification

A disposable 256 MiB running Debian microVM on z83ii reproduced the old failure
before mirror start: `cannot check version of invalid string '10'` on
qemu-server 9.2.8. After candidate installation the same full clone succeeded.

The exact published package was then installed on both affected nodes with
release-digest verification. Daemon PIDs and existing VM PIDs stayed unchanged;
redshirt (122) and piclaw-test (900) remained guest-agent responsive. BlockJob
live/original checksums and the kernel configuration checks passed.

With that published package, a fresh disposable source was booted on z83ii,
a disk marker was flushed, and a full clone completed via drive-mirror. PVE's
freeze/thaw commands completed, the source PID stayed unchanged, and the
new destination booted and read `published-issue22-marker`. Both test VMs
9883/9884 were purged. This tests PVE's normal clone consistency semantics;
it does not guarantee application consistency without suitable quiescence.

Host recovery copies are preserved under
`/root/pve-microvm-recovery/published-0329-*` and `issue22-*` on the two nodes.

## VM 123 relocation

After the fix passed the live clone test and was installed on Radxa, VM 123
(`agents-in-cloud`) was cleanly shut down and a fresh stop-mode backup created:

`/mnt/pve/backup/dump/vzdump-qemu-123-2026_10_10-08_03_08.vma.zst`

The backup completed successfully (1.20 GB compressed); the separate webhook
notification returned HTTP 500. `zstd -t` and streamed `vma verify` passed.
SHA256, also saved beside the archive:
`b541b51a47bb547b109c98ba6e58750127c013694e7b79be6a4b46134e124243`.

Offline migration from z83ii to radxax4 completed in **21m13s**, transferring the
64 GiB local-lvm disk. PVE removed the source LV after the successful transfer.
A read-only `e2fsck -fn` on the stopped destination passed all five phases;
Docker's `agents-in-the-cloud-system` persistent volume and the guest hostname
were present. No duplicate running VM was created. Existing Radxa VM PIDs and
agent responses stayed unchanged.

VM 123 is **stopped with `onboot: 0`**, 1 GiB RAM and 2 vCPUs. AgentsInTheCloud
is installed but the application is not operational: its supervisor enforces
at least 3 GiB effective memory. Radxa had only about 0.5–0.7 GiB available RAM
and several GiB already swapped during this operation. Starting a 4 GiB guest
would overcommit existing workloads, so none were stopped or resized to make
room. App access remains configured for localhost-only. An authorised capacity
change is needed before raising this VM's RAM and completing app onboarding.
