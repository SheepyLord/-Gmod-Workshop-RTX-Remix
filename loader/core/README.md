# loader/core/ (`nl_core`)

Static library holding the loader logic that does not depend on running inside `gmod.exe`, so the
bootstrap DLL, the `nlctl` CLI and the unit tests all use the same code. M2 built archives,
manifests, discovery and planning; M3 added deployment; M4 added activation.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Defines `nl_core` (links the LZMA SDK decoder `nl_lzma` privately); generates `nl/version.h` |
| `include/nl/core.h` | `nl::version()` |
| `include/nl/version.h.in` | Template for the generated `nl/version.h` (`NL_VERSION_*` macros from the CMake project version) |
| `include/nl/crc32.h`, `src/crc32.cpp` | CRC-32 (zlib / PKZIP / GMA polynomial), one-shot and incremental |
| `include/nl/gma.h`, `src/gma.cpp` | GMA reader: `Source` streams (`MemorySource`, `FileSource` opened with full sharing so Steam can still update the file; `skip` seeks), `detect_container`, `read_index`, `verify` (one pass over all contents: file CRCs, optional archive CRC, trailing data), `open_archive` (plain or LZMA-wrapped), `read_entry` (one file, CRC-checked), `extract` (the wanted files of an archive in one pass to an `EntrySink`, CRC-checked, skipping the rest), `path_key` |
| `include/nl/lzma.h`, `src/lzma.cpp` | `lzma::Source`: streaming LZMA-alone decoder over the LZMA SDK, with GMod's optional 8-byte footer |
| `include/nl/json.h`, `src/json.cpp` | Strict JSON parser (`json::parse`, `json::Value`) and `json::quote` |
| `include/nl/utf8.h`, `src/utf8.cpp` | UTF-8 validation shared by the JSON parser and the path rules |
| `include/nl/paths.h`, `src/paths.cpp` | Path rules for anything a package names, and the game-root areas packages may write to |
| `include/nl/manifest.h`, `src/manifest.cpp` | Manifest schema 1: strict `parse` (paths the loader deploys must also be ASCII), `check_contents`, SemVer `parse_version` / `compare` ([docs/PACKAGE_FORMAT.md](../../docs/PACKAGE_FORMAT.md)) |
| `include/nl/package.h`, `src/package.cpp` | Package contents from a `.gma` or a development folder (links and reparse points refused), `Contents::extract` (wanted files streamed to a `Sink` with bounded memory), and `load` (manifest read, parsed and checked; `manifest_sha256` of its bytes) |
| `include/nl/vdf.h`, `src/vdf.cpp` | Valve KeyValues reader (Steam `.vdf`/`.acf`, GMod's `addonnomount.txt`) |
| `include/nl/config.h`, `src/config.cpp` | `native-loader\config.json` schema 1: the allowlist and switches; strict, unknown keys rejected |
| `include/nl/discovery.h`, `src/discovery.cpp` | Finds allowlisted sources without the Steam API: the game's library (or `libraryfolders.vdf`), item archives, `appworkshop_4000.acf`, `addonnomount.txt` |
| `include/nl/planner.h`, `src/planner.cpp` | `consider` (load each candidate's package) and `make_plan` (precedence, one runtime, root overlaps; [ADR 0006](../../docs/decisions/0006-package-precedence-and-planning.md)) |
| `include/nl/sha256.h`, `src/sha256.cpp` | SHA-256 from Windows CNG; `bcrypt.dll` is loaded from System32 by full path on first use, so the bootstrap's import table stays KERNEL32-only |
| `include/nl/fs.h`, `src/fs.cpp` | The deployer's file-system layer: `FileSystem` (every change; `win32()` with flushes, write-through renames and retries while a scanner has a file open; `Counting` for fault injection), `write_atomic`, `remove_tree`, and reads that never follow links (`stat`, `hash_file`, `list`, `read_file`, `refuse_links`); extended-length paths throughout |
| `include/nl/journal.h`, `src/journal.cpp` | `native-loader\state.json` schema 1: `parse` (strict; paths checked against the folders the loader manages), `serialize`, `load`, atomic `save` ([docs/ON_DISK_LAYOUT.md](../../docs/ON_DISK_LAYOUT.md)) |
| `include/nl/deploy.h`, `src/deploy.cpp` | The deployer: `apply`, `rollback`, `uninstall`, `recover` (each one transaction, with lock, recovery and clean-up) and read-only `status` ([ADR 0007](../../docs/decisions/0007-transactional-deployment.md)) |
| `include/nl/activate.h`, `src/activate.cpp` | `activate::plan`: a pure function turning the deployed generation + config + environment + command line into what start-up loads (d3d9.dll, DLL-search folder, vulkan preload), sets (config-file layer lists and package env, the user winning) and adds (launch arguments the user did not pass); [ADR 0008](../../docs/decisions/0008-activation-at-startup.md) |
| `include/nl/cmdline.h`, `src/cmdline.cpp` | Command line: `tokenize` / `has_arg` (argv rules), and `append_arguments`, which adds the runtime's launch arguments in memory by pointing kernelbase's `GetCommandLineW/A` caches and the PEB at longer strings (`cached_pointer_slot` finds the cached pointer behind a `mov rax,[rip+disp]; ret` getter) |
| `src/version.cpp` | `nl::version()` |

## GMA reader rules

Archive bytes are untrusted. The reader follows `tools/gmapack/gmapack.py` where real archives
agree with it, and real archives where they do not:

- `GMAD` versions 1-3; strings at most 16 MiB; at most 1,048,576 entries (`gma::Limits`).
- Empty paths, duplicate paths (ASCII case and `\` vs `/` folded) and negative sizes are rejected;
  size sums that would overflow are rejected.
- An entry CRC or archive CRC of 0 means "written without a CRC" and is not checked.
- The 4-byte archive CRC trailer is **optional**: 19 legacy Workshop items end right after their
  last file. A stream that ends inside the contents or 1-3 bytes into the trailer is truncated.
- Every failure is a `gma::FormatError` naming the field being read.

## LZMA rules (`*_legacy.bin`)

- LZMA-alone header: properties byte below 225, dictionary at most 256 MiB, size known or not.
- Decoding streams into the caller's buffer with memory bounded by the dictionary; reads return what
  is decoded so far, so damage past the bytes a caller needs (an index) does not fail it.
- After the declared size: an optional end marker, then nothing, or exactly GMod's 8-byte footer
  (32-bit size that must match, then `0xBEEFCACE`). Any other trailing byte, an early end, an overrun
  or corrupt data is a `FormatError`.

## JSON rules

Strict RFC 8259: UTF-8 (no byte-order mark), no comments, trailing commas, NaN or Infinity,
duplicate keys or NUL characters; nothing after the value. Limits: 1 MiB per document, depth 32,
64 KiB per string, 100,000 values (`json::ParseLimits`). Errors give the byte offset.

## Path rules

`paths::problem` refuses: empty or over 1,024 bytes; invalid UTF-8; control characters; `\`; `:`
(drive letters and alternate data streams) and `< > " | ? *`; absolute paths; empty, `.` or `..`
components; components over 255 bytes, starting with a space or ending with `.` or a space; Windows
device names with any extension (`con`, `nul.txt`, `com0`-`com9`, `lpt0`-`lpt9`, superscript ports,
`conin$`, `conout$`); `~` followed by a digit (8.3 short names). Package root files may only target
`rtx-remix/mods/<mod>/...`, `garrysmod/lua/bin/...` and `garrysmod/cfg/...` (`paths::root_area`).

## Deployment rules

The full design is [ADR 0007](../../docs/decisions/0007-transactional-deployment.md); in short:

- Every change to the disk goes through an `fs::FileSystem`, so tests can interrupt any one of them.
  Reads use the free functions in `nl/fs.h`.
- A run stages and checks everything (size, CRC-32, SHA-256) before anything in place changes. It
  records the steps in the journal (`pending`), renames within one volume, then commits. An
  unfinished transaction is undone by the next run, step by step, each step only if it happened.
- Only files the journal records are replaced or removed, and only after a full SHA-256 shows they
  are unchanged. Someone else's file blocks its package (or is adopted if identical). Changed files
  are left and reported. Folders go only when empty.
- Nothing is placed, moved or deleted through a link anywhere below the game folder.
- Clean-up never stops a command: what it cannot delete now stays listed, with a note, for the next
  run; uninstall keeps the journal until everything is gone.
- A run with nothing to do makes no change at all.

## Rules for code here

No global state (the one exception: the CNG provider handle, opened once and never changed), no
Windows UI, nothing that needs the loader lock to be free (this code also runs in the bootstrap's
start-up step), and no `catch (...)`: the fault tests simulate a crash with an exception that
nothing may catch. Every public function is covered in [`../tests`](../tests/README.md).
