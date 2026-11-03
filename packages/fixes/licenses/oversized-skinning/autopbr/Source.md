# R12 imported PBR corresponding source (GPL-2.0)

The fixes [LICENSE](../../../LICENSE) applies. This layer builds on the shipped R8 native source
`7094baf6edf6797fd5c3f0b58ca668f9307b4906`, reconstructed through the
[preceding source record](../backrooms/Source.md). The R11 base branch `codex/r11-autopbr` ended at
`633fd5e000aca862a8ae58b5c722d678ac4fa053`. Phase 1 is `72d53f4`; phase 2 is `5ad6f23`;
`1679a99` moves VMT I/O off frame after profiling, and `6e33b90` adds R11-B's source-less game-map
registry. `cc77daa` fixes damaged-registry recovery, durable saves and session-scoped save warnings.
`633fd5e` resolves each live texture identity once per worker and persists USD publication ownership.
Nothing was pushed.

The current fixes branch is `claude/r13-maps`, commit `913bb6b83fc0830f901cbe54904e843cef8ea61d`.
R12 adds conservative UV-feature pairing, texture-scoped durable player choices, the embedded
translated editor, and drawn-before-load identity capture. The source/DLL identity below supersedes
the R11 build identity; the earlier history remains documented for reconstruction.

[autopbr.patch](autopbr.patch) is the complete change from that base. Complete changed files are
also included at their native-repository paths; [source-files.json](source-files.json) records their
SHA-256 values and the built source/DLL identity. Overlay them onto the exact base, or apply the patch.
The tests generate synthetic fixtures; no user model or texture is distributed here.
Copies retain the native working-tree bytes/line endings. Applying the canonical Git patch to the
base reproduces all 35 changed files after CRLF normalization; build hashes record the raw source bytes.

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

R11-B records each successful game material in an atomic, bounded `game_materials.registry` beside
the output textures. A current live `mmd/t/<16 hex>` identity can restore the material without its
source only if every published DDS passes full header/mip-size, byte-count and content-digest checks.
Old hashes never register themselves. Readable sources use the current converter; missing/invalid
records are pruned, other well-formed schema versions/oversized files remain read-only and intact,
and registry edits are preserved before replacement. Damaged files start empty and writable, log once,
and are backed up before a fresh registry is written. Staging uses CreateFileW/WriteFile,
FlushFileBuffers and CloseHandle before write-through MoveFileExW; failures remove staging files.
An unsavable registry warns once per module session, including across worker restarts.
Record compatibility is independent of generator version. Cache clearing retains the registry/DDS
and requeues live materials. See [ADR 0093](../../../../../docs/decisions/0093-cached-imported-game-materials.md).

Each worker invocation now caches successful and no-maps resolutions by live texture identity.
Later jobs register that result with their own current hashes without source probing, conversion,
DDS hashing or registry access. A cache clear or worker restart starts a fresh session.
USD publication keeps a flushed, atomically replaced `<target>.last-published` size/digest sidecar.
An exact match recognizes our output across process restarts. Edited/foreign USD and damaged,
missing or stale records still require the existing backup; no existing backup is deleted.

**Runtime patch 0020 now supplies absolute precedence** ([ADR 0092](../../../../../docs/decisions/0092-generated-fallback-mods-rank-last.md)). The fixes also exclude every authored
hash they can conservatively inspect and remove late conflicts, including Unicode-later mod names.
Folder scanning alone cannot synchronize runtime swaps. See
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
`out/worktrees/r11-fixes/out/build` and `out/deps`. R11-B rebases those prepared projects' build/output
and per-project intermediate paths into `out/worktrees/r11-cache/out/r11-b/build` and `module`,
while reading the same isolated dependencies and fixes source. No source or library is downloaded.

From an x64 VS shell in the R11-B loader worktree:

```powershell
MSBuild.exe out/r12-b/build/gmcl_RTXFixesBinary.vcxproj /nologo /m:4 /v:minimal /p:Configuration=ReleaseWithSymbols /p:Platform=x64 /p:VCToolsVersion=14.44.35207 /p:WindowsTargetPlatformVersion=10.0.26100.0
```

The current DLL is **5,491,712 bytes**, SHA-256
`447b9dde0a201e50320e1225330354e0316eedf93fd2b7bce2f610288da9c4d2`.
The matching PDB remains beside it under the R13-M loader worktree's `out/r13-m/module`.

Native regressions compile the production format handlers, VTF wrapper/core and USD writer with
the existing VTF filesystem/logging stubs and assertions enabled. They cover malformed/resource VTFs,
Unicode-later conflicts, binary-USD suppression, changed/deleted snapshots, preservation of user edits,
zero emission, Source metal/roughness, Exo/GPBR channels and all four format detectors. The separate
game regression covers packed channels, green convention, shared skin, Unicode PMX names, malformed
PMX, rooted/traversal paths, duplicate companions and image sanity. Commands are in the native
[implementation notes](docs/TOPBR_R11.md). The aggregate Lua harness covers the indexed driver.
R11-B's standalone production registry/selector test is also built by the aggregate Release gate:
atomic persistence/failure, edit preservation, identity/current hashes, source refresh, record/generator
versions, missing/truncated/edited DDS, bounded malformed input, settings and authored exclusion.
Review cases verify damaged-file backup/recovery and fresh reload/record/restore, preserved decimal
other-version/oversized bytes, and staging cleanup after a Windows sharing violation at replacement.
Second-review cases cover once-per-worker identity resolution, new live hashes, no-maps/rejection,
distinct identities and new worker sessions. The USD regression republishes in separate processes,
verifies same-size edited/foreign bytes and missing/damaged/stale sidecar fallback, and checks failed
USD/sidecar writes and staging cleanup.
The Lua harness also tests absent source/base metadata and clear/requeue. The existing production
Source/VTF/USD and game-channel harnesses pass on the rebuilt source.

