# Research notes

## R6 T3: companion VRAM binding (2026-10-31)

- Read-only inspection of `garrys-mod-rtx-remixed/source/remixapi/resource_lua_bindings.cpp:38-71`
  confirms `RemixResource.GetVramStats()` returns a flat table with 14 numeric fields, or nil on
  failure. It exposes the driver budget/allocation, DXVK totals, retained pools, six RTX categories,
  the texture-cache count and D3D9 texture/buffer bytes.
- `dxvk-remix-gmod/public/include/remix/remix_c.h:1025-1053` defines the same fields. The driver
  allocation includes non-DXVK overhead such as DLSS/NGX and NRC CUDA; `forkTextureCacheCount` is a
  count, every other field bytes. The companion preserves those names and units in CSV and leaves
  missing fields blank for older modules.
- The PBR tool's `skills/mmd-remix-pbr/tool/rpai/cli.py:384-410` publishes the PNG maps already named
  in `generated.json`; it does not resize them. The `run` dispatch at `cli.py:654-659` generates
  before publishing. `config.py:80-96` applies per-texture size overrides after the global cap,
  including `"source"`, so an 8 GB variant needs generation at 2048 and a check of those overrides.
- Derived texture cost, excluding DDS headers: a full mip chain at 4096 square has about four
  times the bytes of one at 2048 square. BC7/BC5 cost about 21.3/5.3 MiB respectively; BC4 costs
  about 10.7/2.7 MiB. These are format arithmetic, not measured residency or savings on an 8 GB GPU.
- In this nested worktree the guard fixture's cache path is 262 characters long. Its idempotence
  case uses raw `std::filesystem::last_write_time` (`loader/guard/tests/test_early.cpp:198-200`) and
  fails with path-not-found in the default Release layout; other guard file operations already use
  extended-length paths. The unchanged guard suite passes with executables under the shorter
  `out/build/win64-release/bin`, configured only in the ignored CMake cache.
- Sandbox-only Release blockers: `tools/tests/test_field_snapshot.py:136` cannot create its
  throwaway `HKCU/Software/NativeLoaderTest_*` key (21 failures). A non-mutating `winreg.OpenKey`
  request for `KEY_CREATE_SUB_KEY` on HKCU Software also returns WinError 5, access denied. Six
  publisher tests fail at Git reads with "dubious ownership" because the checkout belongs to
  `matt-peng` and the test process runs as `CodexSandboxOnline`. No ACL, registry permission or
  global Git configuration was changed.

## R6 T6: tier inputs and DDS measurements (2026-10-31)

- Source files in `out/inputs/runtime/files/atmosphere/`, from the runtime input index: stars DXT5
  8192 × 8192 (89,478,640 bytes), galaxy DXT5 8192 × 4096 (44,739,408), nebula DX10 BC7 UNORM
  8192 × 8192 (89,478,660), all 14 mips. After dropping only mip 0 they have 13 mips and occupy
  22,369,776 / 11,184,976 / 22,369,796 bytes respectively. The original lower mips, including
  minimum 4 × 4 blocks, compare byte for byte (`tools/sky/drop_top_mip.py`). Derived texel storage
  falls from 213.33 to 53.33 MiB, exactly 160 MiB saved, excluding driver alignment/overhead.
- The three imported xz inputs add 14,811,108 bytes (14.13 MiB) to Git LFS, rather than the
  proposal's estimated 12 MB. The files and their uncompressed/stored hashes are indexed in
  `packages/runtime/files.json`; the original DDS inputs and runtime DLLs remain unchanged.
- At runtime commit `6f2dbd79`, `rtx_atmosphere.cpp`'s `resolveSkyTexturePath` joins a relative
  option to `runtimeFolder()`; `loadSkyTexture:731–813` allocates all declared mip levels and uploads
  each. The low-tier paths therefore need no loader substitution and do not depend on the game's
  working directory.
- At that same commit, `rtx_neural_radiance_cache.cpp:379–422` derives training settings when the
  NRC preset changes: Ultra 4 iterations/9 bounces/1 cm cache detail; High 3/7/4 cm; Medium 2/6/6 cm.
  The callback selects the Derived edit target, routed to User under Custom, so duplicating those
  training values in a lower tier layer cannot override it. The tier selects only the NRC preset.
- The T6 combined package built from this branch's inputs contains 1,013 payload files and
  1,893,630,963 payload bytes (GMA 1,893,940,498 bytes), accepted by Release `nlctl manifest`.
  The new tier payloads are absent from the unconditional DXVK layer list.
- PoC attempt at 22:27:49 UTC deployed generation 59 and initialized `remix-main+6f2dbd79`, then
  stopped at a Steamworks error: "Could not determine Steam client install directory."
  No console/map/FPS/VRAM sample was produced. Evidence: this worktree's
  `out/t6-evidence/startup-error-full.png`, `sessions/session.json`, and the copied Remix log.
  Steam discovery also required an explicit client path for the read-only depot verifier in this
  execution context. All 2,877 depot files passed before the attempt; `autoexec.cfg` was the one
  allowed user-config difference. This is an environment blocker, not performance evidence.
  [ADR 0064](decisions/0064-performance-tier-defaults.md) records the unverified tuning and remaining
  acceptance checks.
- Resumed as the user: `tools/test.ps1 -Config Release` passes (23/23 CTests; Python groups
  28/25/287 tests, two expected skips), as do `inputs.py verify --deep` and the combined package
  with `--require-nlctl`. Logs: `out/t6-release-resumed.log`, `out/t6-inputs-resumed.log`,
  `out/t6-package-resumed.log`. The previous registry/Git failures were sandbox artifacts.
  The running field game (PID 24620) prevents the one-game-at-a-time PoC comparisons; it was left
  alone and the user was asked to quit normally. No PoC files changed during this resumed attempt.

## R4 start-up, guard and bootstrap review (loader 0.10.1)

Facts behind [ADR 0056](decisions/0056-guard-and-startup-fallbacks.md), read from the PoC's stock
Lua (read-only) unless marked:

- The stock toolgun screen, `gamemodes/sandbox/entities/weapons/gmod_tool/cl_viewscreen.lua`, pushes
  its RT at line 51 and `cam.Start2D()` at 52, calls the tool's `DrawToolScreen` unprotected at 62
  and pops at 71-72: a failing tool leaves both scopes open every frame, outside any guard callback.
- Base `GM:PostDrawViewModel` (`gamemodes/base/gamemode/cl_init.lua:600`) draws the player's hands
  for every weapon with `UseHands` or no script, so quarantining that gamemode method hid the hands.
- The base gamemode defines `PreGamemodeLoaded`, `OnGamemodeLoaded` and `PostGamemodeLoaded`
  (`gamemodes/base/gamemode/shared.lua:233-241`); sandbox's spawn menu and the menubar module create
  themselves on `OnGamemodeLoaded`. Their order relative to `Initialize` was not measured in game; the
  owned payload registers only `Initialize` and `InitPostEntity` callbacks today.
- Reported (GMod wiki, AddCSLuaFile): files in `lua/autorun/` and `lua/autorun/client/` are sent to
  clients without `AddCSLuaFile`, so a host that mounts the companion sends its guard autorun anyway.
- LuaJIT 2.x passes extra arguments through `xpcall(f, handler, ...)`, which the guard now uses to
  avoid a closure and argument table per protected callback.
- The guard's cache file names are 81 characters; in this repository's worktrees the early-guard test
  scratch paths reach 259 characters, so its fixture writer uses extended-length paths.
- This machine has no Node.js. In R4 the main-menu harness ran in the desktop app's browser pane
  through a small `vm`/`fs`/`assert` shim and passed (bootstrap polling ends after 239 retries).

## C13 graphics add-ons and map loading

This is a bounded API/source audit plus controlled baseline work, not a reproduced user crash.
The local record is `out/c13-evidence`: `wiki-api-audit.md`, `addons/addon-audit.md`, native
`findings.md`, and their hash/URL inventories. It covers 17 API families and 43 primary URLs
(41 Facepunch wiki pages, Lua's manual and Microsoft's SEH reference). The focused index has
25 call-site files (12 stock/13 add-on), alongside the broader 228-file add-on inventory. The durable
[API audit snapshot](audits/C13-render-api.md) and [compact provenance](audits/C13-render-api.json)
retain source hashes/URLs without game source code or private paths. These counts do not imply every function or payload
was executed. Of 25 distinct selected add-ons, eight sources were obtained: exact LifeMod, FXAA
and NikNaks archives, plus author-linked RealCSM, GShader Library, Projected Volumetric Light,
Spherical Sky and Outline Shader repositories. Repository snapshots are not asserted to match
current Workshop bytes. The coverage ledger marks 17 selected sources unavailable: QuickBloom/HDR
and 16 of the 22 collection members. Only FXAA and NikNaks have exact collection archives; the
other collection source snapshots do not establish current Workshop-byte identity.

