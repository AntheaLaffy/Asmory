# Releasing Asmory

Asmory uses annotated `vMAJOR.MINOR.PATCH` Git tags.

The release workflow builds and validates the project on Linux x86-64, creates
release archives, computes SHA-256 checksums, and publishes the assets to the
GitHub Release associated with the tag.

## Local release

```bash
./scripts/release.sh v0.1.0
```

The helper refuses to release from a dirty worktree and runs the full build,
registry smoke test, and CLI smoke test before creating the tag.

`make release-bundle` assembles the complete relocatable tool set under
`build/release/asmory-linux-x86_64/`, including lifecycle/model helpers, native
build/hash/publication utilities (including `asmory-sha256` and
`asmory-file-publish`) and Registry write/auth services. The release workflow archives
this directory so installed commands can locate their companion tools.
