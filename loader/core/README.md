# loader/core/ (`nl_core`)

Static library holding the loader logic that does not depend on running inside `gmod.exe`, so the
bootstrap DLL, the `nlctl` CLI and the unit tests all use the same code. In M0 it only carries the
version; M2 and M3 add GMA reading, package manifests, discovery, planning and deployment.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Defines `nl_core`; generates `nl/version.h` into the build folder |
| `include/nl/core.h` | Public API of `nl_core` (currently `nl::version()`) |
| `include/nl/version.h.in` | Template for the generated `nl/version.h` (`NL_VERSION_*` macros from the CMake project version) |
| `src/version.cpp` | `nl::version()` |

Rules for code here: no global state, no Windows UI, no calls that need the loader lock to be free
(this code also runs in the bootstrap's start-up step), and every public function covered in
[`../tests`](../tests/README.md).
