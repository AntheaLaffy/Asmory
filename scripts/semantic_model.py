#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DETERMINISM_RANK = {
    "none": 0,
    "same-machine": 1,
    "cross-machine": 2,
    "bit-exact": 3,
}

# Extension Facets use a dotted, lowercase namespace so that a package can
# describe semantics the core vocabulary does not model yet without claiming
# the name globally. Reverse-DNS style (org.example.audio) mirrors how the
# ecosystem assigns unique names outside the Asmory core.
EXTENSION_NAMESPACE_RE = re.compile(
    r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?"
    r"(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+"
)

_MISSING = object()


class ExtensionFacetError(ValueError):
    """A namespaced extension Facet document is malformed or conflicting."""


def _extension_table(table: Any, where: str) -> dict[str, Any]:
    """Validate one extensions table keyed by namespace."""
    if not isinstance(table, dict):
        raise ExtensionFacetError(f"{where} must be a table")

    normalized: dict[str, Any] = {}
    for namespace in sorted(table):
        if (
            not isinstance(namespace, str)
            or EXTENSION_NAMESPACE_RE.fullmatch(namespace) is None
        ):
            raise ExtensionFacetError(
                f"{where}: extension namespace must be a dotted lowercase "
                f"name, got {namespace!r}"
            )
        facets = table[namespace]
        if not isinstance(facets, dict) or not facets:
            raise ExtensionFacetError(
                f"{where}.{namespace} must be a non-empty table"
            )
        normalized[namespace] = facets
    return normalized


def _merge_extension_tables(
    base: dict[str, Any],
    overlay: dict[str, Any],
    where: str,
) -> dict[str, Any]:
    """Merge two normalized extension tables, rejecting conflicting leaves."""
    merged = {namespace: dict(facets) for namespace, facets in base.items()}
    for namespace, facets in overlay.items():
        target = merged.setdefault(namespace, {})
        for key, value in facets.items():
            if key in target and target[key] != value:
                raise ExtensionFacetError(
                    f"{where}: conflicting extension Facet "
                    f"{namespace}.{key}"
                )
            target[key] = value
    return merged


def _normalize(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _normalize(value[k]) for k in sorted(value)}
    if isinstance(value, list):
        if all(isinstance(x, str) for x in value):
            return sorted(set(value))
        return [_normalize(x) for x in value]
    return value


def canonical_semantics(doc: dict[str, Any]) -> dict[str, Any]:
    """Return the semantic meaning only; metadata names are deliberately absent."""
    if "semantics" in doc:
        sem = deepcopy(doc["semantics"])
        capability = doc.get("profile", {}).get("capability")
    else:
        sem = {
            "interface": deepcopy(doc["interface"]),
            "requires": deepcopy(doc.get("requires", {})),
            "guarantees": deepcopy(doc.get("guarantees", {})),
        }
        # Inline manifests may also declare the root shorthand directly. Only
        # copy the key when present so extension-free documents keep their
        # existing canonical form and fingerprint.
        if "extensions" in doc:
            sem["extensions"] = deepcopy(doc["extensions"])
        capability = doc["capability"]

    if not isinstance(sem, dict):
        raise ExtensionFacetError("semantic document must be a table")

    requires = sem.get("requires") or {}
    guarantees = sem.get("guarantees") or {}
    if not isinstance(requires, dict) or not isinstance(guarantees, dict):
        raise ExtensionFacetError(
            "semantics requires/guarantees must be tables"
        )

    # `semantics.extensions` is progressive-disclosure shorthand for
    # `semantics.guarantees.extensions`. Both forms canonicalize identically so
    # the fingerprint never depends on which spelling a package chose.
    root_extensions = sem.get("extensions")
    guarantees_extensions = guarantees.get("extensions")

    if root_extensions is not None:
        root_table = _extension_table(
            root_extensions, "semantics.extensions"
        )
        if guarantees_extensions is None:
            guarantees = {**guarantees, "extensions": root_table}
        else:
            guarantees = {
                **guarantees,
                "extensions": _merge_extension_tables(
                    _extension_table(
                        guarantees_extensions,
                        "semantics.guarantees.extensions",
                    ),
                    root_table,
                    "semantics.extensions",
                ),
            }
    elif guarantees_extensions is not None:
        guarantees = {
            **guarantees,
            "extensions": _extension_table(
                guarantees_extensions,
                "semantics.guarantees.extensions",
            ),
        }

    if requires.get("extensions") is not None:
        requires = {
            **requires,
            "extensions": _extension_table(
                requires["extensions"],
                "semantics.requires.extensions",
            ),
        }

    return _normalize(
        {
            "schema": 1,
            "capability": capability,
            "interface": sem.get("interface", {}),
            "requires": requires,
            "guarantees": guarantees,
        }
    )


