#!/usr/bin/env python3
"""Independent digest oracle and direct ABI consumer for the native hash wheel."""
from pathlib import Path
import hashlib
import os
import random
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "build/asmory-sha256"


def run(argv, *, content=None, status=0):
    result = subprocess.run(list(map(str, argv)), input=content, capture_output=True, timeout=30)
    assert result.returncode == status, (argv, result.returncode, result.stderr)
    return result.stdout


with tempfile.TemporaryDirectory(prefix="asmory-sha256-") as temporary:
    temp = Path(temporary)
    obj, harness = temp / "test.o", temp / "test"
    run([os.environ.get("AS", "as"), "--64", ROOT / "tests/native/sha256.S", "-o", obj])
    run([os.environ.get("LD", "ld"), "-z", "noexecstack", obj,
         ROOT / "build/native/libasmory-native.a", "-o", harness])
    vectors = [
        (b"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (b"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        (b"a" * 1000000, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"),
    ]
    rng = random.Random(256)
    lengths = [*range(131), 255, 256, 511, 512, 4095, 4096, 65535, 65536, 65537]
    vectors += [(data, hashlib.sha256(data).hexdigest()) for data in
                (rng.randbytes(length) for length in lengths)]
    path = temp / "-input with spaces ; $literal"
    for content, expected in vectors:
        path.write_bytes(content)
        assert run([BIN, path]) == (expected + "\n").encode()
        assert run([harness, 0, path]).hex() == expected
        for chunk in (1, 7, 55, 64, 65, 4096, 65536):
            assert run([harness, chunk], content=content).hex() == expected, (len(content), chunk)

    # Streaming must not inherit the native ELF view's 64 MiB/nonempty limits.
    with path.open("wb") as output:
        output.truncate(64 * 1024 * 1024 + 1)
    with path.open("rb") as source:
        expected = hashlib.file_digest(source, "sha256").hexdigest()
    assert run([BIN, path]) == (expected + "\n").encode()

    link, fifo = temp / "link", temp / "fifo"
    link.symlink_to(path)
    os.mkfifo(fifo)
    for argv in ([BIN], [BIN, path, path], [BIN, temp / "missing"],
                 [BIN, temp], [BIN, link], [BIN, fifo], [BIN, "/dev/null"]):
        assert run(argv, status=28) == b"", argv
    for rejected in (temp / "missing", temp, link, fifo, Path("/dev/null")):
        assert run([harness, 0, rejected], status=28) == b""
    header = run(["readelf", "-l", BIN])
    assert b"INTERP" not in header

    # Consumers must refuse absent native verification even with system hash
    # tools available; this checks the actual helpers rather than a mock hash.
    env = dict(os.environ, ASMORY_CACHE_HOME=str(temp / "cache"),
               ASMORY_REGISTRY_URL="http://127.0.0.1:1")
    for name, extra in (("acquire", [temp / "unpublished"]), ("cache", [])):
        helper = temp / f"asmory-{name}"
        shutil.copy2(ROOT / f"scripts/asmory-{name}.sh", helper)
        result = subprocess.run(
            ["bash", str(helper), "test", "1.0.0", "0" * 64, *map(str, extra)],
            capture_output=True, timeout=5, env=env,
        )
        assert result.returncode == 10, (name, result.returncode, result.stderr)
        assert b"native SHA-256 companion unavailable" in result.stderr
    assert not (temp / "unpublished").exists()
    assert not (temp / "cache").exists()

print("sha256-smoke: standard vectors, stream splits, ABI, limits and refusal passed")
