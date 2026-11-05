# R19-X report: the RTX fixes (GPL)

Branch `r19-fixes` (worktree `out\worktrees\r19-fixes`), from `r19-int`. Brief: [R19-plan.md](R19-plan.md),
section R19-X; findings: [R19-review.md](R19-review.md) H3 and "RTX fixes"; decision record
[0112](../decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md).

## Findings

| ID | Verdict | Result |
|---|---|---|
| **H3** (Codex F-02) ToPBR's output folder | confirmed, high | **Fixed** (patch `lua-paths.patch`) |
| H3's miss: `SetEnabled(true)` over the player's 0, `ProcessSingleMaterial` | confirmed | **Fixed** (same patch) |
| Other path setters in the fixes' Lua APIs | found here | **Fixed** (same patch, and the water patch) |
| **F-01** water polygon | partly, low | **Fixed** (`rtxwater-lua-input.patch`) |
| **F-03** a second "on" orphans a light | partly, low | **Fixed** (`cl_remix_flashlight.lua`) |
| **F-04** flashlight receivers unthrottled | partly, low | **Fixed** (`sv_remix_flashlight.lua`) |
| Flashlight miss: `PlayerSwitchFlashlight` true for everyone | confirmed, low | **Fixed** (`sv_remix_flashlight.lua`) |
| F-05 map-light names | false positive | Not touched |
| F-06 glass shard re-requests | false positive (retired add-on, not shipped) | Not touched |

### H3 and its miss (`gmcl_RTXFixesBinary`)

What the shipped Lua uses: nothing calls `SetOutputDirectory`; the converter writes to its default,
`<game root>\rtx-remix\mods\~gmod_topbr\textures` (`to_pbr.cpp` Initialize). So that folder is the root.

