# Build and Link MVP

The consumer loop now reaches a runnable program:

```text
resolve -> verified cache -> editable source -> locked GAS build -> static ELF
```

After `asmory init` and `asmory add`, declare your application sources:

```toml
[build]
sources = ["src/main.S"]
output = "demo"
```

Then run:

```bash
asmory build
./.asmory/build/project/current/demo
```

Builds use the already selected dependency Variant and local source; they work
offline. Edit a materialized dependency and rebuild to experiment. The build
record preserves its base Artifact and labels the actual tree Modified.

Build a repository Package as a deterministic static library:

```bash
asmory build --package simd-dot
```

The result is `.asmory/build/simd-dot/current/libsimd-dot.a`. A consumer can link
it with GNU ld and `--gc-sections`. Alternative Variants need explicit source and
export bindings; see [the build contract](../spec/BUILD.md).

Inspect `build.json` beside the output for sources, objects, selected Variants,
Machine Contracts, compiler versions, export declarations and content hashes.
Compilation and validation failures retain the previous successful generation.

`make build-smoke` covers actual program execution and static-library consumption,
offline locked dependencies, Modified/vendor provenance, section GC, include and
source boundaries, concurrent edits, malformed ELF/plan input and failure
preservation. It is part of `make check`.

The initial adapter is GAS on Linux x86-64. The Assembly executor, ELF checker and streaming file SHA-256 verifier
are statically linked and do not need libc. TOML planning and lifecycle state
remain transitional Python helpers; their replacement conditions are recorded in
the contract. NASM/LLVM-MC, PIC/PIE and accepted Evidence-driven selection remain
future work.
