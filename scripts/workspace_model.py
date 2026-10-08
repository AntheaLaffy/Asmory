from __future__ import annotations

import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tomllib

from machine_model import local_tool


class WorkspaceModelError(RuntimeError):
    pass


def statements(text: str):
    """Yield TOML logical statements without confusing strings/arrays with headers."""
    start = index = depth = 0
    quote = None
    while index < len(text):
        char = text[index]
        if quote:
            if quote[0] == '"' and char == "\\":
                index += 2
                continue
            if text.startswith(quote, index):
                index += len(quote)
                quote = None
                continue
        elif char in ('"', "'"):
            quote = char * 3 if text.startswith(char * 3, index) else char
            index += len(quote)
            continue
        elif char == "#":
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
            continue
        elif char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
        if char == "\n" and quote is None and depth == 0:
            yield start, index + 1, text[start:index + 1]
            start = index + 1
        index += 1
    if start < len(text):
        yield start, len(text), text[start:]


def sections(text: str):
    result = []
    marker = "__asmory_header_probe__"
    for start, end, statement in statements(text):
        value = statement.lstrip()
        if not value.startswith("["):
            continue
        parsed = tomllib.loads(value + f"\n{marker} = 0\n")
        path = []
        array = False
        while parsed != {marker: 0}:
            if isinstance(parsed, list):
                array = True
                parsed = parsed[0]
                continue
            if not isinstance(parsed, dict) or len(parsed) != 1:
                raise WorkspaceModelError("cannot locate a TOML section unambiguously")
            key, parsed = next(iter(parsed.items()))
            path.append(key)
        result.append((tuple(path), array, start, end))
    return result


def dependency_block(text: str, package: str) -> tuple[int, int]:
    headers = sections(text)
    matches = []
    for index, (path, array, start, end) in enumerate(headers):
        if path != ("dependency",) or not array:
            continue
        stop = len(text)
        for next_path, next_array, next_start, _ in headers[index + 1:]:
            if next_path == ("dependency",) and next_array or next_path[0] != "dependency":
                stop = next_start
                break
        block = text[start:stop]
        parsed = tomllib.loads(block).get("dependency", [])
        if len(parsed) == 1 and parsed[0].get("name") == package:
            matches.append((start, stop))
    if len(matches) != 1:
        raise WorkspaceModelError(f"dependency is not uniquely recorded: {package}")
    return matches[0]


def assignment(text: str, key: str) -> tuple[int, int]:
    matches = []
    for start, end, statement in statements(text):
        if statement.lstrip().startswith(("#", "[")) or not statement.strip():
            continue
        try:
            value = tomllib.loads(statement)
        except tomllib.TOMLDecodeError:
            continue
        if set(value) == {key}:
            matches.append((start, end))
    if len(matches) != 1:
        raise WorkspaceModelError(f"cannot locate assignment uniquely: {key}")
    return matches[0]


def key_text(name: str) -> str:
    return name if re.fullmatch(r"[A-Za-z0-9_-]+", name) else json.dumps(name, ensure_ascii=False)


