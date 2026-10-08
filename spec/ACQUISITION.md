# Artifact Acquisition — Draft 0.1

Acquisition is the transport stage between resolution and storage.

```text
resolved exact Artifact identity
        ↓
transport bytes into a temporary file
        ↓
SHA-256 verification
        ↓
atomic publication to the requested destination
```

This stage does **not** define cache policy, extraction policy, local
materialization, or dependency state.

## Identity comes before transport

The acquisition backend receives an expected Artifact SHA-256 from the resolver.
It does not fetch a digest from the same download response and then treat that
as independent proof.

## Fail closed

The destination must not become visible as a successful Artifact until digest
verification passes. Existing destinations are never overwritten.

## No execution and no extraction

Acquisition does not execute package code, run build scripts, extract archives,
or mutate `asm.toml` / `asm.lock`.

Archive path and symlink safety belong to the later materialization stage.

## Bootstrap transport backend

The current Assembly CLI delegates transport to an explicit Bash companion
using system `curl`. The helper verifies bytes with its sibling syscall-only
`asmory-sha256`, backed by the reusable native streaming SHA-256 primitive.
A missing or failed verifier aborts acquisition before publication; there is no
external-tool fallback. Its sibling `asmory-file-publish` publishes the verified
staging inode through the native no-clobber file primitive; mode `0444` and file
fsync precede destination visibility. A missing publisher aborts before download.
See [the native interface](../native/README.md) for staging ownership and cleanup.
Bash transport/temporary-file orchestration remains transitional until native
HTTP/TLS, secure staging-directory creation and cleanup cover this lifecycle.

This is an implementation bootstrap, not semantic authority. Resolver identity
remains in the Assembly CLI / generated Registry metadata.

## Transport policy

Remote registries require HTTPS. Plain HTTP is accepted only for loopback
addresses in the local development Registry. Redirect protocols are restricted
to HTTP/HTTPS.

## Relationship to future cache

The next stage is:

```text
verified Artifact
      ↓
content-addressed immutable cache
```

The explicit acquisition destination remains caller-selected. A separate cache
layer now consumes verified acquisition without changing acquisition semantics.
