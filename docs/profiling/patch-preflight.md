# Patch preflight Python startup

Pre-release profiling for 0.4.2 found repeated Python site-package loading in
patch transforms and their dry-run checks. The four embedded transforms import
only the standard library. They now use `python3 -S` to skip optional site
initialisation. File paths, validation, backup checks and transforms are
unchanged.

## Equivalent-workload comparison

On 10 November 2026, the same `Blockdev.pm` fixture and `--check` transform ran
once with normal Python startup and once with `-S`. Both commands succeeded
without modifying the fixture. The toolchain was Python 3.14.6 and Valgrind
3.27.1. Callgrind measured instructions; a separate Memcheck pass measured
cumulative allocations.

| Metric | Normal startup | `-S` | Change |
|---|---:|---:|---:|
| Instructions | 609,101,219 | 75,387,347 | −533,713,872 (−87.6%) |
| Allocated bytes | 51,447,728 | 5,086,169 | −46,361,559 (−90.1%) |
| Allocated objects | 16,341 | 2,896 | −13,445 (−82.3%) |

Inclusive CPU annotations showed Python import/evaluation and compilation work
in the baseline. Both allocation passes reported zero Memcheck errors. These
are single instrumented runs; no elapsed-time or guest performance change was
measured. The reduction applies to patch application and preflight, including
repeated calls in the isolated installer tests.

The initial full-suite diagnostic was stopped after locating the repeated
startup work. It was not a completed passing profile. Children were drained
before deleting captures. The full CPU/allocation passes are repeated after
the change; their results are recorded in [latest.md](latest.md). Correctness
tests retain **96/96** passes, including fresh/stamped installation, upstream
replacement, dry-run refusal and verified rollback.
