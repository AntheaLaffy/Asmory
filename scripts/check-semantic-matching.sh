#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from copy import deepcopy
from pathlib import Path
import sys
import tomllib

sys.path.insert(0, str(Path("scripts").resolve()))
from semantic_model import (
    ExtensionFacetError,
    canonical_semantics,
    fingerprint,
    flatten_extension_facets,
    match,
)

impl = tomllib.loads(Path("examples/simd-dot/semantics.toml").read_text())
core = tomllib.loads(Path("examples/simd-dot/profiles/core-v1.toml").read_text())
strict = tomllib.loads(Path("examples/simd-dot/profiles/strict-v1.toml").read_text())

m = match(core, impl)
assert m["compatible"]
assert m["exact_semantic_identity"]

m = match(strict, impl)
assert not m["compatible"]
paths = {x["path"] for x in m["rejections"]}
assert "numeric.bit_exact" in paths
assert "numeric.absolute_error_max" in paths
assert "determinism.level" in paths

# Directional alignment:
# A consumer promising 64-byte alignment satisfies an implementation requiring 32.
impl32 = deepcopy(impl)
impl32["requires"]["memory"]["alignment_min_bytes"] = 32
consumer64 = deepcopy(core)
consumer64["semantics"]["guarantees"]["memory"]["alignment_min_bytes"] = 64
assert match(consumer64, impl32)["compatible"]

# But a caller promising only byte alignment cannot satisfy the same implementation.
consumer1 = deepcopy(core)
consumer1["semantics"]["guarantees"]["memory"]["alignment_min_bytes"] = 1
assert not match(consumer1, impl32)["compatible"]

# Stronger numeric guarantee satisfies a looser consumer maximum.
consumer_loose = deepcopy(core)
consumer_loose["semantics"]["requires"] = {
    "numeric": {
        "absolute_error_max": 0.0001,
        "relative_error_max": 0.001,
        "bit_exact": False,
    },
    "side_effects": {"allowed": []},
}
assert match(consumer_loose, impl)["compatible"]

# A tighter maximum than the implementation promises is rejected.
consumer_tight = deepcopy(core)
consumer_tight["semantics"]["requires"] = {
    "numeric": {
        "absolute_error_max": 0.0000001,
        "relative_error_max": 0.000001,
        "bit_exact": False,
    },
    "side_effects": {"allowed": []},
}
assert not match(consumer_tight, impl)["compatible"]

print("semantic-matching: ok")
print("  exact fingerprint identity: pass")
print("  minimum relation:            pass")
print("  maximum relation:            pass")
print("  subset relation:             pass")
print("  semantic alternative reject: pass")

# --- Namespaced extension Facets -------------------------------------------
# Package-specific semantics live in namespaced extension Facets until the
# core vocabulary earns a shared Facet. They are exact and directional, so
# innovation stays free until a consumer actually requires the behavior.

ext_guarantee = {"org.example.audio": {"denormal_policy": "flush"}}

ext_impl = deepcopy(impl)
ext_impl["guarantees"]["extensions"] = deepcopy(ext_guarantee)

ext_consumer = deepcopy(core)
ext_consumer["semantics"]["requires"]["extensions"] = deepcopy(ext_guarantee)

# The root shorthand and the directional guarantee are the same semantics.
root_form = deepcopy(ext_impl)
del root_form["guarantees"]["extensions"]
root_form["extensions"] = deepcopy(ext_guarantee)
assert fingerprint(root_form) == fingerprint(ext_impl)
assert canonical_semantics(root_form) == canonical_semantics(ext_impl)

# A required extension must be guaranteed exactly.
assert match(ext_consumer, ext_impl)["compatible"]

wrong = deepcopy(ext_impl)
wrong_audio = wrong["guarantees"]["extensions"]["org.example.audio"]
wrong_audio["denormal_policy"] = "preserve"
wrong_match = match(ext_consumer, wrong)
assert not wrong_match["compatible"]
assert "extensions.org.example.audio.denormal_policy" in {
    x["path"] for x in wrong_match["rejections"]
}

missing = deepcopy(impl)
missing_match = match(ext_consumer, missing)
assert not missing_match["compatible"]
assert "extensions.org.example.audio.denormal_policy" in {
    x["path"] for x in missing_match["rejections"]
}

# A declared extension that no consumer requires does not constrain anything.
assert match(core, wrong)["compatible"]

# The reverse direction: caller guarantees what the implementation requires.
impl_needs = deepcopy(impl)
impl_needs["requires"]["extensions"] = deepcopy(ext_guarantee)
consumer_provides = deepcopy(core)
consumer_provides["semantics"]["guarantees"]["extensions"] = deepcopy(
    ext_guarantee
)
assert match(consumer_provides, impl_needs)["compatible"]
assert not match(core, impl_needs)["compatible"]

# The resolver's exact prefilter must name the guarantee it needs.
assert flatten_extension_facets(ext_guarantee["org.example.audio"]) == {
    "denormal_policy": "flush"
}

# Malformed or ambiguous declarations fail closed.
for label, broken in (
    (
        "invalid namespace",
        {
            "semantics": {
                "capability": "math.dot.f32",
                "extensions": {"Audio": {}},
            }
        },
    ),
    (
        "conflicting declaration",
        {
            "semantics": {
                "capability": "math.dot.f32",
                "extensions": ext_guarantee,
                "guarantees": {"extensions": {
                    "org.example.audio": {"denormal_policy": "preserve"}
                }},
            }
        },
    ),
):
    try:
        canonical_semantics(broken)
    except ExtensionFacetError:
        pass
    else:
        raise SystemExit(f"extension Facets: {label} was not rejected")

print("extension Facet namespace:  pass")
print("extension exact matching:   pass")
print("extension free divergence:  pass")
print("extension fail-closed:      pass")
PY
