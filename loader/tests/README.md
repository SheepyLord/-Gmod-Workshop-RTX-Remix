# loader/tests/ (`nl_tests`)

Unit tests for [`nl_core`](../core/README.md), registered with CTest and run by
[`tools/build.ps1`](../../tools/build.ps1.md). No third-party test framework: `nl_test.h` is a small
self-registering harness.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Builds `nl_tests` and registers it with CTest |
| `nl_test.h` | Harness: `TEST_CASE("name") { ... }`, `CHECK(expr)` (record and continue), `REQUIRE(expr)` (record and end the case) |
| `test_main.cpp` | Runner: runs every case, or those whose name contains the first argument; prints `ok`/`FAIL` per case; exit code 0 only if at least one case ran and none failed |
| `test_version.cpp` | `nl::version()` matches the CMake project version |

Run directly to filter: `out\build\win64-debug\loader\tests\nl_tests.exe version`.

To add tests, create `test_<area>.cpp`, add it to `CMakeLists.txt` and to this table.
