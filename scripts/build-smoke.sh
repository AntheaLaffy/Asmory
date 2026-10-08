#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
BIN="$ROOT/build/asmory"
# The literal dollar/semicolon filename exercises operand handling without a shell.
# shellcheck disable=SC2016
main_source='src/main ; $literal.S'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PATH="$ROOT/build:$PATH"
export ASMORY_CACHE_HOME="$tmp/cache"
export ASMORY_REGISTRY_URL="http://127.0.0.1:1"

expect_failure() {
  if "$@" >"$tmp/failure.out" 2>&1; then
    echo "build-smoke: unexpected success: $*" >&2
    exit 1
  fi
  cat "$tmp/failure.out"
}

echo '== native ELF bounds, contracts and plan validation =='
python3 - "$ROOT" "$tmp" <<'PY'
from pathlib import Path
import struct
import subprocess
import sys

root, temp = map(Path, sys.argv[1:])
checker = root / "build/asmory-object-check"
runner = root / "build/asmory-build-runner"
obj = root / "build/examples/simd-dot/dot.o"

def call(argv, status):
    result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=5)
    assert result.returncode == status, (argv, result.returncode, result.stderr)

call([checker, obj, "leaf", "simd_dot_f32", ".text.simd_dot_f32"], 0)
call([checker, obj, "leaf", "missing_symbol", ".text.simd_dot_f32"], 25)
call([checker, obj, "leaf", "simd_dot_f32", ".text.wrong"], 25)
content = obj.read_bytes()
bad = temp / "bad.o"
for length in (0, 1, 63, len(content) - 1):
    bad.write_bytes(content[:length])
    call([checker, bad, "object"], 25)
for offset, value in ((4, b"\x01"), (5, b"\x02"), (18, b"\x03\x00"),
                      (40, b"\xff" * 8), (58, b"\x01\x00"),
                      (60, b"\x00\x00"), (62, b"\xff\xff")):
    changed = bytearray(content)
    changed[offset:offset + len(value)] = value
    bad.write_bytes(changed)
    call([checker, bad, "object"], 25)
section_offset = struct.unpack_from("<Q", content, 40)[0]
count = struct.unpack_from("<H", content, 60)[0]
for index in range(count):
    changed = bytearray(content)
    struct.pack_into("<I", changed, section_offset + index * 64, 0xffffffff)
    bad.write_bytes(changed)
    call([checker, bad, "object"], 25)

sentinel = temp / "must not exist"
touch = Path("/usr/bin/touch")
assert touch.is_file()
def job(argv):
    return struct.pack("<I", len(argv)) + str(temp).encode() + b"\0" + b"".join(str(a).encode() + b"\0" for a in argv)
first = job([touch, sentinel])
plan = temp / "plan.bin"
header = b"ASMBLD1\0" + struct.pack("<II", 2, 0)
for suffix in (b"", struct.pack("<I", 513), job([touch, sentinel]) + b"trailing"):
    plan.write_bytes(header + first + suffix)
    call([runner, plan], 25)
    assert not sentinel.exists(), "a malformed late job ran an earlier command"
plan.write_bytes(header + job(["/usr/bin/false"]) + first)
call([runner, plan], 1)
assert not sentinel.exists(), "runner continued after failure"
plan.write_bytes(b"ASMBLD1\0" + struct.pack("<II", 1, 0) + first)
call([runner, plan], 0)
assert sentinel.is_file()
PY

echo '== offline executable, includes, GC and stable generation =='
mkdir -p "$tmp/project with spaces/src" "$tmp/project with spaces/include"
cd "$tmp/project with spaces"
"$BIN" init >/dev/null
cat >>asm.toml <<'TOML'

[build]
sources = ["src/main ; $literal.S"]
output = "demo"
TOML
cat >include/exit.inc <<'ASM'
.equ success, 0
ASM
cat >"$main_source" <<'ASM'
.include "include/exit.inc"
.section .text._start,"ax",@progbits
.global _start
_start:
    mov $60, %eax
    mov $success, %edi
    syscall
.section .text.unused,"ax",@progbits
.global unused_function
unused_function:
    ret
