#!/usr/bin/env python3
"""Check actual native publication, inode identity, refusal and concurrent wins."""
from pathlib import Path
import errno
import os
import shutil
import stat
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "build/asmory-file-publish"


def run(argv, status=0, **kwargs):
    result = subprocess.run(list(map(str, argv)), capture_output=True, timeout=10, **kwargs)
    assert result.returncode == status, (argv, result.returncode, result.stderr)
    return result.stdout


with tempfile.TemporaryDirectory(prefix="asmory-publish-") as temporary:
    temp = Path(temporary)
    obj, harness = temp / "test.o", temp / "test"
    run([os.environ.get("AS", "as"), "--64", ROOT / "tests/native/publish.S", "-o", obj])
    run([os.environ.get("LD", "ld"), "-z", "noexecstack", obj,
         ROOT / "build/native/libasmory-native.a", "-o", harness])

    def native(source, target):
        return struct.unpack("<q", run([harness, source, target]))[0]

    source, target = temp / "-stage ; $literal", temp / "object with spaces"
    for data in (b"", b"artifact\x00bytes" * 10000):
        source.write_bytes(data)
        assert native(source, target) == 0
        assert source.stat().st_ino == target.stat().st_ino
        assert target.read_bytes() == data
        assert stat.S_IMODE(target.stat().st_mode) == 0o444
        assert target.stat().st_nlink == 2
        source.unlink()
        assert target.stat().st_nlink == 1
        target.unlink()

    source.write_bytes(b"candidate")
    target.write_bytes(b"sentinel")
    before = target.stat()
    assert native(source, target) == -errno.EEXIST
    assert target.read_bytes() == b"sentinel"
    assert target.stat().st_ino == before.st_ino
    assert stat.S_IMODE(target.stat().st_mode) == stat.S_IMODE(before.st_mode)
    assert source.read_bytes() == b"candidate"
    target.unlink()
    target.symlink_to(temp / "absent")
    assert native(source, target) == -errno.EEXIST
    assert target.is_symlink() and not target.exists()
    target.unlink()
    target.mkdir()
    assert native(source, target) == -errno.EEXIST
    target.rmdir()

    link, fifo, alias = temp / "symlink", temp / "fifo", temp / "alias"
    link.symlink_to(source)
    os.mkfifo(fifo)
    for rejected, code in ((temp / "missing", errno.ENOENT), (link, errno.ELOOP),
                           (fifo, errno.EINVAL), (temp, errno.EINVAL),
                           (Path("/dev/null"), errno.EINVAL)):
        assert native(rejected, target) == -code
        assert not target.exists()
        assert run([BIN, rejected, target], status=12) == b""
    os.link(source, alias)
    source.chmod(0o600)
    assert native(source, target) == -errno.EINVAL
    assert stat.S_IMODE(alias.stat().st_mode) == 0o600
    alias.unlink()
    assert native(source, temp / "missing-parent/object") == -errno.ENOENT
    assert source.exists() and not target.exists()
    source.chmod(0o600)
    assert native(source, source) == -errno.EEXIST
    assert stat.S_IMODE(source.stat().st_mode) == 0o600
    parent_alias = temp / "parent-alias"
    parent_alias.symlink_to(temp, target_is_directory=True)
    assert native(source, parent_alias / source.name) == -errno.EEXIST
    assert stat.S_IMODE(source.stat().st_mode) == 0o600

    for argv in ([BIN], [BIN, source], [BIN, source, target, target]):
        assert run(argv, status=12) == b""

    # Competing independent stages: exactly one wins; losers retain their source.
    stages = [temp / f"stage-{index}" for index in range(12)]
    for index, stage in enumerate(stages):
        stage.write_bytes(f"candidate-{index}".encode())
    children = [subprocess.Popen([str(BIN), str(stage), str(target)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                for stage in stages]
    statuses = []
    for child in children:
        out, _ = child.communicate(timeout=10)
        assert out == b""
        statuses.append(child.returncode)
    assert statuses.count(0) == 1 and statuses.count(12) == len(stages) - 1
    winner = stages[statuses.index(0)]
    assert target.read_bytes() == winner.read_bytes()
    assert target.stat().st_ino == winner.stat().st_ino
    assert stat.S_IMODE(target.stat().st_mode) == 0o444
    assert all(stage.exists() for stage in stages)
    for stage in stages:
        stage.unlink()
    assert target.stat().st_nlink == 1
    assert b"INTERP" not in run(["readelf", "-l", BIN])

    # No fallback to system ln/chmod when the native companion is absent.
    shutil.copy2(ROOT / "build/asmory-sha256", temp / "asmory-sha256")
    env = dict(os.environ, ASMORY_CACHE_HOME=str(temp / "cache"),
               ASMORY_REGISTRY_URL="http://127.0.0.1:1")
    for name, extra in (("acquire", [temp / "unpublished"]), ("cache", [])):
        helper = temp / f"asmory-{name}"
        shutil.copy2(ROOT / f"scripts/asmory-{name}.sh", helper)
        result = subprocess.run(["bash", str(helper), "test", "1.0.0", "0" * 64,
                                 *map(str, extra)], capture_output=True, timeout=5, env=env)
        assert result.returncode == 10, (name, result.returncode, result.stderr)
        assert b"native file publication companion unavailable" in result.stderr
    assert not (temp / "unpublished").exists() and not (temp / "cache").exists()

print("file-publish-smoke: atomic no-clobber, inode/mode, concurrency, ABI and refusal passed")
