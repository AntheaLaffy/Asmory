from __future__ import annotations

from functools import lru_cache
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess

BASELINES = {f"x86-64-v{level}": level for level in range(1, 5)}


class MachineError(RuntimeError):
    pass


def local_tool(name: str) -> str:
    directory = Path(__file__).resolve().parent
    candidates = [directory / name]
    if directory.name == "scripts":
        candidates.append(directory.parent / "build" / name)
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    found = shutil.which(name)
    if found is None:
        raise MachineError(f"local backend unavailable: {name}")
    return str(Path(found).resolve())


def host_facts() -> dict:
    try:
        text = subprocess.run(
            [local_tool("asmory"), "target"], check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        ).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        raise MachineError(f"cannot read native host target: {exc}") from exc
    host = {"features": set()}
    for line in text.splitlines():
        match = re.fullmatch(r"  (arch|os|object|abi|baseline)\s+(\S+)", line)
        if match:
            host[match[1]] = match[2]
        match = re.fullmatch(r"    ([A-Za-z0-9._+-]+)\s+yes", line)
        if match:
            host["features"].add(match[1].lower())
    missing = [key for key in ("arch", "os", "object", "abi", "baseline") if key not in host]
    if missing:
        raise MachineError("cannot parse native host target: " + ", ".join(missing))
    return host


@lru_cache(maxsize=128)
def _toolchain_check(backend: str, assembler: str, minimum: str, syntax: str, path: str | None) -> tuple[bool, str]:
    # The native backend supplies bounded capture, numeric version comparison,
    # target validation and child cleanup. Cache only within this command and
    # PATH; no persisted compiler-availability claim can become stale.
    del path
    try:
        process = subprocess.Popen(
            [backend, assembler, minimum, syntax], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
        )
    except OSError as exc:
        return False, f"toolchain backend failed: {exc}"
    try:
        _, error = process.communicate(timeout=7)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdout.close()
        process.stderr.close()
        return False, "toolchain probe timed out"
    if process.returncode:
        return False, error.strip() or "toolchain probe failed"
    return True, "compatible"


def check_toolchain(toolchain: dict | None) -> tuple[bool, str]:
    if not isinstance(toolchain, dict):
        return False, "Variant toolchain metadata missing"
    values = [toolchain.get(key) for key in ("assembler", "min_version", "syntax")]
    if not all(isinstance(value, str) and value and "\0" not in value for value in values):
        return False, "Variant toolchain metadata invalid"
    try:
        backend = local_tool("asmory-toolchain-check")
    except MachineError as exc:
        return False, str(exc)
    return _toolchain_check(backend, *values, os.environ.get("PATH"))


def compatible_variant(variant: dict, host: dict) -> tuple[bool, str]:
    target = variant.get("target")
    if not isinstance(target, dict):
        return False, "Variant target metadata missing"
    for key in ("arch", "os", "object", "abi"):
        required = target.get(key)
        if required != host.get(key):
            return False, f"{key} requires {required}, host is {host.get(key)}"
    isa = target.get("isa")
    if not isinstance(isa, dict):
        return False, "Variant ISA metadata missing"
    baseline, actual = isa.get("baseline"), host.get("baseline")
    if baseline not in BASELINES or actual not in BASELINES:
        return False, "unsupported ISA baseline"
    if BASELINES[baseline] > BASELINES[actual]:
        return False, f"baseline requires {baseline}, host is {actual}"
    required = isa.get("required", [])
    if not isinstance(required, list) or not all(isinstance(x, str) and x for x in required):
        return False, "Variant required ISA list invalid"
    missing = sorted({x.lower() for x in required} - set(host.get("features", [])))
    if missing:
        return False, "missing ISA: " + ", ".join(missing)
    exports = variant.get("exports")
    if not isinstance(exports, list) or not exports:
        return False, "Variant export metadata missing"
    for export in exports:
        if not isinstance(export, dict) or export.get("calling_convention") != target["abi"]:
            return False, "export calling convention disagrees with target ABI"
    return check_toolchain(variant.get("toolchain"))
