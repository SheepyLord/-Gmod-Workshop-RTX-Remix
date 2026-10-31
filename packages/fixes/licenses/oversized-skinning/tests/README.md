# Oversized skinning policy tests

Standalone GPL-2.0-only CPU checks for the policy shipped with the RTX fixes module. This test
executable contains no Source SDK, game, Direct3D or GPU dependency and links no MIT loader object
code. The root build adds this directory after the loader; nl_build_options supplies only common
compiler/linker flags. No GPL test code is linked into winmm.dll or nl_core.

| File | Purpose |
|---|---|
| `oversized_skinning_test.cpp` | Exercises the software-limit boundary and hardware/flex eligibility, complete per-strip bone palettes, and fake-device palette/blend state restoration including failure paths |
| `../source/oversized_skinning_policy.h` | Actual shipped GPL policy and state-snapshot implementation used by the test, not a test reimplementation |
| `CMakeLists.txt` | Registers the separate executable and CTest rtx_oversized_skinning_policy; /UNDEBUG keeps assert checks active in Release |

From the repository root in the normal MSVC x64 environment:

```powershell
cmake --preset win64-release
cmake --build --preset win64-release --target rtx_oversized_skinning_policy
ctest --test-dir out/build/win64-release -R '^rtx_oversized_skinning_policy$' --output-on-failure
```

The normal tools/test.ps1 Release run also builds and runs this CTest, including on CI without an
NVIDIA GPU. The test prints PASS and exits zero on success; an assertion failure exits nonzero.
Only normal CMake build output is written under out/build. These CPU checks do not establish
rendering or animation correctness; PoC before/after checks remain separate.
