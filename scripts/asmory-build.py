#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import tomllib

from machine_model import check_toolchain, host_facts as native_host_facts

TOOLS = Path(__file__).resolve().parent
NAME = re.compile(r"[a-z0-9][a-z0-9._-]*")
SYMBOL = re.compile(r"[A-Za-z_.$][A-Za-z0-9_.$]*")
SHA256 = re.compile(r"[0-9a-f]{64}")
VERSION = re.compile(r"[0-9]+(?:\.[0-9]+)+")
BASELINES = {f"x86-64-v{i}": i for i in range(1, 5)}


class BuildError(RuntimeError):
    pass


def companion(name: str):
    path = TOOLS / name
    if not path.is_file():
        path = TOOLS / f"{name}.py"
    loader = SourceFileLoader(name.replace("-", "_"), str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def digest(path: Path) -> str:
    result = subprocess.run(
        [str(TOOLS / "asmory-sha256"), str(path)], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
    ).stdout
    if len(result) != 65 or result[-1:] != b"\n":
        raise BuildError("invalid native SHA-256 result")
    value = result[:-1].decode("ascii")
    if SHA256.fullmatch(value) is None:
        raise BuildError("invalid native SHA-256 result")
    return value


def regular(root: Path, text: str) -> Path:
    if not isinstance(text, str) or not text or "\0" in text or "\n" in text:
        raise BuildError(f"invalid source path: {text!r}")
    rel = PurePosixPath(text)
    if rel.is_absolute() or rel.as_posix() != text or ".." in rel.parts:
        raise BuildError(f"source path must be canonical and inside its package: {text!r}")
    if not rel.parts or rel.parts[0] in (".asmory", ".git"):
        raise BuildError(f"source path points into runtime/control state: {text!r}")
    path = root
    for part in rel.parts:
        path /= part
        if path.is_symlink():
            raise BuildError(f"source path is symlinked: {path}")
    if not stat.S_ISREG(path.stat().st_mode):
        raise BuildError(f"source is not a regular file: {path}")
    return path


def load_toml(path: Path, monitor: dict | None = None) -> dict:
    if path.is_symlink() or not path.is_file():
        raise BuildError(f"manifest is missing or symlinked: {path}")
    content = path.read_bytes()
    if monitor is not None:
        monitor[path] = hashlib.sha256(content).hexdigest()
    return tomllib.loads(content.decode())


def directory(path: Path) -> None:
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        raise BuildError(f"build directory is not an ordinary directory: {path}")
    path.mkdir(exist_ok=True)


def probe(name: str) -> tuple[str, dict]:
    path = shutil.which(name)
    if path is None:
        raise BuildError(f"GNU {name} is required")
    path = str(Path(path).resolve())
    result = subprocess.run(
        [path, "--version"], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
    ).stdout
    first = result.splitlines()[0]
    version = VERSION.search(first)
    if not first.startswith("GNU ") or version is None:
        raise BuildError(f"unsupported {name} implementation: {first}")
    return path, {"path": path, "version": version.group(), "description": first}


def host_facts() -> dict:
    host = native_host_facts()
    host["features"] = sorted(host["features"])
    return host


def machine(manifest: dict, host: dict, *, package: bool) -> dict:
    target = manifest.get("target")
    if target is None and not package:
        target = {
            "arch": "x86_64", "os": "linux", "object": "elf64", "abi": "sysv64",
            "isa": {"baseline": "x86-64-v1", "required": []},
        }
    if not isinstance(target, dict):
        raise BuildError("[target] is required for a package")
    for key in ("arch", "os", "object", "abi"):
        if target.get(key) != host[key]:
            raise BuildError(f"{key} requires {target.get(key)!r}, host is {host[key]}")
    isa = target.get("isa")
    if not isinstance(isa, dict) or isa.get("baseline") not in BASELINES:
        raise BuildError("unsupported or missing ISA baseline")
    if BASELINES[isa["baseline"]] > BASELINES[host["baseline"]]:
        raise BuildError(f"ISA baseline requires {isa['baseline']}, host is {host['baseline']}")
    required = isa.get("required", [])
    if not isinstance(required, list) or not all(isinstance(x, str) for x in required):
        raise BuildError("ISA requirements must be a string array")
    missing = sorted(set(required) - set(host["features"]))
    if missing:
        raise BuildError("missing host ISA: " + ", ".join(missing))
    toolchain = manifest.get("toolchain", {} if not package else None)
    if not isinstance(toolchain, dict) or toolchain.get("assembler", None if package else "gas") != "gas":
        raise BuildError("this build adapter requires toolchain.assembler = gas")
    minimum = toolchain.get("min_version", "2.40" if not package else None)
    if not isinstance(minimum, str) or VERSION.fullmatch(minimum) is None:
        raise BuildError("invalid or missing toolchain.min_version")
    syntax = toolchain.get("syntax", "att" if not package else None)
    if syntax not in ("att", "intel"):
        raise BuildError("GAS syntax must be att or intel")
    normalized_toolchain = {"assembler": "gas", "min_version": minimum, "syntax": syntax}
    ok, reason = check_toolchain(normalized_toolchain)
    if not ok:
        raise BuildError(reason)
    return {"target": target, "toolchain": normalized_toolchain}


def variant_model(manifest: dict, root: Path, selected: str | None, monitor: dict | None = None) -> tuple[dict, str | None]:
    path = root / "variants.toml"
    if not path.exists():
        return manifest, selected
    variants = load_toml(path, monitor).get("variant")
    if not isinstance(variants, list) or not variants:
        raise BuildError("variants.toml has no Variant records")
    ids = [x.get("id") for x in variants if isinstance(x, dict)]
    if len(ids) != len(variants) or len(set(ids)) != len(ids):
        raise BuildError("invalid or duplicate Variant identities")
    selected = selected or ids[0]
    if selected not in ids:
        raise BuildError(f"locked/requested Variant has no source binding: {selected}")
    index = ids.index(selected)
    variant = variants[index]
    result = dict(manifest)
    if index == 0:
        # Inherited source still needs its declared baseline/toolchain, even if
        # a Variant record accidentally weakens those requirements.
        result["_inherited_machine"] = {key: manifest.get(key) for key in ("target", "toolchain")}
    if index:
        if not isinstance(variant.get("build"), dict) or not isinstance(variant.get("exports"), dict):
            raise BuildError(f"Variant {selected} requires explicit build.sources and exports")
        result["build"] = variant["build"]
        result["exports"] = variant["exports"]
    compat = variant.get("compatibility")
    if not isinstance(compat, dict):
        raise BuildError(f"Variant {selected} has no Machine Contract")
    result["target"] = {
        **{key: compat.get(key) for key in ("arch", "os", "object", "abi")},
        "isa": {"baseline": compat.get("baseline"), "required": compat.get("required", [])},
    }
    if variant.get("toolchain") is not None:
        result["toolchain"] = variant["toolchain"]
    return result, selected


def exports(manifest: dict, *, required: bool) -> list[dict]:
    table = manifest.get("exports", {})
    if not isinstance(table, dict) or (required and not table):
        raise BuildError("package/library exports must be declared")
    result = []
    seen = set()
    for logical, record in sorted(table.items()):
        if not isinstance(record, dict):
            raise BuildError(f"invalid export: {logical}")
        symbol, section = record.get("symbol"), record.get("section")
        if not isinstance(symbol, str) or SYMBOL.fullmatch(symbol) is None:
            raise BuildError(f"invalid export symbol: {symbol!r}")
        if symbol in seen:
            raise BuildError(f"duplicate export declaration: {symbol}")
        if not isinstance(section, str) or not section.startswith(".") or "\0" in section:
            raise BuildError(f"invalid export section: {section!r}")
        if record.get("calling_convention") != "sysv64":
            raise BuildError(f"export {symbol} requires unsupported calling convention")
        seen.add(symbol)
        result.append({"symbol": symbol, "section": section, "calling_convention": "sysv64"})
    if len(result) > 128:
        raise BuildError("at most 128 exports are supported per build unit")
    return result


def statements(text: str):
    # GAS uses ';' between statements and '#' for comments on x86. Quoted
    # filenames may contain either character, so splitting raw lines is unsafe.
    current = []
    quoted = escaped = comment = False
    for char in text + "\n":
        if comment:
            if char == "\n":
                comment = False
                yield "".join(current)
                current = []
            continue
        if char == '"' and not escaped:
            quoted = not quoted
        if char == "#" and not quoted:
            comment = True
        elif char in (";", "\n") and not quoted:
            yield "".join(current)
            current = []
        else:
            current.append(char)
        escaped = char == "\\" and not escaped


def snapshot_sources(root: Path, dest: Path, sources: list[str]) -> dict[str, str]:
    inputs = {}
    active = set()
    parsed = set()
    def copy(text: str, parse: bool) -> None:
        if text in active:
            raise BuildError(f"cyclic Assembly include: {text}")
        path = regular(root, text)
        if text not in inputs:
            target = dest / text
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            inputs[text] = digest(target)
        if not parse or text in parsed:
            return
        active.add(text)
        try:
            content = (dest / text).read_text()
            for statement in statements(content):
                statement = re.sub(r"^\s*(?:[A-Za-z0-9_.$]+:\s*)*", "", statement)
                if re.match(r"\.(include|incbin)\b", statement) is None:
                    continue
                match = re.fullmatch(r'\.(include|incbin)\s+"([^"\\]+)"\s*(,.*)?', statement.strip())
                if match is None or (match[1] == "include" and match[3]):
                    raise BuildError(f"only literal package-local includes are supported: {text}")
                copy(match[2], match[1] == "include")
        finally:
            active.remove(text)
        parsed.add(text)
    for source in sources:
        copy(source, True)
    return inputs


def write_plan(path: Path, jobs: list[tuple[Path, list[str]]]) -> None:
    data = bytearray(b"ASMBLD1\0" + struct.pack("<II", len(jobs), 0))
    for cwd, argv in jobs:
        if not 1 <= len(argv) <= 512:
            raise BuildError("native plan argument limit exceeded")
        data.extend(struct.pack("<I", len(argv)))
        for value in [str(cwd), *argv]:
            encoded = os.fsencode(value)
            if not encoded or b"\0" in encoded:
                raise BuildError("invalid native build argument")
            data.extend(encoded + b"\0")
    if not 1 <= len(jobs) <= 4096 or len(data) > 8 * 1024 * 1024:
        raise BuildError("native build plan limits exceeded")
    path.write_bytes(data)


def execute(plan: Path) -> None:
    process = subprocess.Popen(
        [str(TOOLS / "asmory-build-runner"), str(plan)], start_new_session=True,
    )
    try:
        status = process.wait(timeout=120)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise BuildError("native build interrupted or exceeded 120 seconds")
    if status:
        raise BuildError(f"native build job failed (status {status})")


def build(args) -> int:
    state = companion("asmory-state")
    if args.package:
        workspace = companion("asmory-workspace")
        root, _, packages = workspace.model(Path.cwd())
        package = workspace.find_package(packages, args.package)
        source_root = package["root"]
        dep_records = []
    else:
        root = state.workspace_root()
        source_root = root
        dep_records = state.load_lock(root).get("dependency", [])
        if args.variant:
            raise BuildError("--variant is for repository Packages; project dependencies use asm.lock")
    root = root.resolve()
    for name in (".asmory", ".asmory/build"):
        directory(root / name)
    runtime_ignore = root / ".asmory/.gitignore"
    if not runtime_ignore.exists() and not runtime_ignore.is_symlink():
        runtime_ignore.write_text("# Generated runtime state; patches remain Git-visible.\nbuild/\nworkspace.lock\n")
    ignore = root / ".asmory/build/.gitignore"
    if not ignore.exists() and not ignore.is_symlink():
        ignore.write_text("*\n")
    lock_fd = os.open(root / ".asmory/workspace.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return build_locked(args, root, source_root, dep_records, state)


def build_locked(args, root: Path, source_root: Path, dep_records: list, state) -> int:
    host = host_facts()
    tools = {name: probe(name) for name in ("as", "ld", "ar")}
    initial_metadata = {}
    manifest = load_toml(source_root / "asm.toml", initial_metadata)
    if args.package:
        package_meta = load_toml(source_root / "asmory.package.toml", initial_metadata)
        load_toml(root / "asmory.workspace.toml", initial_metadata)
        if any(manifest.get("package", {}).get(key) != package_meta.get("package", {}).get(key) for key in ("name", "version")):
            raise BuildError("source Package identity disagrees with repository member")
        if manifest.get("dependencies", {}):
            raise BuildError("repository Packages must be dependency leaves")
        manifest, selected = variant_model(manifest, source_root, args.variant, initial_metadata)
    else:
        selected = None
        if manifest.get("schema") != 1 or manifest.get("workspace", {}).get("resolver_policy") != "asmory-v1":
            raise BuildError("unsupported project manifest schema/resolver policy")
        initial_metadata[root / "asm.lock"] = digest(root / "asm.lock")
        dep_records = state.load_lock(root).get("dependency", [])
        if digest(root / "asm.lock") != initial_metadata[root / "asm.lock"]:
            raise BuildError("asm.lock changed while reading the build model")
        intents = manifest.get("dependencies", {})
        if not isinstance(intents, dict) or set(intents) != {d["name"] for d in dep_records}:
            raise BuildError("manifest dependencies disagree with asm.lock; resolve before building")
        for dep in dep_records:
            intent = ({"path": dep.get("vendor_path")} if state.dependency_source(dep) == "vendor" else dep.get("intent"))
            if intents[dep["name"]] != intent:
                raise BuildError(f"dependency intent disagrees with asm.lock: {dep['name']}")
    config = manifest.get("build", {})
    if not isinstance(config, dict):
        raise BuildError("[build] must be a table")
    kind = config.get("kind", "static-library" if args.package else "executable")
    if kind not in ("executable", "static-library") or (args.package and kind != "static-library"):
        raise BuildError("build.kind must be executable or static-library; Packages are libraries")
    name = args.package or manifest.get("package", {}).get("name", "project")
    if not isinstance(name, str) or NAME.fullmatch(name) is None:
        raise BuildError("invalid project/Package build name")
    output = config.get("output", f"lib{name}.a" if kind == "static-library" else "program")
    if not isinstance(output, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", output) is None:
        raise BuildError("build.output must be a filename, not a path")
    if output in ("build.json", "objects", "units", "closure.o", "plan.bin", "inputs"):
        raise BuildError("build.output collides with build metadata")
    entry = config.get("entry", "_start")
    if not isinstance(entry, str) or SYMBOL.fullmatch(entry) is None:
        raise BuildError("invalid executable entry symbol")
    link = manifest.get("link", {})
    if not isinstance(link, dict) or type(link.get("gc_sections", True)) is not bool:
        raise BuildError("link.gc_sections must be a boolean")
    if link.get("pic", False) is not False:
        raise BuildError("PIC/PIE builds are not supported by this adapter")
    base = root / ".asmory/build" / name
    directory(base)
    directory(base / "runs")
    current = base / "current"
    if current.exists() and not current.is_symlink():
        raise BuildError("build/current is not an Asmory generation pointer")
    if current.is_symlink() and re.fullmatch(r"runs/[0-9a-f]{64}", os.readlink(current)) is None:
        raise BuildError("build/current has a non-canonical generation target")
    stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=base))
    jobs = []
    records = []
    monitored = dict(initial_metadata)
    dependency_hashes = []
    all_exports = []
    all_objects = []
    try:
        (stage / "objects").mkdir()
        (stage / "units").mkdir()
        snapshots = stage / "inputs"
        snapshots.mkdir()
        units = []
        for dep in sorted(dep_records, key=lambda d: d["name"]):
            dep_name = dep["name"]
            if NAME.fullmatch(dep_name) is None or SHA256.fullmatch(dep.get("artifact_sha256", "")) is None:
                raise BuildError("invalid locked dependency identity")
            local = state.active_dependency_path(root, dep)
            for parent in (local, *local.parents):
                if parent == root:
                    break
                if parent.is_symlink():
                    raise BuildError(f"{dep_name}: dependency path is symlinked")
            integrity, tree = state.dependency_state(root, dep)
            if integrity not in ("Exact", "Modified") or tree is None or local.is_symlink():
                raise BuildError(f"{dep_name}: dependency is {integrity}; restore before building")
            for path in local.rglob("*"):
                if path.is_symlink() or not (path.is_file() or path.is_dir()):
                    raise BuildError(f"{dep_name}: dependency contains a link or special file")
            dest = snapshots / dep_name
            shutil.copytree(local, dest, copy_function=shutil.copy2)
            if state.tree_hash(dest) != tree:
                raise BuildError(f"{dep_name}: dependency changed while snapshotting")
            dependency_hashes.append((local, tree))
            model = load_toml(dest / "asm.toml")
            if model.get("package", {}).get("name") != dep_name or model.get("package", {}).get("version") != dep.get("release"):
                raise BuildError(f"{dep_name}: source Package identity disagrees with asm.lock")
            if model.get("dependencies", {}):
                raise BuildError(f"{dep_name}: recursive package dependencies are not supported")
            model, variant = variant_model(model, dest, dep.get("variant"))
            units.append((dep_name, model, dest, True, variant, {
                "source_kind": state.dependency_source(dep), "integrity": integrity,
                "base_artifact_sha256": dep["artifact_sha256"],
                "base_semantic_fingerprint": dep.get("semantic_fingerprint"),
                "source_tree_sha256": tree,
            }))
        project_dest = snapshots / "_project"
        project_dest.mkdir()
        units.append(("_project", manifest, project_dest, bool(args.package), selected, {}))
        aggregates = []
        for unit_name, model, dest, is_package, variant, identity in units:
            source_contract = None
            if model.get("_inherited_machine") is not None:
                source_contract = machine(model["_inherited_machine"], host, package=True)
            contract = machine(model, host, package=is_package)
            unit_build = model.get("build", {})
            sources = unit_build.get("sources", ["src/main.S"] if not is_package else None)
            if not isinstance(sources, list) or not sources or not all(isinstance(x, str) for x in sources):
                raise BuildError(f"{unit_name}: build.sources must be a non-empty string array")
            if len(set(sources)) != len(sources):
                raise BuildError(f"{unit_name}: duplicate build sources")
            if unit_name == "_project":
                inputs = snapshot_sources(source_root, dest, sources)
                monitored.update({source_root / text: sha for text, sha in inputs.items()})
            else:
                # The dependency snapshot is complete; parse every used include
                # against that same snapshot without touching the active tree.
                check_dest = snapshots / f"_check-{unit_name}"
                check_dest.mkdir()
                inputs = snapshot_sources(dest, check_dest, sources)
                shutil.rmtree(check_dest)
            exported = exports(model, required=is_package or kind == "static-library")
            if set(x["symbol"] for x in all_exports) & set(x["symbol"] for x in exported):
                raise BuildError("duplicate export symbol across direct build units")
            all_exports.extend(exported)
            objects = []
            for index, source in enumerate(sources):
                obj = stage / "objects" / f"{unit_name}-{index:04d}.o"
                # A source filename beginning with '-' must remain an operand.
                jobs.append((dest, [tools["as"][0], "--64", "./" + source, "-o", str(obj)]))
                jobs.append((dest, [str(TOOLS / "asmory-object-check"), str(obj), "object"]))
                objects.append(str(obj))
            aggregate = stage / "units" / f"{unit_name}.o"
            jobs.append((dest, [tools["ld"][0], "-m", "elf_x86_64", "-r", "-z", "noexecstack", "-o", str(aggregate), *objects]))
            if is_package:
                pairs = [value for exp in exported for value in (exp["symbol"], exp["section"])]
                jobs.append((dest, [str(TOOLS / "asmory-object-check"), str(aggregate), "leaf", *pairs]))
            aggregates.append(str(aggregate))
            all_objects.extend(objects)
            records.append({"name": unit_name, "variant": variant, **identity, **contract, "source_binding_contract": source_contract, "sources": sources, "inputs": inputs, "objects": [str(Path(x).relative_to(stage)) for x in objects], "exports": exported})
        closure = stage / "closure.o"
        jobs.append((stage, [tools["ld"][0], "-m", "elf_x86_64", "-r", "-z", "noexecstack", "-o", str(closure), *aggregates]))
        if kind == "executable":
            jobs.append((stage, [str(TOOLS / "asmory-object-check"), str(closure), "entry", entry]))
            flags = ["--gc-sections"] if link.get("gc_sections", True) else []
            jobs.append((stage, [tools["ld"][0], "-m", "elf_x86_64", "-static", "-z", "noexecstack", *flags, "-e", entry, "-o", str(stage / output), *all_objects]))
        else:
            if len(all_exports) > 128:
                raise BuildError("flattened library export limit exceeded")
            pairs = [value for exp in all_exports for value in (exp["symbol"], exp["section"])]
            jobs.append((stage, [str(TOOLS / "asmory-object-check"), str(closure), "leaf", *pairs]))
            jobs.append((stage, [tools["ar"][0], "rcsD", str(stage / output), *all_objects]))
        plan = stage / "plan.bin"
        write_plan(plan, jobs)
        execute(plan)
        for path, sha in monitored.items():
            if path.is_symlink() or digest(path) != sha:
                raise BuildError(f"build input changed during compilation: {path}")
        for path, sha in dependency_hashes:
            if state.tree_hash(path) != sha:
                raise BuildError(f"dependency changed during compilation: {path.name}")
        normalized = lambda text: str(text).replace(str(stage), "$BUILD")
        report = {
            "schema": 1, "builder_policy": "asmory-gas-build-v1", "name": name, "kind": kind,
            "output": output, "output_sha256": digest(stage / output),
            "entry": entry if kind == "executable" else None,
            "gc_sections": link.get("gc_sections", True), "host": host,
            "tools": {key: value[1] for key, value in tools.items()}, "units": records,
            "input_metadata": {str(path.relative_to(root)): sha for path, sha in initial_metadata.items()},
            "commands": [{"cwd": normalized(cwd), "argv": list(map(normalized, argv))} for cwd, argv in jobs],
        }
        payload = (json.dumps(report, sort_keys=True, indent=2) + "\n").encode()
        (stage / "build.json").write_bytes(payload)
        shutil.rmtree(snapshots)
        plan.unlink()
        run_id = hashlib.sha256(payload).hexdigest()
        final = base / "runs" / run_id
        if final.exists() or final.is_symlink():
            if final.is_symlink() or state.tree_hash(final) != state.tree_hash(stage):
                raise BuildError("existing build generation is corrupt")
        else:
            os.rename(stage, final)
        pointer_stage = Path(tempfile.mkdtemp(prefix=".select-", dir=base))
        try:
            (pointer_stage / "current").symlink_to(f"runs/{run_id}")
            os.replace(pointer_stage / "current", current)
        finally:
            shutil.rmtree(pointer_stage)
        print("Build complete")
        print(f"  kind        {kind}")
        print(f"  output      {current.relative_to(root) / output}")
        print(f"  sha256      {report['output_sha256']}")
        print(f"  record      {current.relative_to(root) / 'build.json'}")
        for record in records[:-1]:
            print(f"  dependency  {record['name']} / {record['integrity']} / {record['variant']}")
        return 0
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory build", description="Offline GAS build from locked local source")
    parser.add_argument("--package", help="build a repository workspace member as a static library")
    parser.add_argument("--variant", help="explicit source-bound repository Package Variant")
    args = parser.parse_args()
    os.environ["LC_ALL"] = "C"
    try:
        return build(args)
    except (BuildError, OSError, ValueError, TypeError, KeyError, AttributeError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"asmory build: {exc}", file=sys.stderr)
        return 25


if __name__ == "__main__":
    raise SystemExit(main())