def canonical_bytes(doc: dict[str, Any]) -> bytes:
    return json.dumps(
        canonical_semantics(doc),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()


def fingerprint(doc: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_bytes(doc)).hexdigest()


@dataclass
class Check:
    path: str
    relation: str
    consumer: Any
    implementation: Any
    passed: bool
    explanation: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "relation": self.relation,
            "consumer": self.consumer,
            "implementation": self.implementation,
            "passed": self.passed,
            "explanation": self.explanation,
        }


def _get(d: dict[str, Any], *path: str, default=None):
    cur: Any = d
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def _extension_leaves(table: Any, prefix: str = "") -> dict[str, Any]:
    """Flatten nested extension Facet tables into dotted leaf paths."""
    leaves: dict[str, Any] = {}
    if not isinstance(table, dict):
        return leaves
    for key in sorted(table):
        value = table[key]
        path = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(value, dict):
            leaves.update(_extension_leaves(value, path))
        else:
            leaves[path] = value
    return leaves


def flatten_extension_facets(table: Any) -> dict[str, Any]:
    """Flatten one namespace's Facets into dotted leaf paths.

    The registry facet index and the resolver's exact prefilter must agree on
    this shape; expose it instead of reimplementing the walk.
    """
    return _extension_leaves(table)


def match(consumer_doc: dict[str, Any], implementation_doc: dict[str, Any]) -> dict[str, Any]:
    """
    Directional compatibility:

      consumer.guarantees  >= implementation.requires
      implementation.guarantees >= consumer.requires

    Only the small Draft-0.1 relation vocabulary is implemented.
    """
    c = canonical_semantics(consumer_doc)
    i = canonical_semantics(implementation_doc)
    checks: list[Check] = []

    def add(path, relation, cv, iv, passed, explanation):
        checks.append(Check(path, relation, cv, iv, bool(passed), explanation))

    # Capability narrows discovery first.
    add(
        "capability",
        "exact",
        c["capability"],
        i["capability"],
        c["capability"] == i["capability"],
        "Capability must match before semantic comparison.",
    )

    # Interface identity is exact in v0.1.
    for key in ("shape", "logical_export", "calling_convention"):
        cv = _get(c, "interface", key)
        iv = _get(i, "interface", key)
        if cv is not None or iv is not None:
            add(
                f"interface.{key}",
                "exact",
                cv,
                iv,
                cv == iv,
                "Interface identity uses exact matching in Draft 0.1.",
            )

    # Caller guarantee >= implementation minimum requirement.
    c_align = _get(c, "guarantees", "memory", "alignment_min_bytes", default=1)
    i_align = _get(i, "requires", "memory", "alignment_min_bytes", default=1)
    add(
        "memory.alignment_min_bytes",
        "minimum",
        c_align,
        i_align,
        c_align >= i_align,
        "Consumer alignment guarantee must be at least the implementation minimum.",
    )

    # Readability requirement.
    c_readable = _get(c, "guarantees", "memory", "inputs_readable", default=True)
    i_readable = _get(i, "requires", "memory", "inputs_readable", default=True)
    add(
        "memory.inputs_readable",
        "contains",
        c_readable,
        i_readable,
        (not i_readable) or c_readable,
        "A required caller property must be guaranteed by the consumer.",
    )

    # Observable booleans: implementation must satisfy requested exact behavior.
    for key in ("inputs_written", "out_of_bounds_access"):
        required = _get(c, "requires", "memory", key)
        provided = _get(i, "guarantees", "memory", key)
        if required is not None:
            add(
                f"memory.{key}",
                "exact",
                required,
                provided,
                required == provided,
                "Requested observable memory behavior must be provided.",
            )

    # Numeric maximum error: lower guarantee is stronger.
    for key in ("absolute_error_max", "relative_error_max"):
        required = _get(c, "requires", "numeric", key)
        provided = _get(i, "guarantees", "numeric", key)
        if required is not None:
            passed = provided is not None and provided <= required
            add(
                f"numeric.{key}",
                "maximum",
                required,
                provided,
                passed,
                "Implementation maximum error must not exceed the consumer maximum.",
            )

    # Bit-exact is a one-way strength requirement.
    required_exact = _get(c, "requires", "numeric", "bit_exact")
    provided_exact = _get(i, "guarantees", "numeric", "bit_exact")
    if required_exact is not None:
        passed = (not required_exact) or bool(provided_exact)
        add(
            "numeric.bit_exact",
            "contains",
            required_exact,
            provided_exact,
            passed,
            "bit_exact=true requires an implementation that guarantees bit exactness.",
        )

    # Determinism is an ordered minimum guarantee.
    required_det = _get(c, "requires", "determinism", "level")
    provided_det = _get(i, "guarantees", "determinism", "level")
    if required_det is not None:
        cr = DETERMINISM_RANK.get(required_det, -1)
        ir = DETERMINISM_RANK.get(provided_det, -1)
        add(
            "determinism.level",
            "minimum",
            required_det,
            provided_det,
            ir >= cr >= 0,
            "Implementation determinism must be at least the requested level.",
        )

    # Side effects: implementation effects must be a subset of what consumer allows.
    allowed = set(_get(c, "requires", "side_effects", "allowed", default=[]))
    provided = set(_get(i, "guarantees", "side_effects", "allowed", default=[]))
    add(
        "side_effects.allowed",
        "subset",
        sorted(allowed),
        sorted(provided),
        provided.issubset(allowed),
        "Implementation side effects must be a subset of consumer-allowed effects.",
    )

    # Namespaced extension Facets are matched exactly and directionally, the
    # same way as `inputs_written`: an extension required by one side must be
    # guaranteed verbatim by the other. An extension declared by only one side
    # is not a constraint, so implementations stay free to diverge until a
    # consumer actually requires the behavior.
    def extension_requirements(owner: dict, root: str) -> dict[str, Any]:
        table = _get(owner, root, "extensions", default={})
        if not isinstance(table, dict):
            return {}
        result: dict[str, Any] = {}
        for namespace in sorted(table):
            facets = table[namespace]
            if not isinstance(facets, dict):
                continue
            for path, value in _extension_leaves(facets).items():
                result[f"{namespace}.{path}"] = value
        return result

    c_requires_ext = extension_requirements(c, "requires")
    i_guarantees_ext = extension_requirements(i, "guarantees")

    for key in sorted(c_requires_ext):
        required_value = c_requires_ext[key]
        provided_value = i_guarantees_ext.get(key, _MISSING)
        add(
            f"extensions.{key}",
            "exact",
            required_value,
            None if provided_value is _MISSING else provided_value,
            provided_value is not _MISSING and provided_value == required_value,
            "A required extension Facet must be guaranteed exactly.",
        )

    i_requires_ext = extension_requirements(i, "requires")
    c_guarantees_ext = extension_requirements(c, "guarantees")

    for key in sorted(i_requires_ext):
        required_value = i_requires_ext[key]
        provided_value = c_guarantees_ext.get(key, _MISSING)
        add(
            f"extensions.{key}",
            "exact",
            required_value,
            None if provided_value is _MISSING else provided_value,
            provided_value is not _MISSING and provided_value == required_value,
            "A caller must guarantee every extension Facet the implementation "
            "requires.",
        )

    return {
        "compatible": all(x.passed for x in checks),
        "exact_semantic_identity": fingerprint(consumer_doc) == fingerprint(implementation_doc),
        "consumer_fingerprint": fingerprint(consumer_doc),
        "implementation_fingerprint": fingerprint(implementation_doc),
        "checks": [x.as_dict() for x in checks],
        "rejections": [x.as_dict() for x in checks if not x.passed],
    }
