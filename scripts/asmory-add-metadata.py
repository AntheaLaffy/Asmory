#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path
import re
import subprocess
import sys
import tomllib

from workspace_model import (
    WorkspaceModelError, apply_edits, assignment, changed_text,
    sections, set_dependency, validate_pair,
)


def read(path: Path) -> tuple[str, dict]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise WorkspaceModelError(f"metadata must be a regular file <=1 MiB: {path}")
    text = path.read_bytes().decode("utf-8")
    return text, tomllib.loads(text)


def inspect(package: str, release: str, manifest_path: Path, lock_path: Path):
    if re.fullmatch(r"[a-z0-9][a-z0-9._-]*", package) is None:
        raise WorkspaceModelError("invalid dependency name")
    manifest_text, manifest = read(manifest_path)
    lock_text, lock = read(lock_path)
    existing = validate_pair(manifest, lock)
    if package in existing:
        raise WorkspaceModelError(f"dependency already resolved; refusing replacement: {package}")
    intent = manifest.get("dependencies", {}).get(package, "*")
    if not isinstance(intent, str) or intent not in ("*", release):
        raise WorkspaceModelError(f"unsupported/unsatisfied intent for {package}: {intent!r}; use * or exact selected Release")
    return manifest_text, manifest, lock_text, lock, intent


def prepare(values: list[str]) -> None:
    if len(values) != 15:
        raise WorkspaceModelError("metadata prepare requires resolved identity, tree hash and input/output paths")
    package, release, capability, semantic, profile, provider, variant, artifact, review, safety, tree = values[:11]
    manifest_path, lock_path, new_manifest, new_lock = map(Path, values[11:])
    manifest_text, manifest, lock_text, lock, intent = inspect(package, release, manifest_path, lock_path)
    if re.fullmatch(r"[0-9a-f]{64}", tree) is None:
        raise WorkspaceModelError("invalid materialized tree hash")
    record = {
        "name": package, "intent": intent, "release": release,
        "capability": capability, "semantic_fingerprint": semantic,
        "profile": profile, "provider": provider, "variant": variant,
        "artifact_kind": "source", "artifact_sha256": artifact,
        "tree_hash_schema": "asmory-tree-v1", "materialized_tree_sha256": tree,
        "review_state": review, "registry_safety": safety,
        "materialized_path": f".asmory/deps/{package}", "source_kind": "registry",
    }
    manifest_edits = [] if package in manifest.get("dependencies", {}) else set_dependency(manifest_text, package, json.dumps(intent))
    headers = sections(lock_text)
    root_end = headers[0][2] if headers else len(lock_text)
    start, end = assignment(lock_text[:root_end], "dependency_count")
    count = lock["dependency_count"] + 1
    prefix = "" if lock_text.endswith("\n") else "\n"
    body = prefix + "\n[[dependency]]\n" + "".join(f"{key} = {json.dumps(value)}\n" for key, value in record.items())
    lock_edits = [(start, end, f"dependency_count = {count}\n"), (len(lock_text), len(lock_text), body)]
    expected_manifest = copy.deepcopy(manifest)
    expected_manifest.setdefault("dependencies", {})[package] = intent
    expected_lock = copy.deepcopy(lock)
    expected_lock["dependency_count"] = count
    expected_lock.setdefault("dependency", []).append(record)
    predicted_manifest = changed_text(manifest_text, manifest_edits)
    predicted_lock = changed_text(lock_text, lock_edits)
    if tomllib.loads(predicted_manifest) != expected_manifest or tomllib.loads(predicted_lock) != expected_lock:
        raise WorkspaceModelError("metadata edit would change unrelated intent/resolution")
    validate_pair(expected_manifest, expected_lock)
    apply_edits(manifest_path, manifest_text, manifest_edits, new_manifest)
    apply_edits(lock_path, lock_text, lock_edits, new_lock)


def main() -> int:
    try:
        if len(sys.argv) == 6 and sys.argv[1] == "check":
            inspect(sys.argv[2], sys.argv[3], Path(sys.argv[4]), Path(sys.argv[5]))
        elif len(sys.argv) > 1 and sys.argv[1] == "prepare":
            prepare(sys.argv[2:])
        else:
            raise WorkspaceModelError("usage: asmory-add-metadata check|prepare ...")
        return 0
    except (WorkspaceModelError, OSError, ValueError, TypeError, AttributeError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"add: {exc}", file=sys.stderr)
        return 15


if __name__ == "__main__":
    raise SystemExit(main())
