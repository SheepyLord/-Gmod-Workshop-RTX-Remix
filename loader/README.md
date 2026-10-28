# loader/

C++20 sources of the native loader: the bootstrap DLL that 64-bit Garry's Mod loads as
`bin\win64\winmm.dll`, the core library it shares with a command-line tool, and their tests. Built
with [`tools/build.ps1`](../tools/build.ps1.md) through the root `CMakeLists.txt` and
`CMakePresets.json`.

| Folder | Target | Status | Contents |
|---|---|---|---|
| [`core/`](core/README.md) | `nl_core` (static library) | M2 done | Everything that does not need to run inside the game: GMA and LZMA reading, JSON, path rules, manifests, packages, `config.json`, discovery, planning; deployment comes in M3 |
| [`tests/`](tests/README.md) | `nl_tests` (CTest) | M2 (62 cases) | Unit tests for `nl_core` with a small in-repo harness |
| [`proxy/`](proxy/README.md) | `winmm.dll`, `nl_proxy_logic`, `nl_proxy_tests` | M1 done (inert) | Complete System32 export forwarding, host/off-switch checks, entry-point hook and guarded logging; synthetic-host and installer tests |
| [`cli/`](cli/README.md) | `nlctl.exe` | M2 done (read-only) | `inspect`, `verify`, `scan`, `manifest`, `plan`, `version` on archives, packages and installs, without starting the game; `apply` and `rollback` come with M3 |

`CMakeLists.txt` here only adds the sub-folders. Every module folder keeps a `README.md` that names each
of its source files; [`tools/check_repo.py`](../tools/check_repo.py.md) enforces this.

Design: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). Component map: [docs/COMPONENTS.md](../docs/COMPONENTS.md).
