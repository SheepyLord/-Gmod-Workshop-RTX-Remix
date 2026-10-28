# loader/

C++20 sources of the native loader: the bootstrap DLL that 64-bit Garry's Mod loads as
`bin\win64\winmm.dll`, the core library it shares with a command-line tool, and their tests. Built
with [`tools/build.ps1`](../tools/build.ps1.md) through the root `CMakeLists.txt` and
`CMakePresets.json`.

| Folder | Target | Status | Contents |
|---|---|---|---|
| [`core/`](core/README.md) | `nl_core` (static library) | M0 skeleton | Everything that does not need to run inside the game: GMA reading, manifests, discovery, planning, deployment (M2/M3) |
| [`tests/`](tests/README.md) | `nl_tests` (CTest) | M0 | Unit tests for `nl_core` with a small in-repo harness |
| `proxy/` | `winmm.dll` | planned (M1) | Export forwarding to the system `winmm.dll`, host checks, entry-point hook, activation |
| `cli/` | `nlctl.exe` | planned (M2) | `list`, `inspect`, `plan`, `apply`, `rollback`, `verify` on an install, without starting the game |

`CMakeLists.txt` here only adds the sub-folders. Every module folder keeps a `README.md` that names each
of its source files; [`tools/check_repo.py`](../tools/check_repo.py.md) enforces this.

Design: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). Component map: [docs/COMPONENTS.md](../docs/COMPONENTS.md).
