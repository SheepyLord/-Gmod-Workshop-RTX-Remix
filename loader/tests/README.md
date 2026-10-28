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
| `test_gma.cpp` | GMA reader: fields and offsets, versions 1-3, every truncation of header and index, bad identifiers, versions, names and sizes, limits, verify (damage, zero CRCs, trailing data, every truncation of the contents), container detection, files on disk |
| `test_json.cpp` | JSON quoting: escapes, valid UTF-8 kept, invalid sequences replaced |
| `test_version.cpp` | `nl::version()` matches the CMake project version |

Scratch files: call `nl::test::scratch_dir("name")`, which returns a fresh folder beside the test
executable (in the build tree, never the system temp folder: AGENTS.md rule 9), and delete it at the
end of the case. Close every file first; Windows will not delete open files.

Run directly to filter: `out\build\win64-debug\loader\tests\nl_tests.exe gma`.

To add tests, create `test_<area>.cpp`, add it to `CMakeLists.txt` and to this table.
