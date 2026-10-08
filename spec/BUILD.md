# Offline Build Contract — Draft 0.1

`asmory build` composes direct source dependencies into a static Linux x86-64
executable or a deterministic GNU static archive. It performs no resolution,
download, package hook, conformance execution or benchmark.

## Project input

Run from an initialized consumer workspace. `asm.toml` dependency intent must
agree with `asm.lock`; missing or unknown materializations fail. Registry and
vendor dependencies retain their locked Release, Variant and base Artifact.
Multiple direct dependencies are installed independently and consumed from their
exact lock records. See [the dependency contract](DEPENDENCIES.md).

```toml
[build]
kind = "executable"
sources = ["src/main.S"]
entry = "_start"
output = "program"

[link]
gc_sections = true
pic = false
```

These are also the project defaults when omitted. `sources` is a nonempty,
duplicate-free list. `output` is a filename inside the selected build generation.
An executable entry must be a defined global symbol inside an executable section.

`kind = "static-library"` produces `lib<project-name>.a` by default and requires
the project's `[exports]` declarations. Direct dependencies are flattened into
the archive. Recursive dependencies inside a Package are rejected.

## Machine and toolchain constraints

The initial adapter supports GNU `as --64`, `ld -m elf_x86_64` and `ar rcsD`.
Sources are assembled directly, including files named `.S`; no C preprocessor
or shell interpolation is applied. Source files select AT&T or Intel syntax
using GAS directives.

Projects without `[target]` lower to Linux/x86-64/ELF64/SysV64, x86-64-v1 with no
extra ISA requirements. Their default toolchain is GAS >= 2.40, AT&T syntax.
Packages must declare a complete target and toolchain. Architecture, OS, object
format, ABI, baseline, required ISA and minimum assembler version are checked
before compilation. Host facts come from the native CPUID/XGETBV detector.
Tuning metadata cannot override these checks. PIC/PIE and other assembler
adapters are not implemented yet.

## Variant source bindings

`asmory build --package <name> [--variant <id>]` builds a repository workspace
member as a static library, storing output in the repository's runtime directory
outside the Package root. Repository metadata remains separate from a consumer
lockfile.

When `variants.toml` is present, its first Variant inherits the Package manifest's
build sources and exports. Later Variants must explicitly declare
`[variant.build]` and `[variant.exports.<logical>]`. A selected Variant's
`compatibility` and optional `toolchain` supply its Machine Contract. An unknown
Variant or an alternate without a source binding fails; Asmory never guesses
which source implements a locked Variant. Without `variants.toml`, the Package
manifest is the source binding for the promoted default Variant.

Inherited sources also retain their manifest's target/toolchain constraints.
A weaker Variant declaration cannot make those same bytes runnable on a host
that fails the source binding. Both contracts are checked and recorded.

The existing simd-dot archive binds its first generic Variant through `asm.toml`.
Its older experimental Variant has no explicit source binding and is refused by
this adapter until a new source Release declares that binding.

## Source and export boundaries

Build paths are canonical and relative to their Package root. Traversal,
absolute paths, symlinks and special files are rejected. Literal GAS `.include`
and `.incbin` operands are resolved from the Package root, matching the compiler's
working directory. Dynamic include names and include cycles are rejected.
Compiler inputs are private copies; the global content-addressed cache and active
dependency trees are never compiler output destinations.

The native ELF validator checks file bounds, ELF64/little-endian/EM_X86_64/ET_REL,
section tables, string termination, symbol indexes and symbol ranges. Each source
object is checked before use. Package objects are combined with `ld -r` so
internal references can resolve before checking the leaf contract.

Each declared export must exist exactly once in the declared section and have
SysV64 calling-convention metadata. Undeclared visible global/weak definitions,
missing exports, duplicate exports between direct units and unresolved Package
symbols fail. Defined hidden/internal helpers are private and need no export
declaration. Final linking also rejects duplicate private symbols and unresolved
project references. ELF metadata checks do not prove runtime ABI preservation,
semantic conformance or security review.

Executables default to section GC and a non-executable stack. Static archives use
deterministic GNU archive mode and retain the source object graph for the consumer
linker.

## Generation publication and source identity

Output lives under `.asmory/build/<name>/runs/<build-record-sha256>/`. An atomic
`current` symlink selects a complete successful generation. Failed compilation,
linking, validation or concurrent input changes leave the previous selection
intact. The shared workspace lock serializes cooperating lifecycle writers.
Existing generations are content-checked before reuse.

`build.json` records policy `asmory-gas-build-v1`, normalized command arguments,
host facts, tool versions, source/object edges, input hashes, selected Variant,
exports and output SHA-256. Dependency records include computed Exact/Modified
integrity, ownership, base Artifact/semantics and actual tree SHA-256. Modified
source is allowed for local experiments and never relabeled Exact.

The record supports inspecting and repeating the recipe; it is not a signature,
Registry Performance Evidence or a claim that the produced program was tested.
`asm.toml`, `asm.lock`, cache objects and active source are unchanged by a build.
Build runtime state is ignored in Git. Repository-control `asmory.package.toml`
is excluded from source Artifacts so workspace metadata can evolve independently.

## Assembly migration boundary

The native file-view, process, streaming SHA-256 and ELF modules are reusable SysV64 Assembly
primitives. The CLI locates its build helper beside its own executable without a
shell or PATH search. A syscall-only executor validates a bounded binary plan
completely before running jobs using `fork`/`execve`/`wait4`.

Build file digests use the syscall-only `asmory-sha256` companion. The Python
planner temporarily supplies TOML model expansion, metadata and current lock/tree
hash integration, include scanning, source snapshots and generation publication.
It uses the existing standard-library helpers. Retire this planner when reusable
Assembly TOML parsing, canonical metadata/tree hashing and transactional directory operations
can implement the same contract and pass `make build-smoke`. Complexity alone is
not a reason to retain the transition permanently.