PoC profiling reduced the maximum client snapshot from 23.553 to 0.830 ms by moving VMT reads and
companion discovery off frame. Construct conversion p99 fell from 23.472 to 9.133 ms.

## R12-B original validation

R12 rebases the prepared R11-B projects and intermediates into `out/r12-b/build` and `module`.
They read the same pinned dependency copy; no dependency is downloaded or changed. Generator v6
includes map roles and layout in content keys. The automatic registry format stays unchanged.
`game_matching.inl` and `game_overrides.h` contain the production matcher and independent durable
choices; the new panel is embedded in the existing trusted ToPBR Lua driver, with viewport sizing,
scrolling and all six bundled translations. No companion exemption or runtime source is changed.

The SDK-free `tests/game_matching_test.cpp` uses the production matcher/choice selector and tests
spatial selection, ambiguity/flat/aspect/path/family bounds, canonical normal-only Silver families,
conflicting layouts, drawn-before-load, override/none/automatic precedence, current-hash restoration
without source, changed DDS and atomic-save failure. It compiles with assertions and `/W4 /WX`.
`tests/game_match_probe.cpp` runs production discovery with ordinary/name-hidden pairing and
reports its actual layout; usage is in `tests/game_match_probe.md`. The corpus is 1,133 unique
folder/base pairs from 121 PMX files; 259 canonical references yield 135 agreements, 124 abstentions
and no disagreements with names hidden. This is a naming comparison, not independent human labels.
No model/texture from that corpus is distributed.

The native-loader Release suite also executes the actual embedded Lua panel section under its
Derma/native harness. PoC checks use two model-name-only variants with identical texture bytes,
distinct asset/material names and a shared live texture. The R12-B handover report records rendered
on/off, shared choices, source-hidden restoration, exact PoC rollback and the final Release gate.

The rendered editor check also verified stock Derma compatibility: both panel types clear through
`DForm:Clear`, and native-state polling preserves the base Think handler. The DLL is unchanged.

## Follow-up: R12-B2

The current commit/DLL above includes straight-alpha source decode followed by independent
integer-area RGBA averaging, generator/key/marker v7, isolated bad families and name-confirmed
auxiliary data masks. Core/base descriptors take the existing budget first. Unknown siblings,
diffuse variants, self-votes and conflicting explicit exported families cannot supply auxiliary
matches. Names-hidden core scoring and the .28/.36/.12 thresholds stay unchanged.

The generated PNG regression is SDK-free and runs in the loader Release gate; it verifies
alpha-zero RGB and fractional 7x7 to 3x3 averaging. The native game test also verifies a larger
transparent packed map converted at the normal's smaller size. The real Body01_B map at 128x128
retains mean R/G/B 154.561/113.404/230.281 versus 154.556/113.407/230.278 at source size.
Its conversion checks 16,384 eligible pixels, including 15,904 under alpha zero, for exact
roughness/metallic/AO values. The old Fant path had mean RGB 3.1, with 0.0 under alpha zero.

The unchanged 121-PMX / 1,133-base / 259-reference corpus now measures 146 agree, 0 disagree,
113 abstain with names hidden (WuWa 39/0/36, Endfield 75/0/53, Silver 32/0/24). All 14 new
names-visible acceptances were inspected. A measured 3x3 blur was rejected after a wrong
iris/body pairing; production stays unblurred. The report lists every new acceptance and all
16 Alf2 bases. Hair uses Hair01_A_AnisoMaskPS and 衣饰 uses Body01_B_MRA; 熔岩 and 眉毛 abstain.

The tested DLL gives Alf2 hair and two accessory materials automatic game maps in the PoC.
The screenshot and normal exit 0 have zero Lua/device errors. All 3,284 snapshot files and their
timestamps, the exact prior journal, prior console (restored unread), user.conf and Steam depot
checks match after restoration; the owned PoC lock is released. Evidence is in `out/r12-b2`.

## Follow-up: R12 hotfix (the user's urgent request, 2026-11-03)

Imported game maps no longer stop at ToPBR's 1 GiB of new DDS per module session: only the opt-in
world conversion counts toward it (`WriteTextureToDDS(..., sessionBudget)`; the game converter passes
false). A budget or free-space refusal logs one clear warning per session instead of only the
generic "DDS publication failed". The field game had stopped converting after 56 maps
(1,068,156,512 bytes), so later characters such as 洛茜 got no maps until a restart. Built with a
full rebuild of the same project; published without the usual tests at the user's request.

## Follow-up: R13-M (compact maps, reuse across versions; the user's R12-B3 request)

Imported game maps are stored compactly: the octahedral normal in BC5, roughness and metallic in
BC4 (DX10 headers, full mip chains, `dds_codec.h`), emission uncompressed; the unused AO map is no
longer written. A 2048x2048 family is 11,185,308 bytes instead of 89,478,992, and what Remix loads
for it falls from 67,109,244 to 11,185,308 bytes. Validation still accepts the uncompressed layout.
Content keys and completion markers carry the conversion recipe instead of a generator salt, so a
release that changes no conversion reuses every map. Finished earlier families are re-encoded
instead of converted again (resized v5/v6 maps and ambiguous v5 layouts convert from source);
records without a source are re-encoded and saved atomically. Imported game maps have no session
budget; each refusal names its limit and numbers in the log and the panel, and a family stopped
halfway completes. `tests/game_dds_test.cpp` covers these without an SDK; the loader's Release
suite runs it from this copy. See the loader's ADR 0098 and `docs/TOPBR_R11.md`.