Source exposes concrete compatibility boundaries: RealCSM upgrades eight shadow-target formats
and creates cascaded projected lights; GShader requests shared resolved-depth changes, float
targets/MRT and a DepthWrite material, and installs global/metatable wrappers. These are candidate
native resource paths to isolate, not proof of this user's crash. The official contracts include
[render-target lifetime](https://wiki.facepunch.com/gmod/Global.GetRenderTarget),
[target sizing/format parameters](https://wiki.facepunch.com/gmod/Global.GetRenderTargetEx),
[secondary views](https://wiki.facepunch.com/gmod/render.RenderView) and
[hook dispatch](https://wiki.facepunch.com/gmod/hook.Call). Stock frame blending uses full-frame
size modes with -1 dimensions; stereoscopy makes two views inside RenderScene; the toolgun can
invoke a custom screen callback inside a caller-owned RT/camera scope. Blanket positive-size,
one-view-per-frame or reset-to-depth-zero policies would break those valid cases.

Native backend audit: the referenced [LUX DX11 README](https://github.com/Akabenko/LUX-Gmod-shaderapidx11/blob/30fb5b1b5ec6db70dea93e4556468cb904dc0a98/README.md)
selects `-shaderapi shaderapidx11`. Remix's [D3D9 SDK path](https://github.com/NVIDIAGameWorks/dxvk-remix/blob/main/documentation/RemixSDK.md)
and our native module's `FindD3D9Device`/registration require the Source D3D9 device. Forty-one
bounded installed/fixture PE observations found stock matching graphics-core hashes and a local
DXVK `d3d9.dll`; no DX11 backend was found on the scanned surfaces. No actual DX11-payload live
compatibility or Steam launch-option inspection is claimed. Stock shaderapidx9 SHA-256
`7534cd56738f3f729dab0b88fce7f5fa224898fc15c28021762f3352643f8ca9` imports Direct3DCreate9;
passive REA evidence `ev_868c0082e4c0ba1e112e51c15f3c9920c842f3a82a86695ce68350a8a4ff4853`
is retained locally, with the session closed. DLL presence alone is not an incompatibility test:
DXVK is retained for RTX-off starts and the loader itself uses system DXGI for adapter information.

Loader 0.10.0 now normalizes every explicit shader-API choice in the process command line,
preserving other raw spans and exact rollback. It does not rewrite Steam options or graphics DLLs.
The existing selected-Remix-DLL path/handle identity refusal remains. The early client initializer
view is separate: only a supported stock hash and the enabled catalog-verified owner/V2 guard may
produce the generated owned view, after libraries and before autoruns. This reduces alias-capture
gaps without editing the depot initializer or granting foreign Lua/native code new permissions.
The cache path is `native-loader/presentation/render-guard-<sha>.lua`. The Lua guard additionally
requires `__NATIVELOADER_RTX_GUARD_EARLY`; activation fallback removes its executable read redirect,
and no ordinary late-autorun fallback substitutes for verified early installation.
For the selected `gmod-rtx-remix` runtime, stock/cache failure after catalog verification of a V2
owner raises required-protection failure, disables activation and retains vanilla/hide-RTX fallback.
That requirement does not run before owner/V2 verification or widen trust. A foreign runtime does
not read the initializer/cache through this path; legacy V1 marker failure remains a nonfatal note.

The Lua prototype addresses reserved depth targets, unsupported depth/MRT paths, RenderView
recursion, additional cvar entry points and protected render/loading hook dispatch. Cleanup must
respect each callback's entry state, never call mesh.Abort, and never assume that
depth zero/default render state belongs to it. Recoverable Lua-error containment does not establish
recovery from native access violations, engine fatals or GPU faults. Raw R32F format 27 is valid;
the format check was corrected and the normal/MMDHL target positive control passes. A reserved-name
collision or unsupported MRT/depth feature is a separate capability issue, not proof R32F is invalid.

Current measured baselines are fresh loader-0.9 LifeMod defaults on flatgrass, author-linked
RealCSM with depth format 24/one controller on flatgrass, and GShader/FXAA source inputs on
flatgrass and construct. All load; none reproduces the original failure. The protected-shader2/3
runs activate RTX and record the redirected stock initializer read. The guarded combined
construct-to-flatgrass transition exits zero; combined2 passes ten live assertions including
blocked mat_hdr_level:SetInt, one intentional HUD failure quarantined with RT state restored,
and valid normal/R32F targets. CSM depth-24/one-controller fallback is nonfatal. Two rejected
GShader autoruns remain visible in GMod's reports; this is not full effect compatibility.
Release passes **22 CTests and 294 Python tests (7 skips)**, including 20 early-policy cases,
6 backend cases, 11 targeted command-line cases and 17 unittest cases running 18 actual-source
LuaJIT scenarios. CI builds pinned official LuaJIT and requires it, rather than skipping these
scenarios. CPU tests are separate from the real NVIDIA GPU sessions below.

The actual 998-file GMA reads back against every manifest SHA and matches all preview payloads.
Its construct session passes ten failure/positive controls: reserved RTs, invalid dimensions,
unsupported shader/MRT/depth work, pinned HDR writes, valid normal/R32F targets, one quarantined
HUD failure and restored RT state. Toolgun rendering and spawn-menu open controls pass. Corrupting only its owned
startup cache gives a clean vanilla map load/exit, no RTX patches or executable init redirect,
and preserves the changed cache; the fixture restores its original bytes afterward.

Secure dedicated multiplayer passes with no -insecure, sv_allowcslua 0 and cheats 0. The trusted
RTX payload, RTXDebug and guard load; unrelated local Lua remains excluded and the temporary
catalog API is absent. A normal server-delivered test verifies an unsupported-shader rejection,
one failing HUD callback, continuing healthy callbacks and restored RT state with zero cleanup
errors. It records installation="verified multiplayer bootstrap", with the early flag false.
This is a later readiness boundary, not protection before the remote server's autoruns.

Earlier controlled baselines load LifeMod defaults, CSM depth24/one controller and GShader/FXAA.
The guarded combined construct-to-flatgrass transition and explicit DX11-to-D3D9 process choice
pass. RTX-off loads/exits normally with the guard absent. Steam depot verification passes.

The original user crash was not reproduced with fresh defaults. Exact QuickBloom/HDR source and
sixteen collection members were unavailable; author-linked repositories are distinguished from
exact Workshop archives. Unsupported shader effects can be disabled or quarantined while the
map loads; this does not promise their original appearance or recovery from native/GPU faults.
Earlier aliases, later API replacements, unknown native state and already-completed camera/clip/
matrix pops remain explicit limits. Multiplayer installation is later than server autoruns.

The secure test first exposed an actual gap: a read hit came from menu initialization while
the remote client guard was absent. Loaded-44/errors-empty was not guard-execution evidence.
The final private-environment path and cached-dispatcher HUD fault test establish later client installation.
The late route wraps render registrations because replacing hook.Call alone left the engine
invoking an earlier dispatcher. Loading callback identities remain intact for payload replay.
No runtime/native bridge rebuild was needed; the renderer/native fixes remain unchanged.
Policy: [ADR 0054](decisions/0054-rtx-rendering-startup-boundaries.md).

## Oversized Airi skinning groups (item 24)

Read-only inspection of Workshop 3830665593, VRChat Airi(InuinuBone), identifies the reported
40,509 vertices as the clothing-fur mesh in both `models/pm/airi_inuinubone_pm.mdl` and
`models/npc/airi_inuinubone_npc.mdl`. The source archive `gmpublisher.gma` is 721,989,777 bytes,
SHA-256 `d97ae9d34750e5ad86bcbd95cbd03c12dd1b009f6a5323265e8389ad202bf558`.
Each model has 233 bones, 25 meshes, one compiled LOD and 329,678 LOD0 source vertices.

The matching studiorender.dll, SHA-256
`1dcb270dc9fa7186acd7ae2f66207416412ba1b7c606d7e65bf923d7152ce4b6`, contains the warning.
Independent native inspection locates `R_StudioDrawDynamicMesh` at preferred address 0x18000FA20
and its vertex-count comparison at 0x18000FB3A: groups below 0x8000 continue; groups at or above
32,768 warn and return zero. This is a per-group software draw limit, not a total-model limit.
Hiding the warning alone would retain the skipped draw. The direct hardware helper also has a
software fallback, without the dynamic entry's equivalent capacity precheck. The later reported
62,049-vertex fatal against a 32,768-vertex buffer therefore required protecting both entries.

| Bodypart / mesh ID | MDL source vertices | VTX group vertices | Strips | Material variants |
|---|---:|---:|---:|---|
| Hair / 4 | 61,896 | 62,049 | 3 | Hair, Black, Gray, Brown, Blue, Pink, Green |
| Clothes / 7 | 40,509 | 40,509 | 1 | Fuzz, Fuzz_B |
| Shoes(L) / 19 | 33,422 | 33,422 | 1 | Shoes, Shoes_W |
| Shoes(R) / 20 | 33,422 | 33,422 | 1 | Shoes, Shoes_W |

All four groups occur in both player and NPC models, have compiled `STRIPGROUP_IS_HWSKINNED`
data (flag 0x02) and zero MDL flexes. Hair's extra VTX vertices are palette duplicates; its
original-mesh IDs cover exactly the 61,896 source vertices. Its three strips have 53, 53 and 41
bone palette changes. Each shoe uses four distinct bones. The separate arms model totals 37,757
vertices, but its largest group is 14,754, making it a useful control for group-based detection.

Clothing bodypart 5, submodel `Clothes.smd`, mesh 0/global ID 7 uses Fuzz for skins 0–7 and Fuzz_B
for skins 8–15. Its single strip has 169,398 indices/56,466 triangles and 25 palette changes.
There are 8,219 one-bone, 24,313 two-bone and 7,977 three-bone vertices; every referenced bone
exists and weights normalize within 0.001. Drawing without skinning would lose valid weighted
deformation. Both Fuzz materials are VertexLitGeneric without software-skin directives, proxies
or fallbacks. The archive has dx90.vtx data and no sw.vtx; that alone does not rule out a runtime
software fallback. Runtime material flags/cvar state have not yet been measured by this asset pass.

MDL/VVD/VTX entry CRCs, checksums, vertex ranges, bone ranges/counts and weight sums pass. The
read-only parser did not execute add-on code or extract textures. Detailed evidence is in the
main checkout's `out/oversized-skinning-evidence/asset-findings.md`, `model-inventory.json`,
`mesh-summary.txt` and `validation.json`. REA warning/function references are
`ev_4068803caf065f4700651d539889e94440552386c645bf4ccc14715ac3ce9006`,
`ev_9dd106d75194ea64a06745f6cf72926983e7b756e91521a967a6ef699ce1360d` and
`ev_d046b0940e7e634e8f2c8a5d20621e9fe39d7eb853c7fb667e15c719bc73df7e`.
The implementation is native local commit `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe`; the final
gmcl_RTXFixesBinary_win64.dll SHA-256 is
`5e626e34f412cd55e93a485cd1d777794b339a0cb7a5082935454b72fbc72db7`.
The [source notice and pins](../packages/fixes/licenses/oversized-skinning/Source.md) include the
complete changed source, generated projects, patches and GPL licence. They ship through the short
add-on path `remixbinary/src/hw`; a deeper source path exceeded Windows staging limits.

The automatic path applies only to already hardware-skinned, non-flex groups of at least 32,768
vertices. Creation-time VTX validation requires every strip to assign every hardware bone slot it
uses. A certificate plus runtime strip-data fingerprint rejects unknown/changed groups; cached
palettes from other groups cannot prove missing assignments. The bounded certificate implementation
starts at source/HardwareSkinningHooks.cpp:2175 in the shipped source. At DrawIndexedPrimitive,
D3DCOLOR blend indices use a borrowed UBYTE4 declaration only when needed; a 16-entry cache holds
original/converted COM references and releases them at shutdown. Palette, blend, config, material,
group and bookkeeping state are restored with __finally, as is the original declaration.

Both dynamic and direct entries now borrow that scope, preserving all nine arguments. A
thread-local same-group marker prevents dynamic-to-direct re-entry from wrapping twice. An
oversized group with unknown static-fallback config38 bit 0x08 is skipped safely. Existing
user-forced hardware draws also need the scope for smaller non-flex, multi-bone groups inside
RenderFinal when the legacy r_hwskin_setbones predicate selects them (mode 1 or matching bone
count). Otherwise Source can CPU-pose a small group while native indexed upload transforms it
again. Ordinary force0 draws, rigid single-bone props, flex and forced-eye paths remain unchanged.
Complete certificates remain mandatory only for oversized groups. Small user-forced groups keep
their existing remap/cache fallback and diagnostic mode selection; no stored cvar is changed.

Baseline PM at `r_forcehwskin 0`/`mat_softwareskin 1`, without insecure, repeated all four warnings
and lacked hair/shoes. The dynamic-only 0d4 prototype passed initial PM checks but missed the
direct-entry fatal; it is superseded. The static-only 034 intermediate left smaller body meshes
invisible under force1 and is also superseded. The 357 preview restored force1 PM skins 0/8,
full body, hair, boots and visible arms without a fatal, then exited zero. Final 5e626e34 adds
minor route/debug guards and passes cold default0 NPC skins 0/8 plus arms (`complete-default`).
The actual final GMA also passes force1 PM skins 0/8 with full body and arms visible, no errors
and exit zero (`complete-packaged`). Both the software warning and the later direct-fallback
fatal are addressed; earlier dynamic-only/static-only passes are not the final acceptance record.

An earlier packaged 0d4 client PID 3752 passed secure multiplayer with cslua/cheats off, rendering
configuration apply/restore, denied unsafe commands, hands and the 233-bone Airi rendered. Content
was mounted by normal server-approved game.MountGMA; no other add-on Lua was force-loaded. This
earlier result does not establish final-DLL multiplayer acceptance, which remains pending.

The final standalone policy CTest passes with Release /UNDEBUG assertions, including user-mode
and unsupported-mode cases. Final `final-tests.log` passes 20 CTests/277 Python tests (7 skips).
Reviewed GMA `0.0.0-dev.20261031090406+335c6f09` contains 998 files/1,837,514,493 bytes, payload digest
`13f303982ed43e47bccf09847186bd3bb43477cb65dbbcb1c5534117cbae4ba3`.
Readback matches the final DLL and corresponding source: 28 changes, no files removed and no user
assets included. Final-DLL multiplayer (client PID 18232), CI and publication remain pending. See
[ADR 0053](decisions/0053-oversized-hardware-skinning.md).

## Scoped RTX multiplayer loading (loader 0.9.0)

The game has separate menu and client Lua states. The menu's `require("nlrtxclient")` must resolve
`gmsv_nlrtxclient_win64.dll`, despite the helper initializing client rendering scripts. The initial
`gmcl_` filename did not load from the menu; native module lookup inspection established that the
menu uses the non-client prefix. The `gmsv_` name does not make this a dedicated-server initializer:
`loader/client/module.cpp` explicitly requires `MENU_DLL`, obtains the client state through
`LUASHARED003`, waits for that state's readiness and verifies the active owned runtime.

`loader/client/catalog.cpp:54` prepares the source snapshot from an enabled config and committed
deployment. The package identity is exactly `gmod-rtx-remix`; local/dev sources must match their
respective native allowlists, and Workshop sources must be the configured distribution item
3829070317 under `workshop/content/4000`. Each owned module/script must still match its journaled
size and SHA-256, with unsafe paths, links, case collisions and oversized/NUL source refused.
Other owners cannot supply a replacement at the same virtual Lua path. Generic `rtx_agent` and
Hotloader debug-source execution are excluded. The temporary native callbacks read catalog keys,
not arbitrary paths or source text.

Omitting the existing renderer fixes caused a prototype startup crash. The secure-launch exception
therefore covers only the seven existing rendering recipes in `tools/package_fixes.py:58`, grouped
as 2 engine, 3 shader API, 1 material-system and 1 data-cache fixes. The classifier at
`loader/client/catalog.cpp:41` binds the exact owner, module, patch name, find bytes, offset,
replacement and order. Mutated, extra, incomplete or reordered groups fail classification. Config
`patch_sets.allow_rtx_render_patches: false` disables the exception; the general
`patch_sets.require_insecure` default remains true. See
[ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md).

Two pre-fix client crashes reached `studiorender+0x5D353` on a queued worker with a null hardware
LOD array. The late cl_rtx.lua initial/final MDLCache flush could invalidate static-prop hardware
data after the world was active. The bootstrap now sets `NATIVELOADER_VERIFIED_MULTIPLAYER` only
inside owned environments, and the GPL add-on skips those late flushes. Normal early loading
retains both reloads. Actual-section timer/hook tests cover normal nil/false flags, convar retries,
and verified matching/mismatched/missing convars with zero flushes. Crash analysis is retained in
`out/debug-crash-analysis/findings.md`. The player-shadow proxy also snapshots source bones before
its callback, validates destination bones and avoids accumulating its offset; two body cases pass.

Some bundled clients request catalog, scene-sharing, motion or material-store channels that a
vanilla remote server never pools. The scoped net adapter shares drop state across owned source
environments, suppresses writes/sends for those missing channels and records their names. The
engine's global net table and registered-channel errors/returns stay intact. This prevents client
initialization errors; server-dependent tool features still require matching server add-ons.

Offline evidence: 16 catalog cases, 7 config cases and the actual Lua bootstrap/reload suite's
6 tests/14 scenarios pass. A `gmod.exe -dedicated` prototype was not counted as dedicated-server
proof. Prototype 7 client PID 8544 subsequently joined genuine 64-bit dedicated PID 78088, with
VAC secure mode active, `sv_lan 0`, a password-protected loopback connection, `sv_allowcslua 0`,
cheats off and no client `-insecure`. It completed 44 autoruns with no payload errors, six absent
server channels recorded, no temporary API global and an unrelated local Lua fixture still blocked.
Reconnect and gm_construct -> gm_flatgrass -> gm_construct passed in the same client process;
the Source JPEG at `out/mpc/garrysmod/screenshots/nl_mp_construct.jpg` records the rendered world
and hands. RTXDebug 0.2 reports connected/in-game client and menu realms, no server realm,
successful rendering SetConfig/restore with unchanged config-file hashes, and refused Lua.Eval and
Engine.SetConVar attempts to enable client Lua. Evidence is under `out/multiplayer-evidence/probe7*`.
This controlled session is not a universal VAC/server-policy guarantee. Final full-suite, package
readback and publication results remain pending.

RTXDebug 0.2.0 took "single-player" for its developer mutation gate from the client realm's Lua
`game.SinglePlayer`, which a remote server's client scripts can replace; the server also replicates
`sv_cheats`. 0.2.1 (R4) asks the engine instead. In the vanilla x64 engine.dll (5707088 bytes,
SHA-256 d8f74db72412ffa91c1f01a633d108331145d0a7dff6cffabe1b67ed5abe4fcb), RTTI finds one
`CEngineClient` vtable (RVA 0x39d048) and one `CNetChan` vtable (RVA 0x3e0150). Their slots match
sourcesdk-minimal's `cdll_int.h` and `inetchannelinfo.h`: `CEngineClient` 21 `GetMaxClients` and 12
`GetLocalPlayer` read client-state fields, 26 `IsInGame` and 27 `IsConnected` compare the signon
state with 6 and 2, 72 `GetNetChannelInfo` returns the client state's channel pointer, 76
`IsPlayingDemo` and 78 `IsPlayingTimeDemo` call the demo player at vtable offsets 0x30 and 0x40, and
106 is `ClientCmd_Unrestricted`. `CNetChan` slots 0-9 match in order. Slots 1 `GetAddress` and 6
`IsLoopback` both use the remote address at +0xC4, and `netadr_t::IsLoopback` is only
`type == NA_LOOPBACK` (1), the engine's in-process loopback buffers: a connection to 127.0.0.1 or a
LAN server is not loopback. Slot 8 `IsPlayback` is the same folded function as `IsPlayingDemo`. The
header's last declarations do not match (slot 150, declared `IsDedicatedServer`, takes five
arguments); RTXDebug does not call them. `Engine.World` reported `max_clients` 8 in probe 7's
dedicated session and 1 in single-player (`out/multiplayer-evidence/probe7/debug-checks.json`,
`out/multiplayer-evidence/singleplayer/checks.json`).

## Startup text and main-menu identity (requests 15 and 23)

The launch text was hard-coded in runtime src/dxvk/imgui/dxvk_imgui_splash.cpp:88 and referred to
Xenthio. It now reads companion/presentation/startup_message*.txt from the deployed data
folder and uses literal text rendering. The runtime font atlas adds the selected template's glyphs.

The stock control.Menu.js exposes gScope.Version/Branch through UpdateVersion and InGame through
SetInGame. The [menu realm](https://wiki.facepunch.com/gmod/States) is separate from normal client
add-ons. Loader presentation.cpp appends the local panel through the existing exact-read mechanism.
diagnostics.cpp reads system descriptors and hashes the installed bootstrap; package hashes come
from the committed generation's manifest_sha256, avoiding a self-referential package hash or a
startup rehash of the entire runtime. The UI never reads console logs or displays source paths.

## Imported normals and navigation (requests 17, 19/19.1 and 20)

Hotloader materials.lua returns engine-safe paths from Entity:GetMaterials; original names are in
rig.materials[].name. AME sh_15_mmd.lua now resolves labels separately, including static-prop cache
names. Paths remain rule/profile identities. cl_76_rtx_editor.lua OnWorkspaceChanged previously
preferred SourceDisplaySelected over Selected, retaining the stale Source row. It now follows the
current RTX row on entry and maps the Source row to CanonicalSlot on return.

The motion importer's cl_menu.lua:5862 exposes MMDVMDNPC.OpenMotionManager; the creation tab calls
that existing entry point. The fixes' source/remixapi/remixapi.cpp:1111 GetConfigVariable reads
rtx.conf rather than live layers, so replacing the saved smooth-normal set would be unsafe.
Native rtx_model_layers.h owns a separate NoSave set, joined on D3D9, cached-draw and external
submission paths. Existing rtx_scene_manager.cpp:1858 dispatches area-weighted geometry normals;
no shader source or ABI changes are needed. Tags affect all draws sharing a captured texture.

## Player bodies and first-person arms (2026-10-30)

- The shipped runtime's InstanceManager::createViewModelInstances explicitly zeroed every candidate
  mask and returned when PlayerModel::enableInPrimarySpace was true (rtx_instance_manager.cpp,
  previous lines 1755-1763). GMod continued issuing view-model/hand draws, but screenshots lost the
  entire view model. Removing that branch retains ViewModel::enable and normal camera correction.
- The classic defaults had 549 player texture hashes and three body hashes. The Lua categorizer
  also tagged original player textures with unique_hashes=0, which the classic client defaults use.
  Texture categories apply to all matching geometry, including other players, NPCs and ragdolls.
- Existing RTX_c configuration also contains 529 player texture hashes in rtx.conf and four in
  user.conf. Clean defaults alone do not remove those stronger saved tags. The integration clears
  only player bits for observed original player/hand/ragdoll hashes in memory, preserving files and
  unrelated flags. Native RemoveHashCategory only removes categories in its own cache, so file-only
  tags need temporary local bookkeeping before their targeted removal.
- The former body proxy changed LocalPlayer's bone 0, ignored Z in the default angle mode, and
  created nested body models plus an independently duplicated weapon proxy. The new proxy only
  adjusts its own final render bone matrices, in world Z for either offset mode.
- [render.ReadPixel](https://wiki.facepunch.com/gmod/render.ReadPixel) reads the current captured
  target. One sampled blue channel is inverted for a guaranteed private texture, while
  [OverrideAlphaWriteEnable](https://wiki.facepunch.com/gmod/render.OverrideAlphaWriteEnable)
  preserves the copied alpha. Merely blending a white pixel did not change an already-white texel.
- The runtime recipe verified the seven-patch tree, NVAPI/RTXDI settings and DLSS/SHARC clones.
  Only rtx_instance_manager.cpp changed; an incremental meson compile -j 2 reused the verified shader
  stamp. The resulting DLL SHA-256 is ca3ce8dc21f052bf6026c74b776c8d2e4186c33e42023e29f2776852e865cefc.
  Use Windows PowerShell 5.1 for build_runtime.ps1 -Verify: restoring absent Git environment values
  as empty strings under the current PowerShell/.NET host makes later Git worktree commands fail.

## Prior RTXLauncher installations (2026-10-30)

- [Xenthio fixes](https://github.com/Xenthio/garrys-mod-rtx-remixed) nightly aaefa35c5da3156e3f7352fbb4ac734361affed8
  and [RTXLauncher](https://github.com/Xenthio/RTXLauncher) 7779fc474d2cc4c73c8b02f031cc239159e9e8e4
  identify the tested layout. QuickInstall flattens the runtime ZIP's .trex contents into bin/win64,
  applies seven x64 SourceRTXTweaks edits across four DLLs, then extracts the fixes.
- Runtime ZIP SHA-256: 997747227bfd809434d3b264c2fa9fa0da3cd63773a2dfadabe90e5b1eceb12c;
  fixes ZIP: 2f32286bde9af91d748b44fefaa09408c0e4c1bf9690667b4c1d4eb95f0913f4.
  The 265,998,848-byte old runtime exports remixapi_InitializeLibrary; plain DXVK is not a match.
  Sparse detection reads at most 32 MiB, caches 128 KiB and never executes that DLL.
- The fixes overwrite stdshader_dx6.dll and five stock Lua/image files without preserving originals.
  Four native patches have backup_patches_<timestamp>/bin/win64 originals. steam.inf is not a safe
  binary build identity. Recovery uses exact old/stock hashes, recorded in legacy_stock_data.h from
  Steam depots 4001/7488132547021413298 and 4002/7341198560151933050, build 26229091.
- Fresh fixture: 2,877 verified stock files, then 192 runtime files, 387 fixes entries and four
  patched DLLs. Independent depot verification finds exactly ten altered files, zero missing or
  unverified files. Seven sentinels cover protected user files and an obsolete addon Lua file.
  Full local evidence is out/legacy-research/FIXTURE-HANDOFF.md and fixture-state.json.
- The launcher's optional MaterialSystemFallbackPatch guard was run in an isolated .NET probe:
  Unsupported, InitializeShader counter initialization site not found. It leaves these bytes
  unchanged, matching its normal warning/skip behavior. No downloaded Python code was executed.
- Links (2026-10-31, RTXLauncher 7779fc4 read locally): Mount HL2 RTX builds
  garrysmod/addons/mount-hl2rtx/{models,materials,maps} as real folders whose entries are file and
  directory symbolic links into Half-Life 2 RTX (Hl2RtxMountService.cs BuildMergedDirectory,
  File.CreateSymbolicLink :365, Directory.CreateSymbolicLink :375), next to
  .rtxlauncher-hl2rtx-overlay.json, and adds entries to garrysmod/cfg/mount.cfg. A new launcher
  install (GarrysModInstallService.cs:80-158) links the VPKs, sourceengine, platform and
  garrysmod/{saves,dupes,demos,settings,cache,materials,models,maps,screenshots,videos,download};
  none of those is a path the migration catalogs. mount-hl2rtx is one of its five add-on roots.
- MSVC std::filesystem::absolute (GetFullPathNameW) resolves "." and ".." before a check of the
  result could see them, so a path must be checked as given. Iterating "H:\a" yields "H:" first,
  and stat("H:") reads drive H's current folder, not its root; start link checks at root_path().
- Re-hashing a freshly staged payload before each move (loader 0.8.0, every step): 1.5 GiB in
  0.75 s, 2.0 GiB/s (CNG SHA-256, 1 MiB reads, page cache warm; Ryzen 9 9950X3D, which has SHA
  extensions; other games running; 2026-10-31). The RTX package is about 1.75 GB (files.json:
  runtime 1,204 MB, fixes 433 MB, model-hotloader 83 MB, the rest 30 MB), so about 0.85 s at every
  update here, and several seconds on a CPU without SHA extensions or once the staged files have
  left the cache (estimate). The check now covers the migration's moves only.

Facts the design rests on, with where they came from, so nobody has to dig them up again. Gathered
2026-10-27 unless a section says otherwise. "Verified" = checked directly (file read, PE parse,
hash); "reported" = from a code-reading pass over the named repo, not re-checked line by line.
External paths are local checkouts under `H:\BACKUP_20260815\Modding\` (see [ENVIRONMENT.md](ENVIRONMENT.md)).

## 1. How GMod x64 loads DLLs (verified)

- PE imports (`tools/diag/pe_imports.py` on build 26229091):
  - `bin\win64\gmod.exe`: `USER32, KERNEL32, ADVAPI32, ole32, WINMM, dbghelp`; delay-load `libcef`.
  - `launcher.dll` adds `WSOCK32`; `engine.dll` adds `WININET`; `client.dll` adds `CRYPT32`.
  - `shaderapidx9.dll`: `d3d9.dll`, `d3dx9_42.dll` (static).
  - The root `gmod.exe` is a small 32-bit launcher (`SHLWAPI`, `KERNEL32` only).
- KnownDLLs on this machine do **not** include `winmm`, `dbghelp`, `wsock32`, `wininet`, `crypt32`,
  `d3d9` or `version`, so for those names the copy in `bin\win64` (the application folder) wins.
- Of the executables in a vanilla `bin\win64`, only `gmod.exe` imports `WINMM`/`dbghelp` directly;
  the tools (hlmv, studiomdl, vbsp, ...) load it through `tier0.dll`. The proxy must therefore
  check its host process.
- Vanilla `bin\win64` contains no `d3d9.dll`, `winmm.dll`, `dbghelp.dll`, `version.dll` or
  `vulkan-1.dll` (checked on the PoC copy).
- Windows binds an import to an already-loaded module of the same base name regardless of folder
  (documented search-order behaviour); M4 confirms it for `d3d9.dll` in practice.

## 2. RTX Remix runtime (fork `dxvk-remix-gmod`, verified unless marked)

- Size of the runtime file set in `GarrysMod_RTX_c\bin\win64`: 40 DLL/EXE files, about 928 MB, plus
  `usd\` (150 files, about 5 MB). Biggest: `d3d9.dll` 323 MB, `nvngx_dlssnr.dll` 254 MB,
  `nvrtc64_130_0.dll` 97 MB, `libxess.dll` 74 MB, `nvngx_dlss.dll` 56 MB, `nvngx_dlssd.dll` 46 MB.
- `d3d9.dll` static imports include `usd_*.dll`, `NRC_Vulkan.dll`, `rtxio.dll`,
  `GFSDK_Aftermath_Lib.x64.dll`, `NvLowLatencyVk.dll`, `libxess.dll`, `vulkan-1.dll`, `dbghelp`,
  `VERSION`, `WINHTTP` and the **VC++ 2015+ runtime** (`MSVCP140`, `VCRUNTIME140`, `VCRUNTIME140_1`);
  delay-load `amd_fidelityfx_vk.dll`. Exports: 116, including the D3D9 set and `remixapi_*`
  (with the fork's `remixapi_imgui_*`, persistent instances, game values).
- Config layers (`src/dxvk/rtx_render/rtx_option_layer.cpp:666-746`): `dxvk.conf` < built-in app
  defaults < `rtx.conf` < base-game-mod `rtx.conf` < programmatic layers < `user.conf`.
  `DXVK_CONFIG_FILE` and `DXVK_RTX_CONFIG_FILE` take comma-separated lists (the last `rtx.conf`
  layer is the one the UI saves to); `user.conf` has no environment override and is opened relative
  to the working directory (`rtx_option_constants.h:115-124`). Reported: a per-user layer
  `%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<hash>.conf` is also read. (Corrected in section 19:
  that file holds only first-use and crash-report flags, and is not an option layer.)
- `rtx-remix\{mods,captures,logs}` default to `./rtx-remix/...` made absolute when `d3d9.dll`
  loads, i.e. relative to the working directory, overridable with `DEFAULT_MODS_DIR`,
  `DXVK_CAPTURE_PATH`, `DXVK_LOG_PATH` (`src/util/util_filesys.h:63-65`, `util_filesys.cpp:106-147`).
- DLSS (NGX) feature DLLs are searched in the folder of `d3d9.dll` (`rtx_ngx_wrapper.cpp:165-191`,
  `env::getDllDirectory()`); NRD is located through the module's own path (`rtx_nrd_context.cpp:62`);
  reported: USD plugins resolve from `d3d9.dll`'s folder (`rtx_mod_usd.cpp:2495-2500`).
- GMod is launched with the game root as working directory, which is where `rtx.conf`, `dxvk.conf`,
  `user.conf`, `imgui.ini` and `rtx-remix\` live in `GarrysMod_RTX_c`.

## 3. RTX fixes (`garrys-mod-rtx-remixed`, GPL-2.0)

- Verified: `gmcl_RTXFixesBinary` gets the Remix API through
  `remix::lib::loadRemixDllAndInitialize(L"d3d9.dll")`, which first calls `LoadLibraryW("d3d9.dll")`
  and so accepts an already-loaded runtime (`public/include/remix/remix_c.h:1143-1147`), then falls
  back to `LoadLibraryExW`/`SetDllDirectoryW` variants.
- Verified: its shaderapidx9 and materialsystem patch sets are disabled in code with
  "these don't apply properly" (`source/culling_fixes.cpp:275-277`).
- Reported: requires Remix API 0.1000.1 (fork only; stock NVIDIA runtimes reject it); applies 8
  in-memory engine/client culling patches toggled by `rtx_patch_*` convars, ported from
  SourceRTXTweaks `patches64` (`source/culling_patches.cpp:81-347`); hooks studiorender, datacache,
  filesystem and D3D9 via MinHook and signature scans; the D3D9 device pointer comes from a
  shaderapidx9 signature; `"d3d9.dll"` is hard-coded in several places; game root = exe path minus
  three components.
- Reported: the Lua side (`garrysmod/addons/remixbinary`) bails out in multiplayer unless the
  binary module is installed, and loads it with `require("RTXFixesBinary")`.
- Reported: the RTX stack also needs root `rtx.conf`/`dxvk.conf`, `rtx-remix\mods\{base_mod,
  ~gmod_topbr, rtx_water, gm_poolrooms_rtx}`, a replacement `bin\win64\stdshader_dx6.dll`
  (fixed-function ports of spritecard, eyes, wireframe and water shaders), and cvars in
  `garrysmod\cfg\autoexec.cfg` (`mat_disable_d3d9ex 1`, `r_shadows 0`, `mat_softwareskin 1`,
  `r_novis 1`, ...).
- Reported: `source/startup_assets` is an earlier `d3d9.dll` proxy that reads GMA v3 and finds
  Workshop items without the Steam API (registry, `libraryfolders.vdf`,
  `ugc/4000_subscriptions.vdf`, `appworkshop_4000.acf`). Reference for behaviour only (licence).

## 4. RTXLauncher (reported)

- Installs into a separate copy of GMod (files copied, big folders symlinked; needs admin or
  Developer Mode). The runtime comes from `SheepyLord/dxvk-remix-gmod` GitHub releases (asset
  `*-gmod.zip`, extracted flat into `bin\win64`); the fixes from the `garrys-mod-rtx-remixed`
  nightly zip, extracted into the game root.
- On-disk binary patches from `applypatch.py` (`patches64` from `sambow23/SourceRTXTweaks`):
  hex signatures with `??` wildcards that must match exactly once, length-preserving; plus
  `MaterialSystemFallbackPatch` (x64 only), which caps recursive `$fallbackmaterial` loads.
- Launches `bin\win64\gmod.exe -game garrysmod -console -dxlevel 90 +mat_disable_d3d9ex 1 -nod3d9ex
  -windowed -noborder -noworkshop` with the working directory at the copy's root.
- Updates break because copied binaries go stale against updated VPKs, signatures drift, and
  "update install" can overwrite the fixes' `stdshader_dx6.dll`.

## 5. Workshop and GMA facts (verified)

- Installed items, census of all 759 item folders under `steamapps\workshop\content\4000\<id>\`:
  672 hold one plain GMAD `<name>.gma`; 81 hold an LZMA-wrapped `<hash>_legacy.bin` (older
  uploads; all 81 start with the LZMA properties byte `0x5D`); 6 hold loose files only. The largest
  item is 3.2 GB. `nlctl scan` (M2) parsed all 672 `.gma` indexes, 98,656 entries, in 2.8 s with no
  errors. (An earlier sample of 400 `*.gma`/`*.bin` files, "358 GMAD, 42 LZMA", mixed the two kinds.)
- The 81 `*_legacy.bin` files: LZMA-alone header with properties `0x5D` (lc 3, lp 0, pb 2), 16 MiB
  (19 files) or 32 MiB (62) dictionaries, size always declared (largest 376 MB; 4.4 GB decoded from
  1.5 GB in total). Every file ends with an **8-byte GMod footer** after the LZMA stream: the
  decompressed size as a 32-bit little-endian value, then the magic `0xBEEFCACE` (Bootil's writer).
  `tools/gmapack/gmapack.py` treats those 8 bytes as trailing data, so it cannot read any installed
  legacy item; `nl_core` accepts the footer only when it matches exactly.
- **The archive CRC trailer is optional in practice:** 19 of the 81 legacy items (GMAD v3,
  uploaded 2012-2019) end right after their last file, without the 4-byte CRC, and GMod mounts them.
  One legacy item (1136617425) has a matching CRC trailer followed by four zero bytes of padding.
- `nlctl scan` over all 753 installed archives (2026-10-27): every one parses (672 plain, 81 LZMA,
  104,847 file entries); 19 without trailer, 1 with trailing bytes. `nlctl verify` (Release) over
  all 81 legacy items decoded 4.4 GB in 66 s: 6,191 file CRCs and every footer match; the only
  finding is the padded item above.
- `steamapps\workshop\appworkshop_4000.acf` records per item `size`, `timeupdated` and `manifest`.
  What happens to it when the user subscribes and unsubscribes: section 22.
- `garrysmod\cfg\addonnomount.txt` lists the Workshop ids the user disabled.
- `gmad.exe` only packs whitelisted file types (`.dll`/`.exe` are not); the GMod wiki lists
  DLL and EXE files as restricted for Workshop items. Whether `gmpublish` or the Workshop rejects a
  `.gma` built with other tools is untested (M6).
- GMod launch options `-noworkshop` and `-noaddons` disable Workshop and folder addons for a session.

## 6. Steam depot manifests (verified)

- Cached at `<Steam>\depotcache\<depot>_<manifest>.manifest`; the installed ids are under
  `InstalledDepots` in `steamapps\appmanifest_<appid>.acf`.
- Binary layout: `uint32 0x71F617D0`, `uint32 length`, protobuf `ContentManifestPayload`
  (field 1 = file mapping: 1 filename, 2 size, 3 flags, 5 SHA-1 of content, 6 chunks), then
  `0x1F4812BE` + metadata (1 depot id, 2 manifest id, 4 filenames encrypted). A signature block
  (`0x1B81B817`) and an end marker (`0x32C415AB`) follow, per SteamKit2; our parser does not read
  them. GMod's manifests have plaintext filenames (backslash-separated).
- Flags used: 0x1 user config, 0x40 directory, 0x200 symlink.
- Result on 2026-10-27: 2,877 of 2,878 depot files in the field install matched; the exception was
  the user-config `autoexec.cfg`.

## 7. M1 bootstrap measurements (2026-10-27, Codex)

- Export source: `C:\Windows\System32\winmm.dll`, file version
  `10.0.26100.8875 (WinBuild.160101.0800)`, on Windows build **26300.9711**, display version 26H2
  (registry `CurrentBuild`, `UBR`, `DisplayVersion`; the legacy `ProductName` says Windows 10 Pro).
  The standard-library generator measured **181 populated ordinals**, **180 names**, and **one
  ordinal-only export** (ordinal 2). Inventory: `loader/proxy/generated/exports.json`; generation
  and build-time coverage check: `loader/proxy/generate_exports.py`.
- Independent initial C++ test: `covered 181 system ordinals and 180 names`; forwarding calls
  `timeGetTime`, `timeBeginPeriod(1)`, `timeEndPeriod(1)`, `waveOutGetNumDevs` and
  `mmsystemGetVersion` passed with distinct system/proxy module handles. The initial synthetic
  `gmod.exe` test also passed its log-before-main and absent-engine/shader-API/D3D9 assertions.
  This is synthetic-host evidence, not an enabled PoC result. Test source:
  `loader/proxy/tests/test_proxy.cpp`.
- Debug and Release proxy imports measured by `py -3.12 tools/diag/pe_imports.py`: **KERNEL32.dll
  only**, no static/delay VC++ runtime DLL imports. CMake's static CRT and MASM leaf jumps suffice.
  Python on PATH is now Miniconda 3.14.6 (without `pefile`); the existing `py -3.12` installation
  has `pefile`. No packages were downloaded or installed.
- Baseline PoC map launch (PID 20836, Steam running) reached this ordered sequence:
  `Map: gm_construct`, `Clientside Lua startup!`, joystick initialization,
  `Redownloading all lightmaps`, `Thumbs: 58711 => 58770`. The smoke test requires the map and
  client-Lua markers, then gives post-map output three seconds to flush
  (`tools/smoke_test.ps1`, `Invoke-GameRun`). It normalises only formatting and the numeric
  thumbnail allocation counters (`Normalise-Console`). This strict comparison still needs an
  enabled PoC run; do not assume additional varying lines are harmless.
- PoC `vpk.exe` and `bspzip.exe` statically import `tier0.dll`; PoC `tier0.dll` imports `WINMM.dll`
  (`py -3.12 tools/diag/pe_imports.py` on those three files). No-argument baseline runs exit by
  themselves with codes **1** and **-1**, respectively. Raw stdout/stderr are retained under
  `out/baseline/`; enabled comparisons remain pending.
- Windows Defender blocked the initial Debug proxy at 18:09 local time as
  **Trojan:Win32/Bearfoos.A!ml**, threat id **2147731250**. Subsequent load/copy tests failed with
  Windows' virus/potentially-unwanted-software error. Evidence: `Get-MpThreatDetection` resources
  named the Debug build and the `nl-proxy-测试-*` fixture copies; `Get-MpThreat` reported it active.
  The detection needs human review before further native runtime validation; no antivirus
  configuration was changed. See [M1-report.md](handover/M1-report.md).
- Resumed after the user reported excluding the main checkout: Release passed **11/14** proxy
  cases (including entry timing and all off switches) before fresh detections blocked its remaining
  fixtures and removed the Release DLL in the sibling M1 worktree. Debug passed 7/14; both full
  suites still failed. `0xc0000906` is `STATUS_VIRUS_INFECTED` (installed Windows SDK
  `shared/ntstatus.h:11558`). The new detections name the sibling `!NVIDIA-RTX-Remix-M1` and
  `%TEMP%/nl-proxy-测试-*`, outside the main checkout path the user named. Full logs:
  `out/m1-full-debug-tests.txt`, `out/m1-full-release-tests.txt`.

## 8. M1 final validation and Chromium roles (2026-10-27, Codex)

- Per the user's requested output root, the active `m1-bootstrap` worktree is now
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\m1-bootstrap`. All builds, installer
  fixtures, host fixtures and evidence stay below it. The earlier sibling worktree/build was
  removed. Seven hash-verified legacy host executables were moved from `%TEMP%` to
  `out/prior-validation/legacy-fixtures` (SHA-256
  `5AA6BAD58029EF96C6DC4936B769C5522BD51094F8EC23658880AA860AB78FF4`), preserving them after
  automatic approval review rejected deletion. No generated executable remains in those temp roots.
- GMod's Chromium processes reuse **the same `bin\win64\gmod.exe`**, with roles such as
  `--type=utility --utility-sub-type=network.mojom.NetworkService`. They do not inherit the parent's
  `-nonativeloader` switch. The first real smoke run showed a helper PID replacing the main log
  (`out/smoke/20261028T012617409Z/off-command.loader.log`). A path-only host gate therefore lets a
  helper run the bootstrap even when the main launch is disabled.
- Fixed by treating `--type=value` / `--type value` roles as pure pass-through, using the same
  allocation-free token parser (`loader/proxy/activation.cpp:89`). Prefix near-misses and quoted
  text are covered, plus four child-role integration runs. The smoke check now requires the log PID
  to equal the launched game PID (`tools/smoke_test.ps1:117`). No hook/forwarding technique changed.
- Debug and Release: **4/4 CTest entries pass**, including **16 proxy cases** and **23 installer
  assertions**. The full Debug runner also runs **56 Python tests** (one pre-existing skip).
  Test discovery needed a repository-relative exclusion filter because the selected worktree has
  an ancestor named `out` (`tools/test.ps1:38`); filtering full absolute paths had hidden Python suites.
- Final Release PoC smoke evidence: `out/smoke/20261028T012849979Z/summary.json`:
  `success=true`, `restored=true`; all five launches reach `gm_construct`; console output matches
  after the documented normalization; all off switches produce no log; both tools match baseline.
  Map-load-plus-settle durations: baseline **6.59s**, enabled **6.56s**, command-off **6.53s**,
  environment-off **6.72s**, file-off **6.57s**. These are smoke durations, not benchmark results.
- The enabled log is from main PID **64992**, resolves **181/181** exports, and samples
  `engine.dll=0`, `shaderapidx9.dll=0`, `d3d9.dll=0` at the EXE entry point. Logged startup work:
  **0.2898ms**. Its command line contains the actual `-game garrysmod ... +map gm_construct`
  launch, not a Chromium helper role. Both final configurations still import **KERNEL32.dll only**.
- Final installed and uninstalled verifier reports each have **2,877 OK**, **0 missing**, **0 size
  mismatches**, **0 hash mismatches**, with the existing `autoexec.cfg` user-config difference.
  Evidence: `out/m1-poc-installed-verify.json`, `out/m1-poc-uninstalled-verify.json`. The PoC is left
  with no bootstrap DLL/PDB or loader state. Installed Release DLL SHA-256:
  `E9B1327A89853344DD967D4B6C5C8E48E52F49849C208EA7605B61EF278A3351`.

## 9. M3 deployment measurements (2026-10-27, Claude)

**Release `nlctl`, this machine, a package with a 323 MiB payload file** (the size of the runtime's
`d3d9.dll`, section 2) in a plain `.gma` in a scratch game folder:

| Command | Time | What it does |
|---|---|---|
| `apply`, first | 1.75 s | extract, check size, CRC-32 and SHA-256, flush, place |
| `apply`, again (no-op) | 44 ms | 0 file-system changes, journal untouched |
| `status` | 13 ms | size and time of every recorded file |
| `status --verify` | 231 ms | SHA-256 of every file: about 1.4 GB/s with CNG on cached data |
| `uninstall` | 0.32 s | a full SHA-256 of each file before it is deleted |

The full 930 MB runtime should therefore deploy in about 5 s from a plain archive. From an
LZMA-wrapped one it takes longer, decoding at about 67 MB/s (section 5).

**Process costs.** In a Debug build a deployer command costs about 30 ms before it does any work:
the process start, plus one Toolhelp scan of all processes for the running-game check. Most of the
rest of a tiny deployment is durability: about 15 flushes and write-through renames per apply.
`test_deploy.cpp` therefore runs its thousands of in-process deployments on a file system without
flushes (`FastDisk`), and the test host skips the process scan.

**Change counts.** The fault test's scenarios, killed by `TerminateProcess` before each change; every
one ended in the old or the new state after recovery:

| Scenario | File-system changes |
|---|---|
| first deployment (runtime + root-files package) | 54 |
| upgrade (new runtime folder; root files replaced, added, removed) | 59 |
| rollback | 26 |
| uninstall | 35 |

**PoC acceptance.** The test package held a payload file, a mod file, a binary Lua module and a
create-only cfg file. The bootstrap install, `apply` and uninstall made 58 changes, the second apply
none. All 3,113 files and folders of `GarrysMod_PoC` were identical afterwards, sizes and times
included, and 2,877 depot files verified OK. Evidence: `out/poc-deploy/20261028-043358/` (the run
after the review fixes; the first run, `20261028-035222`, made 54 changes before payload files were
moved one by one).

**Windows behaviour the deployer relies on:**

- `MoveFileExW` without `MOVEFILE_COPY_ALLOWED` renames only within a volume, which is why staging
  lives under the game folder and links are refused there.
- `GetFileAttributesExW` reports a junction itself, not its target.
- A file opened with `FILE_FLAG_OPEN_REPARSE_POINT` is the link itself, so hashing refuses links.
- An exclusive handle (share mode 0) on `native-loader\lock` makes a second deployer fail with
  `ERROR_SHARING_VIOLATION` until the first one's process ends.
- The running-game check snapshots processes with Toolhelp and opens each `gmod.exe` for its image
  path. A process that exits between the snapshot and `OpenProcess` fails with
  `ERROR_INVALID_PARAMETER`, and only `ERROR_ACCESS_DENIED` means "cannot tell". Under parallel
  CTest, M1's proxy tests run short-lived synthetic `gmod.exe` processes. Treating every failed
  open as "running" made `nlctl_e2e_deploy` refuse now and then.
- Windows may keep an executable's image file locked for a moment after its process ends;
  `e2e_deploy.py` retries putting its placeholder `gmod.exe` back.

## 10. M4 activation research (2026-10-27, Claude)

Gathered while planning M4; scripts were one-offs under `out\tmp` (`pefile`, `ctypes`), read-only.

**Who reads the command line, and when** (PoC, build 26229091):

- `gmod.exe`, `launcher.dll`, `tier0.dll`, `vstdlib.dll`, `engine.dll`, `filesystem_stdio.dll`,
  `materialsystem.dll`, `shaderapidx9.dll` and `client.dll` each import both `GetCommandLineA` and
  `GetCommandLineW` from KERNEL32. `tier0.dll` exports `CommandLine`, `Plat_GetCommandLine` and
  `Plat_GetCommandLineA`; all the others except `gmod.exe` import `CommandLine` from it.
- None of `gmod.exe`, `launcher`, `tier0`, `vstdlib`, `engine`, `shaderapidx9`, `client` imports a
  C runtime DLL (`ucrtbase`, `api-ms-win-crt-*`, `vcruntime*`, `msvcp*`): they link it statically.
  `gmod.exe`'s static imports are only system DLLs and `WINMM` (ours); `launcher.dll` and the
  engine load later. So no engine module has read or cached the command line when our entry-point
  hook runs.
- kernelbase on this machine (Windows 10.0.26300.9711): `GetCommandLineW` is `48 8b 05 41 9f 2b 00 c3`
  and `GetCommandLineA` is `48 8b 05 41 08 2b 00 c3` (`mov rax,[rip+disp32]; ret`); KERNEL32's exports
  of the same names are `jmp [rip+x]` thunks to them. The pointer each returns sits at rva `0x3ae058`
  (W) and `0x3ae048` (A), as the `Buffer` of a `UNICODE_STRING` / `ANSI_STRING`: the 8 bytes before
  each slot hold `Length` = the string's length in bytes (202 and 101 for a 101-character command
  line) and `MaximumLength` = `Length` + one terminator.
- RTXLauncher passes `-dxlevel 90 +mat_disable_d3d9ex 1 -nod3d9ex` (section 4).

**How the runtime takes its config layers** (fork `dxvk-remix-gmod`):

- `resolveConfigPaths` (`src/dxvk/rtx_render/rtx_option_layer.cpp:617-627`): when
  `DXVK_RTX_CONFIG_FILE` (or `DXVK_CONFIG_FILE`) is set and not empty, the runtime reads only the
  paths it lists, split at commas; `.\rtx.conf` is read only when the variable is unset. So a loader
  that sets the variable must list the user's root `rtx.conf` itself.
- (Corrected in section 19: for `rtx.*` options the **first** listed path is the strongest, not the
  weakest.) `createLayersFromEnvVar` (`:629-647`) makes one layer per listed path, lowest priority first; the
  last `rtx.conf` layer becomes `s_rtxConfLayer` (`:704-712`), the one the Remix menu saves to. A
  layer whose file is missing or empty is registered but not merged (`isValid()` is "has options",
  `rtx_option_layer.h:141`).

**The runtime's files** (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`):

- `_output` is the complete runtime: 192 files, 1,117,358,408 bytes, built 2026-10-26 23:36, with
  `usd\` and the build by-products `d3d9.pdb`, `.exp`, `.lib`. Nothing the classic install keeps in
  `GarrysMod_RTX_c\bin\win64` for the runtime is missing from it.
- `_CompRelease_x64\src\d3d9\d3d9.dll` (338,675,200 bytes, 2026-10-27 11:32) is the newest build and
  the same file as `built-A8E39D93-lockfree-options\d3d9.dll`. The `built-*` and `deployed-*` folders
  hold only `d3d9.dll` and `d3d9.pdb` (140,800,000 bytes for A8E39D93).
- `d3d9.dll`'s only delay-load import is `amd_fidelityfx_vk.dll`, loaded by bare name; its static
  imports include the UCRT API sets (`api-ms-win-crt-*`) besides the VC++ runtime of section 2.
- `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` and `vulkan-1.dll` are only in System32 on
  this machine, not in the PoC's or `GarrysMod_RTX_c`'s `bin\win64`; the classic install keeps
  `amd_fidelityfx_vk.dll` in `bin\win64`.
- `GarrysMod_RTX_c\bin\win64` holds 77 files (3.63 GB) beyond vanilla: the runtime mixed with
  backups, PDBs, Jolt, the MMD hotloader, VR files, `NvRemixBridge`, `dxsupport.cfg` and a
  `debug.log`. A runtime package therefore takes an explicit file set (`_output`), not that folder.
- `GarrysMod_RTX_c` has the user's `rtx.conf` (161,131 bytes) and `dxvk.conf` (2,610 bytes) in its
  root, the layers the classic install runs with.

## 11. M4 implementation and acceptance findings (2026-10-28, Codex)

- Section 10's cached-string layout is now checked before any write, including the PEB descriptor.
  Synthetic descriptor tests cover mismatched Length/MaximumLength/pointer, USHORT overflow and a
  failure after a partial write. A separate process swaps the real kernelbase W/A and PEB records,
  checks updated lengths and restores their exact bytes (`loader/core/src/cmdline.cpp:96`,
  `loader/tests/cmdline_host.cpp`). The user approved loader version 0.1.0 to match the packager's
  existing `requires_loader >=0.1.0` contract.
- Debug and Release pass **15/15 CTest entries**. Core cases total **120** (117 normal plus three
  exhaustive fault groups); proxy cases remain **16**, installer assertions **23**. Python: **66**
  tests, one pre-existing skip. The PE CTest confirms the final bootstrap imports only KERNEL32.
  Steam registry lookup now dynamically resolves RegGetValueW from System32 advapi32
  (`loader/core/src/discovery.cpp:40`).
- The packaged fake runtime proves bare-name d3d9 reuse, static and delay dependency paths, user
  layers/arguments, full failure rollback, explicit fallback options, all off switches, contention,
  source disappearance/removal and version/hold behavior. **17 scenario groups** pass. Isolated
  Release evidence: `out/m4-synthetic/release-62268/summary.json`; ten unchanged-deployment samples
  have **25.8064 ms median**, **19.8476–27.9013 ms** range, zero deployment operations. Timing ends
  before final report I/O. Raising a native exception in the fake DLL initializer produced Windows
  error **1114** and verified vanilla continuation with restored settings.
- The named B folder was absent. Section 10's alternate `_CompRelease_x64/src/d3d9/d3d9.dll` was
  present with the documented size/time and the **A8E39D93** prefix. Full hashes used:
  - A: `E5C65136EA8BC7A7485776C18F975FE8068F74B5743DC8EA536AAFF8D6065BCA`;
  - B: `A8E39D938D96193DF27D245A7F6E72F1C44B75FB2D066A67BDC2CD974EDEA267`.
  The acceptance script pins the full B hash before accepting this alternate copy. No fork file
  was changed. Config snapshots were hash-checked and reused for both packages.
- Real evidence is under `out/poc-activation/20261028T075336206Z/`. Original A contains **191 files,
  977,303,948 bytes** without PDBs; B has **191 files, 977,403,788 bytes**. These measured sizes
  supersede the earlier rough full-runtime estimate for this recipe.
- The user approved each actual launch and explicitly requested **-multirun**, keeping the RTX_c
  install open. Vanilla PoC PID **6876** reached gm_construct with System32 d3d9 and **mat_dxlevel 95**.
  The initial A PID **70300** deployed generation 1 in **4808.77 ms**, activated in **36.5178 ms**,
  and completed startup in **4846.04 ms**. The engine printed **mat_dxlevel 90**, proving it saw
  the injected arguments. Remix logged an RTX 5090 device, successful Reflex initialization,
  ray-tracing feature support and swapchain creation, then the engine exited before map completion.
- The copied classic DXVK config has **d3d9.shaderModel = 0** (snapshot line 10). The fork rejects
  shader bytecode above that option (`src/d3d9/d3d9_shader.cpp:115`), explaining the logged
  “GetShaderModule: Out of range of supported shader model” errors. Its default is **3**
  (`src/d3d9/d3d9_options.cpp:69`). Windows event 1000 recorded a PoC engine.dll fault with
  exception **0xc0000409**; the exact engine termination cause was not independently debugged.
- After §9 consultation, the user approved a **PoC-only shaderModel=3 layer** and one A retry.
  It kept both reference configs unchanged and added one 132-byte layer. PID **31480** reached
  gm_construct at **mat_dxlevel 90**. Deployment: **4920.9048 ms**; activation: **39.4931 ms**.
  All **34** loaded runtime DLLs in `03-RunA/runtime-modules.json` came from the versioned package,
  including d3d9, amd_fidelityfx_vk, NvLowLatencyVk and the DLSS family.
- The user reported **not path-traced/rendering incorrectly**, then stopped further PoC testing.
  Real RTX-off output, **dxlevel persistence**, B activation and rollback therefore remain open.
  Startup activation success is not evidence of successful later rendering.
- Cleanup removed 383 package files and the bootstrap/control/status state. `verify.json` reports
  **2,877 OK**, **0 missing**, **0 size mismatches**, **0 hash mismatches**, with the existing
  autoexec.cfg user-config difference. `created-or-changed.txt` records preserved Remix/Sentry logs,
  capture directories, engine crash artifacts, metrics and game-written config/cache/console changes.
  No game/Remix data was deleted for cleanup. The other RTX_c instance remained running.

## 11. Session side effects and automation (2026-10-28, Claude)

**Settings GMod keeps between sessions.**

- GMod's video settings are in `HKCU\Software\Valve\Source\garrysmod\Settings` (`ScreenWidth`,
  `ScreenWindowed`, `mat_*`, `DXLevel_V1`, ...). The key has the mod folder's name, so the field
  install, the PoC and `GarrysMod_RTX_c` all share it.
- `DXLevel_V1` does not decide the level a session runs at. With 90 stored (since 2026-10-27 02:02),
  vanilla PoC sessions ran at `mat_dxlevel 95` (Codex's baseline, and run 1 below) and wrote 95 back
  at start-up; a session started with `-dxlevel 90` ran at 90.
- `-dxlevel 90` does not carry over: three PoC sessions, vanilla, `-dxlevel 90 -nod3d9ex
  +mat_disable_d3d9ex 1`, vanilla again, ran at 95, 90 and 95, and neither the registry key nor
  `config.cfg` changed (evidence `out\m4-review\persistence-20261028T040607`; the key was restored
  from the backup taken first).
- Archived console variables persist in the install's own `garrysmod\cfg\config.cfg`, which the game
  writes when it quits normally. The PoC's already held `mat_disable_d3d9ex "1"` before M4; a vanilla
  session then reports `"mat_disable_d3d9ex" = "1" ( def. "0" )` and "mat_disable_d3d9ex changes will
  not take effect until application restart": the variable is read when the device is created,
  before `config.cfg` or `+` commands run. So `+mat_disable_d3d9ex 1` on the command line only changes
  the next session (through `config.cfg`), while `-nod3d9ex`, which `shaderapidx9.dll` reads (both
  strings are in it), acts on the current one.

**Ending a session without a person.**

- `game.ConsoleCommand("quit\n")` from server Lua is refused: `game.ConsoleCommand blocked! (quit)`.
- The menu state loads a fixed list of files (`lua/menu/menu.lua`); `RunGameUICommand("QuitNoConfirm")`
  exists only there, so it cannot be reached without changing depot files.
- `WM_CLOSE` to the main window (`CloseMainWindow`) does not end the game (15 s; Codex saw the same).
- Source's TCP remote console does: with `-usercon -ip 127.0.0.1 -port <p> +rcon_password <x>` and a
  listen server (`+maxplayers 2`), an RCON `quit` ends the session normally (exit code 0). In a
  single-player session the remote console does not listen (connection refused).
  [`tools/poc_session.py`](../tools/poc_session.py.md) uses this.

**Shader DLLs.** A vanilla session at `mat_dxlevel 95` loads `stdshader_dx6.dll` too, by full path:
the module list shows `h:\steamlibrary\steamapps\common\garrysmod_poc\bin\win64\stdshader_dx6.dll`,
lower-cased by the engine's file system.

**Windows loader.** At an `LdrRegisterDllNotification` "loaded" callback, the new module's imports
are already bound (`wininet.dll`: 355 of 355 import address table entries resolved, Windows
10.0.26300). An import hook installed then is in place before the module's own code runs.

## 12. What the classic RTX install adds (M5 research, 2026-10-28, Claude with a research agent)

Compared with the PoC (vanilla build 26229091). "Verified" as in the header; offsets are PoC file
offsets or RVAs as stated.

**`GarrysMod_RTX_c` runs an older GMod build.** Of its engine binaries only `tier0.dll` matches a
cached depot manifest; its VPKs (`garrysmod_000-002`, `fallbacks_*`, `sourceengine\content_hl2_dir`)
differ from the PoC's too. Its runtime is B (`d3d9.dll` SHA-256 `a8e39d938d96193d...`).

**On-disk engine patches.** RTXLauncher applies `patches64` from `sambow23/SourceRTXTweaks`
(`applypatch.py`, fetched at install time; no local copy). Each pattern must match exactly once;
RTX_c holds each in patched form. All seven match exactly once in the PoC's build:

| DLL | Pattern (offset) | Replacement | Purpose |
|---|---|---|---|
| engine | `ff90????????85c0742b` (0) | `b80200000090` | `Mod_LoadLighting`: HDR type 2 |
| engine | `ff90????????85c00f84fa000000` (0) | `b80200000090` | `Mod_LoadWorldlights`: HDR |
| shaderapidx9 | `4833cce8????03004881c448` (0) | `85c0750466b80400` | zero-sized buffer returns 4 |
| shaderapidx9 | `4883ec084c` (0) | `31c0c3` | shader constants function returns 0 |
| shaderapidx9 | `4885db75??498b4500` (3) | `eb` | skip the invalid-vertex-format `Error()` |
| materialsystem | `f77c24683bc10f4fc1488b8c24300100004833cce8????04004881c448010000` (0) | `448b4424684585c0740341f7f839c80f4fc14881c448010000c3` | zero-sized buffer guard |
| datacache | `647838302e767478` (0) | `647839302e767478` | `dx80.vtx` to `dx90.vtx` |

`MaterialSystemFallbackPatch` does not apply to either build (a 2-byte `66 90` where it needs a
15-byte site) and was never applied to RTX_c. The fixes' module applies 8 other, in-memory
engine/client culling patches itself (`source/culling_patches.cpp:81-347`, from `module.cpp:427`);
`source/culling_fixes.cpp` (with "these don't apply properly") is dead code: `CullingHooks` is never
initialised (corrects section 3).

**How `stdshader_dx6.dll` is loaded.** `materialsystem.dll`'s `LoadAllShaderDLLs` (rva `0x4b010`)
asks for `stdshader_dbg.dll`, then `stdshader_dx6.dll` up to the dx level, through
`IFileSystem::LoadModule` (vtable +0xe8). `filesystem_stdio.dll` resolves the name against the
`EXECUTABLE_PATH` search path (`bin\win64`, added first by `launcher.dll`) and calls
`LoadLibraryExA(<full path>, NULL, LOAD_WITH_ALTERED_SEARCH_PATH)` from its `Sys_LoadModule` (rva
`0x5ebe0`; the call at `0x5eb02`). Preloading a copy elsewhere therefore does not help; an import hook
on `filesystem_stdio.dll`'s `LoadLibraryExA` does. `LoadLibraryExA` is also imported by materialsystem,
engine and launcher, `LoadLibraryA` by tier0, engine and shaderapidx9, none delay-loaded.

**The fixes' shader DLL.** A binary committed in the fixes at `garrysmod/bin/win64/stdshader_dx6.dll`
(byte-identical to RTX_c's, 437,248 bytes; sources removed in 4b9da1e, readme points to
`sambow23/obsolete-source-engine`): fixed-function ports of spritecard, eyes/eye_refract, wireframe
and water. It finds `gmcl_RTXFixesBinary_win64.dll!RTX_SetEyeTexGenState` by that module name at run
time. With RTX_c's `dxvk.conf` (`d3d9.shaderModel = 0`, line 10) RTX_c's own Remix log also shows
"Out of range of supported shader model" (28 times), so that message is normal there.

**The fixes' other pieces.** `gmcl_RTXFixesBinary_win64.dll` (1,441,792 bytes in RTX_c, built
2026-10-27), `gmcl_rtxwater_win64.dll`, `gmcl_rtxdebug_win64.dll` (all import only tier0, ole32,
KERNEL32). Lua: `addons/remixbinary/lua/autorun/cl_rtx.lua` (`require("RTXFixesBinary")` at :10,
multiplayer guard at :4), rtx_water (`cl_native.lua:37-42`), niknaks and others. Remix mods from the
fixes: `base_mod` (37 MB), `rtx_water` (11 MB), `gm_poolrooms_rtx` (150 MB), `~gmod_topbr` (87 files
in the repo; ToPBR writes generated DDS files there at run time). `autoexec.cfg` is the fixes' file:
`sv_cheats 1`, `mat_disable_d3d9ex 1`, `r_3dsky 0`, water reflection/refraction 0, `r_shadows 0`,
`mat_softwareskin 1`, specular/bump/normal/parallax 0, `r_frustumcullworld 0`, `r_occlusion 0`,
`r_novis 1`, plus the user's own settings. The fixes also overwrite five Steam files (menu
`problems.lua`, sandbox `gmod_camera.lua`, three images), which this project's rule 2 forbids.
Built with premake 5 and garrysmod_common, VS 2022; no release zip locally.

**The user's test save and measure.** Reference save
`GarrysMod_RTX_c\garrysmod\saves\gm_csgosafehouse 2026-10-25 04-08-30.gms`. Harness
`C:\Users\matt-peng\.rpai\work\_probe\session_run.py` (fixed camera `REF_CAMERA`, captures with the
`jpeg` command, HUD and view model hidden). Measure `look\compare.py`: crop both images to a multiple
of 32, take the mean RGB of every 32x32 block, report the mean absolute difference over all blocks and
channels (0-255); about 1 between repeated captures, 1.5-3.6 "close", 16-26 "broken". The save needs
the Workshop map 944959992 (a legacy `.bin`, 162 MB, in the shared Workshop folder), the CS:GO mount,
the user's `SafeHouse` Remix mod, and the MMD Hot Loader character with its `ai_pbr` mod. The classic
install's launch line (`_debug_tools\launch_gmod_keeplogs.bat:12`) is `-console -condebug -dxlevel 90
+mat_disable_d3d9ex 1 -nod3d9ex -windowed -noborder -w 3840 -h 2160 -tickrate 128 -multirun -insecure
+r_forcehwlight 1`; RTXLauncher adds `-noworkshop` only when its `LoadWorkshopAddons` is false (the
user's is true; corrects section 4).

## 13. M5 on the PoC (2026-10-28, Claude)

**Add-on mounting.** GMod x64 mounts an add-on **folder** in `garrysmod/addons` ("Adding Filesystem
Addon 'addons/nl_probe_folder'", its client autorun ran) but not a loose `.gma` placed there, plain
Lua or not (no message, the Lua did not run): `out/poc-sessions/m5-mount-probe`. Local packages
therefore deploy their Lua as add-on folders ([ADR 0011](decisions/0011-lua-addon-folders.md)).

**`SetDllDirectoryW` broke the RTX fixes.** garrysmod_common's `ModuleLoader.cpp` finds GMod's
modules with `GetModuleHandleExA(0, "bin/win64/lua_shared.dll", ...)`, a path relative to the working
directory. With M4's `SetDllDirectoryW(<runtime folder>)`, which also drops the working directory from
the DLL search, that lookup failed: the fixes' module printed "Failed to get ILuaConVars interface" and
"Failed to create or find convar" for its 15 variables, and the game ended with `0xC0000409` right
after the map loaded. With the runtime folder first on `PATH` instead, the module reports "Got
ILuaConVars interface" and every variable ready, and the session quits normally
([ADR 0010](decisions/0010-rtx-session-extras.md) point 4).

**The loader's RTX session on the PoC** (runtime B with the reference install's `rtx.conf` and
`dxvk.conf` as layers, the fixes package built from the fixes repo with `GarrysMod_RTX_c`'s modules,
the reference install's user content copied by [`poc_parity.py`](../tools/poc_parity.py.md)):

- First start deployed both packages (445 changes, 1.43 GB) in 7.3 s, activation 31 ms; a later start
  changed nothing, deployment 54 ms, start-up 80 ms in all.
- All 7 patch sets applied (engine 2, materialsystem 1, datacache 1, shaderapidx9 3), 15 game modules
  hooked, `filesystem_stdio`'s load of `bin\win64\stdshader_dx6.dll` redirected to the package's copy,
  33 session variables run through `nativeloader_session.cfg`.
- gm_construct at the spawn camera (eye 815.2, 288.0, -79.1, yaw 180, pinned in both installs, HUD
  hidden): `GarrysMod_RTX_c` and the PoC differ by **block_diff 0.90** (the user's measure: about 1
  between repeated captures of one install); mean RGB 119.5/113.2/101.0 in both. Evidence
  `out/m5/acceptance/ref-construct-pinned-2` and `poc-construct-pinned`.

**Session variables do not leak in practice.** After RTX sessions that quit normally, none of the
33 session variables appears in the PoC's `config.cfg` (they are not archived in this GMod build), so
the restore record stays empty (`recorded: 0`); the restore is a safety net for variables a package
adds that are.

**Things in the reference install to know about.** Launched with `-noworkshop`, one of its local
add-ons opens a "Zippy's Library missing" dialog that dims the frame (closed by `poc_session.py
--hide-hud`). Its `rtx-remix\mods` holds two **symbolic links**, `codex_new` and `codex_test`, whose
targets lead back up the tree: a copy that follows links never ends (robocopy wrote about 390 GB before
it was stopped). `poc_parity.py` skips linked mods and passes `/XJ`. Five of its 29 add-on folders
are symbolic links or junctions to the user's working copies under `H:\BACKUP_20260815\Modding\ipg\`
(`!advanced_material_editor`, `!gmod_bullet_break_simulator`, `advanced_bodygroup_tool`,
`eeer_body_impact_sounds`, `enhanced_entity_expression_response`; 8.4 GB with their `.git`).

**Loading the user's test save without anyone at the keyboard.**

- The save's map, `gm_csgosafehouse`, exists only as Workshop item 944959992 (a legacy LZMA `.bin`).
  With `-noworkshop`, `gm_load "saves/<name>.gms"` does nothing and prints nothing. With bad
  arguments it prints `usage: gm_load <path>`, so the command itself exists.
- With the Workshop on, the reference install printed nothing for 15 minutes after the material
  system started. It was still busy (about 2 cores, 9 GB working set) when the session driver gave
  up. The user has 753 Workshop archives installed.
- `host_workshop_map` is unknown on a single-player client.
- What works: client Lua `steamworks.DownloadUGC("944959992", cb)` hands back
  `cache/workshop/944959992.gma` (the legacy item decompressed) at once, and `game.MountGMA` on it
  returns true with one file. `gm_load` then changes level to the save's map.
  `poc_session.py --mount-workshop` does this.
- On that level change both installs log "Couldn't write cache/map_pack.bsp to mount embedded
  content!" (GMod's handling of a map inside a mounted `.gma`). The PoC's extracted copy of the map
  was removed so both load it the same way.
- Text sent through `WM_COPYDATA` while the RTX fixes reload models after a map change can be
  accepted by the window and then lost. The camera Lua sent 3 s after `Clientside Lua startup!` never
  ran, while a `quit` sent later did.

**The safehouse comparison, and what the remaining difference is not.** Reference
`ref-safehouse-mounted` against PoC captures with growing parity, all at the user's camera and
loading the save through the mounted Workshop map:

| PoC capture | block_diff |
|---|---|
| + the reference's 16 plain add-ons and the MMD Hot Loader's and RTX bridges' native files | 3.23 |
| + the Advanced Material Editor's data (`garrysmod/data/advmat`: 29 rules, 32 RTX profiles) | 3.23 |
| + the 5 add-ons linked to working copies, and the 2 linked Remix mods (`codex_new`, `codex_test`) | 3.18 |
| + the reference's own `~gmod_topbr` mod instead of the package's | 3.24 |

Two reference frames 4 s apart differ by 0.83. These are byte-identical in both installs: `d3d9.dll`
(a8e39d93), `gmcl_RTXFixesBinary_win64.dll` (485667b7), `stdshader_dx6.dll` (4bf218db),
`rtx.conf`, `dxvk.conf`, `user.conf`, `config.cfg`, `base_mod`, `gm_poolrooms_rtx` and `rtx_water`.
Geometry, lighting and shadows match. The difference sits in 41-46 of 880 blocks above 8, on the
woven chair backs, which are darker in the PoC. What could not be made equal is the game build: the
reference runs GMod 2026.09.15 (10174) with older `engine.dll` and VPKs, the PoC the current
2026.10.26 (10215). Depot files are never written, so that difference stays.

**Without RTX, a deployed package's Lua add-ons still run** (PoC, `remix.enabled: false`, before
ADR 0013).

- GMod mounted the fixes' nine add-on folders ("Adding Filesystem Addon 'addons/remixbinary'").
- Their server Lua initialised ("[RTX Flashlight] Default flashlight override: ENABLED").
- `cl_rtx.lua` `require`s the binary module whenever it is installed. The module noticed Remix was
  missing ("remix::loadRemixDllAndInitialize() failed"), applied none of its own runtime patches
  ("[MemoryPatcher] Disabled 0 patches") and shut down; RTX Water stayed off.
- The module's own PatchManager is a second patcher besides the loader's patch sets. In RTX sessions
  it resolves the same seven culling patches by its own locators and applies them, then restores them
  at map exit.
- `filesystem_stdio.dll` imports `FindFirstFileA`, `FindNextFileA`, `FindFirstFileExW` and
  `FindNextFileW` from KERNEL32, which is where ADR 0013 hides the add-ons. `engine.dll` and
  `tier0.dll` import only the `ExW`/`W` pair.

**The fixes write into their own deployed files.** The ToPBR converter rewrote
`rtx-remix/mods/~gmod_topbr/topbr_generation.txt` in the first PoC session. The deployer then reports
it ("changed after the loader placed it; left as it is"), and an uninstall leaves it behind. A
reinstall then refused the whole fixes package: "topbr_generation.txt already exists and was not
placed by the loader". `package_fixes.py` now deploys that mod create-only.

## 14. Workshop packing and updates (M6, 2026-10-28, Claude)

- `gmad.exe create` (the PoC's `bin\win64\gmad.exe`) on a folder holding `lua/autorun/a.lua`,
  `native/manifest.json` and `native/payload/test.dll`: "native/manifest.json [Not allowed by
  whitelist]", "native/payload/test.dll [Not allowed by whitelist]", "File list verification failed",
  no `.gma` written. The same folder with only the Lua file packs (181 bytes). Evidence
  `out/m6/gmad-probe`.
- **That whitelist is a packing limit, not a Workshop rule** (the user's correction, checked
  2026-10-28).
  - The `.dll`/`.exe`/`.htm`/`.html`/`.css`/`.js` list on the wiki's
    [Workshop Addon Creation](https://wiki.facepunch.com/gmod/Workshop_Addon_Creation) page says what
    `gmad.exe` will pack.
  - The [Steam Workshop rules](https://wiki.facepunch.com/gmod/Steam_Workshop_Rules) have no rule
    about file types. They ban exploits and backdoors, paid-game content, reuploads, wrong tags, and
    empty, test or placeholder items. Their "good ideas" list (not bans, but it can get an item flagged
    as incompatible) includes "do not upload broken addons", with a size limit of about 4 GB.
- **The real package through the Workshop** (ADR 0016, 2026-10-28).
  - `gmpublish update` uploaded the combined `gmod-rtx-remix` archive, 1,426,861,733 bytes (shown as
    "1.3 GB"), to item 3829070317. The archive was stored plain, not compressed.
  - Building it with `publish_workshop.py` takes seconds when the inputs are in the file cache.
  - GMod's `DownloadUGC` fetched it back byte-identical, under the uploaded file name.
  - `appworkshop_4000.acf` then listed it with the new `timeupdated` (1793223164), and the loader
    reported that time in `status.json`.
- Not tried at first: `gmpublish` (it uploads, with no dry run; outward-facing). Tried on 2026-10-28
  with the user's approval ([ADR 0015](decisions/0015-workshop-route-for-native-packages.md),
  [M6 report](handover/M6-report.md)):
  - **Upload.** `bin\win64\gmpublish.exe create -addon <gma> -icon <512x512 baseline JPEG>`, run
    from a game root that holds `steam_appid.txt`, uploaded a `gmapack` archive with
    `native/manifest.json` and a DLL. It did not check the contents. It printed "Success! Your new
    item ID is 3829070317" and "currently marked as hidden". `update -id <id> -addon <gma> -changes
    <text>` replaced the file.
  - **Download.** GMod's `steamworks.DownloadUGC(id, cb)` fetched the hidden item for its owner,
    without a subscription.
    - It went to `steamapps\workshop\content\4000\<id>\<uploaded file name>`, as a plain `.gma` (not
      LZMA-wrapped), byte-identical. An update replaced the file under the new upload's name.
    - `cb` got the path `content/4000/<id>/<name>.gma`.
    - `appworkshop_4000.acf` listed the item under `WorkshopItemsInstalled` (size, `timeupdated`,
      manifest) and under `WorkshopItemDetails`.
  - **GMod's own mount.** `game.MountGMA` refuses an archive that holds a file outside GMod's
    whitelist, printing "Couldn't mount file [<path>]" and returning false. A Lua-only `gmapack`
    archive mounts. A Workshop item that carries native files is therefore never mounted by GMod,
    and its Lua must come from elsewhere.
- The deployer handles LZMA-wrapped legacy Workshop items end to end, an update included
  (`loader/cli/tests/e2e_deploy.py`, M3).
- `steamworks.FileInfo(id, callback)` gives the item's Workshop `updated` time; the companion compares
  it with the `time_updated` that `appworkshop_4000.acf` had at start-up (now in `status.json`
  `packages`) and asks for a restart when it is newer (`tools/tests/test_companion.py`).


## 15. The field install with the loader (M7, 2026-10-28, Claude)

Measured in the user's Steam-managed install: gm_construct, the user's 44 local add-ons, no Workshop,
camera pinned. Evidence in `out/m7` ([M7 report](handover/M7-report.md)).

- **What the field install holds besides Steam's files.**
  - In `bin/win64`: a DXVK `d3d9.dll` (4 MB) for non-RTX play, a `vulkan-1.dll` (903 KB, five hard
    links), the MMD Hot Loader runtime, Jolt's three `vphysics_jolt_*.dll` with PDBs and its zip, and
    VR and Hammer++ files.
  - In `garrysmod/lua/bin`: the MMD Hot Loader's modules and VRMod's.
  - In the root: logs, `steam_appid.txt`, and GModPatchTool's folder and zip.
  - In `garrysmod/data`: 61 GB in 39,613 files.
  - No `rtx-remix`, `user.conf` or `rtx.conf`.
  - 76 non-depot files sit directly in the folders sessions write to, 255 MB; `field_snapshot.py`
    copies them in 3.4 s.
- **Without the loader** the game loads the DXVK `d3d9.dll` and `bin/win64/vulkan-1.dll`, the
  MMD Hot Loader's three modules, and the stock `vphysics.dll`. Jolt is not loaded. `mat_dxlevel` is 95.
- **With the loader and RTX on** it loads the runtime package's `d3d9.dll`, System32's
  `vulkan-1.dll` (the preload wins over `bin/win64`), the package's `stdshader_dx6.dll` and the
  fixes' module, the MMD Hot Loader as before, and `mat_dxlevel` 90. First deployment: 445 changes;
  map after 19 s.
  - Remix shows its first-run welcome panel, because the install has no `user.conf`.
  - The default Remix settings give a bluer frame than the PoC with the reference's `user.conf`
    (mean RGB 73/94/105 against 120/113/101).
- **With the loader and RTX off** the module set equals the baseline's plus the bootstrap, the 44 add-ons
  mount (the fixes' 9 hidden), and the frame matches the baseline's at block_diff 0.015.
- **What a session rewrites in the user's data**, all with unchanged sizes:
  - the MMD Hot Loader's `approved.json` and `workshop/state.json`;
  - `bbs/filters.json`;
  - `settings/mapkeys.res`;
  - in RTX sessions, the fixes' `pseudoweapontexture*.png`.

  New in RTX sessions: the fixes' `rtx_agent`, `rtx_water` and `pseudoplayertexture*.png` in
  `garrysmod/data`, and `rtx-remix/` (Remix's logs).

## 16. R1 review facts (2026-10-28, Claude, triaging Codex's review)

- **Steam's depot files inside the package areas.** Measured read-only from the field install's
  depot manifests (`out/r1-triage/depot_areas.py` in the R1 worktree, 3,063 depot file entries):
  - `garrysmod/cfg/` holds 18: `360controller-linux.cfg`, `360controller.cfg`, `autoexec.cfg`,
    `config_default.cfg`, `game.cfg`, `listenserver.cfg`, `mapcycle.txt`, `mount.cfg`, `network.cfg`,
    `server.cfg`, `settings_default.scr`, `skill.cfg`, `skill1.cfg`, `skill2.cfg`, `skill3.cfg`,
    `skill_manifest.cfg`, `undo360controller.cfg`, `valve.rc`. So `garrysmod/cfg` stopped being a
    package area ([ADR 0014](decisions/0014-r1-hardening.md)).
  - `garrysmod/lua/bin/`, `garrysmod/addons/`, `garrysmod/data/` and `rtx-remix/` hold none.
- **Import tables without names.** A PE import descriptor may have `OriginalFirstThunk` 0. Windows
  then resolves the imports from `FirstThunk` and overwrites it with addresses, so the names are
  gone once the module is mapped. Codex's repro (R1-006) zeroed it in a copy of the synthetic
  `filesystem_stdio.dll`: the DLL loads, and name-based hooks find nothing.
  - The hooks now match such slots by the bound address.
  - `GetProcAddress` on kernel32 follows its forwarders, so `GetProcAddress(kernel32, ...)` and
    `GetProcAddress(kernelbase, ...)` give the addresses the loader binds.
- **Windows PowerShell 5.1 started from PowerShell 7.** It inherits `PSModulePath` with PowerShell 7's
  module folders first. It then fails to autoload `Get-FileHash` (`Microsoft.PowerShell.Utility`), and
  `install-loader.ps1` stops (R1-029, seen in Codex's second `tools\test.ps1` run). A child started
  without `PSModulePath` builds its own default path and works.
  - The failure reproduces without PowerShell 7 installed: put a Core-only
    `Microsoft.PowerShell.Utility` module first in `PSModulePath`. Its manifest must declare every
    Utility cmdlet, as PowerShell 7's does; one declaring only `Get-FileHash` does not reproduce it.
    The field-snapshot and session-driver tests do this.
- **`reg import` and line breaks.** `reg export` writes a `REG_SZ` value holding a line break as
  `\r\r\n`, and `reg import` cannot restore it. `field_snapshot.py` reads exports strictly and refuses
  to prune after a failed import (R1-011).

## 17. GitHub's Windows runner (CI, 2026-10-28, Claude)

- **The runner decodes text as cp1252; this machine decodes UTF-8.**
  - The runner: GitHub's `windows-2022` image (20261022.344.1, runner 2.338.0, CPython 3.12.10 from
    `setup-python`). Its ANSI code page is 1252, so Python decodes a text-mode pipe without an
    `encoding` as cp1252.
  - This machine's ANSI code page is 65001 (Windows' UTF-8 option). `locale.getpreferredencoding(False)`
    gives `cp65001` even with `PYTHONUTF8=0`, so no local run sees the difference.
- **`nlctl` and the C++ test hosts write UTF-8 whatever the code page.** They `fwrite` UTF-8 JSON and
  read the environment with `GetEnvironmentVariableW` (`loader/core/src/activate.cpp`).
- **The first CI run (40779899329) failed `nl_activation_integration`** with "CLI and startup layer
  plans differ".
  - The layer list holds `用户.conf`, which cp1252 turns into `ç”¨æˆ·.conf`.
  - Start-up's `status.json` had the name right.
  - Tests now pass `encoding='utf-8'` when they read `nlctl` or a host, and open files with an explicit
    encoding.
  - A Python child (`package_runtime.py`) writes in the same locale encoding its parent reads, so
    those calls stay as they are.
- **Reproduced here** with a throwaway wrapper (not committed). It makes text-mode `subprocess` pipes,
  and files opened without an encoding, use cp1252: it patches `subprocess.Popen.__init__`, `io.open`
  and `io.text_encoding`, then runs the test with `runpy.run_path`.
  - The old test failed at the same line; the fixed one passed all 17 cases.
  - CTest starts the test with `python -I`, so a `sitecustomize` on `PYTHONPATH` would not load.
- **The runner has no Vulkan loader** (`System32\vulkan-1.dll`). The activation test skips its
  "optional Vulkan preload uses System32" case there.
- **Node 24 actions.**
  - GitHub runs Node 20 actions on Node 24 and warns about each one.
  - The first majors that target Node 24: `checkout` v5, `setup-python` v6, `upload-artifact` v6 and
    `download-artifact` v7. Their release notes change nothing else this workflow uses, and they
    need runner 2.327.1 or later.
  - Later majors existed on 2026-10-28: checkout v7, setup-python v7, upload-artifact v7, and
    download-artifact v8, which makes a digest mismatch an error.
- **Timings of the first run.** `tools\test.ps1 -Config Release` took 4 min 14 s: CTest 21 s for 16
  tests, the Python suites about 40 s.

## 18. The first field test of the release bundle (2026-10-28, Claude)

The setup: the field install with the CI-built loader 0.2.0 and the subscribed item 3829070317. The
player's Steam launch options were `-multirun -insecure -tickrate 120`. Evidence: the loader's own
logs and `status.json`, and Remix's log. The user's console log was not read.

- **Every start crashed to the desktop.** There were three starts, 22:53-22:55 UTC. The last one
  crashed 9 s in.
  - The loader did its part. It deployed the item (442 changes, 7.5 s on the first start), activated
    it, applied 7 of 7 patch sets and the shader override, and hooked 15 modules.
  - Remix's log (`rtx-remix/logs/remix-dxvk.log`) ends with these lines:
    - a 640x480 device with `Windowed: false`;
    - `Setting display mode: 640x480@0`;
    - `FSR FG: onDestroy called`;
    - `[D3D9WindowProc] Swapchain handle is invalid, some of its values may not be correct.`
  - Remix's crash handler (Sentry) wrote `rtx-remix/logs/.sentry-native/last_crash` 1 ms later.
    Windows logged no Application Error.
- **Why 640x480 fullscreen.** On the PoC, `DXLevel_V1` 95 was stored (what non-RTX sessions write),
  and the video key (section 11) held 960x540, windowed, borderless. A start with `-dxlevel 90` ignored
  that size and window mode, and made a 640x480 exclusive-fullscreen device.
- **Reproduced on the PoC** with the field's launch options and `DXLevel_V1` 95 (a throwaway script in
  the worktree's `out/fullscreen`):
  - Without window options: the same log lines, then exit `0xC0000005` after 13.6 s.
  - With `-windowed -noborder -w 3840 -h 2160` added by hand: a windowed 3840x2160 device, still running
    after 45 s, no crash record.
  - With loader 0.2.1 and no window options: the loader added those options itself, with the same
    result ([ADR 0018](decisions/0018-rtx-sessions-in-a-borderless-window.md)).
  - Windowed sessions log one "Swapchain handle is invalid" warning too, and do not crash.
- **The window options GMod x64 reads**, from strings in the PoC's `engine.dll` and `launcher.dll`:
  `-windowed -window -sw -startwindowed -full -fullscreen -noborder -w -width -h -height`.
- **`gmod.exe` is per-monitor DPI aware.** Its manifest has `<dpiAware>true/PM</dpiAware>`.
- **This machine's display:** the RTX 5090 drives the primary display at 3840x2160 and 240 Hz. The
  CPU's AMD graphics are present too.
- **GMod extracts Workshop items separately for each install.**
  - Legacy items are extracted to `garrysmod/cache/workshop/<id>.gma`, beside `<n>.cache` files.
  - The PoC had never mounted the user's subscriptions, because automated sessions pass `-noworkshop`.
    Three starts with the field's options extracted 163 files (4.4 GB). Each start continued with new
    items. The one item a stopped session had been writing was extracted again.
  - Item 3829070317 is never extracted: it is a plain `.gma`.
  - The field install's cache was last written on 2026-10-24.

## 19. Field parity with the classic install (R2, 2026-10-29, Claude with four research agents)

The measure: the pool rooms (`gm_poolrooms`, Workshop 2849511871, mounted from client Lua by
`poc_session.py --mount-workshop ... --change-map gm_poolrooms`) at a pinned camera. The camera is at
the map's spawn point `1336 -456 -82` (eye z -18), pitch 5, yaw 342.5, with the HUD hidden. The block
measure is that of section 12. Evidence is in the worktree's `out/round2`.

**The runtime fork's config layers** (`dxvk-remix-gmod`, branch `gmod-1.6.1`; corrects sections 2 and 10):

- **For `rtx.*` options, the first entry of a `DXVK_RTX_CONFIG_FILE` or `DXVK_CONFIG_FILE` list is the
  strongest.**
  - Earlier entries are named "00_...", "01_..." and the last gets the plain name. Layers of one
    priority sort alphabetically, and the first wins (`rtx_option_layer.cpp:49-61`,
    `rtx_option_constants.h:159-164`).
  - `d3d9.*` and `dxvk.*` keys come from one merged config in which the last file wins.
- **Priorities:**
  - `dxvk.conf` layers 1, per-game built-ins 2 (only `hl2.exe` has an entry), `rtx.conf` layers 3,
    per-option environment variables 5;
  - `user.conf` 0xFFFFFFFE, presets 0xFFFFFFFF.
  - `user.conf` is always `./user.conf`; there is no override.
  - `%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<hash>.conf` holds only first-use and crash-report
    flags.
- **Save targets:**
  - "Remix Config (rtx.conf): Save" writes the last `DXVK_RTX_CONFIG_FILE` entry, every value of that
    layer, and only `rtx.` keys.
  - "User Settings (user.conf): Save" writes `./user.conf`.
  - "Migrate N Developer Settings" moves API-set values from the user layer into the `rtx.conf` layer,
    in memory only.
  - The RTX fixes write developer options through the API into the user layer: per-map configs,
    `ignoreGame*Lights`, texture categories. So `user.conf` shows unsaved changes by itself.
- **Presets:**
  - A graphics preset other than Custom (4) re-applies its values above `user.conf` at every device
    creation. Auto (5) picks Ultra on Blackwell.
  - DLSS preset On forces the upscaler, DLSS quality Auto and Reflex. `rtx.dlssPreset 2` keeps your
    choices.
  - `rtx.raytraceModePreset` Auto rewrites the three ray-trace modes.
- **Limits and switches:**
  - These variables are read into a 260-character buffer; a longer value counts as empty, and the
    runtime falls back to the bare root conf.
  - `DXVK_FORCE_WINDOWED=1` makes every device creation and Reset windowed (`d3d9_swapchain.cpp:1195`).
- **Texture-hash lists** (`rtx.*Textures`) combine across layers as sets: a layer adds its hashes and
  removes its `-0x...` ones. The classic install's effective lists hold 4,087 decal, 1,576 particle,
  549 player-model and 208 ignore hashes, removals included.
- **The fullscreen crash of section 18:**
  - `D3D9WindowProc` (`d3d9_swapchain.cpp:239-309`) keeps using a swap chain while the device
    destructor runs. The "Swapchain handle is invalid" liveness test is itself a use after free.
  - The hook is removed only at the end of the swap chain's destructor.

**What the field ran differently** (before this round):

- **Remix settings.** The package shipped the classic `rtx.conf` and `dxvk.conf`, but not the classic
  `user.conf`: 91 settings. That file holds the 4-hash `playerModelTextures`, the fog
  (`transmittanceMeasurementDistanceMeters` 420), atmosphere, NRC (`integrateIndirectMode` 2) and
  preset 4.
- **The user's test saves** in the field's root `rtx.conf` (16:58) set fog to 10 m, atmosphere off and
  `playerModel.enableInPrimarySpace` False.
- **The RTX add-ons' settings.**
  - GMod x64 keeps Lua convars in `garrysmod/cfg/client.vdf` and `server.vdf`, not `config.cfg`. The
    fixes also keep `r_forcehwskin` as a cookie in `cl.db`, restored at every map load. It is forced
    to 1 when HL2 RTX content is mounted.
  - The classic `client.vdf` (the fixes' own `.vdf`, which RTXLauncher copied, plus the user's tuning)
    against the field:

    | Setting | Classic | Field |
    |---|---|---|
    | `rtx_pseudoplayer`, `rtx_pseudoweapon` | 0 | 1 |
    | `rtx_api_map_lights_autospawn` | 0 | 1 |
    | `rtx_lightupdater` | 1 | 0 |
    | `rtx_flashlight_brightness` | 5 | 1000 |
    | `rtx_water_custom` | 1 | 0 |
    | `rtx_pseudoplayer_unique_hashes` (server) | 0 | 1 |

  - The field also had the cookie `r_forcehwskin=1`.
- **The pseudo player and Model Hotloader.**
  - With `rtx_pseudoplayer 1` the fixes draw a client-side copy of the local player. Model Hotloader
    adopts it as a player copy (`player_copies.lua:52-74`) and draws it with the character's own
    textures, so nothing is tagged and the MMD body appears in first person.
  - Model Hotloader also cuts the head out of the first-person view with a user clip plane, which the
    path tracer ignores. The field's Model Hotloader 2.3.0 has no RTX handling (no `mhrtx_*`
    variables); the classic install's 2.3.1 has.
- **AMAP's RTX flashlight** (`mmd_vmd_npc`, the Character Motion Importer) calls `RemixLight.CreateSphere`
  directly; ProjectedTexture and `rtx_lightupdater` do not matter to it. A sphere light's output grows
  with radius squared, and the field's `mmd_vmd_npc_flashlight_rtx_radius` was 1 (classic 30, AMAP
  default 20).
  - With the classic values the light is strong: the pinned frame went from mean RGB 80/82/76 to
    117/122/119.
- **The classic install's fixes Lua** has three local fixes the fork lacked, committed to the fork as
  `fc478c0`:
  - `cl_material_pipeline.lua` reads model materials from the `.mdl` header; the old walk froze maps
    with thousands of props;
  - the skybox boundary renderer builds its meshes only when switched on; before, it took 3 ms of each
    frame for a minute after every map load;
  - `func_reflective_glass` is removed again after clean-ups and saves.
- **Remix mods:** the classic install loads 29, the field 5. Among them are `Poolday` (337 MB, a
  "Release Ready" replacement mod for the pool rooms), `Water`, `Emissives`, `gmodrtx_poolday_fix`,
  `ai_pbr` and the user's character and map mods.

**Measurements** (block measure; repeat captures of the classic install: 0.60):

| Field state | block_diff | Mean RGB (classic 72.7/93.6/96.6) |
|---|---|---|
| Package with classic `rtx.conf` only, first-run add-on defaults applied (test 1) | 14.47 | 79.0/82.2/76.1 |
| One merged defaults layer, effective Remix values equal to the classic install's (test 2) | 14.79 | 80.0/81.8/76.1 |
| Texture lists merged as sets, every effective list equal (test 4) | 14.78 | 79.9/81.8/76.1 |
| Plus the classic `Poolday`, `Water`, `Emissives`, `gmodrtx_poolday_fix` and `SubUSDs` mods | 14.90 | 79.8/81.6/75.8 |

- The remaining difference is a uniform warm cast against the classic install's blue-grey. The
  effective Remix settings, the pool rooms mod and add-on, the water and the per-map configs are now
  identical; so are the hash lists.
- Not yet compared: the classic install's other local add-ons and their data, among them Advanced
  Material Editor (29 persistent rules, 32 RTX profiles, its standalone bridge DLL), the other 23
  Remix mods, and the older game build.
- The first-person view is correct: no pseudo-player body. Remix's menu opens through
  `RemixConfig.SetUIState(2)`, and "Remix API: ready" is reported under the loader.

**GMod's shared video settings across modes** (PoC, `-nonativeloader` for vanilla, `--no-window`):

- A normal start with `DXLevel_V1` 90 stored, as RTX leaves it, used the stored 2560x1440 windowed,
  kept it, and wrote 95.
- An RTX start with 95 stored opened at the loader's 3840x2160, left the stored size and window flags
  as they were, and wrote 90.
- So neither mode overwrites the other's video settings; command-line `-w`/`-h`/`-windowed` are not
  saved.

**The user's add-ons and the machine** (static audit of the field's local add-ons, about 700
Workshop GMAs and the binaries):

- **Add-ons:**
  - FPS Boost (2982286549) sets `r_threaded_particles 1` and the queued-rendering variables at every
    client start, after the session cfg.
  - Draconic Base (1847505933) turns motion blur on every second.
  - Draconic Base and ECAfEDAP draw stock post-processing; Zippy's Library draws outlines from screen
    copies.
- **Vulkan layers registered here** load into Remix's instance: OBS's `VK_LAYER_OBS_HOOK` and the AMD
  iGPU's `VK_LAYER_AMD_switchable_graphics` are always on. The Steam overlay and Fossilize layers turn
  on only when their `ENABLE_*` variables are set.
- **Other files:**
  - No `d3d11.dll` or `dxgi.dll` is in `bin\win64`; the Chromium leftovers there (`vk_swiftshader`,
    `dxcompiler.dll`, `dxil.dll`) are inert.
  - `gmcl_vrmod_win64.dll` in `lua\bin` links D3D11 and OpenVR, but no VRMod Lua is installed.
- **Zippy's Library** (Workshop 3146473253) is required by the user's local `enhanced_blood`. GMod's
  Workshop rules forbid reuploading another author's item "whatever the reupload reason is", so it is
  mounted from the user's own subscription in test sessions and never packaged.

**Bundling the requested add-ons** (inventory):

- **Model Hotloader:** its modules statically import `mmdhl_runtime_win64.dll`, which Windows finds
  in `bin\win64` next to the exe. The package format cannot place files there.
- **Advanced Material Editor, the bodygroup tool, procedural bodygroup destruction and the Character
  Motion Importer** are Lua add-ons, with an optional bridge DLL for the editor. They fit the package
  areas.
  - In the field, `mmd_hotloader`, `mmd_vmd_npc` and `advanced_bodygroup_tool` are hand-placed folders
    of the same names; the last is a link to the dev folder. The loader refuses to replace a folder it
    does not own, and that refusal fails the package.
- **The debug module** (`gmcl_rtxdebug_win64.dll`) and its one-file add-on `rtx_debug` now ship with
  the fixes.
- **modern_house_rtx:** 8 Lua files plus 490 DDS textures, 3.32 GB. The textures are AI-upscaled from
  the textures of someone else's map (Workshop 3495468649).

## 20. Third field round: the pseudo player, the classic Remix mods, Modern House (2026-10-29, Claude)

Measured in the field install with `poc_session.py --allow-steam-managed`. The evidence is in the
worktree's `out\round3\`.

**The player's own model in first person came back after round 2.**

- The classic install's `cfg\server.vdf` holds stale copies of three settings, and its `client.vdf`
  has the values the game uses:

  | Setting | `server.vdf` | `client.vdf` |
  |---|---|---|
  | `rtx_pseudoplayer` | `1` | `0` |
  | `rtx_pseudoweapon` | `1` | `0` |
  | `rtx_disablevertexlighting` | `1` | `0` |

- The fixes create these on the client only (`cl_rtx_misc.lua`, `CreateClientConVar`), and the
  field's `server.vdf` has no such entries. In single-player one variable of each name serves both
  realms.
- `classic_defaults.lua` version 2 had them in its server table. `nativeloader_rtx_defaults_server`,
  run after the client command, set them to `1`, and the game saved that in `client.vdf`. The pseudo
  player then drew the player's head in front of the camera.
- After the fix (version 3, the server table without names the client table has) the console prints
  `"rtx_pseudoplayer" = "0" ( def. "1" )`. A first-person start in the pool rooms shows no body.
  Version 3's first run changed 0 of 187 client and 0 of 17 server settings: they were classic already.

**Emissives** (`rtx-remix\mods\Emissives`, from the classic install; 10 files, 3.8 MB):

- It replaces one material, `mat_B19B22D6FDE30598`: albedo, an emissive mask, intensity 18, and
  metal and roughness maps.
- That is `models/props_interiors/florescentlight01a_on`, HL2's fluorescent tube light:
  - the fixes' category manager logs it with that hash in gm_construct;
  - `RemixMaterial.GetTextureHash` returns the same number in game;
  - the classic `rtx.conf` also lists it in `rtx.legacyEmissiveTextures`.
- gm_construct has 16 of these lights as static props, `models/props_interiors/lights_florescent01a.mdl`
  skin 1 (NikNaks `GetStaticProps`). 15 form a grid in the basement at z -179, x -1424 to -2704,
  y -1344 to -1824; one is at (-5460, -3164, 381).
- With the camera pinned at (-1584, -1584, -235), pitch -20, yaw 180:

  | | Mean RGB |
  |---|---|
  | With the mod | 49.5 / 45.8 / 38.6 |
  | Without it | 21.5 / 20.6 / 18.5 |

  The block measure between the two is 24.4, against 0.8 between two runs with it. Without the mod
  the tubes still glow (legacy emissive) but light little.
- Remix warns that its textures have no mip-maps. Four files are not referenced: three `.bmp` sources
  and `mirror_diffuse.dds`.

**Water** (`rtx-remix\mods\Water`, 38 files, 33 MB):

- It replaces 29 materials. All 29 textures are in the classic `rtx.ignoreTextures`, as well as in
  `animatedWaterTextures` and `decalTextures`. Ignored draws never reach the renderer, so the
  replacements never apply.
- Its `replacements.usda` references `./SubUSDs/AperturePBR_Translucent.usda`, which the folder lacks.
- `33FAB345028AFF4A`, one of its textures, belongs to the super gravity gun's sheet; no material uses it.
- **A/B in the pool rooms** at the round-2 pinned camera:

  | Compared with each baseline run | Block measure |
  |---|---|
  | Without Water | 0.88, 0.41 |
  | Without Emissives | 0.64, 0.89 |
  | The two baseline runs with each other | 0.90 |

  The largest 16-pixel block differences are 6-9 in every pair.
- **`SubUSDs`** at the mods root has no `mod.usda`; Remix does not load it.

**A test with props is misleading.** Fluorescent lights spawned as `ClientsideModel` with the `_on`
material rendered as solid red slabs, with the mod and without it. Test with the map's own props.

**gm_construct starts the player at different spawn points.** Three starts put the eye at (763, -801),
(643, -657) and (900, 578). Compare with a pinned camera.

**Modern House RTX through the Workshop** ([ADR 0023](decisions/0023-content-packages-and-modern-house-item.md)):

- **The build.** `package_content.py` built the package from the fork worktree in 9 s, with hard links
  in the work folder:
  - 500 files, 3,322,961,921 bytes; the archive is 3,323,148,599 bytes;
  - version `0.0.0-dev.202610280457+caaa4535`.
- **`nlctl` and hard links.** `nlctl manifest` refuses a package folder whose files are hard links ("is a
  link or reparse point; packages may not contain them"). The linked build is checked as the archive.
- **The upload.** `gmpublish create -addon <gma> -icon <512x512 baseline JPEG>` uploaded it in 50 s (shown
  as "3.0 GB"): item **3829275998**, "currently marked as hidden".
- **The subscription.** GMod's `steam_api64.dll` has the flat Steamworks API (`SteamAPI_InitSafe`,
  `SteamAPI_SteamUGC_v021`, `SteamAPI_ISteamUGC_SubscribeItem`, `..._DownloadItem`,
  `..._GetItemDownloadInfo`, `..._GetItemInstallInfo`). Run as app 4000 from a game root holding
  `steam_appid.txt`, it subscribed the owner to the hidden item.
  - Steam downloaded 2,414 MB, the transfer compressed, in 12 s.
  - It installed `content\4000\3829275998\modern-house-rtx.gma` byte-identical (the same SHA-256)
    and listed it in `appworkshop_4000.acf`.
- **The next start.** With the item allowlisted, the loader deployed it from the Workshop: 492 mod
  files and the add-on, `source: workshop`.
- **The map.** On `modern_house` (the map mounted with `--mount-workshop 3495468649`, then `--change-map`):
  - the add-on printed `[MHRTX] applied 9 Remix settings; sky: physical atmosphere` and `created: 341
    lights in the house, 341 on, the atmosphere's sun, 8 mirrors`, with no Lua errors;
  - from the launch to the screenshots took 2.1 minutes.
- **Against the gallery.** At the remaster's terrace camera (732, 154, 536; 6, 90, 0), the field matches
  its gallery shot from the classic install, mean RGB 139.4 / 122.3 / 102.6 against 139.8 / 122.2 / 103.0.
  The gallery shot has a wider field of view.
- **A harmless warning.** GMod printed `Couldn't write cache/map_pack.bsp to mount embedded content!`,
  and the map's textures were right anyway.

**Field changes this round:**

- The user's `enhanced_blood` moved to `garrysmod\addons_d` (their folder of disabled add-ons). With it
  went the need for Zippy's Library.
- The test copies of Water, SubUSDs and Emissives moved out of `rtx-remix\mods` into
  `out\round3\field-removed-mods`; the package now deploys Emissives.
- The round-2 copies of Poolday, `gmodrtx_poolday_fix` and `Poolday_mirror_fix` stay.

## 21. Fourth field round: the bundled add-ons and module dependencies (2026-10-29, Claude)

**Model Hotloader's natives** ([ADR 0024](decisions/0024-bundled-addons-and-module-dependencies.md)):

- **The import.** `gmcl_mmdhl_win64.dll` and `gmsv_mmdhl_win64.dll` statically import
  `mmdhl_runtime_win64.dll` (PE import tables). The runtime imports only system DLLs and loads
  `lib_coacd.dll` itself.
- **Who loads modules.** GMod's `lua_shared.dll` imports `LoadLibraryExA` and `LoadLibraryExW`;
  `client.dll` and `server.dll` import `LoadLibraryA` and `LoadLibraryExW`. Binary modules load without
  `LOAD_WITH_ALTERED_SEARCH_PATH`, so Windows looks for the runtime next to `gmod.exe`. Model Hotloader's
  installer copies it into `bin\win64` for that reason; its import worker `mmdhl_worker.exe` finds the
  copy in `lua\bin`, beside itself.
- **The release layout.** Its release script (`scripts/package-dropin.py`) stages two drop-in trees:
  - `-win64-vulkan` carries a patched DXVK `d3d9.dll`;
  - `-win64-opengl-remix` leaves Direct3D 9 to Remix.

  Both hold `lua\bin\{gmcl,gmsv}_mmdhl_win64.dll`, `mmdhl_runtime_win64.dll`, `lib_coacd.dll`,
  `mmdhl_worker.exe` and `mmdhl-native-release.json` (the version file the add-on checks), plus
  `shaders\fxc\mmdhl_{ps20b,vs20}.vcs` and `bin\win64\mmdhl_runtime_win64.dll`. The add-on's own
  `shaders/fxc` has the same two shaders, byte for byte.
- **Releases.** The newest local release is 2.3.0 (build `1df48dac`, 2026-10-12). The repository's
  `main` is at "Version 2.3.1" (2026-10-26) with staged changes.
- **What the classic install runs.** Its `mmd_hotloader` folder matches the main repository's working
  tree. Its natives are byte-identical to the build in the worktree `wt-full-textures-props`
  (`gmcl_mmdhl_win64.dll` 2,843,648 bytes, 2026-10-26 16:21).

**The user's own Workshop items for the five add-ons**, all subscribed:

| Item | Add-on | Note |
|---|---|---|
| 3810025467 | Model Hotloader | 2.3.0 |
| 3718373357 | MMD VMD NPC Animation (the motion importer) | |
| 3789611737 | Procedural Bodygroup Destruction | 0.19.15 |
| 3791888631 | Advanced Bodygroup Tool | |
| 3793132326 | Advanced Material Editor | 57 files: its Lua and `materials/advmat/shift.png` |

**The parts**, built with `package_content.py`, add-ons filtered as gmad publishes them:

| Part | Files | Bytes | Left out by the filter | Compared with |
|---|---|---|---|---|
| Model Hotloader (add-on and six natives) | 110 | 86,924,394 | | |
| Advanced Material Editor (and its bridge) | 59 | 2,748,327 | 1,846 | 266 MB unfiltered: 14 character textures of 16 MB each committed under `materials/models/sheepylord/hsin`, which the published add-on leaves out (`--ignore materials/models/*`) |
| Advanced Bodygroup Tool | 6 | 212,124 | 37 | the Workshop's 212,438-byte GMA |
| Procedural Bodygroup Destruction | 16 | 753,816 | 16,714 | the local 0.20.0 GMA, 754,307 bytes |
| Character Motion Importer | 17 | 19,315,255 | | the Workshop's 19,334,061 bytes |

The combined RTX package with the nine parts is 1,541,278,091 bytes.

**Measured with loader 0.3.0:**

- **PoC, RTX:** deployed (234 changes). When the game loaded `gmsv_mmdhl_win64.dll`, the bootstrap first
  loaded `mmdhl_runtime_win64.dll` from `lua\bin` (`session.json`). Model Hotloader's native module is
  live on the server and the client (`mmdhl.native` set); no Lua errors.
- **PoC, without RTX:** the package's 16 add-on folders are hidden (`mmdhl` is nil and
  `lua/autorun/mmdhl.lua` is not in the `GAME` path). `require("mmdhl")` succeeds, with the runtime
  loaded first for `gmcl_mmdhl_win64.dll`. A subscribed Workshop copy can therefore use the bundled
  natives in a normal session.
- **Field, RTX:** deployed (407 changes) and active, no Lua errors, the module live on both sides. The
  first-person view in the pool rooms shows no body.
- **Field, moved out first** (the loader never replaces files it did not place):
  - `mmd_hotloader`, `mmd_vmd_npc` and the `advanced_bodygroup_tool` symlink went to `addons_d`;
  - the six Model Hotloader 2.3.0 files in `lua\bin` went to the round-4 backup. Three of them were hard
    links into a Model Hotloader validation folder (`!Gmodl_MMD_Hot_Loader\.claude\worktrees\
    mmd-importer-performance-87a36d\validation\multiplayer\client*`);
  - so did `bin\win64\mmdhl_runtime_win64.dll` (10,710,016 bytes, 2.3.0).

**The visibility-tuned fixes module.**
- Another session rebuilt `gmcl_RTXFixesBinary_win64.dll` (1,444,352 bytes, SHA-256 `189765c0...`,
  2026-10-28 21:19) in the fork worktree `rtx-remix-map-enhancement-bda9ac`. Its branch commit `e4d548d`
  is "Backrooms RTX: keep the room next door in the ray-traced scene" (`source/culling_patches.cpp`,
  +100 lines).
- It installed the module into the classic install's `lua\bin`, where the fixes part takes its modules,
  so the test package carries it byte for byte.
- The field had the earlier `485667b7...`.

**Hooks.** The add-on repositories (the bodygroup tool has none), the fixes fork and Model Hotloader's repository had no git
hooks. Their default branch is `main`, except the fork's checked-out `sheepylord/rtx-water-poolrooms`.

## 22. What Steam does when the user subscribes and unsubscribes (2026-10-29, Claude)

The user found that unsubscribing from the RTX item left RTX Remix running. To tell an unsubscribe
from a download or an update without the Steam API, a hidden test item (3829311605, a 100-byte
add-on package) was subscribed and unsubscribed. The scripts called GMod's own `steam_api64.dll` as
app 4000 (`ISteamUGC::SubscribeItem`, `UnsubscribeItem`, `GetItemState`, `DownloadItem`), polling
`steamapps\workshop\appworkshop_4000.acf` and the item folder every half second.

**Steam's record** has two sections under `AppWorkshop`:
- `WorkshopItemsInstalled`: the items on disk (`size`, `timeupdated`, `manifest`);
- `WorkshopItemDetails`: the items Steam tracks for this account (`manifest`, `timeupdated`,
  `timetouched`, `subscribedby` (an account id) and `latest_*`).

**Subscribe:**
- At 0.6 s the item state was `subscribed,needs-update`, with nothing on disk yet.
- At about 1.1 s the item was in `WorkshopItemDetails`, with `subscribedby`.
- At 8.5 s it was in `WorkshopItemsInstalled`, and its folder held the `.gma`.

So while a first download runs, the item is in `WorkshopItemDetails` with no folder.

**Unsubscribe:**
- The item state lost `subscribed` at once (`installed` only).
- The acf and the folder stayed as they were for the 90 s watched, both while the API session ran and
  after it ended.
- Some minutes later the item was gone from `WorkshopItemDetails`. It was still in
  `WorkshopItemsInstalled`, and the folder was still there.

**The next launch from Steam** (`steam://rungameid/4000`), timed from the launch request:
- At 1.2 s Steam had removed the item from `WorkshopItemsInstalled` and deleted its folder.
- At 2.8 s `gmod.exe` was running. The bootstrap therefore sees the item gone in its first start.
- A second run launched about 20 s after the unsubscribe, with the item still in both sections. At
  1.2 s Steam had removed it from both and deleted the folder, and `gmod.exe` ran at 2.0 s. The
  launch's clean-up does not wait for the later update of `WorkshopItemDetails`.

**Telling the cases apart:**
- A first download: the item is in `WorkshopItemDetails`, with no folder yet.
- An update: the item stays in `WorkshopItemsInstalled`, even while its folder is replaced.
- An unsubscribe, once Steam has cleaned up: the item is in neither section, and its folder is gone.

This is the rule [ADR 0025](decisions/0025-unsubscribe-removes-the-package.md) uses. A game started
without Steam's launch (for example `gmod.exe` run directly) finds the folder still there and keeps the
package until a launch from Steam has removed it.

**End to end with loader 0.3.1 on the PoC** (evidence in `out\round5\e2e`):
1. **Subscribed.** The item was installed in 1.7 s and allowlisted alone. The PoC start deployed it
   (generation 3), and the add-on's autorun printed on the server and the client.
2. **Unsubscribed, then launched from Steam at once.** Steam cleaned up as above. The next PoC start
   removed the package:
   - generation 4, with the note "its Workshop item was unsubscribed, so its files are deleted";
   - the skipped reason "not subscribed";
   - the add-on folder was gone, and the add-on did not run;
   - `native-loader` held only `config.json`, the journal, the lock, the install receipt and the logs,
     with no `packages` or `backup` folder;
   - the journal had no previous generation.
3. **The config put back.** The next PoC start deployed the 1.5 GB RTX package again in 10.0 s (669
   changes), RTX active, with no Lua errors.

`verify_install.py` afterwards: all 2,877 depot files unchanged.

**Seen on the way:** Model Hotloader prints "Missing bin/win64/mmdhl_runtime_win64.dll" and "The
loaded runtime DLL is not the file that was checked", on the server and the client
(`mmdhl.install.error.*`). Its runtime and both modules are loaded: the bootstrap loads the runtime
from `garrysmod\lua\bin` (ADR 0024), and the add-on says it "uses it anyway". The round-4 sessions,
PoC and field, show the same lines. Fixed in section 23.

## 23. Model Hotloader's install check and the runtime in lua/bin (2026-10-29, Claude)

**Where the warnings come from.** Model Hotloader's repository is
`H:\BACKUP_20260815\Modding\ipg\!GMHLVK\Gmod-Model-Hotloader-with-Vulkan` (`main` at `ecd7c42`
"Version 2.3.1"). Its `addon/lua/mmdhl/installation.lua`:
- **Before loading,** `EvaluateInstallation` reads the runtime where Windows looks for it: `bin/win64`
  through `BASE_PATH` on a client or listen server, beside `srcds_win64.exe` then `bin/win64` on a
  dedicated server, `lua/bin` on Linux. A missing file is a warning, printed before `require`.
- **After loading,** `identitiesMatch` compares the runtime path the native module reports
  (`GetInstallationInfo`) with that file. A difference is the "loaded runtime DLL is not the file that
  was checked" warning.

With the loader, the runtime the module reports is `<game>\garrysmod\lua\bin\mmdhl_runtime_win64.dll`
(LoadLibraryExW of that absolute path, `loader/proxy/modules.cpp` `load_first`). So both warnings
fire, although everything works.

**What the RTX package ships.** The classic install's `garrysmod\addons\mmd_hotloader` equals the
repository's `main` working tree, byte for byte, except `lua/mmdhl/native_policy.lua`:
- The working tree holds work staged since 2026-10-26: 41 files, secondary gravity and buoyancy,
  server settings. It is uncommitted; the session that wrote it is offline.
- The shipped `native_policy.lua` is the one the native build writes. It records release 2.3.1 (build
  `ecd7c426c0b5-20261026T225907Z`, runtime SHA-256 `351a7068...`), which is what the classic install's
  `lua\bin` holds. The committed one stops at 2.3.0.

**The fix** (Model Hotloader commit `bed4582`, made on the branch `claude/runtime-in-lua-bin`;
[ADR 0026](decisions/0026-addon-file-from-its-repository.md)):
- **Before loading:** on a Windows client or listen server with no runtime in `bin/win64` and a copy
  in `lua/bin`, that copy is the runtime checked. The missing file waits in `files.runtime.missingAt`.
- **After loading:** `reportMissingRuntime` drops it when the loaded runtime is that copy. Otherwise
  (nothing loaded, loaded from elsewhere, a module too old to say) the missing file is reported as
  before, so a player without the loader still reads why the module did not load.
- **Tests:** its offline suite (51 scripts, lupa 2.8) and the i18n check pass on the branch. On `main`'s
  working tree with the staged work, 55 scripts pass.
- **Landed** (the user: "Push to main"):
  - Model Hotloader's `main` was fast-forwarded from `ecd7c42` to `bed4582` and pushed to GitHub, and
    the branch was deleted.
  - The checkout's staged work is kept, now on top of the fix: the same 41 files and changed lines,
    compared before and after. A backup of the earlier state is in `out\round6\mmdhl-main-backup`.
  - 55 scripts pass there.

**Measured** with the branch-built RTX package on the PoC (loader 0.3.1, RTX active), evidence in
`out\round6\poc`:
- No runtime warning on either realm.
- `mmdhl.native` is set on the server and the client.
- The server's install status lists no issue. The client's lists only `game_unverified`: "This Garry's
  Mod build has not been tested with this native release (engine.dll, client.dll, materialsystem.dll,
  shaderapidx9.dll changed)". That is Model Hotloader's compatibility profile for 2.3.1 against a
  newer GMod build, unrelated to the runtime.

**Git hooks and the publish script.** Git runs a hook with the hooked repository in `GIT_DIR`,
`GIT_INDEX_FILE` and `GIT_WORK_TREE` (githooks(5); for a worktree, `GIT_DIR` is
`.git/worktrees/<name>`). `git -C <path>` and a `cwd` do not override `GIT_DIR`.
- So the round-4 source hooks ran `publish_workshop.py` against the source repository.
- Seen when the fix above was committed in Model Hotloader's worktree: the run refused with this
  repository's `companion/` and `tools/...` listed as untracked. Its log was in
  `Gmod-Model-Hotloader-with-Vulkan\out\workshop\logs`, which was then removed.
- No earlier source-repository commit had run one (no other such log existed).
- The 15 names `git rev-parse --local-env-vars` lists on git 2.56.0 are the ones the script now
  removes.

## 24. The seventh field round: Draconic's motion blur, GMod's Workshop mount, subscribed content (2026-10-29, Claude)

**"Disabling motion blur will break addons' effects..." every second.**
- It is not GMod's: no game DLL or depot Lua has the line. A scan of the Lua inside all 677 installed
  `.gma` archives found it in Draconic Base (1847505933), `lua/draconic/cl/library.lua:242-248`.
- Once a second (`rt > MBlurCheck`, then `+1`), if `GetConVar("mat_motion_blur_enabled"):GetInt() < 1`,
  it prints the line and runs `LocalPlayer():ConCommand("mat_motion_blur_enabled 1")` and
  `ConCommand("mat_motion_blur_strength 0")`. It cites garrysmod-requests issue 2110.
- The companion's guard pins `mat_motion_blur_enabled` at 0 in RTX sessions (ADR 0022) and drops that
  command, so the check failed every second. GMod caches `GetConVar` objects per name
  (`lua/includes/util.lua:574`), so the guard recognizes the convar by identity.

**GMod's Workshop mount at start**, measured at the main menu with no map requested (the PoC, 755
subscriptions):
- 4.0 s: `Mounted 0 of 755 workshop addons!`, before Steam has listed the subscriptions.
- 5.0 s: `Addons have changes - remounting`, then for each native-loader package
  `Couldn't mount addon file '<path>' from '<title>' (<id>)`.
- 7.0 s: `Mounted 752 of 755 workshop addons!`.
- A map on the command line (`+map`) in a session with Workshop add-ons waits on that fetch: the
  window shows "Fetching Subscriptions... 0 of 755" and "Waiting for Steam Workshop to finish...", and
  goes Not Responding. One such run exited -1 after 21 s with an empty `console.log`. The user had seen
  agents do this nine times. `poc_session.py` now starts such runs at the menu.

**Why GMod's addon list shows the packages red.**
- `html/js/menu/control.Addons.js:488` adds the class `invalid` (`html/css/Workshop.css:484`,
  `#d22`) when the item from `engine.GetAddons()` has an `invalid_reason`. GMod sets that when it cannot
  mount the archive, and a native-loader package cannot be mounted: its files are under `native/`,
  which GMod's Workshop whitelist does not take.
- The menu state loads a fixed list of files (`lua/menu/menu.lua`, `includes/init_menu.lua`): no
  plugin folder, and this build has no `lua_run_menu` (the binaries hold only `lua_run` and
  `lua_run_cl`). So nothing of ours can run in the menu state without editing depot files or
  injecting code into `lua_shared.dll` from the bootstrap.
- The console line comes from `filesystem_stdio.dll` (format `Couldn't mount addon file '%s' from
  '%s' (%llu)`). It imports `Warning`, `Msg`, `DevMsg`, `DevWarning`, `ConColorMsg` and
  `LoggingSystem_Log` from `tier0.dll`. GMod's x64 `tier0.dll` exports the `LoggingSystem_*` API, but
  not `SpewOutputFunc`, `GetSpewOutputFunc`, `WarningV` or `MsgV`.

**Native-loader packages among the subscriptions** (ADR 0027):
- Reading the index of all 677 installed `.gma` archives (98,793 entries) for `native/manifest.json`
  took 0.29 s in Python, warm. It found three packages, each listing the manifest first: 3829070317 (the
  RTX package), 3829275998 (Modern House RTX) and 3829348717 (Guinaifen RTX).
- What they deploy, by area:

  | Package | `garrysmod/addons` | `rtx-remix/mods` | Elsewhere |
  |---|---|---|---|
  | Guinaifen RTX | 28 `dat`, 2 `json` | 44 `dds`, 2 `usda` | |
  | Modern House RTX | 6 `lua`, 1 `json`, 1 `vtf` | 490 `dds`, 2 `usda` | |
  | RTX package | `lua`, `vtf`, `vmt`, `dat`, `png`, `json` and more | `dds`, `usda`, `bmp`, `mdl`, `txt` | `garrysmod/lua/bin`: 8 `dll`, 1 `exe`, 1 `json`; 191 payload files |
- Guinaifen's manifest: id `guinaifen-rtx`, kinds `lua-addon` and `root-files`, roots
  `garrysmod/addons/mmdhl_guinaifen` and `rtx-remix/mods/pbr_guinaifen`, no `remix` section.

## 25. Translated Remix menus: the runtime fork's i18n (2026-10-29, Claude)

**Where the runtime comes from.**
- The fork's main checkout (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`, branch `gmod-1.6.1` at
  `c6b48ed1`) is in the middle of merging tag `remix-1.6.1` (`MERGE_HEAD` `1e6d66c6`, since
  2026-10-25 03:33; `submodules/rtxdi` unresolved, with 3 modified files in the submodule). 415
  tracked files differ from `HEAD`, 4 are untracked.
- No source file is newer than `_CompRelease_x64\src\d3d9\d3d9.dll` (2026-10-27 11:32:17, SHA-256
  `A8E39D93...`, the runtime of `runtime-b4`): that working tree is its source.
- The translation work is branch `claude/remix-i18n` in the worktree
  `dxvk-remix-gmod\.claude\worktrees\remix-i18n`: one snapshot commit of that working tree (not a
  real merge; submodules are junctions to the main checkout's), then the i18n commit. Its
  `_CompRelease_x64` is configured like the main one (`-Dbuildtype=release -Dbackend=ninja
  -Denable_tracy=false -Ddownload_apics=False -Dremix_with_shim=false`); meson 1.12.1 runs as
  `python -m mesonbuild.mesonmain`, MSVC through `tools\lib\VsDevEnv.psm1`.
- A full build of the snapshot in the fresh worktree took **3.9 min** (32 threads, configure
  included); after a `.po` edit **0.2-0.7 min**.

**The menus' text and fonts.**
- ImGui is vendored **1.88 WIP** (`src/dxvk/imgui`), with stb_truetype 1.26 (reads CFF OpenType).
- The atlas had only ASCII: NVIDIA Sans App Medium/Bold (letters and symbols) with Roboto Mono
  digits merged, 16 px; Bold also 24 px for the large UI mode.
- NVIDIA Sans App 3.000 maps 492 characters: Latin-1 (all but U+00A6, U+00B5), 102 of Latin
  Extended-A, U+0400-045F complete; no arrows or math symbols (→ ≤ ≥ ≈ ∞). French and Russian
  need no other font.
- Fonts with CJK glyphs on this machine under the SIL OFL 1.1 (licence in the name table):
  - SteamVR's `tools\steamvr_environments\game\steamtours\panorama\fonts\notosans{sc,tc,jp,kr}-regular.otf`,
    Noto Sans SC/TC/JP/KR 1.004, static Regular, CFF; KR has all 11,172 hangul syllables;
  - Windows 11's `C:\Windows\Fonts\NotoSansSC-VF.ttf` and `NotoSansJP-VF.ttf`, variable fonts whose
    default instance is weight 100 (no TC, no KR).
- ImGui sizes a font by its line height, (hhea ascender - descender) / unitsPerEm: NVIDIA Sans
  1.26 em, Noto Sans CJK 1.48 em. Merged at the same pixel size, CJK glyphs come out 15% smaller, so
  they are merged at 16 x 1.48 / 1.26 = 18.8 px (same em).
- The menus' text: 2,949 messages, 39,034 English words; 969 are descriptions of options the menus
  bind (of 1,253 options declared).

**Measured on the PoC (RTX 5090, 1600x900 window).**
- `RemixConfig` (the fixes' Lua table) exists only with add-ons mounted: the fixes package deploys
  its Lua as add-ons, and `poc_session.py run` passes `-noaddons` unless `--addons`.
- A language change applies at the next frame: the Remix log has `[i18n] menu language: zh-CN`
  and, one frame later, the rebuilt atlas 40-50 ms after it.
- The font atlas (RGBA8, regular 16 px, bold 16 px and large 24 px fonts, CJK merged with
  `OversampleH = 1`):

  | Language | Atlas | Glyphs |
  |---|---|---|
  | en | 512x512 | 366 |
  | fr | 512x512 | 444 |
  | ru | 512x512 | 543 |
  | ko | 1024x1024 | 2,637 |
  | ja | 1024x1024 | 3,258 |
  | zh-TW | 1024x2048 | 3,927 |
  | zh-CN | 1024x2048 | 3,939 |

  (all 3,293 messages translated; English includes the glyphs of the language names.)
- The runtime part: `runtime-b5.gma`, 190 files and the manifest, 984,550,074 bytes;
  `d3d9.dll` 345,815,040 bytes (SHA-256 `b91b2161...`), 7.1 MB more than runtime-b4's
  (the four CJK subsets are 4.7 MB: SC 1.54 MB with 7,586 characters, TC 1.37 MB / 6,034, JP 1.45 MB /
  7,022, KR 0.34 MB / 3,447). Everything else in the package is runtime-b4's.
- The session that switched through every language (`out\i18n\sessions\t5`) quit normally. Its Remix
  log has the same errors as runtime-b4 sessions of the same evening: `GetShaderModule: Out of range
  of supported shader model` (the classic `dxvk.conf`'s `d3d9.shaderModel = 0`, section 11), the
  Neural Radiance Cache failing to initialise, and 47 common device objects not disposed at exit.
- A process that is not DPI-aware sees the 1600x900 game window as 800x450 at 200 % scaling, and
  `PrintWindow` into a bitmap of that size captures only the top-left quarter;
  `poc_session.py` calls `SetProcessDPIAware()` for this reason.
- Mouse messages posted to the game window reach the menus: the fork forwards them to ImGui from
  the game's window procedure whenever no raw input arrived in the last ~100 ms
  (`fork_hooks::overlayInputForward`).

## 26. ReShade with the Remix runtime (2026-10-29, Claude)

**The test client.** `H:\SteamLibrary\steamapps\common\GarrysMod_ReShade`, made with
`make_vanilla_copy.py` from the field install: 2,877 depot files, 7,279,873,012 bytes, all verified, in
about two minutes. Loader 0.4.0 and 0.5.0, the RTX package from Workshop item 3829070317.

**ReShade 6.8.0**, from reshade.me: `ReShade_Setup_6.8.0.exe` (4,075,064 bytes, SHA-256 `207AEA16...`,
signed "ReShade"). The setup carries a ZIP at its end with `ReShade32.dll`, `ReShade64.dll` (5,255,448
bytes, version 6.8.0.2158), `ReShade32.json`, `ReShade64.json` and the `_XR.json` OpenXR manifests.
`ReShade64.json` is the layer `VK_LAYER_reshade` (library `.\ReShade64.dll`, API 1.3.268,
`disable_environment` `DISABLE_VK_LAYER_reshade_1`). For Direct3D 9 the setup puts the DLL next to the
executable as `d3d9.dll`, with `ReShade.ini`, `ReShadePreset.ini` and `reshade-shaders` beside it; for
Vulkan it copies the files to `C:\ProgramData\ReShade` and registers the manifests under
`HKLM\SOFTWARE\Khronos\Vulkan\ImplicitLayers` (administrator rights). This machine has no such
registration (OBS, the Steam overlay and Fossilize only); its Vulkan loader is 1.4.341.

**What ReShade's source says** (tag `v6.8.0`):
- Base folder (`source/dll_main.cpp:55-73`): `[INSTALL] BasePath` from a `ReShade.ini` beside the
  executable (resolved against the DLL's folder, must exist), else `RESHADE_BASE_PATH_OVERRIDE` (same
  rules), else the executable's folder for a DLL with a non-proxy name and the DLL's folder for
  `d3d*`, `dxgi`, `opengl32`, `dinput*` and `.asi`. `ReShade.ini` and the log (`ReShade.log`, then
  `.log1`... when it is taken) live there.
- A DLL with a non-proxy name loads only where that folder has a `ReShade.ini`, unless
  `RESHADE_DISABLE_LOADING_CHECK` is set (`:129-140`): this keeps the global layer out of other games.
- A second ReShade in a process fails its own load (`DllMain` returns FALSE) when another module
  exports `ReShadeVersion` (`:201-212`).
- Vulkan is reached only through the layer mechanism; every name loads the Direct3D and DXGI hooks
  (for system DLLs). The layer's own name appears only in `vkGetPhysicalDeviceToolPropertiesEXT`
  (`source/vulkan/vulkan_hooks_instance.cpp:286`), so a manifest may name the layer differently.
- Settings paths are resolved against the base folder (`resolve_path`, `source/runtime.cpp`):
  `EffectSearchPaths`, `TextureSearchPaths` (default `.\`), `IntermediateCachePath` (default the
  temporary folder), `PresetPath` (default `.\ReShadePreset.ini`), `StartupPresetPath`,
  `PresetShortcutPaths`, `[SCREENSHOT] SavePath` and `PostSaveCommandWorkingDirectory` (default `.\`),
  `SoundPath`, the `[STYLE]` fonts and `[ADDON] AddonPath` (default: the base folder; the log says
  "Searching for add-ons (*.addon, *.addon64) in" it). ReShade writes the whole file back when it exits.
- The built-in add-ons "Generic Depth" and "Effect Runtime Sync" are left out with
  `[ADDON] DisabledAddons=<name>` (`source/addon_manager.cpp:155-190`).
- ReShade's licence texts of its libraries are compiled in and shown on the overlay's About page
  (`source/runtime_gui.cpp:3147-3236`).

**Compatibility, measured** (gm_construct, the RTX package's add-ons mounted, a marker effect of ours
that paints the bottom-right 48 x 48 pixels magenta):
- RTX on, ReShade for Direct3D 9 in `bin\win64`: the game process lists the runtime's `d3d9.dll` and no
  ReShade; no marker. ReShade's log shows it loaded into GMod's Chromium helper (it loads `d3d9.dll` by
  name), as it does without the loader. Its three files kept their SHA-256 through every RTX session.
- RTX off (`remix.enabled` false): the game binds `bin\win64\d3d9.dll`, the marker shows, 1,137 frames a
  second at 1280 x 720. The helper loads it too (`ReShade.log1`).
- RTX on, ReShade 6.8.0 as a layer (`VK_ADD_LAYER_PATH`, `VK_INSTANCE_LAYERS`,
  `RESHADE_BASE_PATH_OVERRIDE`): ReShade takes the runtime's `vkCreateInstance` and its
  `vkCreateSwapchainKHR` calls (the runtime asks for the immediate and FIFO present modes), compiles the
  effects, and the marker shows in the path-traced frame with DLSS frame generation on (the default:
  `rtx.dlfg.enable = True`, two generated frames) and off.
- The Chromium helper inherits the variables: the Direct3D 9 ReShade in it then logs to the layer's
  folder. `mmdhl_worker.exe` (Model Hotloader) imports no Vulkan, so the layer cannot reach it.

**Frame rate** (`poc_session.py --fps 30`, the camera pinned, `fps_max 0`, `engine_no_focus_sleep 0`,
RTX 5090, frames counted by the engine; DLSS frame generation shows about three times as many):

| When | Case | 1280 x 720 | 3840 x 2160 |
|---|---|---|---|
| 02:25-02:52, another session building the runtime and packing `.gma` files | without ReShade | 138-146 | 86-90 |
| same | ReShade layer, no effect / marker / heavy blur | 75-95 | 31 (overlay open) / 71 (blur) |
| 02:59-03:07, quiet machine | without ReShade | 145.0 | |
| same | ReShade layer, marker | 143.2-145.0 (four runs) | |
| 03:09-03:45, quiet machine, final batch | without ReShade | 136.4, 148.2 | 90.0, 90.3 |
| same | ReShade layer, no effect | 145.2 | |
| same | ReShade layer, marker | 145.0, 147.6 | 84.2, 83.2 |
| same | ReShade layer, heavy blur | 147.0 | 71.6 |

- The early drop is not the layer's own cost: on a quiet machine the 1280 x 720 runs with and without
  the layer are alike (143-148 frames a second; one run without it gave 136), whatever the effect.
  The layer's work runs on the runtime's command threads, so it suffers most from a processor other
  work keeps busy; runs without the layer lost about 3 % in the same window.
- At 3840 x 2160 the layer costs frame time: the median frame took 11.04-11.09 ms without ReShade,
  11.87-12.00 ms with the marker (0.9 ms more, 7 % fewer frames) and 13.82 ms with the heavy blur
  (2.8 ms more, 20 % fewer).
- The final batch (`out\round8\perf_final.ps1`, not in git) waited before each run until no game of
  another install ran and the processor had been under 15 % busy for 10 s, and recorded that no other
  game started during a run (processor 9-16 % busy on average while timing).
- Starting ReShade from a `ReShade.ini` with or without its overlay layout made no difference (143-145
  both), and ReShade rewrote it only at start and exit (three writes a run).
- One 4K run with the layer stayed at 31 frames a second for its whole 30 s; its `ReShade.ini`
  afterwards held the overlay's windows at 4K size, so the overlay was open (the window covered the
  screen). The final runs give the overlay a key nobody presses.

## 27. The runtime's late DLLs, and GPUs that are not NVIDIA's (2026-10-29, Claude and a side session)

**FSR and NRC never loaded under the loader.** From the Remix logs and module lists kept under `out\`:
- The classic install (`m5\acceptance\ref-*`) and the M4 loader runs log "FSR: amd_fidelityfx_vk.dll
  loaded" and "NRC SDK: Loading the default network config data"; its game process has
  `amd_fidelityfx_vk.dll`, `cudart64_13.dll`, `nvrtc64_130_0.dll`, `nvrtc-builtins64_133.dll`,
  `nvcuda.dll` and `nvcudart_hybrid64.dll` loaded.
- Every loader session from M5 (`m5\acceptance\poc-construct-2`) on logs "FSR: amd_fidelityfx_vk.dll
  could not be loaded" and "[RTX Neural Radiance Cache] Failed to initialize NRC. Reason: Unexpected
  condition occured during processing", and switches to importance-sampled indirect light; none of
  those six DLLs is in its process.
- The four of them that ship are in the package's `runtime` folder beside `d3d9.dll`. The fork probes
  FSR by bare name when it creates the device (`src\dxvk\rtx_render\rtx_fork_fsr.cpp:537`, a plain
  `LoadLibraryA`; the DLL is delay-loaded, `src\dxvk\meson.build:523`). `NRC_Vulkan.dll` delay-imports
  `nvrtc64_130_0.dll` and names `nvrtc-builtins64`; nothing in the runtime folder names `cudart64_13`
  (ASCII or UTF-16). In the classic process (`ref-construct-3`) the CUDA DLLs are the last modules to
  load, `cudart64_13.dll` just before `nvrtc64_130_0.dll`.
- M4 put the runtime folder into the search with `SetDllDirectoryW`, and FSR and NRC loaded. M5 moved
  it to `PATH` (ADR 0010). Loader 0.5.0's first fix added it with `AddDllDirectory` as well: the
  end-to-end run (`out\round8\e2e\sessions-run1`, four RTX sessions with and without ReShade) still
  logged both failures, with `AddDllDirectory` succeeding (no note).

**Why no search finds the runtime folder** (2026-10-29, measured on the ReShade client):
- **`PATH` is rewritten.** Read from the running game's process environment block, `PATH` was
  `C:\Program Files (x86)\Steam;` followed by the 25 entries the process started with: neither the
  runtime folder the loader put first nor `gmod.exe`'s own `bin\win64` entry is left, so something
  rewrites it after both from the starting value, apparently the Steam client.
- **`gmod.exe` rewrites it too, harmlessly:** it formats `PATH=%s;%s` (its folder, then the `PATH` it
  read; code at `0x14005736E`, with warnings for a game path of 260 characters or more and for the two
  together passing 8,192) and then checks the command line for `--type=` (Chromium's helper processes).
- **The standard search is in effect.** `gmod.exe` holds Chromium's sandbox mitigations; their
  DLL-search flag (`0x200`) calls `SetDefaultDllDirectories(0xC00)` (System32 and user folders;
  `0x1400018FA`, the function name resolved at run time, so no import table shows it). Under that set
  an `AddDllDirectory` folder would be searched; since the game's loads did not find the folder, they
  use the standard search, which reads `SetDllDirectory`'s folder (M4) but never `AddDllDirectory`'s.
  Modules of the game process that name these functions: `gmod.exe`, `libcef.dll` (both
  `SetDefaultDllDirectories`), `apphelp.dll`, `client.dll`, `server.dll`, `GameAnalytics.dll`
  (`AddDllDirectory`), and `gmcl_rtxfixesbinary_win64.dll`, `dxgi.dll`, `NvMemMapStoragex.dll`
  (`SetDllDirectory`).
- **The files are fine.** In a fresh process (`out\round8\tools\probe_search*.py`), all of
  `amd_fidelityfx_vk.dll`, `cudart64_13.dll` and `nvrtc64_130_0.dll` load from the deployed runtime
  folder: by bare name with it first on `PATH`; by bare name after `AddDllDirectory` and
  `SetDefaultDllDirectories(0xC00)`, also after a DXGI adapter list and a Vulkan instance on the NVIDIA
  driver, and after any `SetDllDirectoryA` call; and by absolute path. Their dependencies are System32's
  (`MSVCP140`, `VCRUNTIME140`, `vulkan-1`), the same files the game loads.
- So loader 0.5.0 loads the four right after the runtime, by absolute path (ADR 0030): a later
  bare-name load binds to the loaded module. They are 113 MB (`nvrtc64_130_0.dll` 96.7 MB,
  `amd_fidelityfx_vk.dll` 8.9 MB, `nvrtc-builtins64_133.dll` 6.4 MB, `cudart64_13.dll` 0.5 MB).
- **Result** (`out\round8\e2e\sessions`, the same package, RTX 5090): every RTX session logs "FSR:
  amd_fidelityfx_vk.dll loaded.", "NRC SDK: Loading the default network config data" and "NRC v0.15
  (25 March 2026) Context successfully initialized", and stays on the Neural Radiance Cache. Activation
  took 38.8 ms with the four against 35.8-51.1 ms without them.
- **In the field install** (2026-10-29, `out\round8\field`): loader 0.5.0 in place of 0.4.0, the same
  package from the Workshop, two sessions with the user's add-ons and Workshop items.
  - The first start deployed generation 17 (200 changes, 16,637 file operations, 5.2 s) and activated
    the runtime in 45 ms with the four preloaded. The second found nothing to deploy (start-up 0.25 s,
    activation 40 ms).
  - Both log "FSR: amd_fidelityfx_vk.dll loaded." and NRC's "Context successfully initialized".
    Round 7's field session (`out\round7\field`) logged both failures and ran on importance-sampled
    indirect light.
  - Ray tracing began 20-22 s after the map loaded, so the first run's screenshot, taken seconds
    later, is black (1 FPS). The second run (`--settle 60`) shows gm_construct path-traced (mean RGB
    116, 111, 97).
  - All 2,877 depot files still verify, `autoexec.cfg` aside.

**The preset.** The package's classic layer pins `rtx.graphicsPreset = 4` (Custom). The fork's
`GraphicsPreset` (`rtx_graphics_preset.h:26`) is Ultra 0, High 1, Medium 2, Low 3, Custom 4, Auto 5. It
chooses per GPU only under Auto (`rtx_options.cpp:419`, `rtx_initializer.cpp:128`): for a non-NVIDIA
GPU, Low with `applyNonNvidiaDefaults` (resolution scale 0.5, TAA-U and NIS at Performance;
`rtx_gpu_profile.cpp:203-209`, `rtx_options.cpp:450-460`). Per-GPU overrides
(`rtx.gpuOverride.graphicsPreset.VVVV_DDDD`, `rtx_gpu_overrides.h:38`) name one vendor and device id
each and are read only under Auto.

**What an AMD GPU needs** (the fork, read by the side session):
- Required are only the KHR ray-tracing extensions (`dxvk_extensions.h:326-328`: acceleration
  structure, ray query, ray-tracing pipeline). The NVIDIA extensions (invocation reorder, low latency,
  NVX binary import and image view handle, present metering) are optional. So Radeon RX 6000, 7000
  and 9000 qualify; RX 5000 and older cannot start an RTX session.
- DLSS becomes TAA-U when unsupported (`rtx_context.cpp:579-580`), NRC becomes ReSTIR GI
  (`rtx_options.cpp:500-506`); DLSS frame generation and Reflex are NVIDIA-only; XeSS (`libxess.dll`,
  a static import) runs on AMD.
- On AMD, asynchronous shader prewarming is off (`rtx_initializer.cpp:205`, an old deadlock
  workaround): expect a stutter the first time each effect is used.
- Integrated GPUs are skipped only when a discrete GPU is there (`dxvk_instance.cpp:919`); on an APU-only
  machine Remix uses the integrated GPU.

**AMD smoke test** (2026-10-29, `out\round8\amd_smoke.ps1`, twice: before and after the preload). One
RTX session in the ReShade client with `VK_DRIVER_FILES` set to AMD's driver manifest, so Vulkan sees
only the Ryzen 9 9950X3D's integrated "AMD Radeon(TM) Graphics" (vendor `0x1002`, RDNA 2). DXGI still
lists the RTX 5090, so the non-NVIDIA layer stayed off and the preset Custom (4).
- Remix took the Radeon, found NRC unsupported (`VK_NVX_binary_import` and `VK_NVX_image_view_handle`
  missing) and switched to ReSTIR GI; NGX was not available (DLSS off) and Reflex failed; "AMD driver
  detected" set the ray-tracing modes (trace ray for indirect light, ray query for the G-buffer and
  direct light). The map loaded.
- With the preload, "FSR: amd_fidelityfx_vk.dll loaded." (before it, "could not be loaded").
- In both runs: many "GetShaderModule: Out of range of supported shader model", then the fork's FSR
  sharpening pass (`fork_rcas`) failed to compile and, a second later, `VK_ERROR_DEVICE_LOST` (60-75 s
  after start). The game then hung until stopped; `poc_session.py`'s timeout did not end it. So this
  integrated GPU cannot run an RTX session; a discrete Radeon (RX 6000 or newer) was not available to try.

## 28. The physical sky, time of day and weather (2026-10-29, Claude)

The user's request: environmental control in the RTX settings (the sun's direction, the time of day,
clouds and weather), looking realistic. Built in the companion ([ADR 0031](decisions/0031-physical-sky-time-and-weather.md));
evidence in `out\sky\sessions` (e1-e7: exploration tours, the end-to-end run, the frame-rate run).

**What sessions had before.**

- **The sky mode.** The runtime has two (`rtx_options.h:175`): 0 rasterises the game's skybox into a
  probe; 1, "Numos", is a physical sky (`rtx_atmosphere.*`):
  - Hillaire scattering, Nubis-style volumetric clouds with a second layer, stars, up to four moons;
  - lightning, and rain/snow/sand particles (`rtx_precipitation.*`);
  - in Numos mode the sun and the moons are distant lights the atmosphere adds itself
    (`RtxAtmosphere::syncDistantLights`).

  The RTX fixes' `rtx.conf` has `rtx.skyMode = 0` and `rtx.ignoreGameDirectionalLights = False`.
- **The package's Remix defaults layer** (`01_classic_remix_defaults.conf`, ADR 0021) carries the
  classic install's `user.conf`, which holds what Modern House RTX once pushed through the API:
  - `rtx.skyMode 1`, `rtx.ignoreGameDirectionalLights True`;
  - the sun: `sunElevation 21`, `sunRotation 222`;
  - the clouds: `cloudCoverageMean 0.27`, `cloudCoverageSpread 0.8`, `cloudTypeMean 0.9`,
    `cloudShadowStrength 0`, `cloudVoxelShadowsEnable False`, `cloudLayer2CoverageMean 0.35`;
  - the fog: `rtx.volumetrics.anisotropy 0.55`, `transmittanceMeasurementDistanceMeters 420`.

  So every map ran that one sunny afternoon, with no cloud shadows.
- **Live values are not saved by themselves.** Remix's per-game settings file
  (`%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<hash>.conf`) holds only the consent switches, and
  API values reach `user.conf` only through Remix's Save.

**The atmosphere's conventions** (`rtx_atmosphere.cpp`):

- `sunRotation` and a moon's `rotation` are bearings: degrees from the map's +y towards +x
  (`toWorld` in `syncDistantLights` swaps y and z under `rtx.zUp`).
- **The runtime's day cycle** (`timeCycleEnable`, `timeOfDayHours`, `latitudeDegrees`, `dayOfYear`,
  `northOffsetDegrees`) places only the sun (`getAtmosphereArgs`, lines 579-586). With the cycle off,
  `timeOfDayHours` is ignored, whatever its description says. The moons' position and phase and
  `starRotation` are for the game to push.
- **Moon phase** runs 0 (new) to 0.5 (full) to 1; the lit side faces the sun (`atmosphere_sky.slangh`,
  `getPhaseIllumination`).
- **The star field** is rotated about the pole axis (`starAxisElevation`, `starAxisRotation`) by
  rotating the sampled direction (`evalStarField`), so it appears to turn the other way.
- **Moonlight** scales with the disc's solid angle (`moonSolidAngleSr` in `syncDistantLights`).
  - The option `angularRadius` is in fact a diameter in degrees, 3.5 by default.
  - At 1.2 degrees the ground went nearly black.
  - At 1.6 degrees the ground's share (`surfaceMoonBrightness`, 50) needs (3.5 / 1.6)^2 = 4.8 times
    as much, 240, to keep the default night. At 1,100, the fourth power, a moonlit field blew out
    white.
  - The runtime gives the moon full strength as soon as the sun is down (`nightFactor`, the sun
    0.02 to -0.05 in its sine). At dusk (the sun 5 degrees down) a rising full moon lit gm_construct's
    towers bright orange, the brightest thing in the view, even at 240. Real moonlight is about a
    fiftieth of civil twilight's light.
- **The ground below the horizon** is the virtual planet with a constant albedo
  (`atmosphere_common.slangh:73`, `kGroundAlbedo = 0.3`). From high up, where the map has no geometry,
  it shows as a flat band, red at sunset.

**Weather** (`rtx_weather.*`):

- **The presets.** There are twelve, of 63 fields each. A field the runtime lists in
  `FALLBACK_IF_INVARIANT` is taken over only when the presets disagree on it; 27 fields are the same
  in all twelve.
- **The blender** is driven by `remixapi_SetGameValue("__weather.target", <name>)`
  (`rtx_remix_api.cpp:2831`); `SetConfigVariable` cannot reach it.
- **What Lua can reach.** The RTX fixes' Lua API has no `SetGameValue`, and its `GetConfigVariable`
  reads `rtx.conf` from disk (`source/remixapi/remixapi.cpp:1111`).
- **Blends:** angles take the short way round; fog distance blends in 1/distance; switches flip at the
  midpoint.
- **Variation.** Cover, wind speed and wind direction wander on a 300 s noise (`driftNoise1D`), with
  per-preset speed and intensity in the fork's `docs/integrators/weather-presets.md`.
- **Cover changes do not re-bake the clouds.** The cloud SDF's bake key holds no cover, and the
  thickness is quantised to 0.25 km (`CloudNvdfBakeKey`), so changing the cover often is cheap.

**GMod's scale.** A Remix metre is 100 units (`getMeterToWorldUnitScale`, `rtx.sceneScale 1`), and a
GMod unit is 1.905 cm, so a Remix metre is 1.905 real metres.

- **The map's size.** gm_construct's playable area is about 7,000 by 4,000 units, 70 by 40 Remix
  metres. The game's trace up from its field hits the sky ceiling at z 9,984. Its `light_environment`
  has pitch -56 and yaw 306: the sun is 56 degrees high at bearing 324.
- **The fog colour is sRGB.** `rtx.volumetrics.transmittanceColor` is gamma-encoded; the runtime
  turns it linear before it uses it (`rtx_global_volumetrics.h:144`, `getVolumeArgs` in the `.cpp`).
  0.92 is 0.83 linear, and for the presets' colours the extinction is 2.21-2.27 times what the raw
  value suggests.
- **The presets' fog**, made for kilometre-wide worlds, does not show inside a map. "Foggy" (0.92 over
  80 m) keeps about 85 % of the light across gm_construct.
- **Dense froxel fog turns black.** The froxel fog (`rtx.volumetrics`) is lit by lights only, not by
  the sky. Set from a visibility of 80 real metres, the ground and walls went black under a white sky;
  at 260 m everything was dark and murky; from 660 m up it reads as mist. (The first sessions worked
  the distance out from the raw colour and so took these for 180 m, 600 m and 1.5 km; the companion
  now uses the linear colour, with visibilities 2.27 times smaller for the same fog.)
- **The atmosphere's haze does not help.** Its aerial perspective starts at the froxel range
  (`froxelMaxDistanceMeters`, 20) and fades in over 50-250 m. Raising the aerosol density to 100-400
  barely touched the map; at 1,500 the whole scene went black. Widening the froxel range to 80 m only
  hands the whole map to the unlit froxel fog.

**Rain and snow** (`rtx_precipitation.*`, `particle_system_spawn.comp.slang`):

- **No drop was ever born with the runtime's cover test.** With `occludeUnderCover` (the default), the
  shelter probe traces up to `100000 * sceneScale` units (line 286), and above gm_construct it found
  cover everywhere.
  - The 3D skybox room hangs over the map: its miniature shows overhead in the path-traced sky, drawn
    because RTX sessions set `r_novis 1`.
  - The ray hits geometry the camera does not see, such as the room's floor from below.
- **With the test off, rain and snow fall.** The default volume, 20 Remix metres around the camera and
  14 above, is 2,000 and 1,400 units, so few drops land near the player. At 8 and 6 they are dense.
- **Against a bright sky** both rain streaks and flakes read darker than the sky, as real ones do.

**The cloud shadows.** With `cloudVoxelShadowsEnable True` (the runtime's default), cumulus shadows
drift over gm_construct's field, with sharp sunlit patches.

**What it costs** (2026-10-29, `out\sky\sessions\e8-final`, RTX 5090, 1280x720, the PoC's
settings with DLSS frame generation, machine otherwise idle). Rendered frames over 20 s at the field
camera, timed by a `PostRender` hook; the game's own counter showed about three times as many, the
generated frames included:

| Sky | fps | median | p99 |
|---|---|---|---|
| Physical, partly cloudy | 148.3 | 6.74 ms | 8.74 ms |
| Physical, thunderstorm (rain, lightning) | 148.7 | 6.74 ms | 8.66 ms |
| The map's skybox | 150.5 | 6.65 ms | 8.39 ms |
| Physical again, partly cloudy | 147.7 | 6.78 ms | 8.90 ms |

So the physical sky costs about 0.1 ms a frame here (1.5 %), and rain costs nothing measurable. The
rate may sit near the frame-generation pacing, which could hide some of the cost; a slower GPU pays
more for the clouds, which are marched at full resolution.

## 29. The real Moon and night sky, eclipses and fog presets (2026-10-29, Claude)

**The Moon's source.** Downloaded 2026-10-29, with the user's go-ahead, into
`out\downloads\nasa-svs`, from NASA's Scientific Visualization Studio: the CGI Moon Kit
(https://svs.gsfc.nasa.gov/4720). Credit line: "NASA's Scientific Visualization Studio".

| File | Bytes | SHA-256 | What |
|---|---|---|---|
| `lroc_color_poles_4k.tif` | 13,095,388 | `918649a7...` | RGB 8-bit, 4096x2048, LZW |
| `ldem_4.tif` | 4,153,352 | `330afa25...` | 32-bit float, 1440x720 (4 pixels a degree), km above 1737.4 km: -8.88 to +10.50 |

- Simple cylindrical, north up, longitude 0 at the centre and east to the right (Mare Crisium at
  +59, Tycho at the bottom).
- Colour, linear luminance: 0.30 over the whole sphere, 0.2245 over the near side weighted towards
  the sub-Earth point (the maria make it darker). Per channel 0.340, 0.330, 0.297, a warm grey.
  99.9th percentile 0.80.
- Relief: slopes at 7.58 km a pixel, p50 0.046, p90 0.16, p99 0.30.

**The night sky's first source, rejected.** NASA's Deep Star Maps 2020 (https://svs.gsfc.nasa.gov/4851,
Gaia DR2; `starmap_2020_8k.exr`, half-float, 8192x4096, J2000, RA 0h at the centre, increasing to the
left). Its luminance: p50 0.0016, p99 0.035, p99.99 1.0, mean 0.0046. At 8192 pixels round the sky
a star is a blob several pixels wide once magnified, and the mip choice streaked the poles; the user
rejected it as "very blurry and unsharp". PIL has no EXR reader; `out\sky\exr_read.py` decoded it.

**The night sky's source: Night Sky HD LE** (Skyrim, PraedythXVI,
https://www.nexusmods.com/skyrim/mods/107102), the 8K archive the user supplied,
`NightSky 8K HD LE-107102-1-0-1616679732.7z`: 316,655,566 bytes, SHA-256 `936eb7a3...`, extracted to
`out\downloads\nightsky8k` (a FOMOD: `00Data\Meshes\Sky\stars.nif`, `00Data\tex\<option>\...`).

- **Permissions** (the mod page, read in the built-in browser; WebFetch gets 403): converting it for
  other games and using its assets are allowed with credit to the creator, not in anything sold. The
  FullNebula textures are PraedythXVI's edit of nebula images by Era-7 on Cubebrush, free, open assets;
  the user has permission to use them (2026-10-29).
- **What is in it.** Every texture is BC3 (DXT5) with 14 mips, gamma-space colour and alpha:

| Texture | Size | Bytes | What |
|---|---|---|---|
| `StarsThornShape7\...\skystars.dds` (used; also `Stars5-7`, `StarsThornShape5-6`) | 8192x8192 | 89,478,640 | small sharp stars, two hemispheres tiled |
| `Textures\Sky\skyrimgalaxy.dds` | 8192x4096 | 44,739,408 | the galaxy band |
| `FullNebula1\...\FullNebula.dds` (used; also 2-4) | 8192x8192 | 89,478,640 | a nebula sphere in longitude and latitude |
| `Textures\Sky\skyrimconstellations.dds` | 8192x8192 | 89,478,640 | an atlas of constellation figures |

- **The mod's sky mesh** (`stars.nif`, 79,280 bytes, SHA-256 `c09afd2a...`; read with
  `out\sky\nif_read.py`: Skyrim LE, NIF 20.2.0.7, user version 12, BS version 83, whose geometry
  data holds a 4-byte material CRC after the vector flags). Four shapes, all `BSSkyShaderProperty`
  type 5, blended additively (colour times alpha) over the sky:
  - **Stars**: a sphere whose two hemispheres share one UV layout; antipodal points get the same
    UV. Centre `c = (0, -0.390731, 0.920505)`, theta-0 axis `(1, 0, 0)`, theta-90 axis
    `(0, -0.920505, -0.390731)`. The UV radius at 0, 10, ... 90 degrees from `c`: 0, 0.21128,
    0.41641, 0.60876, 0.7983, 1.01726, 1.24191, 1.46891, 1.70335, 1.95472 (interpolated between
    rings); `uv = (1 + r cos theta, r sin theta)`, tiled. Worst error over every vertex 0.0009.
  - **Galaxy band**: axis `n = (0.722456, -0.042907, 0.690085)`, along-axes
    `(-0.573207, 0.520957, 0.632486)` and `(-0.386642, -0.852504, 0.351773)`;
    `u = 2 + along x 3 / 2 pi`, `v = 0.5 - 0.5 sin(beta) / sin(40 degrees)`, half-width 40 degrees.
    Exact.
  - **Nebula**: `u = 0.5 + lon / 2 pi`, `v = 0.5 - lat / pi`. Exact.
  - **Constellations**: 58 triangles of their own atlas, about 110 atlas texels a degree.
  - Constants and checks: `out\sky\nightsky_mapping.py`. The shader treats the mesh's frame as
    equatorial (x RA 0h, y RA 6h, z the north celestial pole).

**The textures** (`out\sky\make_sky_textures.py`, `out\sky\bake_nightsky.py`; NVIDIA Texture Tools
Exporter 2023.4.0, the one in the RTX Remix app, at `-q production`):

| File | DXGI format | Size | Mips | Bytes |
|---|---|---|---|---|
| `moon_albedo.dds` | BC7_UNORM_SRGB (99) | 2048x1024 | 12 | 2,796,388 |
| `moon_normal.dds` | BC5_UNORM (83) | 1440x720 | 11 | 1,383,524 |
| `stars.dds` | BC3 (the mod's `skystars.dds`, unchanged) | 8192x8192 | 14 | 89,478,640 |
| `galaxy.dds` | BC3 (the mod's `skyrimgalaxy.dds`, unchanged) | 8192x4096 | 14 | 44,739,408 |
| `nebula.dds` | BC7_UNORM (98), box mips without gamma | 8192x8192 | 14 | 89,478,660 |

- **Moon albedo:** resized in linear light (Lanczos) and scaled by 1.114 to a near-side mean of 0.25
  (0.016 % of the pixels clip). The shader divides by 0.25 and multiplies by `moonTextureAlbedo`
  (0.12).
- **Moon relief:** central differences, east corrected by the cosine of the latitude, wrapped in
  longitude; mips without gamma.
- **Nebula:** `FullNebula.dds` colour times alpha, with the constellations rasterised into it from
  their triangles (ray through the planar triangle, barycentric UV, the atlas pre-filtered 2x2,
  added in gamma space as Skyrim adds them). The stars and the galaxy stay the mod's own files, so
  nothing resamples their stars.

**The runtime fork** (branch `claude/sky-night` in the worktree `remix-i18n`, from `2129d75f`):

- **Bindings.** 216 night sky galaxy (a retired slot: no pass binds it), 217 Moon albedo, 218 Moon
  relief, 219 night sky stars, 221 night sky nebula. 220 is `INTEGRATE_INSTRUMENTATION`, which is
  not in the common set; the sparse-rendering passes use 240-251. `BINDING_ATMOSPHERE_MAX` is now
  221. All five are sampled with `AtmosphereSkyViewSampler` (repeat in u, clamp in v; the stars'
  tiling uses `frac(uv)`).
- **`AtmosphereArgs`** takes the former `padAerial7/8` and grows by three 16-byte rows. All the new
  fields are zeroed in `normalizeForSkyLutCache`, so they never re-bake the sky tables. What the
  bakes must see of an eclipse is folded into `sunIlluminance` and `moons[0].color`.
- **Loading.** `AssetDataManager::findAsset` reads the DDS (gli or the partial DDS loader). Each mip
  goes up with `DxvkContext::updateImage`, whose pitches are bytes per row of 4x4 blocks. It happens
  at the first physical-sky frame for what is switched on, and again only when a path option
  changes. A 1x1 stand-in is bound until then. The three night sky layers take 223.7 MB of GPU
  memory, the Moon 4.2 MB.
- **The night sky's composite:** the three layers' colour times alpha added in gamma space, clamped
  at 1, then `pow 2.2` and `starMapBrightness`. Mips without derivatives: a traced pixel is
  `2 tan(fovY / 2) / downscaled height` radians (`skyPixelAngle`), times `2^mipBias` with the
  materials' total mip bias (DLSS: `log2(render / output width)`, -1 at Performance), against each
  layer's texels per radian there.
- **The night sky's brightness, against the mod's own screenshots** (the FOMOD's `Screenshots\1.png`
  and `2.png`, 3840x2160, `FullNebula1.png`, 1920x1080; gamma-space percentiles of the frame,
  `out\sky\shot_stats.py`): `1.png` p50 0.039, p90 0.35, p99 0.89; `FullNebula1.png` p50 0.007,
  p90 0.064, p99 0.47. Black space, bright nebulae, the galaxy core near white with its dust lanes.
  - In the PoC at night (1280x720, DLSS Performance, the classic tone mapping) auto exposure sits at
    its limit (`rtx.autoExposure.evMinValue -3.45`), so the image's brightness shows one to one: the
    same background with the image and with the procedural stars.
  - `starMapBrightness` 0.03, 0.06, 0.12, 0.25: p99 of the view up 0.49, 0.62, 0.76, 0.88 (session
    `b11`). 0.12 matches the mod's nebulae.
  - The weather's airglow held space at 0.176 whatever the image did (clear: `nightSkyBrightness`
    0.008). At 100, 15, 10 and 5 % of it: p50 of the view up 0.176, 0.064, 0.052, 0.039; the ground
    in the field 0.061, 0.037, 0.035, 0.033 (session `b12`). Below 15 % the image lights the ground
    more than the airglow does. The companion sends 5 %.
  - Few stars show at 720p: each output pixel averages the star layer over its footprint (DLSS
    accumulates jittered samples), as Skyrim's mipmapped dome does. More show at 1440p and 4K.
- **The Moon's terminator.** A hard `cos i > 0` against the relief normal broke the shadow line into
  blocks at quarter and gibbous. It now follows the smooth sphere through a smoothstep about two
  pixels wide (`2 skyPixelAngle / radius` in `cos i`, clamped to 0.004-0.08), and the relief's
  `cos i` goes through a softplus.
- **Black pixels along the Moon's edge in a partial solar eclipse** (session `b11`, 8 degrees of
  view: 1 isolated black pixel at 50 %, 59 at 80 %, 6 at 93 %). They sat where a one-pixel step ran
  from the drawn disc, about 4e4 under the presets' sun (illuminance 20), to the dark Moon. The
  shader has no NaN there (the sky's final `max(radiance, 0)` would turn one into black, but every
  sqrt, division and pow on that path is guarded). With two-pixel edges and the disc capped at
  16384 the dots joined into a thin black arc along the Moon's limb, worse with Ray Reconstruction
  off (session `b14`: 22-174 a frame, and at 60 degrees of view too). Capped at 1024 the crescent
  read better but the pixels stayed (`b15`: 17-156).
  - **The upscaler makes them** (session `b16`, 88 % through Remix's debug views): the composite
    before the upscaler (`rtx.debugView.debugViewIdx 202`) is clean; the output before tone mapping
    (200) has the black pixels and some red ones; the NaN view (260) shows none. 154 of 156 are
    exactly (0, 0, 0).
  - Near totality the sky around the disc has dimmed to a few per cent, so a fixed cap still left
    the step from the dark Moon to the disc thousands of times the sky. The disc, chromosphere and
    corona are now held together to 64 times the daylight left (the brightest channel of the
    dimmed `sunIlluminance`), scaled as a whole so the hue stays. Session `b17`: no such pixel in
    any close-up from 0 to 100 %, with Ray Reconstruction on or off, 2 in one wide view; the partial
    sun now reads as a disc and a crescent instead of a glare, the corona and chromosphere as before.
- **Eclipse geometry with the companion's moon** (1.6 degrees across, radius 0.8): umbra 2.12
  degrees, penumbra 3.84, first penumbral contact at 4.64 degrees from the antisolar point; the
  companion's moon passes at 5.64 without an eclipse. The drawn sun is 0.776 degrees in radius; first
  contact at 1.576, totality inside 0.024.
- **The worktree's build never recompiles shaders by itself.** The shaders come from one ninja edge,
  `src/dxvk/_built_shaders.txt`, whose only input is `python.exe`, so ninja runs
  `compile_shaders.py` only while that stamp is missing. A shader or shader-header change needs
  `_CompRelease_x64\src\dxvk\_built_shaders.txt` deleted first; `compile_shaders.py` then rebuilds
  what changed (all of it if the outputs are gone: 2.5 min for 582 shaders on 32 threads; the whole
  build with a sky shader change, 2.7 min).
  - **What a missed rebuild does.** The first runtime-b6 paired the new C++, whose `RaytraceArgs`
    fields after `atmosphereArgs` had moved by 48 bytes, with the old shaders. The sky (read inside
    the atmosphere block) drew, every surface came out black, and the GPU hung within half a minute
    (`DLFG pacer: fence timed out`, `VK_ERROR_DEVICE_LOST`, Windows LiveKernelEvent 141; sessions
    `out\sky\sessions\b2`-`b4`).
  - Deleting the `rtx_shaders` outputs alone instead breaks the C++ build (their headers are gone).
  - **A shader-only change needs two builds.** The regenerated headers are not outputs ninja knows
    of, so the run that regenerates them has already judged the C++ up to date: the `.cpp` files
    that embed the shaders (`rtx_pathtracer_gbuffer.cpp`, `rtx_pathtracer_integrate_indirect.cpp`
    for the sky-miss path) recompile, and `d3d9.dll` relinks, only on the next run (0.6 min). A
    change that also touches a header those files include rebuilds them in the first run; one in
    `rtx_atmosphere.h` does not reach them. Sessions `b11`-`b13` ran with the C++ of that build and
    the shaders of the one before.
  - Sizes, measured with the compiler: `AtmosphereArgs` 1,232 bytes, `RaytraceArgs` 10,288, the
    atmosphere block at offset 6,832.
  - With the sky code the `d3d9.dll` grows from 345.8 MB to 362.7 MB: the sky-miss path is in every
    ray-tracing permutation.
- **Builds:** incremental, 0.2-1.1 min after a C++ change (`out\sky\build_runtime.ps1`).
- **Shader compile threads.** `dxvk.numCompilerThreads` sizes the state cache's workers, which
  compile Remix's own shaders (the "Compiling shaders (N remaining)" message, `dxvk_state_cache.cpp`).
  The classic install's `dxvk.conf` sets 1. DXVK's own default (0) is (threads - 1) x 5 / 7, capped at
  32: 22 here. The fork now reads -N as all threads but N; runtime-b6's second layer sets -2, and the
  log says `DXVK: Using 30 compiler threads` on the PoC's Ryzen 9 9950X3D (32 threads).
- **The Moon at 5 degrees of view** (about 15 times the usual zoom; the classic settings run DLSS
  Performance with Ray Reconstruction: `rtx.upscalerType 1`, `rtx.qualityDLSS 1`). The lit side
  along the terminator and the earthshine side break into diamond-shaped blocks 3-4 traced pixels
  across, the limb into steps. What changes them (sessions `b11`-`b14`):
  - Nothing of these: Ray Reconstruction off, DLAA (`rtx.qualityDLSS 5`), no clouds
    (`rtx.atmosphere.cloudEnabled False`), no volumetric fog (`rtx.volumetrics.enable False`, whose
    froxels are 4x4 traced pixels).
  - The relief: at 0 the terminator is a clean line, at 0.5 it has a few notches, at 1 a row of
    dark ones. The companion sets 0.6.
  - The texture is not it: `moon_albedo.dds` decodes sharp (Copernicus' rays at 2048x1024), and
    the full Moon, lit flat by Lommel-Seeliger, shows its craters cleanly at the same zoom.
  - At 20 degrees of view the Moon is clean.
  - Sky pixels give Ray Reconstruction a black albedo guide (alpha 0, `gbuffer_guides_output.slangh`),
    and its evaluation passes no bias-current-colour mask (`rtx_ngx_wrapper.cpp`). It was the first
    suspect, but turning it off changed nothing.
- **Two failures on the way that were not the sky's.**
  - A start-up "hang" right after Remix parsed its user settings (sessions `b7` and `b13b`, each the
    first start after a crash). It is Remix's crash-report prompt: the game's only window is
    "RTX Remix Crash Report", a modal `MessageBoxW` asking to upload the last crash
    (`showCrashReportDialogIfNeeded`, `src/util/util_sentry.cpp`). The prompt clears Sentry's
    crashed-last-run flag before it asks, so a session ended during it (the run's timeout) starts
    normally the next time, uploading nothing. `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES=1`
    is no way round it: it also gives Sentry upload consent.
  - An access violation in `studiorender.dll` (a null read on the material system's render thread,
    at `studiorender.dll+0x5d353` every time) 7 s into a map, just after the RTX fixes forced a
    model reload: sessions `b6`, `b13` and `b16`, 3 of the 17 sky sessions, two of them on a runtime
    that had already run cleanly. No Remix code was on the stack. In `b16` the RTX fixes' own hook
    logged it first: `[HWSkin] CRASH in DrawGroupHWSkin trampoline!`, then
    `[HWSkin] Exception in RenderFinal trampoline (occurrence #1)`.

**runtime-b6** (`out\sky\make_runtime_b6.ps1`): runtime-b4's extract with the sky fork's `d3d9.dll`
and `atmosphere\` (the five textures and `CREDITS.txt`), the same dxvk layer, environment and launch
arguments as runtime-b5, and the compiler-threads layer. 197 files and the manifest, 1,229,297,958
bytes, version `0.0.0-dev.202610292335+a2e1708e`; the `.gma` 1,229,349,449. `d3d9.dll` 362,684,416
bytes, SHA-256 `a2e1708e...`. The combined RTX package built from it (`out\sky\build_e2e.py`): 877
files, 1,798,369,314 bytes.

## 30. One repository: the package's inputs in Git LFS (2026-10-30, Claude)

**Where the package came from before** (`tools/workshop.json` at `bbab69e`): ten parts from six places
outside this repository. Measured with `out\sky\inventory_inputs.py` (git metadata, `_Comp*` build
folders and `external\` left out):

| Source | Files | Size | Origin |
|---|---|---|---|
| runtime-b6's tree (`out\sky\runtime-b6-src\runtime`, the runtime-b4 extract plus the sky textures) | 189 | 977 MB | built; `d3d9.dll` 339 MB, `nvngx_dlssnr.dll` 266 MB, `nvrtc64_130_0.dll` 101 MB |
| the fixes repository (`garrys-mod-rtx-remixed`) | 64,565 | 83.7 GB | `SheepyLord/garrys-mod-rtx-remixed`; its `source\` map extracts and work trees |
| the classic install's `garrysmod\lua\bin` | 21 | 35 MB | built modules |
| Model Hotloader (the classic install's add-on; its repository) | 104; 27,381 | 61 MB; 2.9 GB | `SheepyLord/Gmod-Model-Hotloader-with-Vulkan` |
| the material editor | 1,910 | 3.9 GB | `SheepyLord/-advanced_material_editor` (work trees) |
| the bullet-break simulator | 16,721 | 3.7 GB | `SheepyLord/-gmod_bullet_break_simulator` (a 961 MB theater build, artifacts) |
| the motion importer | 275 | 362 MB | `SheepyLord/Gmod-Mmd-Motion-Importer` |
| the runtime fork's worktree | 19,047 | 3.6 GB | `sambow23/dxvk-remix-gmod`, NVIDIA's SDK submodules (`nvngx_dlssd.dll` twice, `nvrtc`) |

**What the parts actually use** (each packager's `<out>.inventory.txt`, the `source` column), imported
by `out\sky\migrate_parts.py` into `packages\`:

| Part | Files | Size | Stored |
|---|---|---|---|
| runtime | 197 | 1,229.4 MB | 412.4 MB |
| fixes | 444 | 449.7 MB | 116.5 MB |
| model-hotloader | 111 | 87.0 MB | 68.2 MB |
| character-motion-importer | 17 | 19.3 MB | 9.1 MB |
| reshade | 1 | 4.1 MB | 4.0 MB |
| emissives | 1 | 3.8 MB | 0.1 MB |
| advanced-material-editor | 59 | 2.7 MB | 2.5 MB |
| procedural-bodygroup-destruction | 16 | 0.8 MB | 0.8 MB |
| advanced-bodygroup-tool | 6 | 0.2 MB | 0.2 MB |
| remove-halo | 1 | 27 bytes | 27 bytes |

853 files, 1.8 GB, stored in 614 MB (588 MB on disk). The packagers read two files they do not list:
the fixes' `garrysmod\garrysmod\cfg\autoexec.cfg` (session variables) and, for `--addon-file`, the
add-on's own file it replaces (Model Hotloader's `installation.lua`: "the add-on has no such file to
replace" otherwise).

- **LZMA (xz, preset 6) on the first 64 MB:** `d3d9.dll` 0.17 (5.0 MB/s), `nvngx_dlssnr.dll` 0.70,
  `nvrtc64_130_0.dll` 0.30, `stars.dds` 0.05 (mostly black). Decompression runs far faster.
- **Parity.** `tools/build_package.py --compare out\workshop\published.json` from the imported parts:
  877 files, a 1,798,746,608-byte archive, content digest `942d0083...`, equal to the upload of
  `bbab69e` (version `0.0.0-dev.20261030000530+f6c615a6`). The digest leaves out versions, but the
  part versions came out the same too: `unpack` restores each file's recorded time, and the packagers
  stamp versions from the newest input's time.
- **The runtime rebuild is deterministic.** `runtime/build_runtime.ps1` on the fork worktree
  `remix-i18n` (the base plus the four patches) built a `d3d9.dll` with the packaged SHA-256
  (`d9cf79e6...`).
- **Git LFS on GitHub** (docs.github.com, billing for Git LFS, read 2026-10-30): GitHub Free and Pro
  include 10 GiB of storage and 10 GiB of bandwidth a month; Actions downloads count against the
  owner's bandwidth; over the bandwidth (no payment method) LFS is disabled for the account until the
  next month; over the storage, pushes of new LFS files fail. The repository is private
  (`gh repo view`: `PRIVATE`).
- **`git lfs install` and this repository's hooks.** `post-commit`, `post-merge` and `pre-push` were
  already this project's (the Workshop publisher), so `git lfs install` would not have written its own.
  Without `git lfs pre-push`, a push sends pointer files whose content GitHub never receives. The
  publisher's hooks now run Git LFS's step first; `pre-push` reads git's ref lines once and gives them
  to both.
- **The runtime fork's patches:** `git format-patch --binary --no-signature --zero-commit
  c6b48ed1..claude/sky-night`: 0001 the snapshot 2,852,185 bytes, 0002 the translated menus
  11,434,313 (generated tables), 0003 the glossaries 70,971, 0004 the sky 63,303. The snapshot adds
  six lines to `.gitmodules`.

## 31. Review R3: what the runtime was really built from, and other facts (2026-10-29, Claude)

**The packaged `d3d9.dll` (`d9cf79e6...`, 362,791,936 bytes) was built from more than
`runtime/patches`.** `runtime/build_runtime.ps1 -Verify` against the worktree it was built in
(`<fork>\.claude\worktrees\remix-i18n`, `claude/sky-night` at `f9937026`):
- The worktree's commit tree is exactly `c6b48ed1` with the four patches (tree `815f0dca`).
- `submodules/nvapi` is checked out at `87dca62` ("R615-Developer SDK"), where `c6b48ed1` and the
  patched tree record `d08488f` (R570). The fork's own checkout (`gmod-1.6.1`) has R615 too.
- `submodules/rtxdi` (at its recorded `3b39a7c`) has three staged, uncommitted changes:
  `rtxdi-sdk/include/rtxdi/ResamplingFunctions.slangh` (100 lines), `Reservoir.slangh` (6) and
  `shaders/ResamplingCompileTest.comp.slang` (20); `git diff HEAD --binary --full-index` 10,604
  bytes, byte-identical in the fork's checkout. Patch 0001 (the snapshot) covered the superproject
  only. Now `runtime/submodules/rtxdi.patch`.
- `submodules/dlss` (`https://github.com/NVIDIA/DLSS.git`, `3749594`, "DLSS 310.9.1 SDK") and
  `submodules/sharc` (`https://github.com/NVIDIAGameWorks/Spatial-Hash-Radiance-Cache.git`, `4e21b58`,
  v1.8.3) are untracked git clones, in the fork's checkout as well: its tree records neither.
  `external-build/meson.build:151` sets `dlss_root_path = 'submodules/dlss'`.
- In the worktree, `include/MathLib/External/sse2neon/.git` (inside a submodule) points to no
  repository, so `git status --ignore-submodules=untracked` and `git submodule status` both stop
  with "gitfile does not point to a valid repository". The script reads each submodule's recorded
  commit from `git ls-tree -r HEAD` (mode 160000) and its own `HEAD` instead.

**RemixConfig.GetConfigVariable** (the RTX fixes' Lua binding,
`garrys-mod-rtx-remixed/source/remixapi/remixapi.cpp`, `ConfigManager::GetConfigVariable`): it parses
the rtx.conf it finds and returns that file's value, else `""` ("no default fallback"; the Remix API
cannot read options back). So a Lua add-on cannot read a live option; to put one back it needs
rtx.conf's value or the defaults itself. The fixes' `rtx_water` and `gm_poolrooms_rtx` restore from it
the same way.

**The runtime's defaults the weather touches** (`RTX_OPTION` fourth argument; 61 options, now in
`weather_presets.lua` `defaults`), for example `rtx.atmosphere.cloudDensity 4`,
`rtx.weather.precipitation.intensity 0`, `spawnRadiusMeters 20`, `spawnHeightMeters 14`,
`fallMarginMeters 8`, `occludeUnderCover True`. The package's classic layer sets nine of them
(`cloudCoverageMean 0.27`, `cloudCoverageSpread 0.8`, `cloudTypeMean 0.9`, `cloudShadowStrength 0`,
`volumetrics.anisotropy 0.55`, `singleScatteringAlbedo 0.98`, `transmittanceColor 0.975, 0.985, 0.995`,
`transmittanceMeasurementDistanceMeters 420`, among them). The fork's checkout and the build worktree
give the same table.

**The loader's in-memory patches after a GMod update** (for R3-001): each of the seven patterns
(`tools/package_fixes.py` `PATCH_SETS`) must occur exactly once in its module, or that patch is
skipped and reported, "the pattern does not occur (another build?)" or "the pattern occurs more than
once" (`loader/core/src/patch.cpp:69`). No game DLL is pinned by hash. The `stdshader_dx6.dll`
override (the fixes' build) is loaded in place of the game's whatever the game's build.

## 32. R3-016: limbs in bind pose on Modern House; the runtime's 259-character variables (2026-10-29, Claude)

**What the user saw** (field install, `modern_house` with Modern House RTX): a new HSR character's
ragdoll (`[577 | -1] prop_ragdoll`), the player and the view model drawn with limbs, clothes and hair
in bind pose around the pelvis. Model Hotloader's models and Hibiki
(`models/littlesdy/kancolle/desdiv6/hibiki/e_hibiki_npc.mdl`, `[566 | -1] npc_citizen`) were right.
Measured in that live session with the RTXDebug module and a probe in the runtime:

- **The trigger:** Modern House RTX's `modern_house_rtx.lua` set `r_forcehwlight 1` among its scoped
  settings, every PreRender on its map. `r_forcehwlight 0` in the same session put every model right at
  once; 1 broke them again.
- **The mechanism:** with it on, the RTX fixes' hook on `R_StudioSetupSkinAndLighting`
  (`prop_fixes.cpp`) forces hardware lighting on every model. With `r_forcehwskin 0`, a mesh Source can
  skin on the GPU (a DX90 `.vtx` and no `.sw.vtx`: the HSR characters, the player model, the hands) then
  goes through Source's fixed-function hardware skinning, which in this build sets neither
  `D3DRS_VERTEXBLEND` nor `D3DRS_INDEXEDVERTEXBLENDENABLE` nor any `WORLDMATRIX(1+)`. The probe
  (`processSkinning` in `src/d3d9/d3d9_rtx.cpp`, logging each draw; removed afterwards) logged
  `vb=0 ivb=0 maxBoneSeen=0` for every such draw. The runtime reads vertex blend off as "not skinned"
  and draws the mesh rigid with `WORLDMATRIX(0)`, the first bone: the pelvis.
- **Why some models were right:** Model Hotloader skins its models on the CPU itself, and Hibiki's
  model has a `.sw.vtx`, so Source skins it on the CPU.
- **`mat_softwareskin` does not hold:** it is `FCVAR_CHEAT` (flags 16384, `Engine.GetConVar`). The
  loader's `nativeloader_session.cfg` and the fixes' `autoexec.cfg` set it to 1, and with 1 every model
  draws right even with `r_forcehwlight 1`; but Source puts cheat variables back to their defaults when
  `sv_cheats` goes from 1 to 0, and its default is 0 (seen in the session: 1, then `sv_cheats 1` and
  `0`, then 0).
- **The classic install never ran with `r_forcehwlight 1`:** its launch line has
  `+r_forcehwlight 1`, but the variable is created later by `gmcl_RTXFixesBinary`, so the launch
  option finds nothing to set and is dropped.
- **The fix:** Modern House RTX no longer sets it (`garrys-mod-rtx-remixed`, branch
  `claude/modern-house-rtx`, `e96ad7f`); item 3829275998 updated to `0.0.0-dev.202610300425+d7efd636`
  (`gma_sha256 d90c206b...`). In the field install with it: `r_forcehwlight` 0 (flags 0, default 0,
  "Force LIGHTING_HARDWARE") and `mat_softwareskin` 1 on `modern_house`, and the user saw the models
  right.

**`DXVK_CONFIG_FILE` (and every variable the runtime reads) holds at most 259 characters (R3-017).**
`env::getEnvVar` (`src/util/util_env.cpp:47-54` in the fork) reads it with `GetEnvironmentVariableW`
into a `MAX_PATH` buffer. A longer value does not fit, nothing is copied, and the variable reads as
empty; `RtxOptionLayer::resolveConfigPaths` (`src/dxvk/rtx_render/rtx_option_layer.cpp:617-627`) then
falls back to `dxvk.conf` alone. Every package layer is dropped without a message. A probe package
with a longer version reached 261 characters and started with a black screen; with a shorter version
(235) it rendered. The loader's paths are relative to the game folder, so the Steam library's path does
not count; the package's id, version and generation do, twice, and every added layer:

| `DXVK_CONFIG_FILE` of the published package (`0.0.0-dev.20261030022927+8beef27e`) | Characters |
|---|---|
| NVIDIA GPU, generation 9 / 21 / 999 | 237 / 239 / 241 |
| No NVIDIA GPU (`native-loader/remix/non-nvidia.conf` added, ADR 0030), the same | 273 / 275 / 277 |

So without an NVIDIA GPU, an RTX session of the published package ran without its layers. The limit
itself was known (section 19, and ADR 0021 noted a long list); the package's longer versions and the
non-NVIDIA layer (ADR 0030) crossed it, and only on GPUs this machine does not test with. Fixed by
listing short copies of the layers instead (ADR 0036): 73 characters for the published package, 109
without an NVIDIA GPU.

**The runtime build is reproducible but for its stamps.** Built again in the same verified worktree
(`build_runtime.ps1 -Verify` passes), `d3d9.dll` has the same size (362,791,936 bytes) and differs from
the packaged one (`d9cf79e6...`, now `d899908e...`) in 15 bytes: the PE time stamp and checksum in the
header, the time stamp's three copies in the debug directory, and one byte of the CodeView record
(`0x1f` against `0x23`, the PDB age).

## 33. Frame generation and the GPU (2026-10-29, Claude, from the user's report)

- **The classic defaults turned DLSS-G on at 3x:** `packages/runtime/layers/classic_remix_defaults.conf`
  had `rtx.frameGenerationType = 1`, `rtx.dlfg.enable = True` and `rtx.dlfg.maxInterpolatedFrames = 2`
  (two generated frames per rendered one), from the classic install's files on an RTX 5090. The
  runtime's own defaults: `rtx.frameGenerationType` 0, `rtx.dlfg.maxInterpolatedFrames` 2 (range 1-6;
  `runtime/patches/0001`, the options table).
- **The user's report:** with it, players on RTX 30, RTX 40 and AMD GPUs crashed at start. DLSS-G needs
  RTX 40 or newer; more than one generated frame needs RTX 50.
- **Remix's menu shows the multiplier only where multi-frame generation is supported**
  (`if (supportsMultiFrame) { dlfgMfgModeCombo... }`, `runtime/patches/0001`, line 8518 of the patch),
  so on RTX 40 the inherited 3x could not be lowered there.
- Fixed in the package's layer and in `tools/remix_defaults.py` ([ADR 0037](decisions/0037-frame-generation-off-by-default.md)):
  off by default, one generated frame when turned on.

## 34. Translation coverage audit (2026-10-30)

- The original companion checker accepted missing, empty and fuzzy entries, so its success did not
  establish completeness. The release builder now rejects them; draft fallback is explicit.
- Runtime extraction found 3,293 existing messages and no missing source keys. Its template had
  stale references. Translating the initial weather state adds one: 3,294 messages per language.
  The weather status formatted raw preset names through `%s`; translating the outer format alone
  could not translate those values (`rtx_weather.cpp`, `showImguiSettings`).
- Native add-on coverage after this pass: Bodygroup Tool 104, Destruction 204, Material Editor 1,141,
  material help 83, Motion Importer 364 and Model Hotloader 2,030 English keys. All six translations
  have matching keys; Motion also retains complete Arabic and Spanish catalogs.
- Material Editor's reverse lookup deliberately refuses ambiguous strings. Different Japanese words
  for the same generic Colour/Strength labels, and inconsistent Texture path wording, caused English
  fallback across every locale. Those terms now agree; Edit buttons carry an explicit context key.
- The six apparent missing Destruction entries were autonyms and a model-path example, not missing
  prose. They are explicit invariants now. Korean was absent, and four add-ons mapped Traditional
  Chinese to Simplified Chinese; both gaps are corrected.
- Runtime setup under this repository exposed delayed expansion consuming `!` in `update-deps.cmd`.
  Quoted paths and disabled delayed expansion fix it. Windows PowerShell 5.1 and Python 3.12 were used
  for the verified runtime rebuild. The fresh runtime tree also needed seven ignored unit/app test
  sources from the existing verified tree to finish Meson setup; these do not enter the runtime DLL.

Evidence is under `out/translation-audit`; final commands and PoC results are in the
[QoL report](handover/QoL-report.md).

The final UI tour inspected 6,850 text elements across English and the six requested languages, with no builder or Lua errors and a normal exit. Six matches for `Hair` were stored bodygroup identifiers (`cl_20_filters.lua:7`, displayed verbatim by `cl_90_settings.lua:307`), not missing UI translations. Runtime logging exposed concatenated migration buttons in `dxvk_imgui.cpp`; patch 0006 replaces them with static translated labels and formatted count lines. The runtime now has 3,298 messages per language. The user explicitly accepts resizing the Remix settings window to reveal long labels.

## Native package cards and Steam publisher preflight (2026-10-30)

- Stock `html/js/menu/control.Addons.js:488` adds `invalid` for `invalid_reason`; lines 498-504 return
  that reason before `file.info.description`. `html/css/Workshop.css:484` colors invalid cards red.
  `lua/includes/util/workshop_files.lua:254-291` already obtains and sanitizes the real Workshop
  description. The generated overlay restores that existing description flow for managed IDs.
- PoC `filesystem_stdio.dll` SHA-256 `814373ea10b7e4e4f48c1eaf820f35e7fed2a5ef756e77f0fb2d68d1323ce1ad`
  imports A/W CreateFile and attribute APIs directly; its CRT is linked statically. REA Ghidra
  evidence `ev_233af55c3f1d0ff2eedebf94964447b1db4bdd18a228cdac909aca0d98dc8ed0` identifies the whitelist
  failure in the filename validator. This was static evidence; the PoC then demonstrated actual
  archive and menu-script redirection through those four IAT slots.
- PoC acceptance mounted **761/761** subscriptions. Four current native packages (RTX runtime,
  Modern House, Guinaifen and Robin) used inert display GMAs; no `native/manifest.json` whitelist
  warning or native-package mount warning remained. All four cards were blue; the runtime's
  normal Workshop description was visible. The game quit normally with exit 0.
- The reviewed `gmpublish.exe` (SHA-256 in `tools/publish_workshop.py`) calls
  `SteamAPI_IsSteamRunning` at VA `0x14000818d`, before real initialization. On this machine it
  returned false while `SteamAPI_InitFlat` and the exact required interface-list initialization
  returned success. Steam's ActiveProcess PID was stale. The guarded isolated-copy fallback changes
  only file byte `0x7595`, `75` to `eb`; the same target continues to the original real init.
  REA evidence `ev_011fc45734d0cb8f00bf67919e04784c234ed717c5d3b32594959e610fb15a06`.
- Evidence: task worktree `out/native-addon-menu`; screenshots, own-session console, loader reports,
  REA snapshots and restoration records. PoC config files were restored by hash; its own video
  changes (ScreenWidth, ScreenHeight, DXLevel_V1) were restored only while they still matched the
  test's recorded values. No user's running game was operated.

## Modern House native glass (2026-10-30)

- The installed map 3495468649 has 52 func_breakable entities and no func_breakable_surf. Its BSP
  entity/model lumps were read without extracting or editing the map. At runtime, 44 have a valid
  convex VPhysics mesh whose material is glass; other entries are metal, shadow or have no physics.
- Existing Glass-Rewrite-Remix `procedural_shard.lua` only handled func_breakable_surf. The real
  baseline pane (*9) had health 15 and 36 physics vertices; bullet damage removed it with no shards.
  The observed hook order was EntityTakeDamage, EntityRemoved, break_breakable, then damage return.
  EntityRemoved alone cannot be treated as a break and cannot immediately discard the cached mesh.
- The engine event is documented by [Facepunch](https://wiki.facepunch.com/gmod/gameevent/break_breakable).
  Physical convex triangles come from [PhysObj:GetMeshConvexes](https://wiki.facepunch.com/gmod/PhysObj:GetMeshConvexes).
  The addon now preserves native brush logic and uses the event for debris only.
- The first fixed probe had 18/18 valid physics shards, 18/18 client meshes and 18 pieces still on
  the floor after 30 seconds. The complete-package RTX run confirmed real reflected glass geometry,
  native OnBreak output, scripted horizontal panes, 256/256 full-resync meshes, cleanup to zero
  and 18 new pieces after rebreaking. Evidence is in the map-glass worktree under out/glass-map.
- Runtime util_filesys.h maps DXVK_LOG_PATH to the Logs directory, which also owns the Sentry
  database. util_sentry.cpp checks crashed-last-run before engine condebug exists. A fresh test-only
  log directory avoids an old report prompt without touching its files or consent. Ray tracing was
  True in the isolated run's Remix log; the game loaded and quit normally with zero Lua errors.

## Hotloader's DepthWrite on Remix (2026-10-30)

- Bundled `mmd_hotloader/lua/mmdhl/native_render.lua` created DepthWrite clones during the first
  color registration, before it knew whether that shader family was present. The existing
  UsesRemixPreview query only read RenderStats, whose native flag starts unresolved.
- Native renderer.cpp initialize selects stdshader_dx9.dll when loaded, otherwise the fixed-function
  stdshader_dx6.dll, and records fixedFunctionRemix. CheckRenderer performs that initialization;
  RenderStats alone does not. The Lua predicate now calls the available CheckRenderer first.
- The reported asset (hash beginning f9c3e4b4) is already in the PoC cache and has 83 slots. A real
  baseline run recorded 83 MMD depth-material requests and 131 unknown DepthWrite console lines
  (83 Hotloader materials and 48 separate built-in engine messages).
  The model's color draws still ran; a console filter would leave the bad material registrations.
- [DepthWrite's documented role](https://wiki.facepunch.com/gmod/Shaders/DepthWrite) includes hardware
  depth and alpha cutouts. The programmable Source path remains unchanged. Remix's ordinary scene
  geometry supplies its ray tracing, so its unsupported Source-only depth draws are skipped.
- Only bundled Lua and its indexed provenance change. The upstream Hotloader checkout, native
  release record, cached asset bytes and carrier identities are not edited by this batch.

## Remix settings persistence (2026-10-30)

- `nativeloader_menu.lua:100` formerly created archived numeric ConVars with empty defaults and bound
  them directly to DNumSlider. PoC client.vdf independently contained max_bounces=0, sky_brightness=0
  and colour_purity=0 while dropdown values remained empty. Source's numeric controls coerce empty
  to zero. The fix uses unbound widgets, guarded initialization and explicit numeric selections;
  startup replay is off by default (current menu lines 100–157 and 215–246).
- The fixes' `source/remixapi/remixapi.cpp:1111` GetConfigVariable reads only a discovered rtx.conf
  and returns empty if the key is absent. It does not read the live runtime or user.conf. The panel
  must not treat it as a synchronized runtime getter. The new controls never use it for sync.
- `rtx_fork_tonemap.h:99` defines Psycho17 purityScale=1.0; its native UI permits 0–5. Zero is a valid
  authored choice, so globally replacing zero or changing user.conf during deployment is incorrect.
- Runtime `src/util/config/config.cpp:1474` previously opened the destination with truncation and
  silently returned on open failure. `RtxOptionLayer::save` changed its baseline before this write
  and then always marked itself saved. Patch 0008 stages with CREATE_NEW, checks writes, flushes and
  closes, and uses MoveFileExW with REPLACE_EXISTING/WRITE_THROUGH. The saved baseline advances only
  after success. Reload reads completely before removing active layer values.
- The rebuilt runtime is 362,799,104 bytes, SHA-256
  `ab03a3f792b1f75fcbb63270ba327e836af29cdd691d2a5b9d01db0052dd296b`, from verified
  eight-patch tree `615096202d12baa268afdac94e13eb8682094fe0`. No shader source changed.

## Welcome policy and animated toolgun screen (2026-10-30)

- The old welcome dialog's missing-value defaults were true. Closing it persisted those values,
  so an old true alone cannot demonstrate explicit consent. The new policy marker and SDK archive
  are evaluated before sentry_init; new/legacy grants fail closed. The NoSave showUI option must
  use its derived layer even through the public API. Exposing FirstUseGuide as BASIC to the public
  getUiState also releases GMod's cursor through the existing tmc bridge.
- Disposable-profile GPU acceptance kept both grants false, cancelled the countdown by clicking
  the title, saved neverShowFirstUseGuide=true and retained dismissal in a new process. The
  unattended opening logged dismissal after approximately twelve visible seconds.
- Dynamic Toolgun Screen item 3826729485 retains the stock
  models/weapons/v_toolgun/screen material while updating its render-target texture. The stock
  mesh has two triangles, weighted to bone 41. Its mesh rest matrix is already inverse bind;
  multiplying the current bone matrix by that matrix reproduces the live pose.
- GMod's render.GetViewSetup(true) supplies the actual viewmodel FOV and near/far planes; using
  the world FOV misaligns a redraw. Source texture flag globals are not exposed in this client,
  so the render-target clamp flags use their numeric value 12. Allocation failure must not clear
  the main framebuffer.
- Live native/DLSS/DLSS-G comparisons on the isolated fixture preserved the moving text and screen
  alignment. The final DLSS-G stages resolved frameGenerationType=1 and dlfg.enable=True, with
  fsrfg.enable=False; capture/draw counts advanced and no module error was logged.

## R4 companion review facts (2026-10-31)

From the RTX fixes' source (`H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed\source`, read only)
and this repository:

- `RemixMaterial.GetMaterialHashRevision()` returns nil whenever the native material-hash lookup is
  unavailable: while a refresh runs, or after one failed (`d3d9_texture_tracker.cpp:794-801`). A
  refresh fails when any cached texture has no hash yet (`:748-752`, `:780-784`) and runs at most
  once a second (`:716-737`), so nil is common while textures load; the old outline module then
  rescanned every cached material and re-read every hash on every frame.
- `RemixMaterial.GetCachedMaterials()` lists the tracker's whole texture cache, every material drawn
  (world brushes, decals and sprites too: `d3d9_texture_tracker.cpp:472-480`); it says nothing about
  which entity uses a material.
- `RemixMaterial.GetAllTextureHashes(name)` reads only that cache (`material_lua_bindings.cpp:644-690`,
  `d3d9_texture_tracker.cpp:445-470`): a material has hashes only after it was drawn.
- `RemixConfig.SetConfigVariable` prints a warning on every refused write (`config_lua_bindings.cpp:27-30`);
  `RemixMaterial.TrackMaterial` warns for a name with no material or no `$basetexture`
  (`material_lua_bindings.cpp:547-553`).
- The runtime's `rtx.gmod.ignoreOutlineMeshes` defaults to `True` (NoSave; runtime patch 0014,
  `rtx_model_layers.h`), so the companion sends `False` to keep the shell rule off.
- `rtx_pseudoplayer` is created by the RTX fixes (`remixlua/cl/cl_rtx_misc.lua:3`, default 1), which
  `autorun/cl_rtx.lua` includes while GMod runs `lua/autorun/`, before `lua/autorun/client/`: the
  companion menu's own `CreateClientConVar("rtx_pseudoplayer", "0", ...)` never set the default.
- Glass Rewrite's client asks for every shard once (an empty `SHARD_NETWORK` 1 s after
  `InitPostEntity`, `networking.lua`) and for each new shard in its `Initialize`
  (`procedural_shard.lua:716-719`); 256 shards of 300 vertices are about 920 KB.

## Layered alpha cutouts and outline meshes (2026-10-30)

- Ordered GBuffer rays forced opaque hits and used resolveVertexFinalContinue's normal offset
  after alpha rejection. With coplanar MMD layers the offset could pass the valid face too.
  Ganyu's raw-albedo nose patch was blue back hair, establishing geometry selection before
  lighting as the remaining cause. In-traversal rejection removed it from the first captured
  cold spawn, with micromaps off and targeted facial workarounds disabled.
- rejectCutoutCandidate uses the existing material alpha evaluation and preserves the original
  comparison and texture operations. Ray queries commit accepted nonopaque candidates; matching
  any-hit stages mirror the existing closest-hit payload variants. SPIR-V entry-point validation
  checks 104 any-hit and 104 closest-hit outputs in both release and dedicated unit builds.
- Cached geometry flags were refreshed only for vertex/billboard changes; static skin/material
  opacity changes also need refresh. Dynamic BLAS compatibility must be checked even without a
  vertex update. Shared geometry is opaque only when all linked instances are opaque, while the
  no-duplicate-any-hit flag is retained if any linked instance needs it.
- Live metadata exposes two skins for models/pm/ganyu_kk_pm.mdl, and one for the cached Lynette
  and March 7th playermodels. Ganyu's hei is the dedicated black outline material; touming is its
  transparent partner. Eyebrow/eye-white names can carry parenthesized mayuge/sirome suffixes.
  These names are relevant only to optional outline suppression, not cutout correctness.
- A front-culled shell can be invisible to the camera while its inward faces block light from
  the model. Ignoring the incompatible shell removes that geometry from every rendering path.
  The owned outline texture list joins the existing Hidden category without replacing user data.
- Pure state synchronization must run from Think: the main opaque pass can have a non-nil render
  target. GPU hash readiness can change without a material-binding revision; unresolved hashes
  need retry and resolved bindings need periodic refresh. Ordinary-image aliases are protected.
- Separate fresh processes avoid retained-mesh ghosts when replacing actors at identical poses.
  All three supplied models were clear at the first, two-second and fourteen-second captures
  with micromaps disabled. GBuffer compute-query, raygen-query and trace-ray views were clear;
  skin changes, opt-out/re-enable and normal micromaps were exercised. RTXDebug Engine.GetConVar
  independently reported nativeloader_ignore_outlines=1 with archive flags.

## R4 field facts (2026-10-31, Claude)

Measured on the user's install (RTX 5090, loader 0.10.0 and the published package, the user's
`mat_queue_mode "2"`, 766 subscriptions); evidence in the main checkout's `out\qa-field\`.

- **Procedural glass and queued rendering.** Drawing a `procedural_shard` with `ENT:Draw` ->
  `self:DrawModel()` and `ENT:GetRenderMesh` returning a Lua `IMesh` crashed the game on the material
  system's render thread: access violation reading `0xffffffffffffffff` at `studiorender.dll+0x6603b`,
  called from `+0x141b9` <- `+0x5cb21` <- `+0x5fea7` <- `materialsystem.dll` queued context <- a
  `vstdlib.dll` job thread; no project module on that stack. It happened for map debris and for the
  add-on's own spawned pane alike, and not at all when the entity drew its mesh itself
  (`cam.PushModelMatrix(self:GetWorldTransformMatrix())` + `IMesh:Draw()`). Destroying meshes late alone
  did not stop it. Codex's PoC acceptance of the map glass ran with the default `mat_queue_mode`.
- **What Remix rasterizes into a render target.** In an RTX session, 2D draws into a render target from
  `HUDPaint` work as in Direct3D 9 (`render.Clear`, `render.ClearRenderTarget` and an opaque rectangle
  all clear it; moving text leaves no trail). The same 2D draws from `PostDrawOpaqueRenderables` leave
  the target black. A perspective draw (`cam.Start` with a 3D camera) is taken into the path-traced
  scene even inside `HUDPaint`. Dynamic Toolgun Screen's target (`DTScreen_Screen512`, drawn in
  `SWEP:RenderScreen`) is sharp when shown flat on the HUD; on the gun only the path-traced screen is
  seen, whose scrolling text smears under temporal reconstruction.
- **Crash-report prompts.** After a crash the runtime's next start shows "RTX Remix Crash Report"
  (Yes/No, in the Windows language: `はい(&Y)` / `いいえ(&N)` here), and after No may show a notice that
  pending reports could not be removed (OK). `WM_COMMAND` with `IDNO` (7), then `IDOK` (1), answers
  them in any language; the reports folder is emptied when it can be.
- **Field timings.** With 766 subscriptions the Workshop remount took 16.5 s and gm_construct was ready
  23-27 s after launch; the loader's start-up took 0.34-0.36 s.
- **GMod's menu reads generated JavaScript as Windows-1252.** A UTF-8 `·` written into the loader's
  copy of `control.Menu.js` showed as `Â·`, and every translated label as mojibake; `\uXXXX` escapes
  (ASCII only) show correctly in all seven languages (loader 0.10.1).
- **The RTX fixes' late model flush races queued rendering** (PoC, the same game binaries as the
  field, `-windowed 1280x720`, no Workshop mount). `cl_rtx.lua` calls
  `RTX_ReloadModelsAfterHardwareSkinningSettings` (`MDLCACHE_FLUSH_STUDIOHWDATA`) once at autorun and
  once one second after `InitPostEntity`, when the world is drawn. 4 of 8 starts crashed within a
  few seconds of that second flush: access violation reading 0 at `studiorender.dll+0x5d353` on a
  `vstdlib.dll` job thread running the `materialsystem.dll` queued context, `[HWSkin] CRASH in
  DrawGroupHWSkin trampoline!` or `[HWSkin] Exception in RenderFinal trampoline` logged during the
  flush. The fork's SEH guards around those hooks date from upstream (2026-08), so the race predates
  the QoL batch. The field (766 add-ons, 4K) reached the map 14 times without it. `RunConsoleCommand
  ("mat_queue_mode", "0")` from client Lua is accepted, and the material system leaves queued mode at
  a frame boundary after waiting for its thread.
- **Minidumps and the declined prompt.** The dump of a crash is written to
  `rtx-remix\logs\.sentry-native\reports\<uuid>.dmp`; once the next start's prompt is answered No,
  Remix deletes it, so a test harness must copy it before that start.

## The Motion importer tab and the bundled motion importer (2026-10-31, Claude)

- **The part was behind its add-on.** `packages/character-motion-importer` was imported on
  2026-10-30 from `H:\BACKUP_20260815\Modding\ipg\Gmod-Mmd-Motion-Importer`, a clone at 318b054
  (2026-10-07). The add-on's `main` (`origin/main`, and the clone in
  `C:\Users\matt-peng\Documents\Codex\2026-10-17\please-help-me-connect-claude-on\Gmod-Mmd-Motion-Importer`) is at fcd56f4 (2026-10-27).
  7751327 there added the in-game importer: `cl_importer.lua` (1,005 lines: the window, Resolve,
  the job in a coroutine at 12 ms a frame), `cl_import_bake.lua` (1,946: a Lua port of the native
  baker), `cl_import_data.lua` (938: the bundled skeleton), `mmdvmd_import`, the tool's import button,
  and 98 phrases in its eight languages (no Traditional Chinese). 810c0d1 and a03b7af added the
  stage placement and movement options. So the RTX package shipped no in-game importer, and ADR 0049's
  tab could only open the Motion Manager.
- **Line endings.** The add-on's working tree has every Lua file with CRLF (`core.autocrlf`) except
  `cl_camera.lua`, which is LF (40,354 bytes, the size of the blob). The part stores CRLF throughout.
- **Catalogs after the upgrade:** 462 keys in each of the nine (`ar en es fr ja ko ru zh zh-tw`),
  `tools/check_addon_i18n.py` 0 problems.
- **When a creation tab is built.** Sandbox's `gamemodes/sandbox/gamemode/spawnmenu/creationmenu.lua`
  (PoC install) creates a plain `Panel` per tab and, in `timer.Simple(0)`, calls the tab's function,
  parents the returned panel to it and docks it `FILL`: at the start of the session and on every
  `spawnmenu_reload`, not when the tab is first opened. Panels only think while visible, so the motion
  tab builds its content in its first `Think` (as External Models does in `mmdhl/menu.lua`, waiting
  for `mmdhl.CreateLibrary`), which also covers the add-on loading after the companion.
- **External Models' look** (`mmdhl/ui.lua`): text `Color(31,43,58)`, muted `Color(93,109,127)`,
  accent `Color(34,109,185)` (line 4); flat rounded button styles primary, success, warning, danger,
  secondary, tab (lines 27-34, `draw.RoundedBox(4, ...)`, a selected tab filled with the accent); the
  page `Color(246,248,251)` (line 141); the left column `clamp(width * 0.37, 260, 460)` scaled by
  `ScrH()/1080` (line 865). `mmdhl.UI` exports these helpers, but only Model Hotloader uses it; the
  motion importer's light theme copies the colours instead of depending on it.
- **Hooks keyed by a panel.** GMod's `hook.Run` passes a non-string identifier as the first argument
  and drops it once `IsValid` fails, so the builders key their hooks by their root panel: a closed
  window or a rebuilt spawn menu drops them without `OnRemove` (the window still releases its hooks
  and stops the music preview in `OnRemove`, as before).

## R4 release facts (2026-10-31, Claude)

- **GUI Scaler** (Workshop 3495129511, `lua/autorun/client/cl_guiscaler.lua`, the user has it): with
  `guiscaler_only_spawnmenu 1` (its default) it walks the spawn menu's panel tree and, per panel class,
  multiplies `DButton` sizes by `ScrH()/1080 * guiscaler_scale_multiplier` and swaps `DermaDefault`,
  `DermaDefaultBold` and `DermaLarge` for its own scaled fonts; other named fonts stay as they are. It
  marks a processed panel `gScF` and skips one already marked, which is how Model Hotloader's
  `ownScale` opts its resolution-aware panels out. So a tab that sizes itself must mark its subtree, or
  its buttons grow twice while its own fonts do not (the motion importer at 4K before R4-31).
- **The field release runs** (763 subscriptions, 762 mounted, 4K, the user's settings): the map was
  ready 21.6-28.6 s after launch; the four release QA sessions took 6.2-6.3 minutes in all, the PoC's
  4.3. A start right after a publish ran the previous package: GMod fetched the update (1.84 GB)
  during that session, byte-identical to the upload, and the next start deployed it.
- **`steamworks.FileInfo` rounds its numbers to a 32-bit float.** For this project's Workshop items
  (PoC, 2026-10-31) `updated`, `created` and `size` came back rounded to steps of 128:
  `updated` 1793444864 for the 1793444836 in `appworkshop_4000.acf`, `size` 1222846336 for 1222846295
  (Evernight and March 7th; Robin, Guinaifen and the RTX package likewise); `fileid` was 0 and
  `installed` false. Compare such times with a tolerance of one step (`math.frexp`: 2^(exponent-24)).

## Loose glass physics in GMod (2026-10-31, Claude, R5)

Read in the PoC install's shipped Lua and the add-on (`packages/fixes/.../Glass-Rewrite-Remix`) for
[ADR 0061](decisions/0061-loose-glass-breaks-again-and-expires.md):

- **`COLLISION_GROUP_WORLD` collides with the world only.** It is what the No Collide tool's right
  click sets (`gamemodes/sandbox/entities/weapons/gmod_tool/stools/nocollide.lua:76-82`; its text,
  `resource/localization/en/tool.properties:234`: "Make an object have no collisions with anything but
  the world") and the context menu's Disable Collisions (`lua/autorun/properties/collisions.lua:34`).
  The add-on's `rtx_glass_expensive_shards 1` ("collide with everything", the default) put map debris
  and small fragments there; 0 gave `COLLISION_GROUP_DEBRIS`.
- **`COLLISION_GROUP_WEAPON` is GMod's group for props that must not collide with players** ("Don't
  collide with the player": `gamemodes/sandbox/entities/entities/gmod_cameraprop.lua:38-39`,
  `gamemodes/base/entities/entities/ragdoll_motion.lua:52-53`; also `prop_effect.lua:54`). TTT gives
  corpses, "nonsolid to players, but can be picked up and shot", `COLLISION_GROUP_WEAPON` with
  `ttt_ragdoll_collide 1` and `COLLISION_GROUP_DEBRIS_TRIGGER` otherwise
  (`gamemodes/terrortown/gamemode/corpse.lua:368, 392-393`). Traces with `COLLISION_GROUP_NONE`
  (bullets, the physgun, the gravity gun, `+use`) hit these groups.
- **A SENT that defines `OnTakeDamage` reacts to no damage physically.** base_anim's server
  `ENT:OnTakeDamage` is empty (`gamemodes/base/entities/entities/base_anim.lua:57-70`); GMod's own
  entities call `self:TakePhysicsDamage(dmginfo)` in theirs ("React to physics damage",
  `gamemodes/sandbox/entities/entities/gmod_light.lua:46-48`; `gmod_wheel.lua:59`, `gmod_thruster.lua:220`,
  `lua/entities/sent_ball.lua:149-150`). `procedural_shard.lua`'s never did, so bullets and blasts did
  not move shards.
- **`CollisionData.HitObject` is a PhysObj** (no `GetClass`); the entity hit is `HitEntity`. The
  add-on's "two breakable shards do not break each other" test reads `HitObject:GetClass` and never
  matches, so a shard flying into a pane breaks it; its impact mass reads
  `HitObject:GetPhysicsObject`, which does not exist either, so the mass of the other object is always
  1. Both are left as they are (panes' behaviour and the rigidity tuning depend on them); ADR 0061
  adds its own `HitEntity` check for two loose pieces.
- **Clients have no physics copy of a shard.** `BuildCollision` runs on the server only (Split, the
  spawn functions, the tool, `rtx_map_glass.lua`, `OnDuplicated`); the client's `Initialize` calls
  `PhysicsInit` on an entity without a model, which fails. The client `Think` that freezes and pins a
  physics copy (`procedural_shard.lua`) therefore never runs past its first check.
- **The client never defines the crack functions.** `procedural_shard.lua` returns on the client
  right after `UpdateTransmitState` (`if CLIENT then NLP(...) return end`), before `ShowCracks`,
  `UpdateCrackMesh` and `DrawCracks`, so `GLASS_SHOW_CRACKS` finds no `ShowCracks` and no crack is ever
  drawn. Found in R5, not changed.
- **Split sizes.** A split makes `num_radial` (`random(max(2, d-1), d+2)`) plus `num_concentric`
  (`random(d-2, d)`) planes for a depth `d`: 21-26 at the default `rtx_glass_shard_count 12` (a pane's
  first break adds 2-4 to the depth), 3-8 at the loose-piece depth 3. Bounding radius 20 was already
  the size below which a fragment is removed with GlassImpact (`BuildCollision`).
- **Falls.** At `sv_gravity 600` a free fall reaches 300 units/s (a pane's break speed) after 75 units
  and 500 units/s after about 210 (`v^2 = 2gh`); map debris also leaves a window with the damage
  impulse, capped at 350 units/s, plus a random scatter of up to 60 units/s per axis at the default
  velocity transfer 2 (`rtx_map_glass.lua`).

## The night sky line on modern_house (2026-10-31, Claude, R5)

Measured in the field install on `modern_house` with [`night_sky_probe.lua`](../tools/qa/night_sky_probe.lua.md)
and variants (evidence in `out\qa-field\r5-sky\01`-`10`):

- **What it was.** A straight-edged brownish haze over part of the night sky, stars faint inside it and
  crisp outside, and in two views 15-20 s apart the whole scene in daylight. Remix's debug views
  (below) showed no geometry in the sky at all; the haze ran along the edge of the previous view's
  frustum, so it lived in the image's temporal history. Modern House RTX's `MHRTX_Settings` timer
  (20 s, three times, started 3 s after the map: `lua/modern_house_rtx/cl_main.lua:320-328`) re-applies
  its settings, its afternoon sun (`atmosphereSun`) among them; the companion, holding the player's
  night, put it back on its 10 s `nativeloader_sky_owned` timer. Each daylight episode left the
  history. In a tour after the third re-apply, and with the companion following the re-applies, all
  views were clean, clouds on or off.
- **Ruled out on the way:** the night sky image's seams (a CPU render of `evalStarMap`'s three layers
  is seamless), the fixes' Custom 2D Skybox (`rtx_sky2d_enable 0` changed nothing; it draws only with
  the world draw patched out), `r_skybox 0`, Modern House's mirrors, and the clouds' hex de-tiling
  (the haze came with `rtx.atmosphere.cloudHexTilingEnable False` too, and went with it on once the
  re-applies stopped).
- **Sky draws in the physical sky.** With `rtx.skyMode 1` (Numos) `tryHandleSky` drops every draw whose
  camera is Sky (`dxvk-remix-gmod src/dxvk/rtx_render/rtx_sky.h:85-89`); a draw is Sky when it carries
  the Sky category: its colour texture is in `rtx.skyBoxTextures`, its viewport `minZ` reaches
  `rtx.skyMinZThreshold`, or `rtx.skyAutoDetect` classifies it (`rtx_types.cpp:548-626`,
  `rtx_camera_manager.cpp:111-118`). The modern_house skybox `sky_day02_03`'s face hashes (Remix's
  `RemixMaterial.GetTextureHash`): lf `0x3A6D016CA2191AE0`, bk `0xA512403F9F80897C`, ft
  `0x9225497508AC6197`, up `0x5D47E153E359F0B1`, dn `0x24CA07058BAA92B0` (rt returned 0); none is in
  the package's list, auto-detection classifies them.
- **Remix debug views from Lua.** `RemixConfig.SetConfigVariable("rtx.debugView.debugViewIdx", n)`
  switches the view in a session (`GetConfigVariable` keeps returning `rtx.conf`'s value, 0); useful
  indices (`src/dxvk/shaders/rtx/utility/debug_view_indices.h`): 271 primary depth, 277 geometry hash,
  23 albedo, 22 material type, 166 stochastic alpha-blend background transparency, 876 the cloud
  render target (black at night: its radiance is too dim to show).
- **The clouds' temporal smoothing** blends each frame's cloud layer with a reprojected history
  (`rtx.atmosphere.cloudHistoryWeight`, 0.92 by the comments) and drops history that is off-screen or
  not from the previous frame (`src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_sky.slangh:948-1060`).
  Which temporal pass kept the daylight longest was not isolated.
- **The night sky image's galaxy band is wrapped three times** around the sky, so the Milky Way's core
  shows three times (`evalStarMap`); an observation for the runtime, not changed.
- **A start-up crash in NVIDIA's driver**, twice in about sixteen field starts on 2026-10-31: an access
  violation reading `0xffffffffffffffff` in `nvoglv64.dll+0xe622f8`, on a worker thread of Remix's
  `d3d9.dll` compiling pipelines, about 4 s after the device was created, with the same stack both
  times (`out\qa-field\r5-sky\08-night-sky-debug-views` on the package before R5,
  `out\qa-field\r5-release\03-map-glass` on R5's; both reruns clean). Recorded for the stability work.

## R6 T1: verified layer consumers (2026-10-31)

At runtime commit `6f2dbd79`, `src/dxvk/dxvk_options.cpp:36-39` reads Aftermath and
`rtx.enableGpuCrashState` from the same merged `Config`; a search finds no RtxOption declaration
for that crash-state key. It belongs with the diagnostics layer after package copies despite
its `rtx.` prefix. `src/dxvk/dxvk_instance.cpp:353-359` reads `DXVK_AFTERMATH_DUMP_PATH`
and inserts a slash when needed before naming the dump. Remix layer precedence remains as
recorded in R5 proposal 1: `rtx_option_layer.cpp:51-61,671-706` and `rtx_option.cpp:1156-1186`.

R6 T1 implementation follows byte comparisons rather than rounded GiB: 8.5 GiB = 8704 MiB,
12.5 GiB = 12800 MiB. `loader/core/src/performance.cpp` classifies names without consulting the
runtime preset or adapter ordering. `loader/core/src/activate.cpp` chooses I1 tier files only from
records owned by the selected runtime; the existing proxy validation checks every payload record's
size/time before copying. A missing record uses the approved old-package fallback; an advertised
but missing/changed payload is an activation integrity failure, not an excuse to trust a loose file.

Measured in the synthetic Release host on 2026-10-31: DXGI selected NVIDIA GeForce RTX 5090,
32187 MiB dedicated VRAM. Auto was high; explicit low used the pre-R6 fallback and copied the
packaged fixture tier when supplied. `loader/core/src/performance.cpp:46,60` implement selection
and exact thresholds; `loader/core/src/activate.cpp:265,320` select the journal-owned tier and
late diagnostics slot. Two package DXVK copies plus tier, diagnostics and root default total
140 characters (259-character budget). The one-start CREATE_NEW claim is at
`loader/core/src/gpu_diagnostics.cpp:58,63`. The real runtime's effective options and GPU dumps
remain unmeasured by this task; the fixture exercises loader behavior only.

## R6 T4: runtime memory snapshots (2026-10-31)

Source references below are to patch 0015 on the recorded fourteen-patch tree, implemented by
`86ac49e9` in T4's isolated runtime clone. The user's fork checkout was not changed.

- `DxvkSubmissionQueue::handleDeviceLost` (`src/dxvk/dxvk_queue.cpp:407-432`) is shared by the submit
  and fence-finish loss paths. Its single-handler gate allows one snapshot/marker at line 421,
  before the Aftermath wait and Sentry processing. No GPU synchronization is added by diagnostics.
  The earlier `onGpuCrash` recorder/Aftermath wait can precede this snapshot when enabled.
- The VRAM API's collection previously lived in `rtx_fork_api_entry.cpp:864-893`. It now calls
  `RtxMemoryDiagnostics::capture` at line 864. `rtx_memory_stats.cpp:29-57` collects all driver heaps
  and sums DXVK allocations/use and eight categories only across device-local heaps. It does not
  read the render-owned texture table; the API still adds its cache count separately.
- `DxvkAdapter::getMemoryHeapInfo` (`dxvk_adapter.cpp:79-108`) queries physical-device memory
  properties, rather than waiting for GPU work. With `VK_EXT_memory_budget`, budget/use are driver
  values; without it, budget is heap size and usage is DXVK's tracked heap allocation counter.
  Snapshots preserve those semantics and are approximate cross-thread observations.
- `RtxContext::onPresent` (`rtx_context.cpp:919`) polls a device-owned steady-clock schedule, giving
  one sample per cut frame and every five minutes while frames are presented. Camera cuts do not
  reset the periodic deadline (`rtx_memory_stats_data.h:54-78`). A stopped render loop cannot log
  a periodic sample.
- OMM is recreated at cuts (`rtx_scene_manager.cpp:3134-3152`), so its two one-minute warning limits
  belong to the device (`rtx_memory_stats.h`). The next eligible occurrence reports the suppressed
  count; no background thread flushes idle warnings (`rtx_memory_stats.cpp:83-98`).
- The crash marker uses the same `RtxFileSys::Logs` directory as `remix-dxvk.log`, including
  `DXVK_LOG_PATH` (`src/util/util_filesys.h:65`). `rtx_memory_stats_data.cpp:69-95` checks a temporary
  file's write, flush and close, then uses `MoveFileExW` replacement. A failed write keeps the old
  marker; timestamps must be checked by the next-start reader. Logging and file failures cannot
  unwind through `onDeviceLoss` (`rtx_memory_stats.cpp:69-81`).
- The recorded fork tree lacks five unit-test sources that its Meson file names:
  `test_particle_system_schema.cpp`, `test_hot_reload.cpp`, `test_rtx_option_dynamic.cpp`,
  `test_gpu_profile.cpp`, `test_gpu_overrides.cpp`; and `apps/RemixAPI/remixapi_medium_test.cpp`.
  They exist as ignored files in the local fork. Patch 0015 guards these optional targets when
  absent; the clean build no longer consumes unrecorded local test sources.
- The development-only GPU crash trigger is real GPU work:
  `rtx_context.cpp:498-503` dispatches `metaGpuCrash()` after Ctrl+Shift+Alt+G when armed by
  `RTX_ENABLE_CRASH_HOTKEY=1` (`rtx_options.h:1092-1105`). It is compiled out without
  `REMIX_DEVELOPMENT` and was not exercised by T4.
- The fork's `scripts-common/install_file_in_dir.bat:2-12` enables delayed expansion before
  assigning its arguments; `install_usd_plugins.bat` also enables it around paths. A source path
  containing `!` is stripped during unit dependency staging. T4 used literal-path PowerShell
  copies into its own unit build after that helper failed; the resulting 22-test suite passes.

## R6 T5 fixes memory-limit compatibility

- `packages/fixes/files.json` initially attributed the native DLL to an aggregate staging path
  (`out/oversized-native-build`) at aggregate commit `04592ae8`; the actual native source is
  pinned in `packages/fixes/licenses/oversized-skinning/build-pins.json`:
  `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe`. Using the fork checkout's `fc478c06` instead would
  lose the later oversized-skinning fixes. The new import stages the DLL inside its native
  worktree, so its origin records native commit `a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`.
- The source delta from that base is four native files: removal of the module-open call
  (`source/module.cpp`, formerly line 431), a no-op implementation
  (`source/remixapi/remixapi.cpp:1329`), its declaration comment (`remixapi.h:298`) and the Lua
  binding comment (`resource_lua_bindings.cpp:75`). The Lua number checks and `true` result remain.
  The README and a standalone regression are the only other changed files. Full snapshots and
  the commit patch are in [the corresponding source bundle](../packages/fixes/licenses/oversized-skinning/memory-limits/Source.md).
- Baseline and changed builds use the same generated projects, dependency revisions,
  `ReleaseWithSymbols|x64`, MSVC 14.44.35207 and Windows SDK 10.0.26100.0. The 4,848,128-byte old
  DLL becomes 4,847,616 bytes. PE x64 imports/exports match; both rejected-key strings occur in
  the original and rebuilt baseline and are absent from the new DLL. HardwareSkinningHooks.cpp
  matches the preceding source hash exactly; the policy header/test match after CRLF normalization.
- The earlier restricted attempt could not write the original fork's `.git`. Its shared bare clone
  under the task's `out/fixes-origin.git` hosts `r6-no-memory-limits`, with its clean worktree at
  `out/fixes-source`; the resumed run preserves that already-committed source and rebuilt DLL.
  Recursive dependencies were archived from locally available git objects at their pinned
  revisions, without fetching or modifying the original checkout. The new commit is unpushed.

## R6 T5 ToPBR texture compression

- The fixes' `garrysmod/rtx-remix/mods/~gmod_topbr/materials.usda:18-20` marks the flat normal
  texture as `raw`; the roughness reference at `:56-58` does too. A complete reference census
  finds 113 raw references covering exactly 83 files: 33 normal maps and 50 roughness maps,
  no colour maps. `encoding = 0` and all USD files remain unchanged. All source DDS headers
  describe uncompressed BGRA8; retaining RGBA in BC7 avoids dropping any encoded normal channel.
- NVIDIA Texture Tools Exporter 2023.4.0 is already installed with RTX Remix at
  `C:/Program Files/NVIDIA Corporation/RTX Remix/exts/omni.flux.resources/deps/tools/nvtt/nvtt_export.exe`.
  CPU-only, highest-quality BC7 with a linear DXGI tag and gamma/premultiplied mip processing
  disabled produces DXGI 98 for every file. Names, dimensions and the full 816 mip levels match
  the originals. See [conversion arguments and hashes](../packages/fixes/licenses/topbr-bc7/conversion.json).
- DDS bytes fall from 142,869,484 (136.25 MiB) to 35,729,420 (34.07 MiB): 107,140,064 fewer
  bytes, 74.9916%. xz inputs fall from 16,454,204 to 15,000,576 bytes. These are disk sizes;
  resident VRAM and renderer output are unmeasured because T5 may not launch the game.
- Independent Pillow 12.3.0 decoding of all 816 mip levels gives pixel-weighted 8-bit R/G/B RMSE
  0.659/0.655/0.391 and identical alpha. Worst top-mip channel RMSE is 0.957, worst individual
  mip channel RMSE 4.0, maximum single-pixel R/G/B errors 28/29/13. Six offline normal/roughness
  pairs show the same patterns. Evidence is under this task's `out/topbr-bc7` (`manifest.json`,
  `quality.json`, `comparison.png`); [package notes](../packages/fixes/licenses/topbr-bc7/README.md)
  preserve the measurements and integration acceptance cases.
