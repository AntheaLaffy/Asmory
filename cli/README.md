# Asmory CLI

The public Linux x86-64 CLI is a static Assembly ELF built with GNU `as` and
`ld`. Its CPUID/XGETBV detector checks OS extended-register state before reporting
AVX-family features as usable.

The CLI supports host inspection, bootstrap/remote discovery and resolution,
semantic Provider matching, verified acquisition, local dependency lifecycle,
repository workspaces, publication staging/promotion and offline builds. See
[the main README](../README.md) for commands and [CLI architecture](../docs/CLI.md)
for dispatch and compatibility rules.

```bash
asmory init
asmory add simd-dot
asmory build
```

The default application source is `src/main.S`; `[build]` can name other sources,
an output filename or a static library. Builds preserve locked Variant identity
and record local modifications. See [the build/link MVP](../docs/BUILD_LINK_MVP.md).

Acquisition and state/model helpers still use Bash/Python while reusable
Assembly capabilities are added. The process executor, ELF checker and SHA-256
file verifier are syscall-only Assembly. Acquisition/cache hashing and build
file digests use the native verifier without an external-tool fallback; the
planner's replacement conditions are explicit in
[the build contract](../spec/BUILD.md). Install the complete tool set with
`make install-user`; release archives include the same helper dependencies.
