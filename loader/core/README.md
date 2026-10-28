# loader/core/ (`nl_core`)

Static library holding the loader logic that does not depend on running inside `gmod.exe`, so the
bootstrap DLL, the `nlctl` CLI and the unit tests all use the same code. M2 builds it up (GMA
reading, manifests, discovery, planning); M3 adds deployment.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Defines `nl_core`; generates `nl/version.h` into the build folder |
| `include/nl/core.h` | `nl::version()` |
| `include/nl/version.h.in` | Template for the generated `nl/version.h` (`NL_VERSION_*` macros from the CMake project version) |
| `include/nl/crc32.h`, `src/crc32.cpp` | CRC-32 (zlib / PKZIP / GMA polynomial), one-shot and incremental |
| `include/nl/gma.h`, `src/gma.cpp` | GMA reader: `Source` streams (`MemorySource`, `FileSource` opened with full sharing so Steam can still update the file), `detect_container` (GMAD or LZMA-alone), `read_index` (header and file index), `verify` (single pass over all contents, CRCs, trailing data), `open_archive`, `path_key` |
| `include/nl/json.h`, `src/json.cpp` | `json::quote`: JSON string literals that keep valid UTF-8 and replace invalid bytes with U+FFFD |
| `src/version.cpp` | `nl::version()` |

## GMA reader rules

Archive bytes are untrusted. The reader matches `tools/gmapack/gmapack.py`:

- `GMAD` versions 1-3; strings at most 16 MiB; at most 1,048,576 entries (`gma::Limits`).
- Empty paths, duplicate paths (ASCII case and `\` vs `/` folded) and negative sizes are rejected.
- Size sums that would overflow are rejected.
- Entry CRC or archive CRC 0 means "written without a CRC" and is not checked.
- Every failure is a `gma::FormatError` with the field that was being read.

LZMA-wrapped archives (`*_legacy.bin` on the Workshop) are recognised but not decoded yet; the
decoder (LZMA SDK, public domain) is M2 part 2.

## Rules for code here

No global state, no Windows UI, nothing that needs the loader lock to be free (this code also runs
in the bootstrap's start-up step). Every public function is covered in [`../tests`](../tests/README.md).
