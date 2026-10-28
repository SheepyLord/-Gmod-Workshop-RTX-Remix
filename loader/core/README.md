# loader/core/ (`nl_core`)

Static library holding the loader logic that does not depend on running inside `gmod.exe`, so the
bootstrap DLL, the `nlctl` CLI and the unit tests all use the same code. M2 builds it up (archives,
manifests, discovery, planning); M3 adds deployment.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Defines `nl_core` (links the LZMA SDK decoder `nl_lzma` privately); generates `nl/version.h` |
| `include/nl/core.h` | `nl::version()` |
| `include/nl/version.h.in` | Template for the generated `nl/version.h` (`NL_VERSION_*` macros from the CMake project version) |
| `include/nl/crc32.h`, `src/crc32.cpp` | CRC-32 (zlib / PKZIP / GMA polynomial), one-shot and incremental |
| `include/nl/gma.h`, `src/gma.cpp` | GMA reader: `Source` streams (`MemorySource`, `FileSource` opened with full sharing so Steam can still update the file; `skip` seeks), `detect_container`, `read_index`, `verify` (one pass over all contents: file CRCs, optional archive CRC, trailing data), `open_archive` (plain or LZMA-wrapped), `read_entry` (one file, CRC-checked), `path_key` |
| `include/nl/lzma.h`, `src/lzma.cpp` | `lzma::Source`: streaming LZMA-alone decoder over the LZMA SDK, with GMod's optional 8-byte footer |
| `include/nl/json.h`, `src/json.cpp` | Strict JSON parser (`json::parse`, `json::Value`) and `json::quote` |
| `include/nl/utf8.h`, `src/utf8.cpp` | UTF-8 validation shared by the JSON parser and the path rules |
| `include/nl/paths.h`, `src/paths.cpp` | Path rules for anything a package names, and the game-root areas packages may write to |
| `include/nl/manifest.h`, `src/manifest.cpp` | Manifest schema 1: strict `parse`, `check_contents`, SemVer `parse_version` / `compare` ([docs/PACKAGE_FORMAT.md](../../docs/PACKAGE_FORMAT.md)) |
| `include/nl/package.h`, `src/package.cpp` | Package contents from a `.gma` or a development folder (links and reparse points refused), and `load` (manifest read, parsed and checked) |
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

## Rules for code here

No global state, no Windows UI, nothing that needs the loader lock to be free (this code also runs
in the bootstrap's start-up step). Every public function is covered in [`../tests`](../tests/README.md).