- **`source/lua_path_policy.h`** (new, standard C++): `RelativePath` (no leading `/` or `\`, so no
  root, UNC or `\\?\`; no `:`; no `..` segment; no segment ending in `.` or a space; no device name;
  no control character; at most 1024 bytes), `LocalDrivePath`, `Inside(root, relative)` (joins plain
  segments, rechecks the lexically normal result against the root component by component, without
  case), `AbsolutePathValue`, `RemixPathOption`.
- **`SetOutputDirectory`** takes a folder relative to the converter's own (`""` or `.` = that folder),
  refuses anything else and a link or junction below the root, warns
  (`Output directory refused (<reason>); it stays <folder>`), keeps the folder, and now returns a
  boolean. An accepted change still cancels pending work, as before.
- **The player's settings:** `SetEnabled(true)` takes effect only while the player's
  `rtx_topbr_enabled` is 1; `SetGameEnabled(true)` only while `rtx_topbr_game_maps` is 1. Read from the
  engine's convar list (`cvar`, else vstdlib's `VEngineCvar007`, as `module.cpp` does), only on the game
  thread and only on an off-to-on change (the driver calls `SetGameEnabled` every frame).
  `PumpSnapshots` (every frame from the driver) switches either off within 250 ms of the player doing
  so, even if a server removed the driver's change callbacks; world conversion needs that snapshot step.
  `ProcessSingleMaterial`, `ConvertTexture` (it decodes and uploads a texture) and the queueing bindings
  (`QueueMaterialsForProcessing`, `ProcessAllMaterials`, `ProcessMaterialsBatch`) check
  `rtx_topbr_enabled` too. The pipeline's own worker queues through the native switch only (no convar
  read off the game thread).
- **Imported game maps** (`QueueGameMaterial`, `GameMaterialAction`): a source that is not a file on a
  local drive, and base/normal/packed/emission paths that leave its folder, count as absent, so a
  recorded map still restores by its live texture identity and nothing else is opened (a UNC source made
  the worker open `\\host\...` before).

**The other path setters**, all reachable from any server's client Lua:

- The game's `IFileSystem::Open` opens absolute and network paths as given. `VTFParser::ReadVTFFile`
  (behind `ToPBR.ConvertTexture`, `InspectMaterial`, `HashCollisionFixer.CheckSolidColor/CheckMaterial`),
  ToPBR's `ParseVMTFile` (behind `InspectMaterial`, `ProcessSingleMaterial`, a patch VMT's `include`)
  and auto-categorisation's `ReadVMTShaderName` (a patch VMT's `include`) fell back to the bare name.
  They now read only `RelativePath` names.
- `RemixMaterial.CreateMaterial/CreateOpaqueMaterial/CreatePortalMaterial` (seven texture fields) and
  `RemixLight`'s dome `colorTexture`: Remix opens these paths itself. Now a Lua error unless
  `RelativePath`. No shipped Lua passes one.
- `RemixConfig.SetConfigVariable` set any runtime option. It now refuses, with a warning and `false`,
  the options whose value the runtime opens, writes or loads code from (scanned in the fork: the five
  atmosphere textures, `rtx.cameraSequence.filePath`, `rtx.neuralRadianceCache.cudaDllDepsDirectoryPath`,
  the three `rtx.nsight.graphicsCapture*` paths, `rtx.captureInstanceStageName`,
  `rtx.captureTimestampReplacement`, `rtx.baseGameModRegex`, `rtx.baseGameModPathRegex`), and any value
  that starts with `/` or `\` or is a drive (`X:`, `X:\`, `X:/`). No shipped Lua sets one of those; the
  companion's `rtx.atmosphere.starMapEnable` and `nubis3InteriorTexture` (a float) stay settable.
- `RTXWaterNative.SetMaterial` (water patch): a texture path that is not a relative game path keeps the
  current material (returns false). The shipped presets use `rtx-remix/mods/rtx_water/textures/...`.

Checked and left: `AutoCat_ExportHashes` already takes a plain name under `garrysmod/data`;
`StartupDisableMap` validates its arguments; the tracker's and auto-categorisation's other VMT reads are
prefixed with `materials/`; the module's embedded `AdvMatRTXBridge` provider registers only when the
standalone bridge DLL is not installed (the RTX package installs it).

### F-01 (`gmcl_rtxwater`)

`SetSurface` now takes a polygon only as an even count of at least six finite numbers
(`lua_input.h: UsablePolygon`); a non-finite coordinate would also have been undefined behaviour in the
tile loops' float-to-int conversion. `SetShape` already truncates to whole triangles.

### F-03, F-04 and the miss (flashlight Lua)

- Client: a repeated "on" for a player destroys the previous Remix light before creating one (the
  join-time sync repeats a broadcast "on"). `DestroyFlashlight` is now forward-declared, so
  `UpdateFlashlight`'s call to it no longer names a nil global.
- Server: a 0.3 s cooldown per player on switches (the shared `debounce.default_delay`), for the toggle
  message and for switching on with the flashlight key; colours are stored at once and broadcast at most
  every 0.1 s, the newest one (a trailing timer), never while off; the tables are cleared on disconnect.
  `PlayerSwitchFlashlight` and the toggle switch on only where the gamemode's own
  `PlayerSwitchFlashlight` (base: `CanUseFlashlight()`, spectators only off) and `CanUseFlashlight()`
  allow, and never for a dead player. Switching off is never refused.

## How it ships

- **Patches:** `packages/fixes/licenses/oversized-skinning/autopbr/lua-paths.patch` (fifth in
  `fixes.patches`), `.../rtxwater/rtxwater-lua-input.patch` (`fixes.rtxwater_patches`, applied after
  the water source is restored). Both under `oversized-skinning`, so the package's GPL source bundle
  (`remixbinary/src/hw`) carries them without a change to `tools/workshop.json`.
- **Recorded trees instead of a commit** (`tools/ci/pins.json`, `build_modules.ps1`): `Assert-Tree` runs
  `git write-tree` on the patched index and compares `rev-parse <tree>:<path>` with `fixes.patched_tree`
  (`source` `d2a0c6f9…`, `public` `7165af4d…`, `premake5.lua` `b308ed2f…`) and, after the water patch,
  `fixes.rtxwater_tree` (`source/rtx_water` `7e707d24…`). `patched_commit` is gone; the provenance
  records the trees. Replayed: the first four patches alone give exactly `913bb6b`'s ids.
- **Source copies:** the files each patch changes, as working-tree bytes (CRLF), at their native paths
  under `autopbr/` (now also `source/lua_path_policy.h`, `source/vtf_parser.cpp`,
  `source/remixapi/*_lua_bindings.cpp`, `.../auto_categorisation.cpp`, `tests/lua_path_policy_test.cpp`,
  `tests/vtf_parser/test.cpp`) and `rtxwater/source/rtx_water/`; `autopbr/source-files.json` updated
  (hashes, `build.dll`, an `r19` record); `autopbr/Source.md` R19 section, new `rtxwater/Source.md`,
  `packages/fixes/README.md` R19 section.

## Build and import

- `tools\ci\build_modules.ps1 -Only fixes,rtxwater -FixesClone <local clone> -GmodCommon <its
  garrysmod_common>`, premake downloaded and checked against its pin: both trees matched.
  - `gmcl_RTXFixesBinary_win64.dll`: 5,512,192 bytes (was 5,491,712), SHA-256
    `ba3fb50573854682be78897d48291a6081e86c788f98ced1501411fc92f4a0da`.
  - `gmcl_rtxwater_win64.dll`: 281,088 bytes (was 274,944), SHA-256
    `970f9dbdcb670a984cd64c798c2d31e9577af10f02502a289337684425afe5a9`.
- `inputs.py import fixes --file` for the two modules and the two flashlight files; `files.json` changed
  exactly those four entries and their origins. `inputs.py verify`: 11 parts, 0 problems.
- `tools\package_fixes.py` with `workshop.json`'s fixes arguments, from `inputs.py unpack --part fixes`:
  builds; its inventory has the new modules, the new Lua and both patches under `remixbinary/src/hw`.
- **A side effect to know:** with `-GmodCommon` pointing into the fixes clone, premake and MSBuild touch
  garrysmod_common's own helper projects in its git-ignored `projects\` folder (R16's run did the same).
  This run only refreshed MSBuild bookkeeping there (tlog, lastbuildstate, recipe; no library rebuilt);
  `git status` of both repositories is clean. `build_modules.ps1.md` now says so and how to avoid it
  (omit `-GmodCommon`).

## Tests

- New `tools/tests/test_fixes_native_inputs.py`: compiles and runs `autopbr/tests/lua_path_policy_test.cpp`
  and the water's `lua_input_test.cpp` (MSVC, `/W4 /WX`, asserts on), and checks each new file of both
  patches against its copy. Pass.
- New `tools/tests/test_flashlight.py` with `flashlight_harness.lua` (LuaJIT, fake GMod): toggle cooldown,
  gamemode/`CanUseFlashlight`/dead rule, coalesced colours, one light per player. Pass on the new Lua;
  the old Lua fails both (checked).
- `tools/tests/test_ci_tools.py`: the pins' tree records and the script's use of them; with the local
  fixes clone, a replay of the script's index steps in a `--shared` scratch clone gives both recorded
  trees. Pass (12 tests with the two above).
- In the fixes tree: `tests/vtf_parser/test.cpp` (new case: a path outside the game never reaches the
  file system) compiled and passed locally.
- pytest is not installed on this machine, so the touched files ran with `python -m unittest` from
  `tools\` (as `tools\test.ps1` does).
- `tools\test.ps1 -SkipNative`: all checks passed (conventions OK; `tools` 585 tests, 7 skipped;
  `gmapack` 28, 1 skipped; `steam` 25, 1 skipped). No C++ of this repository changed, so no native run.

## For the integrator

1. **Merge** `r19-fixes`. It touches `packages/fixes`, `tools/ci/build_modules.ps1` (+ `.md`), the
   `fixes` section of `tools/ci/pins.json`, `tools/ci/README.md` (the pins row), `tools/tests` (three new
   test files with their `.md`, `test_ci_tools.py` and its `.md`) and `docs/decisions/0112-…`.
2. **Imports are done**; nothing to pin by hand. The package workflow rebuilds both modules from the
   pins and checks the trees.
3. **R19-T** (`tools/ci/cache_key.py`): `modules()` hashes `fixes.patches` files but not
   `fixes.rtxwater_patches`. The key still changes with the water patch, because `rtxwater_tree` (hashed
   with the `fixes` section) changes with it; adding `*pins['fixes'].get('rtxwater_patches', [])` to its
   sources would make that explicit.
4. **R19-E, same class as H3:** the material editor's standalone bridge
   (`packages/advanced-material-editor/source/rtx_bridge/src/texture_ingest.cpp:519-536`) calls
   `std::filesystem::canonical` on a Lua-supplied absolute texture source before its root check, so a
   UNC source makes an SMB request before it is refused (`AdvMatRTXBridge` is in `_G`). Refusing a
   source that starts with `\\` or `//` before `canonical` would close it. The fixes' embedded copy has
   the same code but is inactive while the standalone DLL is installed.
5. **In-game checks** (PoC, RTX session; console open):
   - `lua_run_cl MaterialPipeline.ToPBR.SetEnabled(true) print(MaterialPipeline.ToPBR.IsEnabled())` with
     `rtx_topbr_enabled 0` prints `false`; `rtx_topbr_enabled 1` then converts world materials as before
     (`~gmod_topbr` republished); `0` again stops it within a second.
   - `lua_run_cl print(MaterialPipeline.ToPBR.SetOutputDirectory("\\\\127.0.0.1\\x"), MaterialPipeline.ToPBR.SetOutputDirectory("..\\x"), MaterialPipeline.ToPBR.SetOutputDirectory(""))`
     prints `false false true` with two "Output directory refused" warnings; `GetOutputDirectory()` is
     unchanged.
   - An imported game character (Model Hotloader) still gets or restores its game maps (default on), and
     the Imported game PBR panel's actions work; `rtx_topbr_game_maps 0` stops new automatic ones.
   - `lua_run_cl print(RemixConfig.SetConfigVariable("rtx.nsight.graphicsCaptureOutputDir", "x"))` prints
     `false` with a warning; the sky/weather and the companion's Remix settings work with no such warnings.
   - RTX Water on gm_poolrooms or another map with water: the surface and its material appear as before.
   - Flashlight (single player): F toggles the RTX flashlight; F twice quickly gives one change; after
     `kill`, F gives no flashlight; the light follows the view with no duplicate.
6. **No user-visible strings to translate:** the new texts are console warnings and a Lua error message
   (English, developer-facing).

## Proposed shared-doc lines

**CHANGELOG (Unreleased):**
- RTX fixes: Lua can no longer point the fixes' native module outside the game. ToPBR's output folder stays
  inside `~gmod_topbr\textures`; texture, VMT and model paths, Remix material and dome-light textures, and
  Remix options that name files must stay in the game's folders. Before, any server's Lua could make the
  client write elsewhere or open a network share, which offers the Windows login to that host (R19 H3,
  ADR 0112).
- RTX fixes: ToPBR turns on only while the player's `rtx_topbr_enabled` is on, and imported game maps while
  `rtx_topbr_game_maps` is; Lua can no longer override either (R19).
- RTX Water: a surface polygon of odd length is skipped instead of read past its end; texture paths stay in
  the game folder (R19 F-01).
- RTX flashlight: a repeated "on" no longer leaks a light; switches have a 0.3 s cooldown and colours one
  broadcast per 0.1 s; the dead and spectators get no flashlight (R19 F-03, F-04).
- Tools: `pins.json` records the patched fixes' tree object ids instead of a commit, so
  `build_modules.ps1` checks them anywhere; RTX Water gets `rtxwater_patches` (R19).

**RESEARCH:**
- The fixes' module registers `MaterialPipeline`, `RemixMaterial`, `RemixLight`, `RemixConfig` and
  `RTXWaterNative` in the real `_G`: any server's client Lua calls them.
- Source's `IFileSystem::Open` opens an absolute or UNC path as given, whatever the path ID; before R19
  `VTFParser::ReadVTFFile` (`vtf_parser.cpp:232` at `913bb6b`), ToPBR's `ParseVMTFile`
  (`to_pbr.cpp:1855-1859`) and `ReadVMTShaderName` (`auto_categorisation.cpp:312`) fell back to the bare
  name.
- `RemixConfig.SetConfigVariable` writes any runtime option to the User layer. Path-valued options in the
  fork: atmosphere textures (loaded in `rtx_atmosphere.cpp:880-883`), `rtx.cameraSequence.filePath` (read
  on `autoLoad`, `rtx_camera.cpp:1159-1176`), `rtx.neuralRadianceCache.cudaDllDepsDirectoryPath` (given to
  `nrc::vulkan::Initialize` as `depsDirectoryPath`, `rtx_nrc_context.cpp:251-256`; the context is
  re-created on a resolution or `enableCustomNetworkConfig` change, `rtx_neural_radiance_cache.cpp:610-630`),
  Nsight's paths (read at initialisation; `DXVK_ENABLE_NSIGHT_GRAPHICS_CAPTURE` builds only).
- Replaying `build_modules.ps1`'s index steps, the four pre-R19 patches on `f28bd5a` give exactly
  `913bb6b`'s ids (`source` `aa6ed7d1`, `public` `7165af4d`, `premake5.lua` `b308ed2f`); RTX Water's
  `b5c194e` `source/rtx_water` is `b3547296`.
- `build_modules.ps1 -GmodCommon <checkout>` builds garrysmod_common's helper projects inside that
  checkout's git-ignored `projects\` folder.

**TESTING:** `test_fixes_native_inputs.py` (MSVC), `test_flashlight.py` (LuaJIT), and
`test_ci_tools.py`'s tree replay (needs a local fixes clone; else a skip).

**decisions/README.md:** `0112` - The RTX fixes' Lua functions keep paths in the game, and ToPBR follows
the player's settings (R19).

## Open issues

- **The player's convars themselves:** GMod lets client Lua change a Lua-created convar
  (`RunConsoleCommand`, `ConVar:SetBool`), so a server can still switch `rtx_topbr_enabled` on; the
  setting then really is on and shows in the menu, and the 1 GiB world budget and the disk headroom bound
  it. Native convars would close it but change how they are saved (ADR 0112).
- **Manual game-map actions** remain callable by any Lua (the panel needs them); effects stay in ToPBR's
  folder and the player's override file.
- `ToPBR.GetOutputDirectory()` still returns the absolute folder, so a server's Lua can read the install
  path. Not a setter; left unchanged.
- A model imported from a UNC share gets no automatic game maps (a mapped drive works).
- A texture or material name that starts with `/` or `\` is no longer read by the shared readers (the
  engine's own names do not; odd content could).
- Not checked in the game here (rule 7); the in-game list above is for the integration sessions.
