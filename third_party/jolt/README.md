# Jolt Physics 5.3.0

MIT, Copyright Jorrit Rouwe; see [LICENSE](LICENSE).

Vendored byte-for-byte from tag `v5.3.0` of `jrouwe/JoltPhysics`:

- Archive: https://codeload.github.com/jrouwe/JoltPhysics/zip/refs/tags/v5.3.0
- SHA-256: `ee47dbd3de026829bc9734eeed960118c3d0a1a61b16e172009731a407d1466a`
- Included: `Jolt/` (library sources, headers and `Jolt.cmake`), `Build/CMakeLists.txt`,
  and `LICENSE`. No assets, samples, viewers, executables or upstream test dependencies.

The enclosing project's `glass/native/CMakeLists.txt` configures the unchanged upstream build:
static CRT/library, SSE2 baseline, no profiler/debug renderer, no floating-point traps, no LTO,
exceptions enabled. Our module and tests use C++20. No network access occurs during the build.
