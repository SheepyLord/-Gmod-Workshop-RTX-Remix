# loader/tests/ (`nl_tests`)

Unit tests for [`nl_core`](../core/README.md), registered with CTest and run by
[`tools/build.ps1`](../../tools/build.ps1.md). No third-party test framework: `nl_test.h` is a small
self-registering harness. M1's proxy tests compile `test_main.cpp` too, so keep both files
backward compatible.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Builds `nl_tests` and registers it with CTest (working directory: its build folder) |
| `nl_test.h` | Harness: `TEST_CASE("name") { ... }`, `CHECK(expr)` (record and continue), `REQUIRE(expr)` (record and end the case), `CHECK_THROWS_AS(expr, type)`, `scratch_dir(name)` |
| `test_main.cpp` | Runner: runs every case, or those whose name contains the first argument; prints `ok`/`FAIL` per case; exit code 0 only if at least one case ran and none failed. Also defines `scratch_dir` |
| `gma_fixture.h` | Builds synthetic GMAD archives independently of the reader (versions, CRC on or off, custom sizes and CRCs, trailing bytes) |
| `test_crc32.cpp` | CRC-32 check values and incremental updates |
| `test_gma.cpp` | GMA reader: fields and offsets, versions 1-3, every truncation of header and index, bad identifiers, versions, names and sizes, limits, verify (damage, zero CRCs, optional CRC trailer, partial trailers, trailing data, every truncation of the contents), container detection, files on disk |
| `test_json.cpp` | JSON: quoting (escapes, UTF-8 kept or replaced); the strict parser (values, document order, escapes and surrogate pairs, int64 boundaries, 33 inputs strict JSON forbids, every limit, round trip with `quote`) |
| `test_lzma.cpp` | LZMA: header parsing and rejection, decoding in chunks of 1 to 64 bytes, known and unknown sizes, wrong declared sizes, every truncation, trailing bytes, corruption, GMod's footer (accepted only when exact), decoded bytes delivered before later damage, `open_archive` on wrapped files. The small test stream is embedded as hex, made with Python's `lzma.compress(..., format=lzma.FORMAT_ALONE)` |
| `test_paths.cpp` | Path rules: safe paths, 40-odd escaping or aliasing paths refused, length limits, case-insensitive `within`, root areas |
| `test_manifest.cpp` | Manifest schema 1: a complete manifest, defaults, 46 single-rule violations that must be refused, cfg policy, SemVer precedence (the semver.org example) and invalid versions, `check_contents` (missing, resized, unlisted files; case) |
| `test_package.cpp` | Packages: load and read from a `.gma` and a development folder, refuse a missing or wrong manifest, refuse a folder with a junction inside (created with `mklink /J`) |
| `test_vdf.cpp` | KeyValues: blocks, comments, escapes, unquoted tokens, case-insensitive keys, later duplicates win, conditionals skipped, real `addonnomount.txt` / `appworkshop_4000.acf` shapes, unbalanced and over-deep input |
| `test_config.cpp` | config.json: full and minimal files, defaults allow nothing, 13 typos and unsafe values refused, loading from a game root |
| `test_discovery.cpp` | Discovery on a fake Steam library: Workshop folder from the game's library and from `libraryfolders.vdf`, one candidate per allowlisted entry in precedence order, disabled / empty / ambiguous / legacy / missing items, `appworkshop_4000.acf` details |
| `test_planner.cpp` | Planner rules: problems, `requires_loader`, the disabled switch, shadowing by precedence, fallback past a broken copy, one runtime, root overlaps, `remix.enabled` |
| `test_version.cpp` | `nl::version()` matches the CMake project version |

Scratch files: call `nl::test::scratch_dir("name")`, which returns a fresh folder beside the test
executable (in the build tree, never the system temp folder: AGENTS.md rule 9), and delete it at the
end of the case. Close every file first; Windows will not delete open files.

Run directly to filter: `out\build\win64-debug\loader\tests\nl_tests.exe gma`.

To add tests, create `test_<area>.cpp`, add it to `CMakeLists.txt` and to this table.
