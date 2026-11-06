# Oversized mesh hardware-skinning source

R20-E adds the sixth native patch, [live upscaling readback](upscaling-state/README.md), after the
R19 inputs below. Its complete changed files, bounded wire reader and SDK-free test are in that
folder; `tools/ci/pins.json` records the patched native tree. It reads runtime patch 0040 and returns
`nil` with the packaged older runtime until the combined R20 runtime import.

The [R8-B Backrooms native candidate](backrooms/Source.md) layers its reviewed model-loading,
lazy-transform and optional PAS changes on the R6 build below. That local DLL awaits Claude's
import; its full source, patch, tests and hashes are included under this existing bundled tree.

The R6 DLL rebuild adds the [memory-limit compatibility change](memory-limits/Source.md) on top
of this recorded source commit, with the same dependencies and generated projects. That folder
holds the current DLL's source commit, hash and complete patch; the record below describes the
preceding oversized-skinning build.

These files are GPL-2.0 corresponding source for the native RTXFixesBinary change,
kept separately from the MIT loader. [COPYING](COPYING) is the upstream licence.
[build-pins.json](build-pins.json) records the built DLL, source hashes, dependency
revisions and generated project hashes. No Workshop model or texture is included.
The exact source commit is b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe on the local
codex/oversized-skinning-native branch. The preceding DLL SHA-256 is
5e626e34f412cd55e93a485cd1d777794b339a0cb7a5082935454b72fbc72db7.
The body/arms preview passed the owned cold game check; this final build also
adds the reviewed small-group render-pass and diagnostic-filter eligibility guards. That branch
has not been pushed; the complete files and patch below remain sufficient for
reconstruction from the recorded public native base.

The complete modified files are [HardwareSkinningHooks.cpp](source/HardwareSkinningHooks.cpp),
[oversized_skinning_policy.h](source/oversized_skinning_policy.h),
[the standalone test](tests/oversized_skinning_test.cpp), its
[usage notes](tests/oversized_skinning_test.md), and [the modified upstream README](UPSTREAM_README.md).
The public repository is https://github.com/SheepyLord/garrys-mod-rtx-remixed.git.

## Rebuild

The local source checkout was fc478c06ec5ae0a94f64aec19df8610a46c51c35. For a fetchable
native base, use d958da61cc7be04efbb17abf38aa1cbacc300019 from that repository. Every
native source/header named in the generated RTXFixesBinary project was compared
between those two commits and was identical; the complete verified file list is
in build-pins.json. The later local water/Lua changes do not affect this DLL.
The separate [fc478c06 Lua patch](upstream-fc478c06-lua.patch) preserves that local
commit's three Lua edits as an additional reference; it is not required for the
native build and does not replace the aggregate package's current Lua files.

1. Clone the upstream repository and check out the recorded native base.
2. Initialize garrysmod_common and its recursive dependencies at the recorded
   revisions. Its top-level revision is a854f237b79087826aa9a98a05de5e0d2b4502b6;
   sourcesdk-minimal is 61bf02ea6eaedcabf66784dfb0e54c9e3feefdcc.
3. Apply [oversized-hw-skinning.patch](oversized-hw-skinning.patch), or copy the
   complete source/test files above over their matching checkout paths.
4. Overlay build-projects onto the checkout. It contains the generated native
   project and dependency projects used for this build, with relative paths.
5. In a VS 2022 x64 developer environment, build gmcl_RTXFixesBinary.vcxproj with
   Configuration=ReleaseWithSymbols, Platform=x64 and OutDir pointing to a new
   output directory. Keep each project's normal separate intermediate directory.
   The exact MSBuild command and toolchain pins are in build-pins.json.

The native project does not build or link RTXDebug, RTX Water, a game executable
or any MIT loader target. Build all outputs under the aggregate repository's out
directory. The standalone policy test needs C++17 and no game or GPU; leave
assertions enabled for Release builds.

## Behavior and validation

An already hardware-skinned, non-flex group with at least 32,768 vertices can
avoid Source's software-path rejection without changing r_forcehwskin. Before
approving it, the creation hook checks the compiled VTX: every hardware bone slot
used in each strip must be assigned by that strip's own bone-state changes. The
runtime strip data must match. A bounded certificate table and a strip-state
fingerprint reject unknown or changed groups; prior cached palettes cannot
approve missing assignments.

The same borrowed-state scope covers both the dynamic and direct hardware draw
entries: Source's direct HW entry has its own software fallback without the
dynamic entry's capacity check. A scoped re-entry preserves all nine arguments;
the same-group marker prevents a dynamic-to-static call from wrapping twice.
Unknown static-fallback config38 bit0x08 skips an oversized group safely.

With r_forcehwskin enabled, smaller already-HW/non-flex groups also use the scope
when inside the main render pass with a valid multi-bone pose and when the legacy
r_hwskin_setbones predicate selects that model (mode1 or matching bone count).
This prevents simultaneous CPU posing and native indexed bone upload. Ordinary
small force0 draws, rigid single-bone props, explicit small-model diagnostic
disable/filter settings and existing forced-eye/flex behavior retain their paths.
Complete strip certificates remain mandatory only for oversized groups; smaller
user-forced groups keep the existing remap cache and fallback behavior.

The scoped draw restores renderer/material flags and limits bone upload to that group.
Its DrawIndexedPrimitive call borrows an unswizzled UBYTE4 blend-index declaration
only when needed, then restores the original declaration. The declaration cache
holds both original and converted COM references, is bounded to 16 entries and
is released at shutdown. Bone palette/blend states, group flags and per-strip
state are restored on normal or exceptional return. Missing required state skips
the eligible draw safely. Certified oversized draws require bone upload even when
the diagnostic filter is zero or mismatched, to prevent their unsafe software
fallback; the filter's stored value itself is never changed.

Offline checks cover threshold boundaries, hardware/flex/user-force eligibility, missing
strip slots, rejection despite stale cache contents, repeated borrowed-state
restoration, diagnostic-filter selection and failed capture. GPU acceptance is separate: the owned PoC test
uses the same large model with two skins, hardware skinning off/on and ordinary
models/first-person arms afterward. No real game install is changed by these
source files or tests.
