# Tests

The maintained behavior tests live in `scripts/*-smoke.sh` and `scripts/*-smoke.py` and are exposed by
the Makefile. Run the baseline serially:

```bash
make check
make smoke
make cli-smoke
```

`make check` includes model checks, project/repository workspace tests and
`make build-smoke`, toolchain and multi-dependency tests.
Build tests execute linked programs and consume generated
static libraries, covering offline source identity and failed-build preservation.
`make sha256-smoke` checks the native hash primitive against fixed vectors and
an independent oracle, including stream/padding boundaries, direct Assembly ABI
consumption, overflow, empty/large files and refused special/symlink inputs. Its
direct consumer lives in `tests/native/sha256.S` and runs without libc.
`make file-publish-smoke` (also in `make check`) checks native no-clobber publication,
inode and read-only mode, concurrency, special-file/symlink/shared-inode refusal,
direct SysV64 calls and missing-companion refusal. `make acquire-smoke` and
`make cache-smoke` verify lifecycle integration, including concurrent cache misses.
Lifecycle/remote tests have dedicated Make targets listed in `AGENTS.md`.

Registry tests share ports and process names, so smoke targets must run serially.
Kernel correctness is separate: `make conformance`. Performance measurement
requires its own power policy and exact Artifact/Contract binding; see
`spec/PERFORMANCE.md`.
