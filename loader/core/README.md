# loader/core/ (`nl_core`)

Static library holding the loader logic that does not depend on running inside `gmod.exe`, so the
bootstrap DLL, the `nlctl` CLI and the unit tests all use the same code. M2 built archives,
manifests, discovery and planning; M3 added deployment; M4 added activation.

R7-B replaces the memory percentage warning with strict 18 GiB free-commit / 24 GiB total
thresholds derived from saved R6 sessions; see [the measurements](../../docs/RESEARCH.md#r7-b-commit-headroom-from-the-saved-r6-runs-2026-11-01).

R7-B also extends `include/nl/evidence.h` / `src/evidence.cpp` with exit-code classification,
fresh same-session commit inference, an external-observer `finish`, receipted exit-report JSON
and a clean/abnormal end marker reused at the next start. A per-root mutex serializes collectors;
exact start-marker bytes reject changed or different sessions. This code has no Windows UI.

| File | Purpose |
|---|---|
| `include/nl/performance.h`, `src/performance.cpp` | Pure R6 adapter/class/VRAM tier classification and interface I2 serialization (ADR 0062) |
| `include/nl/gpu_diagnostics.h`, `src/gpu_diagnostics.cpp` | Read-only one-start marker probe, local diagnostics-layer/dump-folder preparation and atomic next_start consumption (ADR 0062) |

| `include/nl/memory.h`, `src/memory.cpp` | R6 local memory samples through runtime-loaded DXGI and kernel counters; UTC/byte CSV, bounded rotation with ownership receipts, strict system-commit warning thresholds and a latest-only menu snapshot |
| `include/nl/memory_profile.h`, `src/memory_profile.cpp` | Pure R13 memory profiles (ADR 0101): below minimum, minimum, recommended or high from the largest adapter's VRAM and the total RAM, the `remix.memory_profile` override, the per-profile budgets (characters kept ready, game-texture GPU budget, CPU copies), `activation.memory` JSON and the runtime's D3D9 layer text |
| `include/nl/evidence.h`, `src/evidence.cpp` | R6: classify the previous session, archive local logs/dumps with full source sharing before runtime log truncation, and retain five intact archives within 200 MiB; never modify original evidence or prune user-edited copies ([ADR 0063](../../docs/decisions/0063-local-session-evidence-and-memory-telemetry.md)) |
| `CMakeLists.txt` | Defines `nl_core` (links the LZMA SDK decoder `nl_lzma` privately); generates `nl/version.h` |
| `include/nl/core.h` | `nl::version()` |
| `include/nl/version.h.in` | Template for the generated `nl/version.h` (`NL_VERSION_*` macros from the CMake project version) |
| `include/nl/crc32.h`, `src/crc32.cpp` | CRC-32 (zlib / PKZIP / GMA polynomial), one-shot and incremental |
| `include/nl/gma.h`, `src/gma.cpp` | GMA reader: `Source` streams (`MemorySource`, `FileSource` opened with full sharing so Steam can still update the file; `skip` seeks), `detect_container`, `read_index`, `verify` (one pass over all contents: file CRCs, optional archive CRC, trailing data), `open_archive` (plain or LZMA-wrapped), `read_entry` (one file, CRC-checked), `extract` (the wanted files of an archive in one pass to an `EntrySink`, CRC-checked, skipping the rest), `path_key` |
| `include/nl/lzma.h`, `src/lzma.cpp` | `lzma::Source`: streaming LZMA-alone decoder over the LZMA SDK, with GMod's optional 8-byte footer |
| `include/nl/json.h`, `src/json.cpp` | Strict JSON parser (`json::parse`, `json::Value`) and `json::quote` |
| `include/nl/legacy_detect.h`, `src/legacy_detect.cpp` | Bounded sparse PE export detection of an independently installed Remix runtime, without loading it; for a file below a game root, links are refused below the root only |
| `include/nl/legacy_migrate.h`, `src/legacy_migrate.cpp`, `src/legacy_stock_data.h` | Read-only legacy archive/recovery planning and hash-only upstream/Steam catalogs (the built-in one, or a synthetic one for tests); links stay in place, Steam's files are restored all or none; deploy executes it in the normal transaction and deploys without it when it cannot be planned ([ADR 0042](../../docs/decisions/0042-legacy-remix-migration.md)) |
| `include/nl/utf8.h`, `src/utf8.cpp` | UTF-8 validation shared by the JSON parser and the path rules |
| `include/nl/paths.h`, `src/paths.cpp` | Path rules for anything a package names, and the game-root areas packages may write to |
| `include/nl/manifest.h`, `src/manifest.cpp` | Manifest schema 1: strict `parse` (paths the loader deploys must also be ASCII), `check_contents`, SemVer `parse_version` / `compare` ([docs/PACKAGE_FORMAT.md](../../docs/PACKAGE_FORMAT.md)) |
| `include/nl/package.h`, `src/package.cpp` | Package contents from a `.gma` or a development folder (links and reparse points refused), `Contents::extract` (wanted files streamed to a `Sink` with bounded memory), and `load` (manifest read, parsed and checked; `manifest_sha256` of its bytes) |
| `include/nl/vdf.h`, `src/vdf.cpp` | Valve KeyValues reader (Steam `.vdf`/`.acf`, GMod's `addonnomount.txt`) |
| `include/nl/config.h`, `src/config.cpp` | `native-loader\config.json` schema 1: the allowlist and switches; strict, unknown keys rejected |
| `include/nl/discovery.h`, `src/discovery.cpp` | Finds allowlisted sources without the Steam API: the game's library (or `libraryfolders.vdf`), item archives, `appworkshop_4000.acf`, `addonnomount.txt`; then the subscribed items whose `.gma` lists `native/manifest.json` (`lists_native_manifest`), as content-only candidates ([ADR 0027](../../docs/decisions/0027-content-packages-from-any-subscription.md)) |
| `include/nl/content.h`, `src/content.cpp` | What a content-only package may hold: GMod's Workshop whitelist (`workshop_whitelisted`, gmad's table), Remix mod data (`remix_mod_file`), and `problem` (any native code, or a file outside those, ADR 0027) |
| `include/nl/reshade.h`, `src/reshade.cpp` | ReShade in RTX sessions ([ADR 0028](../../docs/decisions/0028-reshade-in-rtx-sessions.md)): `probe` (the game's `bin/win64/ReShade.ini` and its `[INSTALL] BasePath`, the RTX sessions' own `native-loader/reshade/ReShade.ini`, the package's layer manifest), `parse_layer`, `plan` (`remix.reshade` auto/on/off), `migrate` (the game's settings with every path made absolute and the presets pointed to copies), `fresh`, `is_preset` and `prepare`, which makes the folder and its settings once and never writes the game's ReShade |
| `include/nl/planner.h`, `src/planner.cpp` | `consider` (load each candidate's package) and `make_plan` (precedence, one runtime, root overlaps; [ADR 0006](../../docs/decisions/0006-package-precedence-and-planning.md)) |
| `include/nl/sha256.h`, `src/sha256.cpp` | SHA-256 from Windows CNG; `bcrypt.dll` is loaded from System32 by full path on first use, so the bootstrap's import table stays KERNEL32-only |
| `include/nl/fs.h`, `src/fs.cpp` | The deployer's file-system layer: `FileSystem` (every change; `win32()` with flushes, write-through renames and retries while a scanner has a file open; `Counting` for fault injection), `write_atomic`, `remove_tree`, and reads that never follow links (`stat`, `hash_file`, `list`, `read_file`, `refuse_links`); extended-length paths throughout |
| `include/nl/journal.h`, `src/journal.cpp` | `native-loader\state.json` schema 1: `parse` (strict; paths checked against the folders the loader manages), `serialize`, `load`, atomic `save` ([docs/ON_DISK_LAYOUT.md](../../docs/ON_DISK_LAYOUT.md)) |
| `include/nl/deploy.h`, `src/deploy.cpp` | The deployer: `apply`, `rollback`, `uninstall`, `recover` (each one transaction, with lock, recovery and clean-up) and read-only `status` ([ADR 0007](../../docs/decisions/0007-transactional-deployment.md)) |
| `include/nl/activate.h`, `src/activate.cpp` | `activate::plan`: a pure function turning the deployed generation + config + environment + command line into what start-up loads (d3d9.dll, DLL-search folder, vulkan preload), sets (config-file layer lists, naming short copies of the package's layers in `native-loader/remix` ([ADR 0036](../../docs/decisions/0036-remix-layers-as-short-copies.md)), and package env, the user winning) and adds (launch arguments the user did not pass); `activate::use_sources` for copies the bootstrap could not write; [ADR 0008](../../docs/decisions/0008-activation-at-startup.md) |
| `include/nl/patch.h`, `src/patch.cpp` | M5 patch sets: wildcard pattern search (`find`), the sections of a mapped PE32+ module, and `apply`, which writes a patch only where its pattern occurs exactly once across the module ([ADR 0010](../../docs/decisions/0010-rtx-session-extras.md)) |
| `include/nl/session.h`, `src/session.cpp` | M5 session console variables: `config.cfg` values, the restore record (`native-loader/session_cvars.json`), the generated cfg text, and `plan`, which decides per start what to record, run (`+exec`) and restore; `hidden_addons`, the add-on folders of `requires_remix` packages that a start without a runtime hides ([ADR 0013](../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)) |
| `include/nl/cmdline.h`, `src/cmdline.cpp` | Command line: `tokenize` / raw `argument_spans` / `has_arg`, validated transactional `swap_records` (Buffer/Length/MaximumLength and USHORT limits), `append_arguments` and guarded `rewrite_arguments` for kernelbase W/A plus the PEB. Rewrites verify the expected wide line and original ANSI ACP conversion first. A move-only `SwapResult` supports explicit/automatic exact-descriptor restore or committing buffers for process lifetime; write failure restores every attempted slot. |
| `src/version.cpp` | `nl::version()` |
| `include/nl/startup.h`, `src/startup.cpp` | Startup preparation and pure keep-last-good policy: config/journal preflight, current-PID-only exclusion, explicit disabled sources versus unavailable ones, safe contention/pending decisions ([ADR 0009](../../docs/decisions/0009-startup-deployment-last-good.md)) |
| `include/nl/status.h`, `src/status.cpp` | Startup status schema 1 and matching log fields; atomic per-PID temporary-file replacement; uninstall removes generated status and the empty data folder, preserving unrelated files |

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
`conin$`, `conout$`); `~` followed by a digit (8.3 short names).

Package root files may only target these areas (`paths::root_area`):

- `rtx-remix/mods/<mod>/...`;
- `garrysmod/lua/bin/...`;
- `garrysmod/addons/<addon>/...` (M5);
- `garrysmod/data/<folder>/...` (M5; not `native-loader`).

In the three folder areas a file must be inside a named folder (`paths::file_depth_ok`).
`garrysmod/cfg` is not an area: it holds Steam depot files
([ADR 0014](../../docs/decisions/0014-r1-hardening.md)).

## Deployment rules

The full design is [ADR 0007](../../docs/decisions/0007-transactional-deployment.md); in short:

- Every change to the disk goes through an `fs::FileSystem`, so tests can interrupt any one of them.
  Reads use the free functions in `nl/fs.h`.
- A run stages and checks everything (size, CRC-32, SHA-256) before anything in place changes. It
  records the steps in the journal (`pending`), renames within one volume, then commits. An
  unfinished transaction is undone by the next run, step by step, each step only if it happened.
- Only files the journal records are deleted, and only after a full SHA-256 shows they are
  unchanged. A changed `replace-owned` file is moved to `backup/edits` and the package's copy put
  back; someone else's file in a package's way is moved to `backup/originals` and put back once no
  generation names its path; an identical one is adopted (ADR 0035). The loader never deletes either
  folder's files. Folders go only when empty.
- Nothing is placed, moved or deleted through a link anywhere below the game folder.
- Clean-up never stops a command: what it cannot delete now stays listed, with a note, for the next
  run; uninstall keeps the journal until everything is gone.
- A run with nothing to do makes no change at all.

## Rules for code here

No global state (the one exception: the CNG provider handle, opened once and never changed), no
Windows UI, nothing that needs the loader lock to be free (this code also runs in the bootstrap's
start-up step), and no `catch (...)`: the fault tests simulate a crash with an exception that
nothing may catch. Every public function is covered in [`../tests`](../tests/README.md).