def set_dependency(text: str, package: str, value: str, *, replace: bool = False) -> list[tuple[int, int, str]]:
    headers = sections(text)
    matching = [(index, start, end) for index, (path, array, start, end) in enumerate(headers) if path == ("dependencies",) and not array]
    if matching:
        index, start, end = matching[0]
        stop = headers[index + 1][2] if index + 1 < len(headers) else len(text)
        entry = f"{key_text(package)} = {value}\n"
        if replace:
            first, last = assignment(text[end:stop], package)
            return [(end + first, end + last, entry)]
        prefix = "" if stop == 0 or text[stop - 1] == "\n" else "\n"
        return [(stop, stop, prefix + entry)]
    # Inline/dotted dependency declarations are valid TOML too. Replace only
    # their logical declaration when a simple root inline table was used.
    root_end = headers[0][2] if headers else len(text)
    for start, end, statement in statements(text[:root_end]):
        try:
            parsed = tomllib.loads(statement)
        except tomllib.TOMLDecodeError:
            continue
        if set(parsed) == {"dependencies"} and isinstance(parsed["dependencies"], dict):
            dependencies = parsed["dependencies"]
            dependencies[package] = tomllib.loads("value = " + value)["value"]
            entries = []
            for name, intent in dependencies.items():
                if isinstance(intent, str):
                    rendered = json.dumps(intent, ensure_ascii=False)
                elif isinstance(intent, dict) and set(intent) == {"path"} and isinstance(intent["path"], str):
                    rendered = "{ path = " + json.dumps(intent["path"], ensure_ascii=False) + " }"
                else:
                    raise WorkspaceModelError("inline dependency intent needs a supported string/path value")
                entries.append(f"{key_text(name)} = {rendered}")
            return [(start, end, "dependencies = { " + ", ".join(entries) + " }\n")]
    if replace:
        raise WorkspaceModelError(f"cannot locate manifest dependency: {package}")
    prefix = "" if text.endswith("\n") else "\n"
    return [(len(text), len(text), prefix + f"\n[dependencies]\n{key_text(package)} = {value}\n")]


def changed_text(text: str, edits: list[tuple[int, int, str]]) -> str:
    for start, end, value in sorted(edits, reverse=True):
        text = text[:start] + value + text[end:]
    return text


def apply_edits(source: Path, text: str, edits: list[tuple[int, int, str]], output: Path) -> None:
    expected = changed_text(text, edits).encode()
    current = source
    if not edits:
        edits = [(0, 1, text[:1])]
    for index, (start, end, value) in enumerate(sorted(edits, reverse=True)):
        patch = output.parent / f"{output.name}.{index}.patch"
        target = output if index == len(edits) - 1 else output.parent / f"{output.name}.{index}.part"
        patch.write_bytes(value.encode())
        subprocess.run([local_tool("asmory-text-splice"), str(current), str(len(text[:start].encode())),
                        str(len(text[start:end].encode())), str(patch), str(target)], check=True)
        patch.unlink()
        if current != source:
            current.unlink()
        current = target
    os.chmod(output, stat.S_IMODE(source.stat().st_mode))
    if output.read_bytes() != expected:
        raise WorkspaceModelError("source metadata changed during native editing")


def validate_pair(manifest: dict, lock: dict) -> dict:
    if manifest.get("schema") != 1 or manifest.get("workspace", {}).get("resolver_policy") != "asmory-v1":
        raise WorkspaceModelError("unsupported project manifest schema/policy")
    if lock.get("schema") != 1 or lock.get("resolver_policy") != "asmory-v1":
        raise WorkspaceModelError("unsupported lock schema/policy")
    entries = lock.get("dependency", [])
    if not isinstance(entries, list) or type(lock.get("dependency_count")) is not int or lock["dependency_count"] != len(entries):
        raise WorkspaceModelError("lock dependency_count disagrees with records")
    intent = manifest.get("dependencies", {})
    if not isinstance(intent, dict):
        raise WorkspaceModelError("manifest dependencies must be a table")
    seen = set()
    for entry in entries:
        name = entry.get("name") if isinstance(entry, dict) else None
        if not isinstance(name, str) or re.fullmatch(r"[a-z0-9][a-z0-9._-]*", name) is None or name in seen:
            raise WorkspaceModelError("invalid/duplicate locked dependency name")
        seen.add(name)
        expected = {"path": entry.get("vendor_path")} if entry.get("source_kind", "registry") == "vendor" else entry.get("intent")
        if entry.get("source_kind", "registry") not in ("registry", "vendor") or intent.get(name) != expected:
            raise WorkspaceModelError(f"manifest/lock dependency intent disagrees: {name}")
    return {entry["name"]: entry for entry in entries}
