# Semantic Facets — Draft 0.1

Semantic Facets are the canonical compatibility model of Asmory.

Named Profiles / Contracts are optional aliases for reusable Facet bundles.

## 1. Semantic document

Conceptual example:

```toml
[semantics]
capability = "math.dot.f32"

[semantics.interface]
shape = "dot-f32-v1"

[semantics.numeric]
mode = "ieee-relaxed-reduction"
absolute_error = 1e-6
relative_error = 1e-5

[semantics.memory]
inputs = "read-only"
alignment = "arbitrary"
aliasing = "allowed"

[semantics.determinism]
level = "same-machine"
```

The final schema is intentionally not frozen by this draft.

The purpose of Draft 0.1 is to establish the model.

## 2. Requirements and guarantees

Future manifests should be able to distinguish:

```toml
[semantics.requires]
# Conditions the implementation needs from its caller.

[semantics.guarantees]
# Observable behavior the implementation promises.
```

Likewise, a consumer can express what it guarantees and what it requires.

Compatibility is directional, not merely equality.

## 3. Canonicalization

Before indexing or hashing, semantic documents must be canonicalized.

Canonicalization should eventually define:

- normalized keys;
- normalized enum spelling;
- deterministic ordering;
- explicit defaults;
- normalized numeric representation;
- versioned Facet schemas;
- validated extension namespaces.

Equivalent semantic declarations should produce the same canonical form.

## 4. Semantic fingerprint

Exact semantic shapes may use:

```text
semantic_fingerprint =
    SHA256(canonical_semantic_document)
```

The fingerprint is an identity/cache/index primitive.

It is not a replacement for directional requirement/guarantee matching.

## 5. Core Facets

Draft candidates:

```text
interface
numeric
memory
aliasing
alignment
determinism
error behavior
concurrency
side effects
```

The core set should remain intentionally small.

## 6. Extension Facets

Experimental or package-specific semantics should use namespaced extensions
instead of immediately expanding the core vocabulary.

An extension namespace is a dotted, lowercase name, normally reverse-DNS
style, so unrelated packages cannot silently claim the same meaning:

```text
org.example.audio
com.acme.json
asmory.experimental.reduction
```

Extension Facets live beside the core Facets under the directional
requirements and guarantees of the semantic document:

```toml
[semantics.requires.extensions."org.example.audio"]
denormal_policy = "preserve"

[semantics.guarantees.extensions."org.example.audio"]
denormal_policy = "flush"
```

For the common case where a package describes its own behavior, the semantic
document may use the root shorthand:

```toml
[semantics.extensions."org.example.audio"]
denormal_policy = "flush"
```

`semantics.extensions` is exactly equivalent to
`semantics.guarantees.extensions` and canonicalizes to the same form, so the
fingerprint never depends on which spelling a package chose. Declaring the
same leaf in both places with different values is rejected instead of guessed.

Extension Facets are part of semantic truth, not metadata:

- they participate in canonicalization and therefore in the Semantic
  Fingerprint;
- the registry indexes each extension leaf exactly like a core Facet, under
  its `requires.extensions.<namespace>.<path>` or
  `guarantees.extensions.<namespace>.<path>` key;
- the resolver may use a required extension as an exact prefilter, but
  directional matching remains the authority.

Matching is exact and directional:

- a consumer requirement must be guaranteed verbatim by the implementation;
- an implementation requirement must be guaranteed verbatim by the caller;
- an extension declared by only one side is not a constraint.

That last rule is deliberate. It keeps a package free to publish
implementation-specific behavior while still letting an explicit consumer
require it. Repeated community adoption can later justify promotion into a
shared core Facet or a named Profile.

## 7. Matching relations

Initial resolver relations should be limited to:

```text
exact
subset
superset
contains
minimum
maximum
range
```

No arbitrary Boolean constraint language is planned for Draft 0.1.

## 8. Profile expansion

A declaration may reference a Profile:

```toml
[semantics]
profile = "asmory/dot-core@1"
```

The resolver expands the immutable Profile into its canonical Facet bundle
before matching.

Semantic truth remains the expanded Facets, not the Profile name.
