# loader/proxy/tests

CTest tests reuse `loader/tests/nl_test.h` and compile its unchanged `test_main.cpp` runner.
`nl_proxy_tests` has 16 cases: allocation-free host/root/token/off-switch logic, all current system
export names and ordinals, calls through a separate loaded proxy, and child-process entry hook,
off switches, non-game hosts, Chromium subprocess roles, failed logging and five-log rotation. Unicode scratch paths exercise
wide Win32 file handling. A host marker records its FILETIME and whether the log existed at main.

| File | Purpose |
|---|---|
| `test_presentation.cpp` | Display GMA CRC/index/metadata checks, inert payload, package identity and source-path refusal, cache edits preserved, stock menu marker validation, private-path exclusion and generated main-menu diagnostics redirect |
| `test_presentation_hooks.cpp` | Real filesystem fixture IAT: exact A/W read redirects and attribute sizes, unrelated/write-capable/OPEN_ALWAYS calls unchanged, edited caches refused, uninstall pass-through and cache traversal boundary |
| `CMakeLists.txt` | C++ fixtures/tests, generated-export check, PowerShell installer CTest |
| `test_activation.cpp` | Path/root, quoted/backslash command-line parsing and off-switch unit cases |
| `test_backend.cpp` | Separate `nl_backend_tests` target: case/duplicate/assignment/quoted-path backend normalization, unchanged RTX-off and unrelated raw Unicode arguments, malformed operands, real W/A/PEB replacement and byte-exact nested rollback/refusal in the test process only |
| `test_proxy.cpp` | Export/forwarding checks and temporary-host integration/rotation tests |
| `test_runtime.cpp` | Applies the real activation code to the fake runtime: blocked/read-only low fallback and failed off-mode marker reset preserve RTX; no GPU reader required |
| `../runtime.cpp` | Real activation implementation linked into `nl_proxy_tests` for the write-failure regressions |
| `host.cpp` | Statically imports `timeGetTime`; writes the timestamped main marker |
| `activation_probe.h`, `activation_probe.cpp` | M4 host probe: module/static/delay paths, environment, DLL directory, W/A/PEB command line; test-only TLS descriptor fault and hold mode |
| `fixture_runtime.cpp`, `fixture_static.cpp`, `fixture_delay.cpp` | Packaged fake d3d9 with one static and one delay dependency; controlled DllMain failures for rollback tests |
| `activation_integration.py` | M4 synthetic acceptance and unchanged-startup timing; [usage](activation_integration.py.md) |
| `install_tests.ps1` | Synthetic installer/hash/foreign-file/Steam protection cases; [usage](install_tests.ps1.md) |
| `fixture_engine.cpp`, `fixture_shader.cpp` | M5: a fake `engine.dll` whose marker a patch set rewrites (DllMain copies it, so the probe sees whether the patch came first) and a `stdshader_dx6.dll` to override |
| `fixture_filesystem.cpp` | M5 (ADR 0013): a fake `filesystem_stdio.dll` that lists a folder with `FindFirstFileA`/`FindNextFileA` and `FindFirstFileExW`/`FindNextFileW` through its own imports, as GMod's does when it mounts add-ons |
| `fixture_luashared.cpp`, `fixture_dep_module.cpp`, `fixture_dep_runtime.cpp` | Loader 0.3.0 (ADR 0024): a fake `lua_shared.dll` that loads a binary module with `LoadLibraryExA` through its own import, as GMod's does for `require`, and a `gmcl_nl_dep_win64.dll` whose static import `nl_dep_runtime_win64.dll` is deployed only beside it in `garrysmod\lua\bin` |
| `session_probe.h`, `session_probe.cpp` | M5 host probe (`--m5-probe`): loads `bin\win64\engine.dll` and `stdshader_dx6.dll` as the engine does, lists `garrysmod\addons` (relative and absolute) and `garrysmod\cfg` through the fake `filesystem_stdio.dll`, and records it all with the command line |
| `session_integration.py` | M5 synthetic acceptance: patch before DllMain, override, session cfg, restore; [usage](session_integration.py.md) |
| `check_imports.py` | Standard-library PE import/delay-import check: the bootstrap must import only KERNEL32; [usage](check_imports.py.md) |

Run all tests through `tools/build.ps1`, or select `nl_backend_tests`, `nl_proxy_tests`, `nl_proxy_generated_exports`,
`nl_proxy_installer` with CTest. `nl_proxy_host` is copied to a temporary `bin/win64/gmod.exe` beside
the built proxy. Tests never launch or modify a real game. Host scratch directories live under
the CMake binary directory (`loader/proxy/tests/scratch`); installer roots live only in `out/`.
Neither test writes generated executables to the system temporary directory.
If antivirus blocks the newly built DLL, tests must fail with the OS error; no exclusions, security
settings or alternate loading paths are added by the tests.

M4 adds `nl_proxy_kernel32_imports` and `nl_activation_integration`. The latter builds actual
packages with the runtime packager from three test DLLs, then exercises startup/activation in
synthetic gmod.exe processes below `out/tmp`. Its 17 scenario groups cover unchanged deployment,
System32 Vulkan (when installed), static and delay dependencies, off switches, user layers/arguments,
source failure/removal/Workshop disable, locks/pending recovery, another same-root process, invalid
configuration/journal, DLL initialization failures, swap fallback, path/cwd/size preconditions and
status cleanup. It records ten unchanged-startup timing samples and keeps text evidence under
`out/m4-synthetic`. No real game is launched by CTest.

M5 adds `nl_session_integration`: a runtime package and a fixes development folder (patch set,
override, session variables) in a synthetic game whose `bin\win64` holds the two M5 fixtures. Five
scenarios: RTX with `-insecure` (patched before DllMain, override, session cfg, user values recorded),
without `-insecure` (no patches, override still), RTX off (vanilla engine and shader, restore cfg run
once), the next start (record forgotten), and a later RTX session (recorded again). R1 added an
invalid journal (no restore), a restore that keeps a value the user changed, a `filesystem_stdio.dll`
without an import name table, and junctions where `loader.log` and `session.json` live (never written
through). Evidence under `out/m5-synthetic`. Loader 0.3.0 added module dependencies to the same
package: the probe loads the fake module through the fake `lua_shared.dll` in RTX sessions, in starts
without RTX and after a failed activation (it loads, its runtime loaded first from `lua\bin`), and with
the loader off (`ERROR_MOD_NOT_FOUND`).

## R6 T1 synthetic checks

`activation_probe.cpp` also captures DXVK_AFTERMATH_DUMP_PATH at host entry.
`activation_integration.py` covers first-match loader layer order, diagnostic layer/folder/env,
next_start once, preview/re-arm/config preservation, always/off, built-in low fallback, invalid
tier notes, CLI equality and generated medium/low payload copies. `test_presentation.cpp` checks
I2 in menu data and the localized row embedding. All fixtures stay below this worktree's out.
