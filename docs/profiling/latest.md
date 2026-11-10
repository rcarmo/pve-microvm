# Latest pre-release profiling

Workload: full local regression suite, run once for each profile type.

Exit codes: CPU run 0; allocation run 0 (zero means success).

Source revision: `bfd87db415eeaf76a37b92d583b7d5b77f8e3c8f`.

Tool version: `valgrind-3.27.1`.

CPU profiles: 1464; allocation profiles: 1464.

Callgrind counts executed instructions. Memcheck counts cumulative allocated bytes and objects. The two runs use the same test workload. These counts do not measure elapsed time.

## Highest instruction counts

* 1526570154: `python3 tests/test-blockdev-patch.py`
* 1497463352: `python3 tests/test-audit-regressions.py`
* 1484757437: `python3 tests/test-blockjob-patch.py`
* 1463808642: `python3 tests/test-postinst.py`
* 870362261: `python3 tests/test-profile-summary.py`
* 800296855: `python3 standard-input test`

## Largest allocations

* 155592601 / 39112: `python3 tests/test-blockjob-patch.py`
* 142500611 / 43464: `python3 tests/test-audit-regressions.py`
* 139988561 / 39884: `python3 tests/test-blockdev-patch.py`
* 130456096 / 37970: `python3 tests/test-postinst.py`
* 82622229 / 75473: `cc1 tests/landlock-smoke.c`
* 80289833 / 73747: `cc1 tests/network-smoke.c`

## Analysis

Python startup and imports use most of the measured work in the mock tests.
The tests do not measure PVE runtime or guest performance. Each test keeps its
process isolation. Raw profiles and temporary files are deleted after analysis.

This capture used the 0.4.2 release working tree, including `python3 -S` for
embedded patch transforms; the revision above identifies its base commit.
Both passes completed the unchanged 96-test workload. Raw captures were deleted
after analysis. The earlier interrupted diagnostic is not passing evidence.

The highest CPU and allocation entries are the audit, Blockdev and installer
regression drivers. They run many isolated subprocesses and parse fixture text;
Python import/compilation work dominates their inclusive CPU annotations. These
processes are test tools, not persistent PVE services. The measured repeated
startup outlier in installed patch preflight was reduced and remeasured; see
[patch-preflight.md](patch-preflight.md). The single-transform comparison does
not establish a full-suite or guest speedup. No major unresolved runtime
performance outlier was identified by this test workload.