.section .note.GNU-stack,"",@progbits
ASM
"$BIN" build
.asmory/build/project/current/demo
if nm .asmory/build/project/current/demo | rg 'unused_function' >/dev/null; then
  echo 'build-smoke: section GC did not remove an unused function' >&2
  exit 1
fi
generation="$(readlink .asmory/build/project/current)"
hash="$(sha256sum .asmory/build/project/current/demo)"
"$BIN" build >/dev/null
[[ "$(readlink .asmory/build/project/current)" == "$generation" ]]
[[ "$(sha256sum .asmory/build/project/current/demo)" == "$hash" ]]
[[ ! -e src/main ]]

echo '== failed compilation, entry, include and toolchain preserve success =='
cp "$main_source" "$tmp/main.S"
printf '\ninvalid_assembly_instruction\n' >>"$main_source"
expect_failure "$BIN" build
[[ "$(readlink .asmory/build/project/current)" == "$generation" ]]
cp "$tmp/main.S" "$main_source"
cp asm.toml "$tmp/project.toml"
printf '\nentry = "missing_entry"\n' >>asm.toml
expect_failure "$BIN" build
rg -q 'entry must be' "$tmp/failure.out"
cp "$tmp/project.toml" asm.toml
printf '\n.include "../outside.inc"\n' >>"$main_source"
expect_failure "$BIN" build
rg -q 'inside its package' "$tmp/failure.out"
cp "$tmp/main.S" "$main_source"
printf '\n.include "include/link.inc"\n' >>"$main_source"
ln -s "$tmp/main.S" include/link.inc
expect_failure "$BIN" build
rg -q 'symlinked' "$tmp/failure.out"
cp "$tmp/main.S" "$main_source"
printf '\n[toolchain]\nassembler = "gas"\nmin_version = "999.0"\n' >>asm.toml
expect_failure "$BIN" build
rg -q 'requires 999.0' "$tmp/failure.out"
cp "$tmp/project.toml" asm.toml
printf '\n[target]\narch = "aarch64"\n' >>asm.toml
expect_failure "$BIN" build
rg -q 'arch requires' "$tmp/failure.out"
cp "$tmp/project.toml" asm.toml
[[ "$(readlink .asmory/build/project/current)" == "$generation" ]]
[[ "$(sha256sum .asmory/build/project/current/demo)" == "$hash" ]]

echo '== a source filename beginning with a dash remains a file operand =='
cp -- "$tmp/main.S" -entry.S
python3 - <<'PY'
from pathlib import Path
p = Path("asm.toml")
p.write_text(p.read_text().replace("src/main ; $literal.S", "-entry.S"))
PY
"$BIN" build >/dev/null
.asmory/build/project/current/demo
cp "$tmp/project.toml" asm.toml
"$BIN" build >/dev/null
[[ "$(readlink .asmory/build/project/current)" == "$generation" ]]

echo '== concurrent input edit is refused before selecting an output =='
mkdir "$tmp/assembler-shim"
cat >"$tmp/assembler-shim/as" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != --version ]]; then
  printf '\n# concurrent source edit\n' >>"$ASMORY_TEST_ACTIVE_INPUT"
fi
exec "$ASMORY_TEST_REAL_AS" "$@"
SH
chmod 0755 "$tmp/assembler-shim/as"
ASMORY_TEST_REAL_AS="$(command -v as)"
export ASMORY_TEST_REAL_AS
export ASMORY_TEST_ACTIVE_INPUT="$PWD/src/main ; \$literal.S"
expect_failure env PATH="$tmp/assembler-shim:$PATH" "$BIN" build
rg -q 'input changed during compilation' "$tmp/failure.out"
cp "$tmp/main.S" "$main_source"
unset ASMORY_TEST_REAL_AS ASMORY_TEST_ACTIVE_INPUT
[[ "$(readlink .asmory/build/project/current)" == "$generation" ]]

echo '== relocated release bundle finds companions without build PATH =='
cp -a "$ROOT/build/release/asmory-linux-x86_64" "$tmp/relocated tools"
env PATH=/usr/bin:/bin "$tmp/relocated tools/asmory" build >/dev/null
python3 - .asmory/build/project/current <<'PY'
import hashlib
import json
from pathlib import Path
import sys

