# loader/tests/ (`nl_tests`)

Unit tests for [`nl_core`](../core/README.md), registered with CTest and run by
[`tools/build.ps1`](../../tools/build.ps1.md). No third-party test framework: `nl_test.h` is a small
self-registering harness. M1's proxy tests compile `test_main.cpp` too, so keep both files
backward compatible.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Builds `nl_tests` and `nl_fault_host`; registers the CTests `nl_tests` (everything but the exhaustive fault cases), `nl_tests_faults_upgrade`, `nl_tests_faults_other`, `nl_tests_faults_errors` (one each, so they run in parallel) and `nl_deploy_faults` |
| `nl_test.h` | Harness: `TEST_CASE("name") { ... }`, `CHECK(expr)` (record and continue), `REQUIRE(expr)` (record and end the case), `CHECK_THROWS_AS(expr, type)`, `scratch_dir(name)` |
| `test_main.cpp` | Runner: runs every case, those whose name contains the first argument, or, with `--skip=<text>`, all but those; prints `ok`/`FAIL` per case; exit code 0 only if at least one case ran and none failed. Also defines `scratch_dir` |
| `gma_fixture.h` | Builds synthetic GMAD archives independently of the reader (versions, CRC on or off, custom sizes and CRCs, trailing bytes) |
| `test_crc32.cpp` | CRC-32 check values and incremental updates |
| `test_gma.cpp` | GMA reader: fields and offsets, versions 1-3, every truncation of header and index, bad identifiers, versions, names and sizes, limits, verify (damage, zero CRCs, optional CRC trailer, partial trailers, trailing data, every truncation of the contents), container detection, files on disk, one-pass `extract` (wanted files only, a CRC failure stops before `end()`) |
| `test_json.cpp` | JSON: quoting (escapes, UTF-8 kept or replaced); the strict parser (values, document order, escapes and surrogate pairs, int64 boundaries, 33 inputs strict JSON forbids, every limit, round trip with `quote`) |
| `test_lzma.cpp` | LZMA: header parsing and rejection, decoding in chunks of 1 to 64 bytes, known and unknown sizes, wrong declared sizes, every truncation, trailing bytes, corruption, GMod's footer (accepted only when exact), decoded bytes delivered before later damage, `open_archive` on wrapped files. The small test stream is embedded as hex, made with Python's `lzma.compress(..., format=lzma.FORMAT_ALONE)` |
| `test_paths.cpp` | Path rules: safe paths, 40-odd escaping or aliasing paths refused, length limits, case-insensitive `within`, root areas |
| `test_manifest.cpp` | Manifest schema 1: a complete manifest, defaults, 47 single-rule violations that must be refused (a non-ASCII path among them), cfg policy, SemVer precedence (the semver.org example) and invalid versions, `check_contents` (missing, resized, unlisted files; case) |
| `test_package.cpp` | Packages: load and read from a `.gma` and a development folder, `extract` from both, the manifest's SHA-256, refuse a missing or wrong manifest, refuse a folder with a junction inside (created with `mklink /J`) |
| `test_vdf.cpp` | KeyValues: blocks, comments, escapes, unquoted tokens, case-insensitive keys, later duplicates win, conditionals skipped, real `addonnomount.txt` / `appworkshop_4000.acf` shapes, unbalanced and over-deep input |
| `test_config.cpp` | config.json: full and minimal files, defaults allow nothing, 13 typos and unsafe values refused, loading from a game root |
| `test_discovery.cpp` | Discovery on a fake Steam library: Workshop folder from the game's library and from `libraryfolders.vdf`, one candidate per allowlisted entry in precedence order, disabled / empty / ambiguous / legacy / missing items, `appworkshop_4000.acf` details |
| `test_planner.cpp` | Planner rules: problems, `requires_loader`, the disabled switch, shadowing by precedence, fallback past a broken copy, one runtime, root overlaps, `remix.enabled` |
| `test_sha256.cpp` | SHA-256: the FIPS 180-4 example values (one million `a` included), updates in pieces, a finished hash refuses further use |
| `test_fs.cpp` | `nl::fs`: stat, hashes, atomic writes replacing a stale temporary file, paths over 400 characters, `Counting` and a failing hook, junctions refused and removed without being followed |
| `test_journal.cpp` | Journal schema 1: round trip of every field, "no hold" versus an empty hold, 17 invalid, unsafe or out-of-bounds journals refused, the loader's own paths longer than a package path accepted (up to 4,096 bytes), save and load in a game folder |
| `test_deploy.cpp` | The deployer on fake game folders: first deployment and the no-op re-run, upgrade, rollback with hold and back, retirement of the oldest generation, removing every package and rolling back, foreign and adopted files, a file adopted and later put back by the loader across a rollback, changed files, create-only, fallback past a package that fails its SHA-256, a read-only retired file, the hold ending and not lifted by a broken package, rollback after a re-placed missing file, recovery that retires a stranded copy and keeps a stranger's file, junctions (also one swapped in for a loader folder later), dry run, the lock, an invalid journal, uninstall back to the original folder. The `deploy faults:` cases interrupt (an exception nothing catches) or fail every change of a first deployment, an upgrade, a rollback and an uninstall, some recoveries interrupted too, and require exactly the old or the new state afterwards; they use `FastDisk`, a file system without flushes |
| `test_activate.cpp` | `activate::plan`: a deployed runtime loads with no layers and leaves config discovery alone, layers go below the user's root conf in order, the user's own environment wins, launch arguments the user passed are not repeated (case-insensitive, quoted), no runtime deployed and `remix.enabled` false are both inactive |
| `test_cmdline.cpp` | `tokenize` / `has_arg` (quoting, backslashes, case), the cached-pointer getter shape accepted and other shapes refused, `cached_pointer_slot` resolving the RIP-relative address with and without an endbr64 prefix, and `append_arguments` extending this test process's own command line through the real kernelbase |
| `test_version.cpp` | `nl::version()` matches the CMake project version |
| `fault_host.cpp` | `nl_fault_host`, test-only: one deployer command (`apply`, `rollback`, `uninstall`, `recover`) that ends itself before change N (`--kill-at N`, exit 99) or fails it (`--fail-at N`) |
| `deploy_faults.py` | CTest `nl_deploy_faults`: kills `nl_fault_host` before every change of the same four scenarios on the real file system ([doc](deploy_faults.py.md)) |

Scratch files: call `nl::test::scratch_dir("name")`, which returns a fresh folder beside the test
executable (in the build tree, never the system temp folder: AGENTS.md rule 9), and delete it at the
end of the case. Close every file first; Windows will not delete open files.

Run directly to filter: `out\build\win64-debug\loader\tests\nl_tests.exe gma`, or everything but the
slow cases: `nl_tests.exe "--skip=deploy faults:"`.

To add tests, create `test_<area>.cpp`, add it to `CMakeLists.txt` and to this table.
