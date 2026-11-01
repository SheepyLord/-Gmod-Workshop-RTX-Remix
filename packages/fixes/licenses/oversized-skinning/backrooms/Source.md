# R8-B Backrooms native source

GPL-2.0 corresponding source for the candidate `gmcl_RTXFixesBinary_win64.dll`, layered on
the [R6 memory-limit build](../memory-limits/Source.md) and its
[oversized-skinning base](../Source.md). The existing [COPYING](../COPYING) applies.
This directory is inside the source tree already bundled as `remixbinary/src/hw` by
`tools/workshop.json`; it needs no new package-builder setting.

The DLL is built and committed locally, **pending Claude's import**. This task does not
change `packages/fixes/files.json` or its binary inputs. Until that import the indexed DLL
remains `cfcbdc95617f88ec3b002e47d35838376e77e5bba77023365a81927bbd04cfe0`.

- Repository: https://github.com/SheepyLord/garrys-mod-rtx-remixed.git.
- Exact packaged base: `a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`.
- Local source commit: `7094baf6edf6797fd5c3f0b58ca668f9307b4906`, branch
  `codex/r8-backrooms-native`. Neither branch nor commit was pushed.
- Candidate DLL: 4,864,512 bytes; SHA-256
  `18e1ebc75ac96099211205203bb6ed58cdc8d8b1c7390cee62607ec5124d9f42`.
- Matching PDB: 40,153,088 bytes; SHA-256
  `822d9356ca8900e599f3a84087cff82ab963dfdc3e14c6a5f26c145335759554`.
- [build-pins.json](build-pins.json) records paths, dependencies, generated project hashes,
  source/test hashes, toolchain and validation. [backrooms-native.patch](backrooms-native.patch)
  is the complete native commit, including its regression harness.

Complete changed native files: [HardwareSkinningHooks.cpp](source/HardwareSkinningHooks.cpp),
[modelload_fixes.cpp](source/modelload_fixes.cpp), [culling_patches.cpp](source/culling_patches.cpp),
[culling_patches.h](source/culling_patches.h), [vis_pas_policy.h](source/vis_pas_policy.h),
and [module.cpp](source/module.cpp). The new [test script](tests/test_backrooms_native.py)
and [test instructions](tests/test_backrooms_native.py.md) are included. Other native source
and dependency pins are unchanged. Complete predecessor source remains in the two layers above.

## Port and review

The reviewed branch, `claude/rtx-remix-map-enhancement-bda9ac`, ends at
`e4d548d90a814c8e927d2569674c4dacc5185b8a`; it has no later native change to inspect.
All selected hunks applied cleanly. There was a semantic dependency on an earlier change,
and the following safeguards were added during review:

- **6b4794f: cache missing SW VTX files per map.** Also port the model-loader hunk from
  `672ada9`, which stops probing each mount after a GAME-wide search has already proved
  the file absent. A separate `missing` result distinguishes an unsuccessful open from a
  truncated/zero-checksum SW VTX: malformed or mismatched files still try lower-priority
  mounts. Cache keys ignore case and slash direction but keep GAME and null/all-path searches
  separate; a GAME miss cannot hide a file from another path ID. Specific path IDs bypass it. The
  mutex protects the bounded 65,536-entry cache and statistics, not filesystem I/O.
  Model-load shutdown clears it; hardware-cache flushes keep it. Mounted content is assumed
  stable for the map session; newly supplied files at the same path need a new map session.
- **62f4af0: defer the entity coordinate-frame read.** Bone-upload, per-strip and diagnostic
  consumers call the same checked `ReadProcessMemory` resolver, at most once per studio
  renderable, including a failed read. The finite/range validation is retained. A nested
  studio draw saves and restores its caller's pending renderable and resolved matrix,
  including SEH exits. The oversized automatic path still uploads bones with `r_forcehwskin 0`;
  complete strip certificates, scoped palette/declaration restoration, static-fallback guards,
  flex exclusions and small-model diagnostic filters are retained.
- **e4d548d native part: optional PAS visibility.** `rtx_patch_vis_pas` defaults to `0` and
  uses the existing `RTX_SyncPatches` entry point. It redirects each in-memory PVS offset to
  that cluster's existing PAS offset. The port requires a unique executable CM_Vis match,
  globals inside engine.dll, a readable vis lump of at most the SDK's 16 MiB limit, a writable
  offset table, 1–65,536 clusters, and in-bounds offsets. It records original PVS/PAS offsets
  plus allocation, map name and size; it restores only a table it still owns. Changed/freed
  tables lose their saved state. Native module close explicitly restores owned offsets
  before code patches are removed. Default-off sync performs no vis-table reads or writes.

