# Native primitives

These GNU as modules implement reusable Linux x86-64 SysV64 interfaces without
libc. `make` creates `build/native/libasmory-native.a`; the CLI, build executor
and ELF checker link the same library.

| Symbol | Arguments | Result / ownership |
| --- | --- | --- |
| `asmory_write_all` | fd, bytes, byte count | 0 or negative Linux errno; retries EINTR and partial writes |
| `asmory_file_map` | path, view pointer | 0 or negative errno; view is two u64 fields: address and byte length; caller owns mmap |
| `asmory_file_unmap` | view pointer | munmap result; releases a successful view |
| `asmory_process_run` | absolute-path argv, envp | child exit code, 128 + termination signal, or negative errno; waits for its own child |
| `asmory_exec_sibling` | helper basename, argv, envp | execve replacement, or negative errno; finds the helper beside `/proc/self/exe` |
| `asmory_process_run_sibling` | helper basename, argv, envp | waits for a sibling helper and returns exit/signal status or errno |
| `asmory_exec_path` | name/path, argv, envp | literal PATH search followed by execve; no shell fallback |
| `asmory_process_capture` | argv, envp, buffer, capacity | stdout byte count or errno; bounded output and 5-second monotonic deadline; kills/reaps its own child on failure |
| `asmory_text_equal` | two terminated strings | 0/1 equality |
| `asmory_text_find` | terminated haystack/needle | borrowed match pointer or 0 |
| `asmory_version_parse` | terminated text, uint32[4] output | end pointer or -EINVAL; 2–4 components with at most 9 digits each |
| `asmory_version_compare` | two uint32[4] versions | -1/0/+1 numeric comparison with zero trailing components |
| `asmory_decimal_parse` | terminated decimal string | nonnegative signed-64 value or -EINVAL; checks multiplication overflow |
| `asmory_sha256_init` | context pointer | initializes caller-owned 112-byte streaming state; returns 0 |
| `asmory_sha256_update` | context, bytes, byte count | 0 or -EOVERFLOW; zero-length input may be null; overflow leaves state unchanged |
| `asmory_sha256_final` | context, 32-byte output | 0; writes big-endian digest and consumes context |
| `asmory_sha256_file` | path, 32-byte output | 0 or negative errno; streams an ordinary file, refuses final symlinks; failure leaves output unchanged |
| `asmory_elf64_object` | view pointer, metadata pointer | 0 or -EINVAL; successful metadata borrows pointers from the view |

File views require an ordinary nonempty file of at most 64 MiB and refuse a final
symlink. They use read-only private mappings. ELF metadata is eight u64 fields:
section pointer/count, section-name strings/size, symbol pointer/count and
symbol-name strings/size. Consume it only after a successful return and before
unmapping the view. Extended section counts/indexes are currently rejected.

All routines preserve SysV64 callee-saved registers. `process_run` uses absolute
paths and sibling execution uses `/proc/self/exe`; only the explicit PATH/capture
interfaces search PATH. No routine performs implicit shell expansion. Capture
accepts capacities from 1 byte to 1 MiB, permits an exact fit, and treats a
nonzero/signalled child exit as -EIO. Text APIs require caller-owned valid,
terminated strings and suitably sized output arrays. These primitives validate their
documented structures; they do not sandbox tool processes or attest package
semantics. See [the build contract](../spec/BUILD.md) for their consumers and
transitional planner retirement conditions.

`asmory-toolchain-check` uses capture/text primitives to validate GNU as version
and x86-64 ELF target before source selection. `asmory-text-splice` uses mapped
inputs, checked decimal byte ranges and exclusive/fsynced output writes for
metadata editing. The TOML planner remains transitional; see
[ADD_MVP.md](../docs/ADD_MVP.md) for its removal gate.

SHA-256 follows [FIPS 180-4](https://doi.org/10.6028/NIST.FIPS.180-4), using
baseline x86-64 integer instructions. Contexts and outputs need no alignment;
input, context and output must not overlap. Initialize each independent context,
update with valid byte ranges, and finalize once; initialize again to reuse.
The maximum total input is 2^61 - 1 bytes (the bit count must fit 64 bits).
File hashing uses a private 64 KiB read buffer, retries EINTR, supports empty
files and has no 64 MiB view limit. It hashes bytes read, without promising a
snapshot of a concurrently edited file; lifecycle consumers retain their own
input-change checks. It does not extract or modify the input.

`asmory-sha256 <path>` prints exactly 64 lowercase hex digits and a newline,
or exits 28 on argument, read or output failure. Build file hashes and Artifact
acquisition/cache verification use this companion without a fallback.
`make sha256-smoke` checks known vectors, independent Python digest results,
padding/read boundaries, split updates, direct SysV64 calls and refusal behavior.
Python remains the test oracle rather than the implementation of the hash wheel.
