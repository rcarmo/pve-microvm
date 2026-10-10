# Latest pre-release profiling

Workload: full suite; Callgrind instructions and Memcheck cumulative bytes/objects in paired passes.
CPU pass: 0; allocation pass: 0.
8e1ac7038eaa127a0f126c72a7e92b67285802de
valgrind-3.27.1
CPU captures: 822; allocation captures: 975.
CPU units are instrumented instructions, not latency. Heap units are cumulative bytes and objects. Paired runs execute the same test workload.

## Largest cpu instructions processes
* 1494174958:  /home/linuxbrew/.linuxbrew/bin/python3 tests/test-audit-regressions.py
* 1463767190:  /home/linuxbrew/.linuxbrew/bin/python3 tests/test-postinst.py
* 1457214237:  /home/linuxbrew/.linuxbrew/bin/python3 tests/test-blockjob-patch.py
* 800402802:  /home/linuxbrew/.linuxbrew/bin/python3 -
* 799555198:  /home/linuxbrew/.linuxbrew/bin/python3 -
* 798678974:  /home/linuxbrew/.linuxbrew/bin/python3 -

## Largest allocated bytes/objects processes
* 146990468 / 38723: /home/linuxbrew/.linuxbrew/bin/python3 tests/test-blockjob-patch.py
* 140414915 / 43367: /home/linuxbrew/.linuxbrew/bin/python3 tests/test-audit-regressions.py
* 130447920 / 37956: /home/linuxbrew/.linuxbrew/bin/python3 tests/test-postinst.py
* 82622229 / 75473: /usr/libexec/gcc/x86_64-linux-gnu/13/cc1 -quiet -imultiarch x86_64-linux-gnu /workspace/projects/pve-microvm/tests/landlock-smoke.c -D_FORTI
* 68233343 / 21681: /home/linuxbrew/.linuxbrew/bin/python3 -
* 67745527 / 21649: /home/linuxbrew/.linuxbrew/bin/python3 -

Analysis: interpreter/import startup dominates the mock fixture suite.
No PVE runtime or guest performance claim; CPU is instruction events, not wall time.
Both passes completed 91/91, but lifecycle tests were extended while this
local profiling job was in flight (822 CPU vs 975 allocation processes).
Those local captures are not an equivalent-workload performance comparison.
No measured optimisation claim is made. Release CI repeats the immutable
committed workload for both passes. Isolation preserved; raw captures disposed.
