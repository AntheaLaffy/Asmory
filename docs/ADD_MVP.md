# End-to-end `asmory add` MVP

This milestone turns resolver, acquisition and cache into the first complete
package-manager workflow:

```bash
asmory init
asmory add simd-dot
```

The command performs:

```text
resolve machine legality
  -> exact Registry identity
  -> verified content-addressed cache
  -> safe archive validation
  -> project-local materialization
  -> manifest intent
  -> exact lockfile record
```

The result is visible writable source under `.asmory/deps/simd-dot/`.

The installer supports multiple independent direct leaf dependencies. It preserves
project configuration and all earlier lock records when appending a Package,
including local Modified source and project-owned vendor state. Ordinary
`[dependencies]` tables, inline tables, dotted Package names and a predeclared
exact selected Release are covered by the regression suite.

It refuses to overwrite an existing dependency, extract unsafe members, accept
unsupported/unsatisfied intent, or change manifest/lockfile when acquisition,
materialization or metadata validation fails. Workspace mutations are serialized
with a local lock, and a concurrent metadata edit is preserved.

Once the exact Artifact is present and verifies in the global cache, another
project can `asmory add simd-dot` while the Registry is offline.

This is the first executable form of:

> **Cache for reuse. Local workspace for understanding and evolution.**

The local-state lifecycle now computes Exact versus Modified from the materialized
tree and implements restore as the first explicit state transition.

Metadata edits are range-checked and written by the syscall-only
`asmory-text-splice` tool, using exclusive destination creation. The transitional
Python model helper validates TOML and plans edits while retaining unrelated
fields and source text. Replace it when Assembly TOML parsing and structural
model validation can pass `make multi-add-smoke`; file I/O and numeric range
validation already have reusable native implementations.
