#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
export PATH="$ROOT/build:$PATH"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import copy
import json
import os
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "scripts"))
from machine_model import compatible_variant, host_facts

native = root / "build/asmory-toolchain-check"
def invoke(minimum="2.40", *, env=None, assembler="gas", syntax="intel", status=0):
    result = subprocess.run([str(native), assembler, minimum, syntax], env=env,
                            capture_output=True, text=True, timeout=8)
    assert result.returncode == status, (result.returncode, result.stderr)
    return result

print("== native numeric minimum, adapter and probe target checks ==", flush=True)
invoke()
result = invoke("999.0", status=26)
assert "requires 999.0" in result.stderr and "found" in result.stderr
for minimum in ("2", "2.40.extra", "2..40", "2.40.0.0.0", "1234567890.0"):
    assert "invalid numeric minimum" in invoke(minimum, status=26).stderr
invoke(assembler="nasm", status=26)
invoke(syntax="unknown", status=26)

host = host_facts()
record = json.loads((root / "build/registry-data/simd-dot-0.1.0.json").read_text())
variant = record["release"]["variants"][0]
# These checks vary the contract while preserving actual native host facts.
variant = copy.deepcopy(variant)
variant["target"]["isa"] = {"baseline": "x86-64-v1", "required": []}
assert compatible_variant(variant, host)[0]
bad = copy.deepcopy(variant); bad["toolchain"]["min_version"] = "999.0"
ok, reason = compatible_variant(bad, host)
assert not ok and "requires 999.0" in reason
bad = copy.deepcopy(variant); bad["exports"][0]["calling_convention"] = "win64"
assert not compatible_variant(bad, host)[0]
bad = copy.deepcopy(variant); bad.pop("toolchain")
assert not compatible_variant(bad, host)[0]

with tempfile.TemporaryDirectory(prefix="asmory-toolchain-") as temp:
    directory = Path(temp)
    program = directory / "as"
    environment = dict(os.environ, PATH=str(directory))
    def fake(version="2.9", target="x86_64-pc-linux-gnu", prefix="GNU assembler", extra=""):
        payload = f'{prefix} (GNU Binutils) {version}\nThis assembler was configured for a target of `{target}\'.\n' + extra
        program.write_text("#!/usr/bin/python3\nimport os\nos.write(1," + repr(payload.encode()) + ")\n")
        program.chmod(0o755)
    fake("2.9")
    invoke("2.10", env=environment, status=26)
    fake("2.10")
    invoke("2.9", env=environment)
    fake("2.40.0")
    invoke("2.40", env=environment)
    fake("2.9", prefix="GNU assembler (vendor release 99.0)")
    invoke("2.10", env=environment, status=26)
    fake("2.47", target="x86_64-w64-mingw32")
    assert "must target" in invoke(env=environment, status=26).stderr
    fake("2.47", prefix="not GNU assembler")
    assert "probe failed" in invoke(env=environment, status=26).stderr
    fake("2.47", extra="x" * 16384)
    invoke(env=environment, status=26)
    program.unlink()
    invoke(env=environment, status=26)

    print("== bounded capture reaps a timed-out child even after stdout closes ==", flush=True)
    pid_file = directory / "pid"
    program.write_text("#!/usr/bin/python3\nimport os,time\n"
                       f"open({str(pid_file)!r},'w').write(str(os.getpid()))\n"
                       "os.close(1)\ntime.sleep(60)\n")
    program.chmod(0o755)
    before = time.monotonic()
    invoke(env=environment, status=26)
    assert time.monotonic() - before < 7
    pid = int(pid_file.read_text())
    assert not Path(f"/proc/{pid}").exists(), "timed-out compiler child was not reaped"

    print("== bootstrap resolution rejects a missing assembler ==", flush=True)
    result = subprocess.run([str(root / "build/asmory"), "resolve", "simd-dot"],
                            env=dict(environment, PATH=str(directory / "missing")),
                            capture_output=True, text=True, timeout=8)
    assert result.returncode != 0 and "Variant" in result.stdout

print("toolchain-smoke: ok")
PY
