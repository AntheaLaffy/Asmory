#!/usr/bin/env bash
set -euo pipefail
ROOT="${ASMORY_ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
export PATH="$ROOT/build:$PATH"
export ASMORY_REGISTRY_URL="http://127.0.0.1:1"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import copy
import hashlib
import os
import subprocess
import sys
import tarfile
import tempfile
import tomllib

root = Path(sys.argv[1])
binary = root / "build/asmory"
adder = root / "build/asmory-add"
splice = root / "build/asmory-text-splice"

def call(argv, cwd, status=0):
    result = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, text=True, timeout=30)
    assert result.returncode == status, (argv, result.returncode, result.stdout, result.stderr)
    return result

with tempfile.TemporaryDirectory(prefix="asmory-multi-add-") as temp:
    base = Path(temp)
    os.environ["ASMORY_CACHE_HOME"] = str(base / "cache")
    cache = base / "cache/objects/sha256"
    cache.mkdir(parents=True)
    identities = {}
    for name, symbol, value in (("leaf.one", "leaf_one", 42), ("leaf-two", "leaf_two", 7), ("leaf-three", "leaf_three", 3)):
        package = base / name
        (package / "src").mkdir(parents=True)
        (package / "asm.toml").write_text(f'''[package]
name = "{name}"
version = "0.1.0"
[target]
arch = "x86_64"
os = "linux"
object = "elf64"
abi = "sysv64"
[target.isa]
baseline = "x86-64-v1"
required = []
[toolchain]
assembler = "gas"
min_version = "2.40"
syntax = "att"
[build]
sources = ["src/leaf.S"]
[exports.leaf]
symbol = "{symbol}"
section = ".text.{symbol}"
calling_convention = "sysv64"
''')
        (package / "src/leaf.S").write_text(f'.section .text.{symbol},"ax",@progbits\n.global {symbol}\n{symbol}: mov ${value}, %eax; ret\n.section .note.GNU-stack,"",@progbits\n')
        archive = base / f"{name}.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(package, arcname=name)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (cache / digest).write_bytes(archive.read_bytes())
        (cache / digest).chmod(0o444)
        identities[name] = digest

    def add(name, project, status=0):
        return call([adder, name, "0.1.0", "test.leaf", "a" * 64,
                     "asmory/test-leaf@1.0.0", "Asmory/Tests", "x86_64-v1-default",
                     identities[name], "unreviewed", "normal"], project, status)

    print("== byte-range editing is bounded and never overwrites output ==", flush=True)
    original = base / "original"; original.write_bytes("前缀abcdef".encode())
    patch = base / "patch"; patch.write_bytes(b"XY")
    output = base / "output"
    call([splice, original, "6", "2", patch, output], base)
    assert output.read_bytes() == "前缀XYcdef".encode()
    call([splice, original, "0", "0", patch, output], base, 27)
    assert output.read_bytes() == "前缀XYcdef".encode()
    call([splice, original, "999", "0", patch, base / "outside"], base, 27)
    assert not (base / "outside").exists()

    print("== independent leaf additions preserve configuration and Modified source ==", flush=True)
    project = base / "project"; project.mkdir()
    call([binary, "init"], project)
    manifest = project / "asm.toml"
    manifest.write_text(manifest.read_text() + '''
[build]
sources = ["src/main.S"]
output = "demo"
[notes]
message = """保留用户配置
[dependencies]
dependency_count = 99
"""
''')
    before = tomllib.loads(manifest.read_text())
    add("leaf.one", project)
    first_record = copy.deepcopy(tomllib.loads((project / "asm.lock").read_text())["dependency"][0])
    local = project / ".asmory/deps/leaf.one/src/leaf.S"
    local.write_text(local.read_text() + "\n# local experiment\n")
    changed = local.read_bytes()
    add("leaf-two", project)
    lock = tomllib.loads((project / "asm.lock").read_text())
    assert lock["dependency_count"] == 2 and lock["dependency"][0] == first_record
    assert local.read_bytes() == changed
    current = tomllib.loads(manifest.read_text())
    before["dependencies"] = {"leaf.one": "*", "leaf-two": "*"}
    assert current == before
    assert '"leaf.one" = "*"' in manifest.read_text()
    (project / "src").mkdir()
    (project / "src/main.S").write_text('''.section .text._start,"ax",@progbits
.global _start
_start:
    call leaf_one
    mov %eax, %ebx
    call leaf_two
    add %ebx, %eax
    cmp $49, %eax
    setne %dil
    movzbl %dil, %edi
    mov $60, %eax
    syscall
.section .note.GNU-stack,"",@progbits
''')
    call([binary, "build"], project)
    call([project / ".asmory/build/project/current/demo"], project)
    status = call([binary, "status"], project).stdout
    assert "Modified" in status and "leaf.one" in status and "leaf-two" in status

    print("== vendor targets one record in a multi-dependency lock ==", flush=True)
    second = copy.deepcopy(lock["dependency"][1])
    call([binary, "vendor", "leaf.one"], project)
    lock = tomllib.loads((project / "asm.lock").read_text())
    assert lock["dependency"][1] == second
    assert lock["dependency"][0]["source_kind"] == "vendor"
    assert tomllib.loads(manifest.read_text())["dependencies"]["leaf.one"] == {"path": "vendor/leaf.one"}
    vendor = project / "vendor/leaf.one/src/leaf.S"
    assert vendor.read_bytes() == changed
    add("leaf-three", project)
    assert vendor.read_bytes() == changed
    assert tomllib.loads((project / "asm.lock").read_text())["dependency_count"] == 3
    call([binary, "build"], project)
    call([project / ".asmory/build/project/current/demo"], project)
    manifest_bytes, lock_bytes = manifest.read_bytes(), (project / "asm.lock").read_bytes()
    add("leaf-two", project, 15)
    assert manifest.read_bytes() == manifest_bytes and (project / "asm.lock").read_bytes() == lock_bytes

    print("== inline intent, exact predeclared Release and empty materialization failure ==", flush=True)
    inline = base / "inline"; inline.mkdir(); call([binary, "init"], inline)
    (inline / "asm.toml").write_text('schema = 1\ndependencies = {}\n[workspace]\nresolver_policy = "asmory-v1"\n')
    add("leaf.one", inline); add("leaf-two", inline)
    assert set(tomllib.loads((inline / "asm.toml").read_text())["dependencies"]) == {"leaf.one", "leaf-two"}
    exact = base / "exact"; exact.mkdir(); call([binary, "init"], exact)
    exact_manifest = exact / "asm.toml"
    exact_manifest.write_text(exact_manifest.read_text() + '"leaf.one" = "0.1.0"\n')
    previous = exact_manifest.read_bytes()
    add("leaf.one", exact)
    assert exact_manifest.read_bytes() == previous
    call([binary, "vendor", "leaf.one"], exact)
    for name, expected in identities.items():
        assert hashlib.sha256((cache / expected).read_bytes()).hexdigest() == expected

print("multi-add-smoke: ok")
PY
