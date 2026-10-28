# loader/proxy/tests

CTest tests reuse `loader/tests/nl_test.h` and compile its unchanged `test_main.cpp` runner.
`nl_proxy_tests` has 14 cases: allocation-free host/root/token/off-switch logic, all current system
export names and ordinals, calls through a separate loaded proxy, and child-process entry hook,
off switches, non-game hosts, failed logging and five-log rotation. Unicode scratch paths exercise
wide Win32 file handling. A host marker records its FILETIME and whether the log existed at main.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | C++ fixtures/tests, generated-export check, PowerShell installer CTest |
| `test_activation.cpp` | Path/root, quoted/backslash command-line parsing and off-switch unit cases |
| `test_proxy.cpp` | Export/forwarding checks and temporary-host integration/rotation tests |
| `host.cpp` | Statically imports `timeGetTime`; writes the timestamped main marker |
| `install_tests.ps1` | Synthetic installer/hash/foreign-file/Steam protection cases; [usage](install_tests.ps1.md) |

Run all tests through `tools/build.ps1`, or select `nl_proxy_tests`, `nl_proxy_generated_exports`,
`nl_proxy_installer` with CTest. `nl_proxy_host` is copied to a temporary `bin/win64/gmod.exe` beside
the built proxy. Tests never launch or modify a real game. Installer roots live only in `out/`.
If antivirus blocks the newly built DLL, tests must fail with the OS error; no exclusions, security
settings or alternate loading paths are added by the tests.