current = Path(sys.argv[1])
record = json.loads((current / "build.json").read_text())
assert record["output_sha256"] == hashlib.sha256((current / record["output"]).read_bytes()).hexdigest()
PY
selected="$(readlink .asmory/build/project/current)"
mv "$tmp/relocated tools/asmory-sha256" "$tmp/hash companion"
expect_failure env PATH=/usr/bin:/bin "$tmp/relocated tools/asmory" build
[[ "$(readlink .asmory/build/project/current)" == "$selected" ]]
mv "$tmp/hash companion" "$tmp/relocated tools/asmory-sha256"
.asmory/build/project/current/demo

echo '== deterministic multi-source static library and actual consumer =='
mkdir -p "$tmp/library/src"
cd "$tmp/library"
"$BIN" init >/dev/null
cat >>asm.toml <<'TOML'

[build]
kind = "static-library"
sources = ["src/leaf.S", "src/internal.S"]

[exports.leaf]
symbol = "leaf"
section = ".text.leaf"
calling_convention = "sysv64"
TOML
cat >src/leaf.S <<'ASM'
.section .text.leaf,"ax",@progbits
.global leaf
leaf:
    jmp internal_helper
.section .note.GNU-stack,"",@progbits
ASM
cat >src/internal.S <<'ASM'
.section .text.internal_helper,"ax",@progbits
.global internal_helper
.hidden internal_helper
internal_helper:
    mov $42, %eax
    ret
.section .note.GNU-stack,"",@progbits
ASM
"$BIN" build >/dev/null
archive="$PWD/.asmory/build/project/current/libproject.a"
archive_hash="$(sha256sum "$archive")"
"$BIN" build >/dev/null
[[ "$(sha256sum "$archive")" == "$archive_hash" ]]
cat >"$tmp/consumer.S" <<'ASM'
.global _start
.section .text._start,"ax",@progbits
_start:
    call leaf
    cmp $42, %eax
    setne %dil
    movzbl %dil, %edi
    mov $60, %eax
    syscall
.section .note.GNU-stack,"",@progbits
ASM
as --64 "$tmp/consumer.S" -o "$tmp/consumer.o"
ld -static -z noexecstack --gc-sections "$tmp/consumer.o" "$archive" -o "$tmp/consumer"
"$tmp/consumer"
cp src/leaf.S "$tmp/leaf.S"
printf '\n.global undeclared\n.section .text.undeclared,"ax"\nundeclared: ret\n' >>src/leaf.S
expect_failure "$BIN" build
rg -q 'export symbol/section' "$tmp/failure.out"
cp "$tmp/leaf.S" src/leaf.S
printf '\n.section .text.external,"ax"\n.hidden external_call\n.global external_call\nexternal_call: jmp undeclared_dependency\n' >>src/leaf.S
expect_failure "$BIN" build
rg -q 'undefined external' "$tmp/failure.out"
[[ "$(sha256sum "$archive")" == "$archive_hash" ]]

echo '== repository package and explicit Variant source binding =='
mkdir -p "$tmp/repository/packages/leaf/src"
cd "$tmp/repository"
cat >asmory.workspace.toml <<'TOML'
schema = 1
[workspace]
repository = "https://example.invalid/leaf"
members = ["packages/leaf"]
TOML
cat >packages/leaf/asmory.package.toml <<'TOML'
schema = 1
[package]
name = "leaf"
version = "0.1.0"
TOML
cat >packages/leaf/asm.toml <<'TOML'
[package]
name = "leaf"
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
sources = ["src/default.S"]
[exports.leaf]
symbol = "leaf"
section = ".text.leaf"
calling_convention = "sysv64"
TOML
cp "$tmp/leaf.S" packages/leaf/src/default.S
sed -i '/^\.section \.note.GNU-stack/d' packages/leaf/src/default.S
cp "$tmp/library/src/internal.S" packages/leaf/src/internal.S
printf '\n.include "src/internal.S"\n' >>packages/leaf/src/default.S
cat >packages/leaf/src/alternative.S <<'ASM'
.section .text.alternative,"ax",@progbits
.global alternative
alternative: mov $43, %eax; ret
.section .note.GNU-stack,"",@progbits
ASM
cat >packages/leaf/variants.toml <<'TOML'
[[variant]]
id = "default"
[variant.compatibility]
arch = "x86_64"
os = "linux"
object = "elf64"
abi = "sysv64"
baseline = "x86-64-v1"
required = []
[variant.toolchain]
assembler = "gas"
min_version = "2.40"
syntax = "att"
[[variant]]
id = "alternative"
[variant.compatibility]
arch = "x86_64"
os = "linux"
object = "elf64"
abi = "sysv64"
baseline = "x86-64-v1"
required = []
[variant.build]
sources = ["src/alternative.S"]
[variant.exports.alternative]
symbol = "alternative"
section = ".text.alternative"
calling_convention = "sysv64"
TOML
"$BIN" build --package leaf >/dev/null
nm .asmory/build/leaf/current/libleaf.a | rg ' T leaf$' >/dev/null
"$BIN" build --package leaf --variant alternative >/dev/null
nm .asmory/build/leaf/current/libleaf.a | rg ' T alternative$' >/dev/null
expect_failure "$BIN" build --package leaf --variant unknown
rg -q 'no source binding' "$tmp/failure.out"

