# v0.3.29 validation

Version 0.3.29 fixes full clones from running microVMs
([#22](https://github.com/rcarmo/pve-microvm/issues/22)). The cause and patch are
described in [the RCA](rca-issue-22.md).

## Regression and release checks

The suite passed **91/91** tests. Cases cover exact-machine mirror dispatch and
arguments, conventional drive/blockdev selection, pristine and legacy upgrades,
repeated application, upstream file replacement, manual guard normalisation,
unsupported-layout refusal and changed-file/backup rollback refusal.

[Release CI](https://github.com/rcarmo/pve-microvm/actions/runs/38033674776) passed
tests, kernel rebuild, booted Landlock/EROFS checks, Debian packaging and
publication. Paired profiling on the committed source completed successfully;
raw captures were analysed and disposed after use. No runtime performance
improvement is claimed.

## Running full-clone check

An isolated Debian microVM using qemu-server 9.2.8 reproduced the version-check
failure before mirroring. With the fix installed, the full clone completed
through the existing drive-mirror path.

The test was repeated using the exact published **0.3.29-1** package. The source
remained running with the same process ID and responsive guest agent; PVE's
freeze/thaw operations completed. The destination booted and read the expected
flushed disk marker. Disposable test guests were removed after validation.

These checks exercise PVE's existing clone consistency semantics. Applications
still need suitable quiescence and backups for their own recovery requirements.

[v0.3.29 release](https://github.com/rcarmo/pve-microvm/releases/tag/v0.3.29).
