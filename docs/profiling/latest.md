# Latest pre-release profiling

Workload: full suite; Callgrind instructions and Memcheck cumulative bytes/objects in paired passes.
CPU pass: 0; allocation pass: 0.
3daba938d96427e360fa319313a6ea44281821f6
valgrind-3.22.0
CPU captures: 975; allocation captures: 975.
CPU units are instrumented instructions, not latency. Heap units are cumulative bytes and objects. Paired runs execute the same test workload.

## Largest cpu instructions processes
* 1087006627:  /usr/bin/python3 tests/test-audit-regressions.py
* 1072679612:  /usr/bin/python3 tests/test-blockjob-patch.py
* 1066720986:  /usr/bin/python3 tests/test-postinst.py
* 683537778:  /usr/bin/python3 -
* 682839788:  /usr/bin/python3 -
* 681913632:  /usr/bin/python3 -

## Largest allocated bytes/objects processes
* 118169935 / 40782: /usr/bin/python3 tests/test-blockjob-patch.py
* 116188947 / 45840: /usr/bin/python3 tests/test-audit-regressions.py
* 111675825 / 40079: /usr/bin/python3 tests/test-postinst.py
* 82663802 / 75478: /usr/libexec/gcc/x86_64-linux-gnu/13/cc1 -quiet -imultiarch x86_64-linux-gnu /home/runner/work/pve-microvm/pve-microvm/tests/landlock-smoke.
* 71742356 / 26736: /usr/bin/python3 -
* 71247401 / 26724: /usr/bin/python3 -

Analysis: interpreter/import startup dominates the mock fixture suite.
No PVE runtime or guest performance claim; CPU is instruction events, not wall time.
Equivalent paired workload; isolation preserved. Raw captures disposed after analysis.
