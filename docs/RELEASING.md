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

## Maintainer remotes

The same `main` is published from two GitHub repositories:

```text
origin    git@github.com:AntheaLaffy/Asmory.git   personal development
upstream  git@github.com:Asmory/Asmory.git        public organization
```

The organization repository is the public identity. CI, Pages badges, package
`provider` fields and Registry provenance keep naming `Asmory/Asmory`; the
personal repository is an equivalent development remote and must not replace
that published identity.

`origin` is configured with two push URLs, so a normal push updates both:

```bash
# origin/main -> personal + public organization
git push
git push origin main

# explicit push to the organization repository
git push upstream main
```

Re-create that configuration in a fresh clone with:

```bash
git remote add origin git@github.com:AntheaLaffy/Asmory.git
git remote set-url --push --add origin git@github.com:Asmory/Asmory.git
git remote add upstream git@github.com:Asmory/Asmory.git
git remote -v
# origin   git@github.com:AntheaLaffy/Asmory.git (fetch)
# origin   git@github.com:AntheaLaffy/Asmory.git (push)
# origin   git@github.com:Asmory/Asmory.git (push)
# upstream git@github.com:Asmory/Asmory.git (fetch)
# upstream git@github.com:Asmory/Asmory.git (push)
```

`git fetch` still talks to the personal repository, so both remotes can be
fetched when reconciling the two.
