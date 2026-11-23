# Latest pre-release profiling

Workload: full local regression suite, run once for each profile type.

Exit codes: CPU run 0; allocation run 0 (zero means success).

Source revision: `d7df985c1b5edc751159f54a165530cf9ed3cf31`.

Tool version: `valgrind-3.27.1`.

CPU profiles: 1554; allocation profiles: 1554.

Callgrind counts executed instructions. Memcheck counts cumulative allocated bytes and objects. The two runs use the same test workload. These counts do not measure elapsed time.

## Highest instruction counts

* 1525929241: `python3 tests/test-blockdev-patch.py`
* 1498589761: `python3 tests/test-audit-regressions.py`
* 1485405111: `python3 tests/test-blockjob-patch.py`
* 1473534945: `python3 tests/test-template-storage.py`
* 1464360712: `python3 tests/test-postinst.py`
* 870072212: `python3 tests/test-profile-summary.py`

## Largest allocations

* 155594649 / 39113: `python3 tests/test-blockjob-patch.py`
* 142520985 / 43465: `python3 tests/test-audit-regressions.py`
* 139990610 / 39885: `python3 tests/test-blockdev-patch.py`
* 134556265 / 38287: `python3 tests/test-template-storage.py`
* 130458144 / 37971: `python3 tests/test-postinst.py`
* 82622306 / 75473: `cc1 tests/landlock-smoke.c`

## Analysis

Python startup and imports use most of the measured work in the mock tests.
The tests do not measure PVE runtime or guest performance. Each test keeps its
process isolation. Raw profiles and temporary files are deleted after analysis.

This run used the 0.4.3 working tree on the base revision above. Both passes
completed the 97-test workload. The new storage fixture used 1,473,534,945
instructions and 134,556,265 allocated bytes (38,287 objects). Inclusive CPU
annotations show Python import/evaluation work in this regression driver;
it launches isolated mocked commands for each failure case. The installed
config parser uses `python3 -S`, retaining the measured startup fix from
[0.4.2](patch-preflight.md). PVE storage validation uses its native Perl API.
No material new persistent-runtime outlier was identified in this workload.
No performance improvement is claimed from comparing different test suites.
Raw captures were removed after analysis.
