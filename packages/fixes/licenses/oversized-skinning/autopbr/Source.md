# R11 automatic PBR corresponding source (GPL-2.0)

The fixes [LICENSE](../../../LICENSE) applies. This layer builds on the shipped R8 native source
`7094baf6edf6797fd5c3f0b58ca668f9307b4906`, reconstructed through the
[preceding source record](../backrooms/Source.md). The local fixes branch `codex/r11-autopbr` ends at
`1679a99a3b54576b0b4c68f8bf86972bf3c42969`. Phase 1 is `72d53f4`; phase 2 is `5ad6f23`; the final commit moves VMT I/O off frame after profiling. Nothing was pushed.

[autopbr.patch](autopbr.patch) is the complete change from that base. Complete changed files are
also included at their native-repository paths; [source-files.json](source-files.json) records their
SHA-256 values and the built source/DLL identity. Overlay them onto the exact base, or apply the patch.
The tests generate synthetic fixtures; no user model or texture is distributed here.

## Behavior

The worker prepares VMT metadata in two bounded slots. One client-frame snapshot adds live engine
properties/hashes without file reads; two ready slots feed one decode worker.
World and imported-game switches are independent. Source content/recipe keys replace timestamp-only
reuse, registrations are session-local, and USD output is an atomic complete snapshot, including
removals. Prior/user-edited generated USD is retained before replacement. Invalid DDS cache candidates
are quarantined. Decode, queue, raster, scan, new-output and free-space limits fail safely. Native
worker start/stop is serialized; no live IMaterial is accessed by its decode thread.

Game conversion uses bounded local PMX UV/class data and companions: WuWa RG normals plus class
fallbacks, Endfield RG normals and P (R metal, A smoothness, B AO), Silver Palace XYZ normals and MRA.
Endfield green is flipped. Named skin/face/eye regions are protected, original albedo/alpha remain,
and AO is retained as data. A completed, content-keyed cache bypasses decode/raster work on later runs.
The default-on checkbox is translated by the MIT companion. Source conversion remains opt-in.

**Runtime integration is still required for absolute precedence.** The fixes exclude every authored
hash they can conservatively inspect and remove late conflicts, including Unicode-later mod names.
They cannot change the runtime's first-mod lookup or synchronize its asynchronous swaps. This is
not a claim that folder scanning proves the user's unconditional priority requirement. See
[ADR 0091](../../../../../docs/decisions/0091-automatic-pbr-fallbacks.md) and the
[R11-A report](../../../../../docs/handover/R11-A-report.md).

## Rebuild and validation

Use the same recorded ReleaseWithSymbols x64 projects and pinned dependencies as R8. All 2,334
tracked dependency files matched local git objects after CRLF normalization; 59 omitted build files
were restored under the isolated dependency copy ([record](dependency-verification.json)). Only
ToPBR sources, its Lua, tests and documentation changed. The premake source/header globs already cover
the new headers. WIC/COM system libraries were already linked by the module's texture bridge.

MSVC 14.44.35207, Windows SDK 10.0.26100.0, C++17. Run the R8 MSBuild command with all output,
intermediates and TEMP/TMP under out. R11's isolated generated projects and dependency copy are in
`out/worktrees/r11-fixes/out/build` and `out/deps`; reproducing this layout only rebases the recorded
projects' paths, OutDir and per-project IntDir. No new source or library is downloaded.

The DLL is **5,060,608 bytes**, SHA-256
`c4833fc18673ab050aeac7d6c43431908cd9e4d1212dbfce0b5cd88157418a1c`.
The matching PDB remains beside it under the fixes worktree's `out/r11-module`.

Native regressions compile the production format handlers, VTF wrapper/core and USD writer with
the existing VTF filesystem/logging stubs and assertions enabled. They cover malformed/resource VTFs,
Unicode-later conflicts, binary-USD suppression, changed/deleted snapshots, preservation of user edits,
zero emission, Source metal/roughness, Exo/GPBR channels and all four format detectors. The separate
game regression covers packed channels, green convention, shared skin, Unicode PMX names, malformed
PMX, rooted/traversal paths, duplicate companions and image sanity. Commands are in the native
[implementation notes](docs/TOPBR_R11.md). The aggregate Lua harness covers the indexed driver.

PoC profiling reduced the maximum client snapshot from 23.553 to 0.830 ms by moving VMT reads and
companion discovery off frame. Construct conversion p99 fell from 23.472 to 9.133 ms.
