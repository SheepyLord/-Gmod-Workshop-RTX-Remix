# 0112: The RTX fixes' Lua functions keep paths in the game, and ToPBR follows the player's settings

- Status: Accepted 2026-11-05
- Decided by: the user's request after the pre-release review ("All real findings", R19), the R19 plan's
  section R19-X; Claude choosing the rules
- Concerns: the GPL RTX fixes in `packages/fixes` (`gmcl_RTXFixesBinary`, `gmcl_rtxwater`, the flashlight
  Lua), built by `tools/ci/build_modules.ps1` from the public base and the patches in
  `packages/fixes/licenses`

## Context

- Binary modules register their Lua functions in the real `_G`, so **any server's client Lua** calls
  them: `MaterialPipeline.ToPBR`, `RemixMaterial`, `RemixLight`, `RemixConfig`, `RTXWaterNative`.
- **H3 of the review:** `ToPBR.SetOutputDirectory` stored any string. `EnsureOutputDirectory` then
  created that folder and the converter wrote USD, DDS and cache files there every few seconds. A UNC
  path (`\\host\share`) makes Windows open an SMB session to a host the server picks and offer the
  player's Windows login (NTLM). `SetEnabled(true)` also overrode the player's `rtx_topbr_enabled 0`,
  and `ProcessSingleMaterial` queued conversions.
- **Looking through the rest**, the same kind of input reaches a file elsewhere:
  - the game's file system opens absolute and network paths as they are, and ToPBR's VMT reader,
    `VTFParser::ReadVTFFile` (behind `ToPBR.ConvertTexture`, `ToPBR.InspectMaterial` and
    `HashCollisionFixer`) and auto-categorisation's VMT reader fall back to the name as given;
  - imported game maps open the source PMX, its folder and its textures where `QueueGameMaterial` and
    `GameMaterialAction` say;
  - Remix opens `RemixMaterial`'s texture paths and `RemixLight`'s dome `colorTexture` itself;
  - `RemixConfig.SetConfigVariable` sets any runtime option, including the ones whose value is a path the
    runtime opens, writes or loads code from: the atmosphere textures, `rtx.cameraSequence.filePath`,
    `rtx.neuralRadianceCache.cudaDllDepsDirectoryPath` (the folder NRC is given for its CUDA DLLs when
    it initialises, which the runtime also does when some options or the resolution change), Nsight's
    install and output folders, the capture names and the mod-path redirect;
  - `RTXWaterNative.SetMaterial` joined its texture paths to the game folder unchecked, so `..` left it.
- No shipped Lua calls `SetOutputDirectory`, names a Remix texture path, or sets one of those options.

## Decision

1. **One rule for a path from Lua** (`source/lua_path_policy.h` in the fixes, standard C++ only): a
   relative game path has no leading `/` or `\` (a root, a UNC or a `\\?\` path), no `:` (a drive, a
   stream, a device), no `..` segment, no segment that Windows would shorten (a trailing `.` or space)
   or read as a device (`CON`, `NUL`, `COM1`...), no control character, and at most 1024 bytes.
2. **ToPBR's output folder** is the converter's own, `<game>\rtx-remix\mods\~gmod_topbr\textures`, or a
   folder below it. `SetOutputDirectory` takes a path relative to it (`""` for the folder itself),
   rechecks the lexically normal result against it, refuses a link or junction on the way, warns and
   keeps the folder otherwise, and now returns whether it took the path.
3. **The player's settings decide when ToPBR works.** `SetEnabled(true)` takes effect only while the
   player's `rtx_topbr_enabled` is 1, and `SetGameEnabled(true)` only while `rtx_topbr_game_maps` is 1;
   the module reads them from the engine's convar list (`ICvar::FindVar`) on the game thread, never
   through Lua globals the same Lua could replace. A missing convar counts as off. `PumpSnapshots`
   switches either off within 250 ms of the player doing so, whatever happened to the driver's change
   callbacks; world conversion cannot pass that snapshot step without it. `ProcessSingleMaterial`,
   `ConvertTexture` and the queueing bindings check `rtx_topbr_enabled` as well.
4. **Imported game maps** use a source only when it is a file on a local drive (`X:\...`) and model
   paths (base, normal, packed, emission) only when they stay below its folder; anything else counts as
   absent, so a recorded map still restores by its live texture identity and nothing else is opened.
5. **The file system readers** (ToPBR's VMT reader, `VTFParser::ReadVTFFile`, auto-categorisation's VMT
   shader reader) read only relative game paths, whichever caller asks.
6. **Remix inputs:** `RemixMaterial`'s seven texture paths and `RemixLight`'s dome `colorTexture` must be
   relative game paths (a Lua error otherwise). `RemixConfig.SetConfigVariable` refuses the options
   listed above and any value that names a root, a drive or a network path, with a warning and `false`;
   those options stay with `rtx.conf` and the Remix menu.
7. **RTX Water** (`lua_input.h`): `SetSurface` takes a polygon only as an even count of at least six
   finite numbers (the review's F-01); `SetMaterial` keeps the current material when a texture path is
   not a relative game path.
8. **The flashlight Lua** (F-03, F-04 and the review's miss): a repeated "on" replaces a player's Remix
   light; the server gives each player a 0.3 s cooldown on switches (the shared debounce) and sends at
   most one colour per 0.1 s, the newest; `PlayerSwitchFlashlight` and the toggle message switch on only
   where the gamemode's rule and `CanUseFlashlight()` allow, and never for a dead player. Switching off
   is never refused.
9. **How it ships:** two GPL patches in `packages/fixes/licenses/oversized-skinning`
   (`autopbr/lua-paths.patch`, `rtxwater/rtxwater-lua-input.patch`). `tools/ci/pins.json` records the
   object ids of the trees they give instead of a commit (`fixes.patched_tree`, `fixes.rtxwater_tree`),
   and `build_modules.ps1` checks them with `git write-tree`, so the check holds anywhere with no pushed
   commit.

## Consequences

- A server can no longer make the module write outside ToPBR's folder, open a network path, or point
  Remix at a file or folder through these functions. What stays reachable: ToPBR's folder, the game's
  own folders and the player's local model files.
- **A server can still change the player's convars** with client Lua (`RunConsoleCommand`,
  `ConVar:SetBool` on a Lua-created convar), which GMod allows for any convar Lua created. Then the
  setting really is on, and shows so in the menu; the 1 GiB world-conversion budget and the disk-space
  headroom still bound it. Making those convars native would change how they are stored and saved, so
  it is left for a later round.
- **Manual game-map choices** (`GameMaterialAction`) stay reachable from any Lua, as the panel needs them.
  Their effect stays inside ToPBR's folder and the player's override file.
- A player who imported a model from a network share (`\\nas\...`) gets no automatic game maps for it;
  the model itself is unaffected, and a mapped drive letter works.
- The other ToPBR switches (`SetDebugOutput`, `SetMetallicGeneration`, `SetAutoDiscover`,
  `SetParseCommentedProperties`, `SetAutoProcessing`) remain session toggles any Lua can set; they
  change only how an enabled conversion runs.
- A future Remix option whose value is a path must join the list in `lua_path_policy.h`; the value
  rule already refuses absolute and network paths for every option.

## Alternatives considered

- **Removing `SetOutputDirectory`.** It is a shipped Lua function; keeping it with a relative,
  contained path changes the least.
- **Asking Lua for the convars** (`GetConVar`). The same server Lua could replace those globals.
- **Refusing every path in `RemixConfig`.** Many option values are lists with `:` or `/`; only path
  options and absolute values are refused.