PAS reuses the engine's compiled visibility streams; this is not a BSP/RLE validator.
CM_Vis remains an engine-version-dependent signature. A failed/ambiguous resolution leaves
PVS unchanged and logs the reason; the convar's existence alone does not prove PAS applied.
Map replacement relies on the normal client-module close lifecycle as well as map/table identity.
The additional visible geometry may cost more on other maps; enabling this optional switch
there is a deliberate user/add-on choice. It cannot widen a remote server's visibility:
listen-server shared engine data can follow it, while a separate server remains authoritative.

The branch's alternative large-mesh shortcut and unrelated `0562ed8` texture-tracker change
were not copied. The packaged oversized protections and memory-limit no-op remain in force.
The module opens only after Remix initializes; ordinary RTX-off loading gains no new native path.
These changes edit process memory, never depot files or Remix configuration files.

## Rebuild

1. Use the exact local base above. If reconstructing it, follow the preceding
   [oversized-skinning](../Source.md#rebuild) and [memory-limit](../memory-limits/Source.md)
   records from their public native base. Apply `backrooms-native.patch` with `git apply`
   (or `git am` on the recorded base), or overlay the complete changed files at matching paths.
   The patch was independently applied to an a2c8dbc5 fixture and every result matched the
   built source after CRLF normalization.
2. Reuse the prepared `oversized-native/garrysmod_common` dependencies and overlay the unchanged
   [generated projects](../build-projects). All 2,334 tracked dependency files were compared
   against pinned local git objects; 59 omitted build/template files were restored from those
   objects. No download or submodule update was performed. Details:
   [dependency-verification.json](dependency-verification.json).
3. In a VS 2022 x64 developer shell use MSVC **14.44.35207** and Windows SDK **10.0.26100.0**.
   Build only the generated `gmcl_RTXFixesBinary.vcxproj` and its library references:

   ```powershell
   MSBuild.exe gmcl_RTXFixesBinary.vcxproj /nologo /m:4 /v:minimal /p:Configuration=ReleaseWithSymbols /p:Platform=x64 /p:VCToolsVersion=14.44.35207 /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:OutDir=<fixes-worktree>/out/r8-module/
   ```

   The first build used `/t:Rebuild`; the final command rebuilt the last modified inputs.
   Keep default separate project intermediates and TEMP/TMP under the aggregate `out/`.
   No other module or game target is built. Existing SDK/source warnings and the existing
   LNK4229 delay-load directive warning remain; both builds succeeded.
4. Preserve DLL and PDB together. This is a controlled pinned rebuild, not a promise of
   identical binary bytes across checkout paths, timestamps and linker invocations.

## Offline validation and Lua API

All native checks passed with assertions enabled:

- [test_backrooms_native.py](tests/test_backrooms_native.py.md): production checksum/model
  resolver, lazy resolver/studio hook, PAS adapter and policy in three MSVC C++17 `/W4 /WX`
  harnesses; 8,000 concurrent cache hits, malformed-file fallbacks, bounded/reset cache,
  lazy failed/successful reads, nested pending/resolved draws, nine forwarded arguments, SEH,
  1,000 visibility toggles, maximum clusters, ownership/map changes, signature rejection,
  read-only/inaccessible/freed memory and module-close restoration.
- Existing oversized-skinning policy/strip-palette/borrowed-state regression.
- Existing production-method memory-limit harness: 8,000 concurrent calls, disconnected API,
  Lua success/invalid arguments, one notice and zero configuration writes.
- [PE check](pe-check.json): x64, unchanged imports (including delay imports) and named exports
  against the packaged a2c8dbc5 DLL; unsupported memory-limit key strings absent.

[lua-api-check.json](lua-api-check.json) records the static API review of the add-on at e4d548d.
It calls `RemixLight.CreateSphere/CreateRect/CreateDisk/DestroyLight` and
`RemixConfig.GetConfigVariable/SetConfigVariable`; the native registrations, parameter tables
and light-ID handling support these calls already, including entity ID `0`. Package Lua requires
the module, syncs patches, exposes `Light2RTX.Clear` and `rtx_api_map_lights_autospawn`, and uses
all three updater hook names that the add-on suspends. Packaged NikNaks provides `ClusterFromPoint`
and `PASForOrigin`. Its material collector already avoids per-prop mesh extraction. **No matching
Lua change is needed.** The new convar is supplied by this candidate DLL.

No game, Lua VM or renderer was launched. Native harnesses use fake engine/filesystem interfaces;
signature matching against the installed engine, rendered lights, map-load performance, multiplayer
visibility and frame-time acceptance remain with Claude. The integration QA steps and aggregate
Release-suite result are in [R8-B-report.md](../../../../../docs/handover/R8-B-report.md).