echo '== inherited source constraints cannot be weakened by Variant metadata =='
cp packages/leaf/asm.toml "$tmp/package.toml"
sed -i 's/min_version = "2.40"/min_version = "999.0"/' packages/leaf/asm.toml
expect_failure "$BIN" build --package leaf
rg -q 'requires 999.0' "$tmp/failure.out"
cp "$tmp/package.toml" packages/leaf/asm.toml
sed -i 's/required = \[\]/required = ["asmory-unavailable-feature"]/' packages/leaf/asm.toml
expect_failure "$BIN" build --package leaf
rg -q 'missing host ISA' "$tmp/failure.out"
cp "$tmp/package.toml" packages/leaf/asm.toml

echo '== locked offline dependency, Modified provenance and vendor =='
if "$BIN" resolve simd-dot >/dev/null 2>&1; then
  sha="$(sha256sum "$ROOT/build/packages/simd-dot-0.1.0.tar.gz" | cut -d' ' -f1)"
  mkdir -p "$ASMORY_CACHE_HOME/objects/sha256" "$tmp/dependency-project/src"
  cp "$ROOT/build/packages/simd-dot-0.1.0.tar.gz" "$ASMORY_CACHE_HOME/objects/sha256/$sha"
  chmod 0444 "$ASMORY_CACHE_HOME/objects/sha256/$sha"
  cd "$tmp/dependency-project"
  "$BIN" init >/dev/null
  "$BIN" add simd-dot >/dev/null
  cat >>asm.toml <<'TOML'

[build]
sources = ["src/main.S"]
TOML
  cat >src/main.S <<'ASM'
.global _start
.section .text._start,"ax",@progbits
_start:
    lea a(%rip), %rdi
    lea b(%rip), %rsi
    mov $1, %edx
    call simd_dot_f32
    ucomiss expected(%rip), %xmm0
    setne %dil
    movzbl %dil, %edi
    mov $60, %eax
    syscall
.section .rodata,"a",@progbits
a: .float 3.0
b: .float 7.0
expected: .float 21.0
.section .note.GNU-stack,"",@progbits
ASM
  "$BIN" build
  .asmory/build/project/current/program
  printf '\n# local experiment\n' >>.asmory/deps/simd-dot/src/dot.S
  "$BIN" build >/dev/null
  python3 - .asmory/build/project/current/build.json "$sha" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
dep = report["units"][0]
assert dep["integrity"] == "Modified"
assert dep["base_artifact_sha256"] == sys.argv[2]
assert dep["source_tree_sha256"]
PY
  "$BIN" vendor simd-dot >/dev/null
  "$BIN" build >/dev/null
  .asmory/build/project/current/program
  python3 - .asmory/build/project/current/build.json <<'PY'
import json, sys
dep = json.load(open(sys.argv[1]))["units"][0]
assert dep["source_kind"] == "vendor" and dep["integrity"] == "Modified"
PY
  [[ "$(sha256sum "$ASMORY_CACHE_HOME/objects/sha256/$sha" | cut -d' ' -f1)" == "$sha" ]]
else
  echo 'build-smoke: host lacks simd-dot AVX2/FMA; generic native/build cases passed'
fi

echo 'build-smoke: ok'
