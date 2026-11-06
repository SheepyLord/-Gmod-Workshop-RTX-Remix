# Research notes

## R20-E: effective upscaling state, 2026-11-06

- R20-Q exposed a gap in E's isolated proof: the merged advancing sky cleared readiness on every
  dirty option. Q measured 14 ready / 65 pending reads normally, 140 / 0 with unrelated writes
  deferred, 10 / 110 after restoration; `sunElevation` caused 536 transitions. A 1/1 request timed
  out after 45 seconds. Source: branch `r20-qa`, `out/r20q/native-readiness.json`.
- Follow-up: `RtxInitializer` registers actual `RtxOptionImpl` addresses from the upscaling preset/FG
  code. `markDirty` passes its address; the store ignores nonmembers. This keeps generic option
  writes independent of rendering subsystems. The new runtime regression uses real
  `readOption`/callback/resolution machinery with controlled sky-like writers; live proof uses
  the merged companion's actual advancing sky.

- PoC: RTX 5090 reports DLSS/DLSS-G/FSR 3 FG support all true. Startup is unready at 04:01:49.660
  and ready after presets at 04:01:52.054. Six in-memory edits read unready first, then effective
  **0/0, 3/0, 1/0, 1/1, 3/2, 1/0** (upscaler/FG). The new module with the old runtime returns nil.
  Both games exit 0 with no Lua/device errors. Evidence: `out/r20e/poc/validation.json`.
- PoC stock still matches ENVIRONMENT.md's original manifests, while the field names newer ones:
  4001/7488132547021413298 and 4002/7341198560151933050 verify 2,877 files / 7,279,873,012 bytes
  before and after. Rollback uses those verified real manifests; all 4,022 copied tree files'
  hashes/timestamps match afterward, with a clean rollback and lock release.

- The fixes' original disk getter is `remixapi.cpp:1111` in the bundled memory-limits source. Runtime
  `src/dxvk/rtx_render/rtx_initializer.cpp:129` applies DLSS/graphics presets later, and `:151`
  resolves their callbacks. The disk getter cannot serve R20-B's startup hint.
- In runtime patch 0040 (`codex/r20-native`), `rtx_fork_game_state.h:26` names the atomic wire value;
  `:46` rejects plugin writes to the runtime namespace; `:54` starts an unready device; `:81` records
  callback convergence. `rtx_option.cpp:356` invalidates readiness on every dirty option, and
  `rtx_option_manager.cpp:244` records convergence before its existing dirty-map clear.
  `rtx_initializer.cpp:184` reads actual DLSS/DLFG/FSR capabilities and both effective enums under
  the option update mutex. Publication runs after initialization and at every present.
- The GPL binding is `upscaling-state/source/remixapi/config_lua_bindings.cpp:69`, registered at
  `:290`. It uses an export lookup and bounded thirteen-byte schema-1 value, with no optional
  interface offset, config read or save. Publisher/reader checks pass with MSVC `/O2 /W4 /WX`.
- Pinned premake drops `!` in generated intermediate paths in this nested worktree. The direct
  module build failed with C1083/D8040; a temporary `subst W:` pointing into this worktree's `out`
  gives correct paths. The unchanged build script then built the 5,515,264-byte module, SHA-256
  `53da14f9269f042869510fe8be56b8b055263acd7c80a54d3e6178dbbfa94e73`.

## R13-F: when a texture loaded during a frame's draws reaches that frame (2026-11-03, Claude)

Runtime source at `403b2336` (patch 0028); the patch, the A/B and its evidence are in the
[R13-F report](handover/R13-F-report.md).

- **Frame order.** The game's draws reach `SceneManager::processDrawCallState`, whose
  `createSurfaceMaterial` calls `trackTexture` and so `RtxTextureManager::addTexture` for every texture
  of the material, every frame it is drawn (`rtx_scene_manager.cpp:1824-1841`, `:2215-2229`). Then
  `RtxContext::injectRTX` calls `submitTexturesToDeviceLocal` (`rtx_context.cpp:658`), which creates each
  ready texture's image and records its copy, before `prepareSceneData` builds the scene and before the
  trace. The texture manager's `garbageCollection` runs after the trace, from
  `copySamplerFeedbackToHost` (`rtx_texture_manager.cpp:1472`). So a texture staged synchronously while
  a frame's draws are processed is sampled whole by that same frame.
- **The synchronous path** (`scheduleTextureLoad(tex, false)` -> `AsyncRunner::queueAdd`, async false)
  stages on the calling thread into `m_synchronousAlloc`, a `DxvkStagingBuffer` of 4 MiB whose larger
  requests each get their own host-visible buffer (`dxvk_staging.cpp`); it is freed once the copy
  retires. It does nothing for a texture already `kQueuedForUpload`.
- **A purge is explicit only.** `purgeResidentTextures` (which makes `addTexture` reload a pinned
  preload whole at its next draw) runs for the menu's free-texture buttons, the Remix API's
  `RequestTextureVramFree` and a resolution change with `rtx.reloadTextureWhenResolutionChanged`
  (`rtx_scene_manager.cpp:3660`, `rtx_context.cpp:329`), not at a map change. No add-on in the package
  calls the API (the fixes' `ForceCleanup` wraps it, unused from Lua).
- **Measured, patch 0030 (as 0029 on 0028) on the PoC** (3840x2160, Samsung 980 PRO NVMe, files in the
  file cache):
  staging a character's whole maps on the render thread took 101-201 ms for 313-529 MB (2.3-3.1 GB/s).
  The frame that drew the character first lasted 112-324 ms. Replacement-texture bytes changed once,
  one game frame after the hotloader's presentation, by the character's whole maps.
- **The hotloader's own first-spawn freezes**, with either runtime: two consecutive frames of
  0.8-1.3 s about 110-145 frames (two seconds) before Robin or Evernight appears, two of 0.2-0.3 s
  for Guinaifen, while it loads the model; then two or three frames of 60-100 ms at the presentation.
- **Cold reads.** Through a file mapping, with every byte copied out as `packImageData` does, copies
  made with `xcopy /J` (unbuffered, so not in the cache) read at 0.69-0.89 GB/s against 1.34-1.39 GB/s
  from the cache (Python's copy): 0.4-0.7 s per GB more on that drive (`r13-f/cold_read.py`).
- **The three character packs** hold 170 preloaded textures, 2.38 GB; drawing all four characters
  loads 111 of them (1.66 GB). The other 59 (0.72 GB) belong to parts the probe's scenes never draw
  and stay at their tails.

## R13-D: the option crash, proven (2026-11-03, Claude)

The R13 integration notes below record the crash. Its cause is now proven, and runtime patch 0029
fixes it ([R13-D report](handover/R13-D-report.md)).

- **What the dump's registers say.** `RtxOptionImpl::resolveValue+0x3e` is
  `mov edx, dword ptr [rcx+50h]` (0028 build, RVA `0x1b7dfe`), which reads `m_type`.
  `RtxOptionImpl` lays out its vptr, `minValue` and `maxValue` (`std::optional<GenericValue>`, 16
  bytes each), `m_hash`, `m_name`, `m_category`, `m_environment` and `m_description` first, so
  `m_type` is at `0x50`, and `m_resolvedValue` at `0x58`.
  - The crash had `rcx=rdi=0` (`this`), `rdx=r14=0x58` (`&m_resolvedValue`) and `rbp=r8=0` (no
    excluded layer).
  - So `applyPendingValues` resolved a dirty-map entry holding `nullptr`.
  - That map is an `std::unordered_map` (`fast_unordered_cache`), and `markDirty()` is
    `getDirtyOptionMap()[m_hash] = this`. `operator[]` links a node holding a value-initialized
    `nullptr` before `this` is stored in it.
- **Who wrote it without the lock.** `remixapi_SetConfigVariable` (`rtx_remix_api.cpp:1776`) calls
  `readOption` (`rtx_option.cpp:448`) holding only the API's `s_mutex`. `readOption` inserts into
  the option's layer values and calls `markDirty()`, while the render thread's `applyPendingValues`
  walks the map under the update mutex.
  - The companion's sky calls `RemixConfig.SetConfigVariable` every `nativeloader_sky_interval`
    (0.02 s by default, `nativeloader_sky.lua:27`) for each changed sun, moon and star value (lines
    453-461).
  - The fixes' binary logs nothing per call: the crashed session's console has no such line.
- **Threads.**
  - The Remix menu draws on the game's thread: `ImGUI::render` is called from
    `D3D9SwapChainEx::PresentImage` (`d3d9_swapchain.cpp:1297`), inside `Present`.
  - Graph components (`RtxOptionLayerAction`, the only runtime caller of
    `acquireLayer`/`releaseLayer`) initialize, update and clean up on the render thread:
    `SceneManager` -> `m_graphManager.update(ctx)` (`rtx_scene_manager.cpp:707`). No mod in the RTX
    package has graph prims.
  - onChange callbacks run on the render thread after `applyPendingValues` has released the update
    mutex.
- **Reproduced.** A unit test that calls `readOption` on one thread while another loops
  `applyPendingValues` crashes the 0028 code within 1.3-2.1 s (3 of 3 runs). A crash caught by
  attaching a debug loop is the field crash: an access violation reading `0x50` at
  `resolveValue+0x3e` (`rtx_option.cpp:1151`), with `rcx=rbx=rsi=rdi=rbp=r8=0` and `rdx=r14=0x58`.
- **Reproduced in the game** (PoC, gm_construct, R13's settings; `out/r13-d` in the
  `r13-option-lock` worktree). On the published runtime (`91f0696c`), Lua's
  `RemixConfig.SetConfigVariable` at 250 calls per Think plus 250 in each of two render hooks, frame
  rate uncapped, crashed it within 10 s with the field signature:
  - `d3d9.dll+0x1b7dfe` = `resolveValue+0x3e`, reading `0x50`;
  - `applyPendingValues+0x2b9` on the stack.

  The same writes at the 60 fps cap from Think alone (3.3 million in 220 s) did not crash it.
  Capped, the game's thread mostly sleeps while the render thread ends the frame, so the two seldom
  overlap. Patch 0029 took the uncapped load: 21 million writes in 220 s, normal quit.
- **Lost writes.** `applyPendingValues` released the update mutex between passes even with no
  callback to run, and its final "Don't let dirty options persist across frames" clear came after
  another release. A burst of writes from another thread could keep it going to `maxResolves` (4),
  and the clear then dropped the newest marks. The write took effect only when the option was marked
  again. The test caught it in round 313 and round 208 of 500 with only the locks fixed.
- **The minidump holds no heap.** R13's Sentry dump has only thread stacks: `d3d9.dll`'s data and
  the heap are not in it, so the dirty map's nodes could not be read. `out/r13/verify/dirty_map.py`
  (what the registers point at), `symaddr.py` (a function's RVA from a PDB) and `catch_crash.py` (a
  Win32 debug loop that catches a test's first access violation, launching or attaching) are with
  R13's tools in the main checkout.

## R13-P: how a streamed replacement texture reaches its mips (2026-11-03, Claude)

Runtime source `out/worktrees/r12-vram/out/runtime-src` at `403b2336`; the A/B and its evidence are in
the [R13-P report](handover/R13-P-report.md).

- **A material's sampler-feedback stamp is its first replaced texture**, in the order albedo,
  roughness, metallic, secondary, normal, tangent, height, emissive (`trackTexture`,
  `rtx_scene_manager.cpp:1824-1841`, called at `:2215-2229`). The others are associated with it, at most
  8 per stamp. A material that keeps the game's albedo (ToPBR's game maps, 54 of `ai_pbr`'s 219
  materials) still gets feedback through its roughness, metallic or normal map.
- **Feedback** is written only in the primary and PSR passes (`RAY_TRACING_PRIMARY_RAY`,
  `opaque_surface_material_interaction.slangh:727-740`). It is the mip level a pixel needs, measured
  against a fixed 4096 texture (`:443-455`), kept with an atomic minimum per stamp. The host reads the
  previous frame's copy (`rtx_texture_manager.cpp:1448-1474`) and turns it into a count of mips: the
  owner's mip count minus that level, given to the associated textures too (`:1500-1561`). An owner
  smaller than 4096 therefore asks one level too few per halving. The largest count seen is kept until
  budget pressure (`:1563-1588`).
- **An undrawn streamed texture drops to its tail at once**: `garbageCollection` requests 0 mips for a
  demotable texture no instance holds (`:1676-1682`), and the DDS loaders keep a five-mip tail
  (`kMipLevelsToCache`, `rtx_asset_data_manager.cpp:35`, `:354`). Removing four characters freed 1.39 GB
  within about 105 ms. Anti-culling keeps the instances of characters the camera turns away from
  (`rtx.antiCulling.object.enable`), so turning away freed nothing.
- **Load path**: one lowest-priority thread memory-maps each DDS, copies the requested mip range into a
  96 MiB staging ring and hands at most 32 textures per frame to the render thread
  (`rtx_texture_manager.cpp:472-706`, `:1051-1085`).
- **Measured on the PoC** (3840x2160, NVMe, warm file cache): a streamed character's first upgrade
  arrived 2-5 frames after it was first drawn, and the last 155-880 ms after it (251-464 MB per
  character). The PoC's three character packs (2.22 GB) preloaded cost 2.23 GB of replacement textures,
  1.64-1.71 GB of driver VRAM and 1.70 GB of private bytes at idle, with an unchanged working set.
- **Mod precedence for a material defined twice**: `getReplacementMaterial` returns the first mod's
  (`rtx_asset_replacer.cpp:110-121`), and mods sort by fallback priority, then path
  (`rtx_mod_manager.h:130-140`). In the field `ai_pbr` therefore wins over the `pbr_*` packs, whose
  copies of the same files are preloaded anyway.

## R13 integration: per-profile memory, an option crash, Steam Cloud (2026-11-03, Claude)

- **Per-profile memory with the final package** (PoC, 1920x1080, gm_construct, the copied field
  library of 98 saved NPC/player rigs, no Workshop add-ons; `remix.memory_profile` set on the 32 GB
  card; `out/r13/int/final-*` in the `r13-int` worktree). Private / working set / driver VRAM:

  | Profile | Idle | Four characters spawned | Peak |
  |---|---|---|---|
  | minimum (low tier) | 9.2 / 3.5 / 5.6 GB | 12.8 / 4.9 / 7.7 GB | 12.8 / 5.0 / 7.7 GB |
  | recommended (medium tier) | 11.7 / 5.7 / 5.8 GB | 15.3 / 7.2 / 7.9 GB | 15.7 / 7.2 / 8.3 GB |
  | high (auto) | 15.1 / 9.1 / 5.9 GB | 18.8 / 10.6 / 8.0 GB | 22.5 / 10.7 / 11.6 GB |

  The PoC's own Remix mods preload 2.5-2.7 GB of replacement textures in every profile. A plain
  Combine soldier after the four were removed raised game textures 2.44 -> 2.66 GB (minimum), 2.49 ->
  3.07 GB (recommended) and 2.49 -> 6.36 GB (high); only the minimum exceeded its budget (2 GiB) and
  came back under it: 2,770 CPU copies and 48 images released, 42 re-uploads on later use
  (`[RTX Managed Textures]` lines).
- **First spawns from the NPC tab:** 阮·梅 R18 (about 1.2 GB of game textures) 4.0 s when ready
  (recommended, high), 6.0 s cold (minimum); other characters 0.5-2.1 s; a loaded character again
  0.04-0.07 s.
- **An intermittent crash in Remix's option system.** One recommended/medium session (runtime
  `0c20772f`) ended about 15 s into idle with an access violation reading 0x50 on the render thread:
  `RtxOptionImpl::resolveValue+0x3e` (`rtx_option.cpp:1151`) <- `updateResolvedValue` <-
  `RtxOptionManager::applyPendingValues+0x2b9` (`rtx_option_manager.cpp:196`, iterating the dirty
  option map under `getUpdateMutex()`) <- `RtxContext::injectRTX+0x2729` (a heuristic stack from the
  Sentry minidump, symbolized with dbghelp against the build's PDB). The main thread was waiting on the
  same mutex. The repeat and seven other sessions ran cleanly. Candidate (R13-B, unproven):
  `acquireLayer`/`releaseLayer` change every option's layer list under the layer mutex only. Tools:
  `out/r13/verify/read_dump.py`, `stack_scan.py`, `threads_scan.py`, `symbolize.py` in the main
  checkout; the Python `minidump` package reads the dump.
- **Steam Cloud carries a PoC session's settings to the field game** (R13-A found it): GMod reads
  `Steam\userdata\<account>\4000\remote\cfg\config.cfg` at start and writes it at its quit, one copy
  for every install. After R13-B's sessions with `+fps_max 60` the cloud copy differed from the
  field's `config.cfg` only in `fps_max` (60 against 300). After sessions that execute the field's
  `config.cfg` and `host_writeconfig` before the quit (now every `poc_session.py` run), the two were
  byte-identical (`0ebf6a15`).
- **The field game after R13** (loader 0.13.0, high profile, gm_construct, 3840x2160, 767 Workshop
  subscriptions; `out/r13/field/05-r13-steady`, main checkout): working set 10.86 GB idle and 11.17 GB
  with two characters (R12 baseline 17.98 and 18.47 GB); private bytes 27.23 GB idle (28.70 GB);
  the Combine trigger +5.43 GB of game textures, driver 22.4 of 32.95 GB. Replacement textures
  10.27 GB (R12 baseline session 4.05 GB; the user's R12 session in the lag report 10.3 GB). They are
  the user's preloading mods: the field's mods preload 11.05 GB of files (R13-B), ToPBR's published
  `~gmod_topbr` references 1.22 GB of game maps (8 preloading materials), and on the PoC the R12 and
  R13 runtimes hold the same replacement textures for the same content (2.68 GB idle). Private bytes
  count the VRAM the driver maps into the process, so the working set is the RAM measure here.

## R13-B: where the runtime's host memory goes, and the texture budget (2026-11-03)

Read from the runtime fork at `fc62f44f` (patches 0001-0022) and measured on this machine (RTX 5090,
driver Vulkan memory: heap 0 device-local with type 1 `DEVICE_LOCAL` and type 4
`DEVICE_LOCAL|HOST_VISIBLE|HOST_COHERENT` (resizable BAR); heap 1 system with type 2
`HOST_VISIBLE|HOST_COHERENT` and type 3 `HOST_VISIBLE|HOST_COHERENT|HOST_CACHED`).

- **Chunks.** DXVK sub-allocates device-local memory in 320 MiB chunks and every other type in
  128 MiB chunks (`dxvk.deviceLocalMemoryChunkSizeMB` / `dxvk.otherMemoryChunkSizeMB`,
  `dxvk_options.cpp:64-65`; `pickChunkSize`, `dxvk_memory.cpp:722-748`); a request of a chunk's size or
  more, or one the driver prefers dedicated, gets its own memory object (`tryAllocFromType`,
  `:555-568`). Host-visible memory objects are mapped for their whole life (`tryAllocDeviceMemory`,
  `:653-661`).
- **Texture CPU copies.** Every managed-pool texture keeps one buffer per mip in
  `HOST_VISIBLE|HOST_COHERENT|HOST_CACHED` memory (`D3D9CommonTexture::CreateBufferSubresource`,
  `d3d9_common_texture.cpp:214-240`): type 3, mapped read-write. A 4096-square A8R8G8B8 mip 0 (64 MiB)
  shares a 128 MiB chunk; an 8192-square one (256 MiB) or the 11059x8847 one (391 MB) is a dedicated
  allocation, the 268.4 MB and 391.4 MB blocks of the field's idle census.
- **Write-combined private memory is mostly VRAM.** The NVIDIA driver maps the process's device-local
  allocations into its address space as committed `PAGE_READWRITE|PAGE_WRITECOMBINE` private memory, and
  they count in its private bytes (commit). The GPU probe's census: 2.03 GB write-combined committed, of
  which DXVK's own mappings (type 2 staging chunks and the type 4 chunk) were 0.60 GB; releasing four
  89.5 MB images (358 MB) lowered write-combined commit and private bytes by 358 MB while read-write was
  unchanged. Releasing their CPU copies lowered read-write commit by 402 MB. So the field's 11.0 GB of
  write-combined memory is the game's VRAM in use plus DXVK's staging, and it holds system commit.
- **The replacement texture budget** (`calcTextureMemoryBudget_Megabytes`,
  `rtx_texture_manager.cpp:1817-1873`) is `rtx.texturemanager.budgetPercentageOfAvailableVram` (50 %) of
  the free VRAM plus what replacement textures hold, the free VRAM being the device-local heap's driver
  budget minus the process's usage (less DXVK's free chunk space), or `fixedBudgetMiB` when
  `fixedBudgetEnable`; a 2 GiB reserve applies before Remix's resources exist. It is recomputed in every
  ray-traced frame's garbage collection (`garbageCollection`, `:1563-1648`), so it follows the driver's
  live budget. Textures bound to instances are kept at the mip count sampler feedback asked for, best
  first, while they fit; the rest are demoted to their 5-mip tail (`kMipLevelsToCache`,
  `rtx_asset_data_manager.cpp:35`; `requestMips` clamps to at least one mip, `rtx_texture.cpp:189-198`).
  Unbound ones stay at the tail. Textures too large for the 96 MiB staging ring, sky textures and
  USD materials with `preloadTextures` are never demoted. The Remix menu's "Texture Streaming" section
  sets a fixed budget up to 32 GB or the percentage from 10 to 100 % (`dxvk_imgui.cpp:4869-4912`),
  saved in `user.conf`: a fixed budget does not follow the driver at all.
- **Preloaded replacement textures are pinned for the session.** A USD shader's
  `inputs:preload_textures` makes `preloadTextureAsset` create the texture with `m_canDemote = false` and
  every mip requested (`rtx_mod_usd.cpp:677`, `:731-757`; `rtx_texture_manager.cpp` `preloadTextureAsset`);
  `requestMips` then forces every mip (`rtx_texture.cpp:188-197`), and both lists of the budget pass and
  `manageBudgetWithPriority` take only `m_canDemote` textures. The texture is created when the mod loads,
  before anything is drawn, and `m_assetHashToTextures` and the sampler-feedback table keep it for the
  session, also after a USD reload leaves no material referencing it. Only the explicit purge
  (`requestTextureVramFree`, the fixes' `rtx_flush_textures` and their map-exit purge) drops its image,
  and it comes back only when drawn. Remix keys replacement textures by file path
  (`rtx_asset_data_manager.cpp:85`), so the same file under two mods is loaded twice. Who sets the flag:
  rpai on every material (`skills/mmd-remix-pbr/tool/rpai/usda.py:61`), the material editor by default
  (`sh_36_rtx_schema.lua:159`), the fixes' ToPBR for game maps (R13-M), `gm_poolrooms_rtx`, `rtx_water`,
  `blood_overhaul_rtx`.
- **"Drawn" for a replacement texture** is its `m_refCount`: every texture index of a bound material is
  retained by the instance (`SceneManager::retainSurfaceMaterial`, `rtx_scene_manager.cpp:1720-1754`)
  and released when it goes, and Remix destroys an instance one frame after its last draw
  (`rtx.numFramesToKeepInstances` = 1, `rtx_options.h:698`). The non-sampler-feedback list already uses
  it: unbound demotable textures drop to their smallest mip (`garbageCollection`).
- **Preloads measured** (`out/r13-b/preload_survey.py`, read-only): the field's mods preload 889 files,
  11,048,853,372 bytes (`ai_pbr` 8,496,386,704 in 219 shaders; `pbr_evernight_march7th`,
  `pbr_guinaifen`, `pbr_robin` 2,220,023,384 bytes with the same file names and sizes as `ai_pbr`'s
  folders for those characters; `blood_overhaul_rtx` 171,647,308; `gm_poolrooms_rtx` 149,599,544;
  `rtx_water` 11,196,432). The lag report's replacement textures were 10,320 MiB, the files 10,537 MiB.
  The PoC's mods preload 170 files, 2,380,819,360 bytes; its census at idle on gm_construct, with no
  character spawned, held 2,425,102,336 bytes of material textures in 691 images.
- **The lag trigger in numbers** (PoC, copied field library, 1920x1080, `out/worktrees/r13-runtime/out/r13-b`):
  a plain Combine soldier raised game textures 0.96 -> 17.08 GB and private bytes 28.27 -> 43.69 GB on
  the original runtime, which kept them (`b3-orig-1080`). Patch 0027's counters: all 1,128 new images
  came from the draw path (`UploadManagedTextures` from `PrepareTextures`), none from `PreLoad`, a
  sampling view, a flushed upload or mip generation; the same draw burst (1,064 images, 16.91 GB)
  happens once while the map loads, before Source destroys those textures and loads them again (the
  start-up peak of 40.7 GB private bytes). The burst raised write-combined commit by 15.36 GB.
- **The review's defects, reproduced** (GPU probe, `out/worktrees/r13-runtime/out/r13-b/probe-pre0028`,
  runtime `0c20772f` with patches 0023-0027): with a 1 MiB budget a second thread reading
  `dxvk_GetTextureHash` while images were released got wrong hashes (`ReleaseManagedImage` moved the image
  out before it wrote the released hash, `d3d9_device.cpp`); with CPU copies released a
  `D3DLOCK_NO_DIRTY_UPDATE` write was lost after idle passes (`FlushImage` uploads only the dirty box,
  and `ReleaseIdleHostCopies` checked only `NeedsAnyUpload`). Patch 0028 passes both, about 1.2 billion
  hash reads per run without a wrong one (`probe-0028`).
- **The terrain baker does not retain what it samples:** it tracks its source textures through
  `SceneManager::trackTexture` every frame it bakes (`rtx_terrain_baker.cpp:144-178`), so their
  instance reference count stays 0, and the baked instance binds the baker's own material
  (`rtx_context.cpp:2868-2875`). `RtxTextureManager::addTexture` is the one path every consumer takes.
- **An intermittent option crash** (an access violation reading 0x50 in `RtxOptionImpl::resolveValue`,
  `rtx_option.cpp:1151`, under `applyPendingValues`; one integrated PoC session, not reproduced): the
  dirty-option loop of `RtxOptionManager::applyPendingValues` holds only the update mutex, while
  `acquireLayer` and `releaseLayer` (`rtx_option_manager.cpp`) hold only `s_layerMutex` as they insert into
  and erase from every option's layer queue (`readOptionLayer`, `disableLayerValue`) and call
  `markDirty()`, which writes the dirty map without a lock (`rtx_option.cpp:355-357`). A layer acquired or
  released on another thread during that loop (the graph's option layer actions,
  `graph/components/rtx_option_layer_action.h:104-127`) would corrupt the queue `resolveValue` iterates.
  A candidate, not proven: the dump showed no such thread at the crash.
- **WDDM and a VRAM hog:** with 25.8 GB of render targets held (and cleared twice a second) by another
  process, the foreground game's `VK_EXT_memory_budget` budget fell from 32.95 only to 26.15 GB, its own
  usage at the time (26.14 GB); the hog's budget fell to 6.9 GB and its memory was paged. A background
  process does not create real pressure for the game on this computer.
- **DXVK chunk space after a release:** after the minimum profile released 14.7 GB of the burst's
  images, the device-local chunks held 9.14 GB with 5.32 GB used (a chunk is freed only when empty), so
  the driver's usage stayed 3.7 GB above its level before the burst; releasing the large dedicated
  images instead (the default budget) stranded nothing.
- **Remix holds game textures** in its texture cache (one slot per image view) until the scene is cleared
  (a map change or an explicit cleanup) or the D3D9 texture is destroyed
  (`releaseApplicationReleasedTextures`, `rtx_texture_manager.cpp:1191-1217`, frees an
  application-released image's slot once no bound instance samples it; no other path frees a game
  texture's slot). An image drawn once therefore stayed referenced until the next map even if Source
  never drew it again; R13-B's release marks the image application-released for that reason.

## R13-M: compact imported game maps and reuse across versions (2026-11-03, Claude)

- **What Remix samples from each map.** Roughness and metallic read only `.x` and the octahedral
  normal only `.xy` (runtime fork `src/dxvk/shaders/rtx/concept/surface_material/opaque_surface_material_interaction.slangh:863`,
  `:908`, `:927`), so BC4 (one channel) and BC5 (two) carry everything the uncompressed maps did.
  The fixes' octahedral encoder writes B = 0 and A = 255 (`source/material_pipeline/to_pbr/vtf.cpp:253-256`).
- **Remix's DDS reader.** `rtx_asset_data_manager.cpp:123-194` parses DX10 headers through gli's
  format table, sizes each level in whole blocks (`max(1, ceil(w/4)) * max(1, ceil(h/4)) * block`),
  needs `DDSD_MIPMAPCOUNT` for more than one level and holds at most 16 levels. It maps a DDS with
  `FILE_SHARE_READ` only (`:286-295`): while Remix streams a file, nothing can replace, rename or
  delete it, so migrated maps are written under new names.
- **Sizes, 2048x2048 with a full chain:** uncompressed 22,369,748 bytes, BC5 5,592,580, BC4
  2,796,364. A family was normal + roughness + metallic + AO = 89,478,992 bytes on disk, of which
  Remix loaded 67,109,244; now 11,185,308 for both. Emission (22,369,748) is unchanged.
- **The field cache (read only, 2026-11-03):** `rtx-remix/mods/~gmod_topbr/textures` holds 384 files,
  4,567,891,854 bytes; 301 are imported game files (4,425,021,500 bytes of DDS). 58 families are
  finished (27 `r11-game-v5`, 31 `r12-game-v7`); `game_991AF3B052DC62B2` stopped after its metallic
  map (no marker), as the bug report found. 49 AO maps hold 886,402,452 bytes that nothing reads.
  17 families (29%) have an emission map, 308,982,548 bytes; half of those maps light at most 1.1% of
  their texels (median lit fraction 0.01091, `out/r13-m/emission-field.json` in the R13-M worktree).
- **The shipped key formulas check out against real data.** For all 12 converted families of 洛茜,
  阿芙2.0 and endminf, the v7 formula (and for endminf's three families also v5) finds the field's
  finished family; every stored base level equals today's conversion of the same inputs, and the
  R13-M uncompressed writer reproduces those files byte for byte (`game_dds_probe`, `out/r13-m/probe-field-2.log`).
  v5 keys hash the present maps without role tags or layout, so the same bytes can belong to a
  different layout: v5 chose Silver for every family in a folder holding any `*_MRA` file.
- **BC4 encoder quality on real maps** (field files, 1,500-20,000 sampled blocks, 8-bit RMS):
  min/max endpoints give normal maps 4.44/2.79/3.28; with least squares 3.96/2.44/2.96; the
  exhaustive optimum is 3.50/2.13/2.63, and restricting it to the per-texel bound changes it by
  under 0.02. Quantized roughness is the outlier: least squares 1.12, optimum 0.54, because its few
  levels lie on a palette whose endpoint extends past the data (for example {65, 118, 170} on
  r0 = 249, r1 = 65). Aligning the block's minimum and maximum to two palette positions for blocks of
  at most four levels reaches 0.53 at about 1.7 us per block; on normal maps it would cost 5x for 1%.
- **Real maps after R13-M** (`game_dds_probe`, three characters, 12 families, every block within
  (max - min) / 14): normal RMS 0.27-3.30, roughness 0.12-1.20, metallic 0-1.18 (8-bit units);
  conversion with encoding 0.44-2.90 s per family. Disk 945,122,708 -> 145,408,760 bytes; what Remix
  loads 732,609,912 -> 145,408,760 bytes.
- **Remix debug views for these maps** (`src/dxvk/shaders/rtx/utility/debug_view_indices.h`):
  25 roughness, 16 shading normal, 94 primary base reflectivity (raw; metals show their albedo),
  set with `RemixConfig.SetConfigVariable("rtx.debugView.debugViewIdx", n)`.
- **PoC, the same three characters (high tier, 1280x720, gm_flatgrass; `out/r13-m/poc`):** spawning them
  with the shipped uncompressed maps raised Remix's replacement-texture bytes (`usedMaterialTextureBytes`)
  by 732,669,952, within 60 KB of the files' sum; with R13-M's compact maps by 139,901,952 (the
  compact files new to that session, predicted 139,816,228).
- **Remix preloads a previous session's game maps at startup.** Game-map materials carry
  `preload_textures = 1` (`usda.cpp:350-357`, so generated normals do not stay at their smallest mip).
  Before any character was drawn, the session after the uncompressed run already held 705,814,528
  more replacement bytes than a clean start (the published normal/roughness/metallic maps; emission
  loads when drawn), and still held them after ToPBR replaced the USD and its characters used new
  files. After a compact run the startup surplus was 118,640,640 bytes. So every map of every
  character the last session published is resident from the next start until the game exits.

## R13-A: what loads a saved character, and when (2026-11-03, Claude)

- **Map start loaded every saved character.** `sharing.lua`'s `InitPostEntity` registered each
  approved citizen/combine/player rig through `ReadyActor` (`actors.lua:88-103` before R13-A):
  mount the material archive and carrier, then `util.PrecacheModel` and `util.IsValidModel` on the
  server. Precaching loads the model, its materials and its textures. On the copied field library
  (57 characters; 98 loadable saved NPC/player rigs of generator 30-31 across 55 characters; 20.5 GB
  of material archives) the PoC at 1920x1080 held, with nothing spawned: private bytes 27.0 GB,
  working set 20.9 GB, game textures on the GPU 0.29 GB (patch 0022 defers their GPU images).
- **Carrier spawn icons are empty.** A carrier has no visible mesh: every engine spawn icon of a
  hotloader carrier in the field's `materials/spawnicons/models/mmd/<16 hex>/` is a 215-byte PNG. The
  PoC's Player Model window drew one for each of 7 saved player models (it writes them to
  `garrysmod/materials/spawnicons`), loading each model to do so.
- **Sandbox precaches before `SetModel`.** The base player class runs `util.PrecacheModel(modelname)`
  then `self.Player:SetModel(modelname)` (`gamemodes/base/gamemode/player_class/player_default.lua:71-72`);
  `InternalSpawnNPC` sets an NPC-list entry's model before `Spawn` (`sandbox/gamemode/commands.lua:481-485`).
- **The native module's name records date the last use.** `registerShortName` rewrites
  `names/<kind>/<short>.json` on every call (`native/assets.cpp:132-137`): `PrepareCarrier` (cached or
  packaged, `module.cpp:482`, `rig.cpp:487`) rewrites `names/rigs/<key>.json`, `loadAsset` /
  `prepareSourceMaterials` rewrite `names/assets/<id>.json` (`assets.cpp:217-220`, `:472`). A map start
  also rewrites `approved.json` (`sharing.lua`'s `ForgetPublishedAssets`, even with nothing missing),
  and so does a hotloader spawn that publishes a new entry (`PublishActor` → `PublishRig`). The
  field's writes of `names/assets` (02:41:07, 02:41:10) and `approved.json` (02:41:16) before the lag
  report's jump are what the PoC's hotloader spawn as a Combine soldier wrote (run 09).
- **The lag trigger: the first Combine soldier makes every loaded texture GPU-resident.** On the
  current package with the copied library (every saved character precached, game textures 0.29 GB),
  a stock `gmod_spawnnpc npc_combine_s` raised game textures to 17.07 GB and private bytes from 26.96
  to 43.31 GB between two frames 1.4 s after the command, with no hotloader call in between (R13-A
  run 19, per-frame trace on `SysTime()`). A character spawned as a Combine soldier from the hotloader
  does the same (run 09: 1.54 → 17.12 GB). With only the ready set loaded (R13-A, high profile, 10
  characters with 4.8 GiB of archives) the same soldier raised them 0.30 → 5.32 GB (run 20). None of
  these raised game textures: the catalog broadcast, the hotloader window's preview, the NPC tab, the
  Player Model window, NPC-tab and player-model spawns, a manhack attacking for 25 s, an archive
  mount, a ragdoll new fit, a citizen new fit, a map change, a reload of the map,
  `mat_reloadallmaterials`, `mat_reloadtextures` (runs 08, 09, 13, 19, 20). No packaged Lua names
  Combine soldiers or reacts to one in a way that loads materials.
- **The part of the Combine soldier that does it is `item_ammo_ar2_altfire`.** Every
  `npc_combine_s` precaches that item with `item_healthvial` and `weapon_frag`. Spawned one at a time
  on the current package (R13-A run 21), a Metro Police officer, a citizen with an AR2, a frag
  grenade and a health vial left game textures at 0.29 GB; the AR2's alt-fire ammo item raised them to
  17.07 GB (private 26.89 → 43.44 GB) within two seconds. A soldier that never dropped one did it
  too (run 19), so its precache does, not a draw. The item's precache loads its model
  `models/items/combine_rifle_ammo01.mdl` and, as recalled from the Source SDK 2013 code (not
  checked here), the `combineball` particle system; `mmd_lazy_session.py --sequence ammo` splits them.
- **GMod keeps `cfg/config.cfg` in Steam Cloud.** A game takes
  `Steam\userdata\<account>\4000\remote\cfg\config.cfg` at start (the PoC's local `config.cfg` was
  rewritten with the cloud copy seconds after a launch) and writes its settings back at its quit, so
  a PoC session's last settings reach the field game at its next start. After R13-A runs 08-13 the
  cloud held `cl_playermodel "kleiner"` (the measure sequence's reset) and `fps_max "60"`
  (`mmd_reimport_session.py` sends it), against the field's own `"Bai Mei"` and `300`; a player
  model chosen in run 08 was the player's model at the start of runs 10 and 11 although each run
  restored the PoC's local `config.cfg`. Executing the field's `config.cfg` and `host_writeconfig`
  before the quit leaves the cloud copy byte-identical to the field's (R13-A runs 09 onwards).
- **The native module needs `textures/<sha256>.png`.** `loadAsset` reads an asset's PNG textures to
  build it for spawning and presentation; the main session's field-cache copy has none, so a spawn
  failed with `Cannot read ...textures\<hash>.png` until the 546 PNGs its manifests name (1.35 GB)
  were added to the test copy. The native module keeps at most 8 loaded assets (`module.cpp:240`).
- **The game cuts a printed line at about 4 KB** (a 4,011-character `R13A_ENTRIES` line was cut);
  probes print one JSON object per line.
- **Intermittent PoC start crash:** two of the first eight launches (runs 03 and 06, each within a
  minute of another game's exit) stopped at the main menu with `0xC0000005` in
  `nvoglv64.dll+0xe622f8` (reading address 0 / 0xffffffffffffffff), as R12-C's `07` control
  (`+0xe6230a`). With a 45 s pause before launching, none of the later launches crashed; no hotloader
  code had run.
- **What a used character keeps after removal.** Source keeps its model, materials and textures until
  the map changes (no unprecache). The fixes' `rtx_flush_textures` (`UncacheAllMaterials`, then a
  renderer purge) released 2.2 GB of game textures and 20 GB of private bytes in the current package
  (run 12); with R13-A it released the CPU copies (private 19.74 → 14.79 GB) while 2.5 GB of game
  textures stayed until the map changed (run 16). The next map loads none of them unless they are in
  the ready set.

## R12-A: retained carrier archive versus metadata (2026-11-03)

- PoC copy of the user's Endministrator imports as `a9c7045d38634d1d0469733b152022f5a6d47a161dffafbf0c8688d0ffd23ab3`.
  A saved NPC carrier `5dba2333854dc362c0fc5f85f3fced0d`, deleted/reimported before its first spawn
  in that session, reproduces the exact carrier-outdated message (`out/r12-a/baseline-cold/console-after.log:692`).
  Source still reports a valid model, but `rig.json` is absent and the client instance is 0. A warm
  server cache masks that error while the client remains broken. Final PoC QA restores every
  sidecar across nine factory requests and two conversions, with seven retained-entity observations
  unchanged and zero restore/Lua errors (`out/r12-a/qa-summary.json`).

- In the read-only upstream hotloader source, `native/assets.cpp:522` collects a selected asset's
  rig directory and short-name records for deletion. `assets.cpp:529` keeps Windows-locked files
  in `cleanup.json`. `native/module.cpp:482` finds an existing `carrier.gma`, restores its name
  record/retention and returns `rig.manifest`, but does not rewrite `rig.json`; only the packaging
  branch (`native/rig.cpp:489`) writes that sidecar. Native binaries are unchanged in R12-A.
- The shipped model lookup in `packages/model-hotloader/mmd_hotloader/lua/mmdhl/materials.lua`
  originally required the short-name record before checking `mmdhl.rigs`. The persistence wrapper
  (`persistence.lua`, `EnsureModel`/`SetModel`) runs before the factories' attachment step caches
  the newly prepared manifest. R12-A remembers it and repairs only missing metadata before that
  wrapper. Its `MMDHL.AssetForgotten` event evicts per-asset reusable rig/geometry/conversion state;
  live entities retain their own bound manifest. See [ADR 0094](decisions/0094-reimported-carrier-metadata-and-state.md).

## R12-D: manual eye-white identity and a missed Baizhi surface (2026-11-02)

- `companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua:65` now restricts discovery
  to existing hotloader entities and already available asset metadata. The public list is
  `packages/model-hotloader/mmd_hotloader/lua/mmdhl/carrier.lua:83`; it includes native actors and
  client ragdolls, while an asset table can outlive its last spawned instance. Library metadata is
  therefore insufficient evidence for a texture lookup. The harness verifies zero Material calls
  and zero writes for unspawned assets, previews and foreign public paths.
- Choices use the complete content ID plus one-based material slot/native name, independently of
  renderer-generated paths (`nativeloader_eye_whites.lua:17`). The setter validates current spawned
  ownership and real generated VMT/VTF inputs, compares the existing DATA bytes before writing, and
  verifies persistence before applying the selection (`nativeloader_eye_whites.lua:342`). False is
  distinct from absent and outranks a positive automatic name (`nativeloader_eye_whites.lua:58`).
- A read-only source from `E:\G\Upload\1_fin\Baizhi\1_PMX\鸣潮_白芷1.12_by_鸣潮_b1b864afc9b3711e895c34a155eb3d84\鸣潮_白莲1.12.pmx`
  was copied with its textures into `out/r12-d/model/baizhi` (30,699,734 bytes). PMX SHA-256 is
  `3b31d7f554d8dbdbb229185ea39db53d213b941e9e6836853a946701287d4ad8`. The shipped worker imports this
  copy as asset `489c095ce90ee2dcfdefa669febcd7ec875ebcec0c865b7164d184e73d921cd8`, 31 materials.
  Slots 10 `bai` and 16 `bai3` both miss automatic names. UV inspection shows `bai` samples pink
  backing from the eye atlas; `bai3` samples the white eye region of the shared face atlas. The
  manual fixture therefore selects only slot 16. Evidence: `out/r12-d/model-copy.json`,
  `status.json`, `model-surfaces.json`, `uv-slot-10.png`, `uv-slot-16.png`.
- The PoC's real API returns **0**, not -1, for `file.Size` on the nonexistent choices file:
  `file.Exists=false`, `file.Read=nil`, while the generated VMT/VTF both exist (VTF 22,369,700 bytes).
  Inferring existence from size originally blocked the first save. The controller now tests existence
  independently before bounded reading; `manual_missing_size_zero` fails before and passes after
  this correction. `out/r12-d/scope-qa2.json` records the actual API result and JSON reload.
- The actual capture helper at `tools/poc_session.py:698` creates `nl_session_close` with repeat
  count **0** (continuous), despite its documentation saying 30 seconds. For UI captures the probe
  explicitly removes that test-only timer; it never changes the product's UI hooks. The first run's
  removed chooser and refused choices are excluded from acceptance.
- The accepted behavior matrix changes only `mmd/489c095ce90ee2dc/bai3_16` out of 31 materials.
  The other 30, including the shared-atlas face surfaces, retain their texture bindings. Unmark/reset
  restore all 31; native JSON reload keeps the explicit true choice. The alias is
  `0x71f624d5c68def10=0x872f42a9c3b2ca2f`. Its single 22,369,700-byte VTF took 1,960.334 ms on first
  preparation and 127.548 ms after controller reload in this run: one-time cold resource work can
  visibly stall, and is not a steady rendering cost or a measured GPU-allocation total. Broader VRAM
  reclamation remains R12-C's work. Evidence: `scope-qa2.json`, `poc/manual-eyes-final/console.log`.

## R12-B2: WIC transparent colour and optional evidence (2026-11-03)

- Review's unchanged `out/r12/wic_alpha_test.exe` reproduces the old production path on the
  copied Body01_B_MRA: source 2048x2048 has 97.7% alpha-zero pixels, mean RGB 167.6 there and
  166.1 overall; WIC Fant at 128x128 has 97.1% alpha zero, mean RGB **0.0** there and **3.1**
  overall. `game_pbr.h:167` now converts the source frame directly to straight RGBA before
  independent integer-area averaging. At 128x128, mean R/G/B is 154.561/113.404/230.281 versus
  source 154.556/113.407/230.278; alpha-zero mean RGB stays 167.34. The real production conversion
  at 128 checks all 16,384 eligible pixels, 15,904 under alpha zero, for exact roughness/metallic/AO.
- `game_matching.inl:120` isolates ambiguous/unreadable families. `:144` prepares core/base
  descriptors before optional data roles; `:238` requires equal nonzero vocabulary groups for
  auxiliary evidence. Self-votes, diffuse variants and conflicting explicit `T_*_D` families
  abstain. Decode, input/pixel/file/depth/family bounds remain. Core resource exhaustion still
  fails closed; optional failure does not fail the folder. Logs include the winning image.
- The same 1,133 folder/base pairs, 121 PMX files and 259 naming references now give **146/0/113**
  agree/disagree/abstain, versus 135/0/124. WuWa is 39/0/36 (+1 agree); Endfield 75/0/53 (+6);
  Silver 32/0/24 (+4). Fourteen new names-visible acceptances were visually reviewed. Six prior
  acceptances now abstain: three explicit-family conflicts, two weak features, one decode-budget
  exhaustion. These are naming-reference comparisons, not independent annotations.
- The measured one-pass 3x3 edge blur increased the trial from 148/0/111 to 167/0/92, but its
  names-visible results included Avywenna's iris matched to body; reject the blur and retain
  unblurred production. Initial broad auxiliary siblings also self-voted diffuse bases and crossed
  EyeTrans/Pupil and Hair_02/Hair_01; final data-role and exported-family guards remove those cases.
- The Alf2 copy's 衣饰→Body01_B uses MRA RGB (.8602 total, .7802 spatial, .7470 margin).
  头发→Hair01_A uses AnisoMaskPS (.5989 total, .5189 spatial, .5212 margin). 熔岩 and 眉毛 abstain.
  The PoC confirms hair and two accessories `automatic`; existing face/eye/skin protection remains.
  Generated PNG fractional/downsample and smaller-normal conversion regressions pass. Evidence:
  `out/r12-b2`, with every new acceptance and all 16 bases in the R12-B report.


## R12-B: features without pairing names (2026-11-02)

- The production `GamePBR::Discover` probe covered **1,133 distinct folder/base pairs** from 121 PMX
  sources under the user's read-only `E:/G/Upload`, including Wuthering Waves, Endfield and Silver
  Palace. Deduplicating repeated model variants avoids counting the same folder/base repeatedly.
  The 259 accepted exact-stem pairs provide a naming reference. With pairing names hidden, **135
  agree, 0 disagree, 124 abstain**. By production layout: WuWa 38/0/37, Endfield 69/0/59, Silver 28/0/28.
  This measures agreement with the existing naming route, not independent human annotations.
- The 阿芙2.0 folder's three PMX files reference 16 distinct bases, including gun/strap/box props
  beyond the 13 character bases. Feature matching accepts clothing → Body01_A (.7301, margin .6686), stockings →
  Socks01_A (.6932, .6362), hat → Hat01_A (.6548, .4170), and an eye-reflection base → Pupil01_A
  (.5208, .3257). The eye atlas remains protected at conversion. Hair and accessories abstain;
  their weak feature evidence is not rescued by vocabulary. The player can explicitly choose them.
- Features are spatial edge correlations from actual production WIC thumbnails, not an image
  classifier. Score thresholds are .28 raw/.36 supported/.12 margin; vocabulary contributes .08.
  Debug base/normal/packed comparisons and complete per-base decisions are under `out/r12-b`.
  Production source is included in the GPL corresponding-source tree's `game_matching.inl`.
- `QueueGameMaterial` now collects frame hashes before `DrawnIdentity` invokes `FindMaterial`.
  Its regression proves the resolver is never called for empty, zero or excessive hashes. This
  removes the specific R11-B eager-load path identified by R12-C; it is not a total VRAM measurement.
  `CollectMaterialFrameHashes` (`to_pbr.cpp:4229`) queries only tracked texture variants;
  `D3D9TextureTracker::GetTextureVariantsForMaterial` (`d3d9_texture_tracker.cpp:446`) performs a
  cache lookup/AddRef without resolving a material, so the ordering does not hide another eager load.
- The exact bundled-path regression (`tools/tests/test_render_guard_addons.py:111`) requires the
  render guard's Lua exemptions to match the indexed inputs. A new standalone panel therefore
  failed the Release gate. The final panel is embedded in the existing ToPBR driver path; the
  exemption table and companion files stay unchanged. The targeted 25-test path suite passes.
- Stock `garrysmod/lua/vgui/dform.lua:30` defines `Clear`; only the sandbox control-panel wrapper
  adds `ClearControls` (`gamemodes/sandbox/gamemode/spawnmenu/controlpanel.lua:19`). The first actual
  console-editor smoke caught this difference. The editor now uses their common `Clear` method;
  its harness deliberately omits `ClearControls`, and polling preserves the base Think handler.
- UI QA must remove `poc_session.py:696`'s `nl_session_close` timer before testing a Derma window
  with `--hide-hud`. The material picker uses `GetEyeTraceNoCursor`: a popup's mouse cursor must
  not redirect the looked-at character selection. The final probe aims the actual player and
  checks its 35 material records, rather than trying to shadow a player method on one entity.

## R12-C: VRAM attribution and Source census (2026-11-03)

- Copied-field-cache controls at 3840×2160/high, gm_construct, no Workshop, stock Kleiner,
  no active imported character and all three suspect helpers disabled: **68** published actor
  registrations use **13,511,942,144** app-texture bytes; the control with an empty copied rig
  approval map uses **1,065,893,888**. Source's `mmd/t/` estimates fall from **12,432,024,184**
  to zero while other Source estimates stay exactly **900,475,060**. The readiness path calls
  `util.PrecacheModel` / `util.IsValidModel` (`actors.lua:87-103`, restored from `sharing.lua:237`).
  These are registered models, not active imported-character entities.
- Runtime patch 0022 preserves those **68** registrations and **49** visible library entries,
  but allocates the unused static managed GPU images only on first GPU use. The same replay
  drops app textures to **908,630,016** bytes: **12,603,312,128 bytes / 11.74 GiB / 93.3%** less.
  Replacement textures (**2,656,725,504**) and Remix targets (**1,333,341,184**) stay exact.
  DXVK used falls **18,094,716,224 → 5,490,795,072**; driver allocation
  **20,776,869,888 → 8,171,347,968**. Source's logical MMD estimates stay unchanged, because
  its CPU objects remain cached. Evidence: `out/r12-vram/{04,05,16}-census.json` and matching
  session/restoration receipts; byte values in these files remain integers or exactly
  representable JSON Lua numbers, not rounded GB values.

- Read-only capture of the active field's existing `garrysmod/data/native-loader/vram.csv` at
  `2026-11-03T01:40:49Z`: DXVK used **22,858,297,408 bytes**, exactly the sum of its eight
  categories. App textures **14,380,545,024**, replacement textures **5,856,326,144**, render
  targets **1,417,882,624**, OMM **603,456,768**, buffers **397,831,744**, acceleration structures
  **153,115,392**, app buffers **49,139,712**, replacement geometry **0**. Allocated
  **24,040,001,024** includes **1,181,703,616** retained allocator bytes; do not add retained to
  used and allocated together. The driver reported **25,935,142,912** allocated and a
  **31,739,682,816** budget. Local evidence: `out/r12-vram/field-active-vram.json`.
- Read-only module inventory binds that session (PID 8488) to the R11-B fixes
  `526a6584...` and runtime `f76c316a...`, the shipped binaries at `2dd3033`; no field module,
  window or setting was changed. The independent WDDM process counters are not the same metric
  as the runtime's allocation accounting (`field-runtime-identity.json`, `field-gpu-processes.json`).
- Header-only inventory selects the highest numbered `materials-v*.gma` per asset, rather than
  adding historical versions: PoC **9 archives / 111 supported RGBA8888 texture variants /
  3,281,798,328 logical texel bytes**; field **146 / 1,244 / 45,853,418,624**. No unsupported
  layouts or conflicting names occurred. Field's **279** 4096-square/13-mip atlases account for
  **24,964,497,036** of those logical bytes, **10** 8192-square/14-mip atlases another
  **3,579,139,400**. These are disk inventory estimates, not residency; all source payloads
  stay byte-identical (`tools/vtf_census.py`, `out/r12-vram/poc-vtfs.json`, `field-vtfs.json`).
- The ordinary MMD alpha classifier used to call `Material` before obtaining draw hashes.
  R12-C's actual-script harness proves that 4,096 cold material records incur no
  VMT/material/tracker loads with the draw gate and that a new draw still becomes classified.
- Stock x64 `shaderapidx9.dll` SHA-256 is
  `7534cd56738f3f729dab0b88fce7f5fa224898fc15c28021762f3352643f8ca9`. REA/Ghidra shipped-artifact
  observations in `out/r12-vram/rea-*.json` validate the six `DebugTextureInfo001` slots at RVAs
  `15490/155f0/17b30/181f0/18a70/1dbc0` (hex). They set byte flags at +9/+10, return the list at
  +16, read **64-bit** byte totals (the older SDK declares int), check freshness and set debug
  rendering. The public list is empty on the tested Remix render path; an empty list is not
  evidence of no loaded textures.
- REA evidence `ev_ab674a6ef1d3ae41042a2c6db8ba073203e8c8febe27e79eb6181000c6a37144`
  observes the stock list builder at RVA `15eb0`: it is conditional on the enable flag and two
  non-null surface fields, walks the existing host registry and writes Name/TexGroup/Size/Format/
  dimensions/bind counts. `Size` is in bytes. Pooled-name lookup (`3d090`, evidence
  `ev_2cf8e0af51b79ff916205119c5020cff7a8fee9d80d981b50dbe9684220dfe95`) takes a read lock;
  format lookup (`35550`, `ev_09a6c4532c96a033cf70155d368e2de18c8d0ec1b377750e865a3ce15eb48d96`)
  reads a static table. These are static observations, not original source or proof of execution.
  The local-only probe's fallback is gated by that file SHA plus all six vtable RVAs, reads only
  its own registry and rejects read failures, cycles and a changed head/frame. Back/depth-buffer
  entries added separately by the public list are excluded; runtime allocation rows still cover
  them. Unsupported engine builds do not use private offsets.

## R11-B review: damaged registries and durable saves (2026-11-02)

- In the GPL source, `game_registry.h:98` resets load state; only a file over `MaxBytes` or an exact
  `TOPBR_GAME_REGISTRY <digits>` header whose numeric version differs from 1 disables writes. Decimal
  classification handles arbitrarily long versions without overflow. Empty/garbage headers, duplicate
  identities and excess rows discard all records, preserving writability and the original bytes until
  the next backed-up save. Invalid individual records still prune as before.
- `game_registry.h:181` writes staging bytes with `CreateFileW`/`WriteFile`, calls `FlushFileBuffers`,
  closes the handle and uses the existing write-through `MoveFileExW`. A sharing-violation regression
  confirms the old registry survives and the staging file is removed. `to_pbr.cpp:4708` centralizes
  save warnings behind a session member that survives worker restarts; damaged-load logging is separate.
- The production regression verifies seven damaged-header/duplicate/row-bound fixtures, exact `.bak`
  bytes, fresh reload/record/restore, four other-version decimal forms and byte-identical oversized
  input. Review build/test/render evidence remains under `out/r11-b/review`.
- The gate at 22:49:33 UTC found no remaining field process, as did setup/launch checks. The reviewed
  shipped DLL (5,147,136 bytes, `c5ae890e...`) restores the seven Alf records with zero conversions in
  `08-review-missing`; 7/0/7 on/off/restored, zero after cleanup, normal exit 0 and no Lua errors/device
  loss. Exact camera/actor bounds, hashes, USD and registry match the prior low-profile run. All 189
  snapshots and the original Workshop package are restored offline; the verifier's only drift is the
  generated `materials.usda`, matching the original empty-registration snapshot. Depot check: 2,877
  OK files, zero mismatches. The PoC lock is released; no field process or source folder was changed.

## R11-B: persistent imported game maps (2026-11-02)

- A hotloader material name identifies a model/slot; its actual base texture has the separate
  content identity `mmd/t/<16 hex>`. The client now snapshots that live texture name and current
  hashes (`packages/fixes/licenses/oversized-skinning/autopbr/source/material_pipeline/to_pbr/to_pbr.cpp:4507`),
  never a stored material name or old USD hash. Alf's 17 public parts include face/eye parts and
  debug-white parts; seven distinct supported texture identities are visible in the fixed front view.
- `game_registry.h:96` bounds and reads the registry; `:129` preserves edited bytes and replaces it
  atomically; `:175` resolves only known live identities. Four published channels retain their DDS
  byte counts and streaming FNV-1a digests. A valid header alone does not detect same-size pixel edits;
  the production regression explicitly rejects such an edited DDS. Minimum record version 1 is
  independent of generator version 5; the test retains source-less generator provenance, replaces it
  on successful conversion, and rejects retired record version 0. AO is not a material input and is
  not a restoration dependency.
- Source availability is checked on the worker (`to_pbr.cpp:4750`). A readable source with base
  metadata calls the current converter; a missing source uses the validated record. The worker owns
  file I/O and the registry; client work adds no filesystem probes. `rtx_topbr_clear` retains the
  records/DDS and resets both native and Lua submission tracking. `FallbackGuard::Select`, used at
  `to_pbr.cpp:4622`, handles settings and authored exclusion for both paths. Runtime patch 0020
  supplies the unconditional precedence required by ADR 0092; this change leaves it intact.
- The QA character is a read-only copy of `E:/G/Upload/Alf`: 532 files, 3,562,938,076 bytes under
  this worktree's `out/r11-b/source/Alf`. The unindexed candidate package permits testing before
  the one final DLL import. The first exploratory high-profile run reached all expected material
  states, but device loss followed the final camera return (9.04 GB reported budget with another
  field session running); it is diagnostic evidence, not successful acceptance. The cached medium
  run later also lost the device with 8.65 GB budget / 7.86 GB usage and micromap denials. Final
  pinned comparison uses the existing low PoC profile and a 30 fps cap. Source run `04-low-source`
  quits normally with zero Lua errors, seven materials on/restored and zero off.
- The final `04-low-source` / `05-low-missing` pair has identical actor/camera bounds, USD (6,574
  bytes, SHA-256 `97a0f545...`) and registry (1,879 bytes, `615a9d85...`), and 7/0/7 on/off/restored
  hashes in both sessions. Missing source: zero conversions, seven cached restores. Both quit normally
  with zero Lua errors. Character ROI byte-RGB MAE: source/missing on-off 3.669/4.162, on repeats
  1.152/1.168, cross-session on 1.799 and restored 1.332; temporal/exposure drift remains visible.
  Only the checked copy under `out` was renamed; the user's source was never changed. Final indexed
  package and restored-Workshop smokes pass; original config/metadata bytes match, active generated
  materials are zero, and depot verification finds zero mismatches. See [the report](handover/R11-B-report.md).
- Hotloader manifests (`data/mmd_hotloader/assets/<id>/manifest.json`, version 2): `sourceHash` is the
  SHA-256 of the PMX bytes (checked on three field entries whose source exists), so a moved PMX can be
  found by content; `textures[i].base` (64 hex) is **not** the SHA-256 of the image file next to the PMX
  (checked on `tex\颜.png`), so images cannot be matched that way. In the field library (2026-11-02),
  20 of 45 recorded sources are missing; 7 of those exist byte for byte elsewhere under `E:\G\Upload`,
  none of them the five game-PBR characters, whose `Desktop` folders were gone before R11 shipped.

## R10-E: imported eye-white surfaces (2026-11-02)

Final GPU evidence is in the [R10-E report](handover/R10-E-report.md): the automatic 100% ratio is
0.738–1.017 over six conditions, versus 0.921–1.274 for Robin in the same front-view protocol; exact
local parity is not achieved by C-16's frame-average input. Three visible Linlongs measure median
12.209 ms off / 12.202 ms on, with one 22,369,700-byte proxy shared by the instances. Preparation
reached 153.208 ms. Only the selected eye part changes among Linlong's 30 and Robin's 83 public
material bindings, including final comparisons of generated soft bindings. Native hotloader
`module.cpp:619-627` (the local source, read only) selects separate soft names under Remix; the
controller covers the matching asset/slot's copy. Six Lua scenarios cover that lifecycle. All named
corpus whites have material alpha 0 or 1; five have no PMX texture path, so name hits alone do not
prove availability of a supported owned albedo at runtime.

- The production Lua matcher finds **522 surfaces in 493/1,225 PMX models** (27,096 materials) in
  the main checkout's `out/r10/corpus.jsonl`; **470/493** share their texture with other materials.
  PoC: **5/5** characters, five matched surfaces, all shared. Read-only field snapshot: **143 manifests,
  6,233 materials, 121 matches in 118 models**, 109 sharing their texture; 25 lack a recognized
  separate white. The brief's 144-library count differs from this snapshot. Reproduce with
  [eye_white_catalogue.py](../tools/qa/eye_white_catalogue.py.md); evidence `out/r10/catalogue.json`.
  Unnamed/combined surfaces cannot be inferred from names. Near misses are review candidates, not
  proven false negatives.
- PMX UV/geometry inspection confirms Ganyu's exact `eyeball` covers white eye regions (156
  triangles, centroid RGB median 255/255/255). Four `目白底` materials sample painted lower white
  backing. `目白框`/`目白边` sample dark rims (RGB medians 139/120/107 or 136/136/136). `eye_back`
  samples pink backing (215/192/200); `眼角膜` covers colored iris/cornea regions. Keep those excluded.
  Per-material bounds, UV overlays and color measurements: `out/r10/ambiguous-materials.json`,
  `uv-*.png`; original PMX/PNG files were read only through `rpai.pmx.read_pmx`.
- Robin's shipped PoC `pbr_robin/models/robin_r18_f9c3e4b4.usda:141-142` has fallback **0.6** and
  adaptive input **15**. Decoding the published 4096² DDS albedo/emission maps from sRGB and measuring
  **131,891** eroded sclera texels gives **15 × emission/albedo = 0.6276053226**, equal at p05/median/p95.
  The nominal class formula `.025/.6*15` is **0.625** (0.417% quantization difference). Automatic
  intensity uses 0.625 through C-16's helper, preserving source shading. Paths/results are in
  `out/r10/robin-reference.json`.
- The generated atlases inspected are VTF **7.2**, 80-byte header, RGBA8888 (format 0), one frame/depth,
  no thumbnail, mip data smallest-to-largest. DXVK hashes **subresource 0 pixels**, not file metadata
  (`d3d9_common_texture.cpp:672-684`, `d3d9_texture_hash.h:123` in the recorded fork). A header change
  cannot isolate an eye texture identity. The validated clone toggles one top-mip RGB low bit;
  alpha and lower mips remain byte-identical. Unsupported layouts fail closed.
- Hotloader `native_render.lua:93-105,303-306` binds public IMaterials, allowing an eye-only base
  texture change without a native-renderer hook. Remix tracking waits for a real draw
  (`material_lua_bindings.cpp:515-550,644` in the fixes source, read only). The original hash comes
  from immutable original/proxy helpers in a tiny offscreen 2D target on separate frames before world rebinding.
  Original-hash mod lookup precedes fallback in `SceneManager::determineMaterialData` (patch 0019),
  preserving authored pack emission. [ADR 0088](decisions/0088-imported-character-eye-whites.md)
  records filtering, compatibility, lifecycle and memory tradeoffs.
- PoC verification found distinct Lua `ITexture` wrappers need not compare equal: normalized texture
  names identify owned bindings for apply/restore. Source's queued tracker reliably observes immutable
  helpers on separate frames. The render guard needs their three exact bundled source paths; no broad
  exemption is added. An eye proxy must also inherit the original atlas's category snapshot, because
  the existing MMD-alpha scanner intentionally rejects a DATA texture outside `mmd/`.

## R8-C material review: loading, provenance and cost (2026-11-01)

The fixes' `remixlua/cl/cl_fix_pbr_materials.lua:50-72,88` inspects native ExoPBR shader/texture
fields after Material; inert objects lose those inputs. The hotloader's `mmdhl/client.lua:68-84`
creates screenspace_general with mmdhl_vs20/mmdhl_ps20b and then sets its textures; blanket creation
suppression breaks its immediate path. `loader/client/bootstrap.lua:169` compiles owned files with
@lua/<path> labels, omitting add-on identity. The reviewed guard uses an exact 344-path snapshot
checked against indexed package hashes plus companion/glass sources (no internal collisions after
retired glass is excluded). Other mounted add-ons or forged labels can collide and bypass the
material compatibility exemption; this does not authenticate Lua or grant native execution.

There is no evidence establishing that merely loading/reading these materials caused the tester's
crash. The known PoC loaded/exited normally; some shader warnings precede Lua. Native loading is
therefore retained. The review removes all material VMT preflight; only status/session startup
reads remain. Untrusted bindings inspect cached native shader/program fields. Entity bindings
resolve once through native Material per live cached path; trusted bindings add no such resolution.

In `out/r8-compat/material-cost.json`, three-run medians with a modeled 761-mount, 1 ms failed
lookup show the prior guard taking 1,205.573 ms/1,200 mixed paths, 1,204.843 ms/repeated paths and
1,214.444 ms/PNG+JPG icons: each batch makes 1,200 reads/913,200 modeled mount probes. The reviewed
guard makes zero material-preflight reads/probes and takes 0.299, 0.247 and 0.909 ms respectively.
Trusted new reads take 0.959 ms; first/repeat entity bindings 2.167/1.284 ms; fresh/repeat render
bindings 2.700/2.213 ms. Plain loads make zero metadata queries; entity repeats add zero native
resolutions or metadata queries. Windows QPC measures batch elapsed time with fake native objects;
mount probes and 1 ms are explicit assumptions, not field measurements. Native cold I/O and GPU
behavior remain unmeasured. Expected added guard VMT I/O is zero regardless of 761 mounts. See
[the reproducible harness](../tools/tests/bench_render_guard.py.md) and
[updated handover](handover/R8-C-report.md); the older preflight claims below describe the earlier implementation.

## R8-C: graphics add-ons, exact sources (2026-11-01)

[The second audit](audits/R8-C-addon-compat.md) and [hash ledger](audits/R8-C-addon-compat.json)
index 86 Lua/VMT files and 856 candidate API lines across eight exact installed Workshop archives.
Every indexed file matches its archive-entry CRC and SHA-256; source bodies remain in ignored
`out/r8-compat/src`. This is a static inventory, not an execution count. Quick Bloom is now exact: its
only client autorun writes two bloom cvars in Initialize. Life Mod legacy decoding is bounded and
its declared-length GMA passes all 98 entry CRCs and aggregate CRC 374141b9.

Claude's existing r8/07-gshader console contains 26 failed-shader lines, an intentional guard error
at bumps_building.lua:35 and one at worldpos.lua:27 through !!shaderlib.lua:800. The map loads/exits
normally there; the tester's crash is not reproduced. Raw RGBA32323232F29 is a documented Source
format, but the guard's old enum snapshot predates GShader exporting it. That false diagnostic is
separate from backend support: D3D9Ex dependencies, reserved target replacement, MRT/depth copies,
world-mesh reconstruction and shared light-metatable edits remain concrete capability risks.
[ADR 0086](decisions/0086-inert-shader-effects-and-safe-guard-fallbacks.md) makes the incompatible
work inert with real engine-backed fallbacks; it does not claim native/GPU fault recovery.

R8-C final offline checks pass 26 CTests and 488 Python tests (two existing symlink skips), with
40 guard methods/43 LuaJIT invocations including 18 new replay cases. Repeated GShader light
acquisition needs readback of its private metatable edits; returning a fresh native-table clone
on every call would reset the wrong __index table. The harness checks that readback and simulates
GLua ITexture type labels. Isolating GShader's native Remove override also requires retiring its exported projector-cache entries
and rebuilding their indices; the replay removes several lamps in sequence and requires an empty
cache afterward. No actual game, GPU or third-party Lua was executed. The new policy's
[harness and QA receipt](handover/R8-C-report.md) explicitly separates these results from the
original tester crash and foreign-initializer startup gap.

## R8-B: Backrooms native port (2026-11-01)

Fixes source `7094baf6edf6797fd5c3f0b58ca668f9307b4906` is based on packaged `a2c8dbc5`.
The Backrooms branch ends at `e4d548d`; 6b4794f's model-miss cache also needs the model-loader
hunk from `672ada9`. Its original `GetVtxFileChecksum` returns zero for missing, truncated and
zero-checksum files: treating all three as absence suppresses a valid lower mount. The port
reports genuine open failure separately (`source/modelload_fixes.cpp:418`, `:503`, `:519`),
keeps malformed-file fallback and caps the mutex-protected cache at 65,536 paths. Shutdown
clears it at `:1499`; hardware-cache flushes keep it. SDK `filesystem.h:515` specifies that a null
path ID searches all paths; null/all-path misses and GAME misses therefore have separate keys.

The lazy transform is consumed by bone upload at `source/HardwareSkinningHooks.cpp:3179`
and `:3525`, including the protected automatic oversized path with force-hardware off; per-strip
state resolves at `:3618`. Nested studio draws preserve pending/cached state at `:3751`.
`source/culling_patches.cpp:408` validates the unique executable CM_Vis locator and engine-relative
globals; `:446` validates the vis lump and offset table. SDK `bspfile.h:85` and `:91` define
65,536 clusters and 16 MiB of visibility. `:475` restores still-owned PVS offsets at module close;
default-off synchronization does not read the vis table. PAS uses existing engine vis streams,
not a new BSP decoder. It cannot change a separate multiplayer server's visibility decisions.

Offline checks passed: three production-code harnesses, existing oversized-skinning and
memory-limit tests, unchanged PE imports/exports, 2,334 pinned dependency files and a clean
patch reconstruction. DLL size is 4,864,512 bytes (16,896 above the packaged R6 DLL).
Static add-on/API review found 1,682 lights in gm_br_complex and 2,687 in gm_br_pitfalls;
package Lua already provides the native lighting globals, Light2RTX clearing and updater hooks,
and packaged NikNaks has PASForOrigin. No game/frame-time measurement was made in R8-B.
Details and exact hashes: [corresponding source](../packages/fixes/licenses/oversized-skinning/backrooms/Source.md).

## R7-B: external exit diagnostics (2026-11-01)

The final text review caught lossy catalog generation through Windows PowerShell 5.1's
ASCII native-pipeline encoding (code page 20127): original UTF-8 labels survived, while new
non-ASCII text became `?`. A before-failing Python catalog check and embedded C++ message
checks now reject it. Writing the catalog through a UTF-8 source file restored the text;
the full catalog then exceeded MSVC's 16 KiB single-literal limit. CMake now concatenates
adjacent raw literals at existing label-file line boundaries, preserving the bytes. The
native French dialog probe is repeated against that corrected embedded catalog, not merely
against the source JSON.

Final Release gate: 26/26 CTests (36.50 s) and 455 Python tests (28 gmapack, 25 steam,
402 tools; two expected fixture skips). `out/r7-b/release-verified.log` records the pass.
A separate native-window probe (`out/r7-b/dialog-probe.json`) observed exactly one visible
French dialog after a synthetic access-violation exit, checked the title/body/code/folder,
acknowledged only that observer's OK button and verified its process then exited. Its
`+gmod_language fr` correctly beat the synthetic config's archived Japanese setting. This
does not exercise GMod, Remix's own prompt or a real resource fault.

The final parallel native run measured empty evidence collection at 1.379 ms mean / 4.073 ms
maximum over 30 starts (an earlier isolated run: 0.484 / 0.676 ms). Startup's observer handshake
has a separate 3 s readiness bound, not included in those collector numbers. The first full gate
exposed the existing `loader/guard/tests/test_early.cpp` unprefixed timestamp path over MAX_PATH;
using `fs::long_path` for its timestamp getter/setter removes the need for a local build-output
path workaround. The fixture still proves that repeated preparation does not rewrite the cache.

The same built proxy works inside System32 `rundll32.exe` with its DllMain loader guard.
The synthetic integration covers 23 cases, including a genuinely separate sleeping observer,
an inherited restricted game handle, process/path/creation/parent validation, exit before JSON
and observer termination afterward. The actual exception/OOM/driver failures are simulated
exit codes/logs, not resource exhaustion. The bootstrap remains KERNEL32-only; MessageBoxW
is resolved dynamically after exit. No executable is extracted or downloaded.

`loader/proxy/observer.cpp` starts/validates/waits; `loader/proxy/exit_report.cpp` selects and
formats the seven catalogs. `loader/core/src/evidence.cpp` shares `classify` and archive copying
between exit and startup. The end marker lets the next collector reuse the same reason/folder,
and prevents clean sessions without a Remix shutdown marker from filling the five-archive queue.
Fresh `.nvdbg` shader-debug information is copied as context but no longer proves a crash;
actual GPU dumps use `.nv-gpudmp` (the fork's writer is recorded in runtime patch 0001).

Memory inference is deliberately narrower than the map warning: <=512 MiB free commit in a
sample <=30 seconds old, tied to the same process token (snapshot) or start/end interval (CSV),
and only for a generic nonzero exit without stronger evidence. The reason is
`likely_out_of_memory`; concrete exceptions keep their exception classification/code. A zero
exit stays clean unless a fresh fatal Remix message/marker or actual crash artifact exists.

## R7-B: commit headroom from the saved R6 runs (2026-11-01)

Read-only reanalysis of the main checkout's `out/qa-poc/r6/tiers*/<run>/memory.csv`;
no game or new measurement session was started. Each CSV includes earlier sessions, so the
last bootstrap sample with private bytes below 256 MiB identifies the current session's start.
The damaged `tiers-pinned/04-house-auto-pin` snapshot has no such sample and is excluded.
These are whole-start-to-map differences, deliberately conservative for a warning at the menu;
system commit includes other programs and ten-second sampling can miss transient peaks.

| Saved R6 sessions | Peak process private GiB | Added system commit GiB |
|---|---:|---:|
| `tiers/01-construct-auto` | 11.669 | 16.184 |
| `tiers/11-construct-medium`, `12-construct-auto` | 11.922, 12.434 | 12.669, 13.212 |
| `tiers/04-house-auto`, `05-house-medium`, `06-house-low` | 11.600, 11.153, 10.959 | 12.530, 12.089, 11.886 |
| `tiers-pinned/07-construct-auto-pin`, `08-construct-medium-pin`, `09-construct-low-pin` | 11.688, 11.433, 11.303 | 12.640, 13.623, 12.194 |
| `tiers-pinned/10-house-low-pin-b8` | 10.899 | 16.015 |

Across the 24 usable runs, added commit spans 11.074-16.184 GiB. The runtime's GPU
snapshots and the tier comparison in [ADR 0064](decisions/0064-performance-tier-defaults.md#poc-measurements-2026-10-31)
measure VRAM, not CPU commit; lower tiers do not justify a dramatically smaller system reserve.
`loader/core/src/memory.cpp` therefore warns strictly below 18 GiB free commit, or a
24 GiB total limit. This is a conservative heuristic (about 1.8 GiB above the largest
sampled increase), not a map-fit guarantee. Unknown limits do not warn; subtraction saturates.
64.0 / 90.6 GiB leaves 26.6 GiB and stays quiet. The small-limit floor replaces R6's 32 GiB floor.

## G1-A second pass: client build cost (2026-11-01)

- Full Release gate exits 0: repo conventions, 25/25 CTests (48.67 s), and 453 Python tests
  (28 gmapack, 25 steam, 400 tools, two existing skips). All 50 G1-A glass tests execute.
  The tools tests take 79.927 s. Evidence: `out/g1-lua-fix2/release.log`. No G1-B/native/Jolt,
  QA, package or Workshop configuration paths were edited in this branch.

- `glass/addon/lua/nlglass/client.lua:102` queues a dirty pane once; `:114` drains it after the
  receiving FrameNumber with a two-pane cap and a soft 1 ms elapsed-time stop. A whole break
  clears stale meshes/collision immediately. Removal/snapshot replacement/cleanup invalidate
  pending entries. `Attach` preserves collision dirtiness for an entity arriving while queued.
  Current contact-default anchors are `config.lua:7`, `damage.lua:71` and `server.lua:154`
  in the same directory (the earlier contact note's fallback line numbers were one line late).
- `glass/addon/lua/nlglass/geometry.lua:74` supplies mesh and convex positions from one extrusion;
  face fans and crack strips share read-only vertex records. The crack strip builder at
  `client.lua:73` also makes winding agree with outward normals on both faces. The engine
  harness checks position identity, triangle counts, winding, queue bounds/coalescing and
  cancellation including late entities and a whole break overtaking partial work.
- Updated 40-sample benchmark on the same 100-hit preparation: ad3ed46 has 502 cells, this pass
  164. Client break handler mean/p99 13.5920/20.7774 -> 1.8676/2.6174 ms; deferred build after
  1.0124/2.1511 ms; per-sample combined cost 13.5931/20.7784 -> 2.8800/4.5732 ms. Hit combined
  cost 13.3168/21.9155 -> 3.2667/5.6801 ms. The queue does not hide deferred work in these sums.
  Initial snapshot/attach is outside timing; engine/physics/transport/debris are mocked.
  This is CPU evidence only, not GMod or Remix frame-time acceptance.
- The stronger active-cap coarsening probe peaks at 199 cells with 0.048986 units² area error;
  36,015 generated edges remain at least 1/256 long. The typed snapshot is 5,723 bytes for
  176 live cells/7 groups. New density/lit/default/defer regressions fail on ad3ed46; all
  50 glass cases pass now. Logs remain under this worktree's `out/g1-lua-fix2/`.

## G1-A second pass: lit cracks and walking (2026-11-01)

- `glass/addon/lua/nlglass/client.lua:7` creates `nlglass_frost_lit` with VertexLitGeneric and
  `models/debug/debugwhite`, no selfillum. A new name avoids the existing material cache after
  Lua refresh. The `lit_cracks` mock checks the shader and strips at z=±0.515 for thickness 1,
  outward normals, equal front/back vertices and full width at most 0.20 units. Whether Remix
  shades those strips correctly at night/in a dark room remains a real renderer check.
- `config.lua:7` now defaults the replicated contact speed to 250; `damage.lua:72` and
  `server.lua:155` use the same fallback. The `walk_run` harness checks contacts/sweeps at
  200/249 (no damage) and 250/400 (damage), menu value and admin reset to 250. Existing archived
  values remain user choices. The menu help and six MIT catalogs include the default guidance.

## G1-A second pass: break density (2026-11-01)

- `glass/addon/lua/nlglass/fracture.lua:7` defines kind-specific active caps (200 annealed,
  300 tempered) within MAX_CELLS=512. `rings` stretches only the final outer ring when its
  ray/ring product exhausts the budget; `uniform` bounds its row/column product explicitly.
  `Apply` coarsens before assigning refined cells, so every release is bounded without losing
  area. Repeated radius queries no longer build unused tile polygons.
- `tools/tests/nlglass_fracture_harness.lua density` fails on ad3ed46 and passes after the fix.
  At spacing 8, seed 171 and a 2-unit corner inset, annealed fresh/damaged whole-break counts
  are 89/160 centre and 52/197 corner (96x64), 116/170 and 63/184 (256x128), 116/151 and
  65/182 (128x256). Damaged means 24 prior 180,000-energy spatial visual-only native hits.
  Tempered counts are 96, 300 and 300 at either location, fresh or damaged. The harness also
  checks 8192x1, 1x8192, 8192x8192, spacings 4/8/64 and conserved total area.
- Local pre-change handler baseline: 502 prepared cells, 40 samples, client break mean/p99
  14.5843/23.7406 ms. This differs from the first-pass handover's earlier machine/load sample;
  both measure mocked engine calls, not live frame time. Lower-cap pure-fracture means over
  80 samples (164 cells): hit 0.4183, repeat 0.0652, break 0.1389 ms versus local baseline
  0.6187/0.0805/0.5113 ms at 502 cells. Evidence stays in this worktree's ignored
  `out/g1-lua-fix2/`. No game or install was changed.

## G1-B second pass: final offline receipt (2026-11-01)

- Final matched QPC samples (`out/g1-native-fix2/render-before-final.log` / `render-after-final.log`):
  moving Think+draw means 0.1623 -> 0.1650 ms with all 2,000 pieces visible; mixed visibility
  0.1349 -> 0.1144 ms (2,000 -> 500 draws); settled 0.0155 -> 0.0119 ms (15 -> four draws).
  Settling allocates 41,795 -> 14,220 KiB with GC stopped, including 288,000 -> 47,952 Vector
  and 144,000 -> zero Angle constructions. The mocks omit real engine-call and GPU cost.
- Source anchors: `debris_mesh.lua:59` mutates shared transformed vertices; `debris_batches.lua:5`
  bounds upload/preparation work, `:102` stages rebuild/retirement and `:133` culls settled areas;
  `debris_draw.lua:19` groups individual draws; `debris_view.lua:25` tests spheres and projected
  size using camera depth; `debris.lua:196` publishes the manager's rolling metrics. All are
  under `glass/addon/lua/nlglass`. A slow-vector double yields before the count cap, and a 2.5 ms
  upload injection remains in the peak statistic after quiet frames.
- Release passes 25 CTests/448 Python tests (two existing skips) after the already documented
  local guard-output shortening; 19 native glass cases pass. The unchanged native test drops
  4,000 colliding pieces to sleep in 11.0167 simulated seconds with zero contact overflows;
  settled core step+poses averages 0.00165 ms. It runs alongside the full test suite, not a game.
  Separate final Lua manager/probe checks pass 14,576 assertions. No game frame target is claimed.

## G1-B second pass: moving draw work and attribution (2026-11-01)

- `debris_draw.lua` maintains individual material groups; a fully visible 2,000-piece mock frame
  binds once instead of 2,000 times. Across 240 frames, setters fall from 1,440,000 to 962,000
  (two pose setters per piece/update plus one initial scale setter). Repeated draw passes with
  unchanged poses perform no matrix writes. No per-piece Vector/Angle/Matrix is constructed by
  either warmed draw path; the change avoids engine calls and culls work rather than claiming
  the original draw path allocated those userdata every frame.
- `debris_view.lua` uses the render view, numeric Source basis and conservative sphere bounds;
  the controlled mixed scene retains 500 of 2,000 pieces, rejecting rear, beyond-8192-unit and
  distant subpixel pieces. It submits 500 rather than 2,000 draws. Engine doubles make material
  and matrix calls effectively free: fully-visible Think+draw **increases** from 0.132 to 0.164 ms
  with culling/instrumentation, while mixed visibility falls from 0.129 to 0.115 ms. This does not
  measure the reduced real-engine binding/GPU cost and does not prove the <20 ms game target.
- `debris.lua` records 120-frame Think/draw means, last and peak samples; draw passes sharing
  FrameNumber accumulate before publication. Injecting 1.25 ms Think work and 0.4 ms/mesh for two
  two-mesh passes produces exactly 1.25 ms Think, 1.6 ms draw and four calls/frame. Rebuild and
  upload peaks survive quiet frames. These fields separate hook work from asynchronous Jolt;
  Spawn/fracture outside Think and GPU time are explicitly excluded.

## G1-B second pass: pile allocation and draw findings (2026-11-01)

- Read-only game receipts: `out/qa-poc/g1/03-qa/console.log:657,660,662` in the main checkout
  report 678 sleeping pieces/40 batches at 8.71 ms mean, 2,000 live/1,453 moving at 33.83 ms
  (Jolt 1.5816 ms), then 2,000 sleeping/388 batches at 11.91 ms mean, p99 28.95 ms. These
  frame spikes cannot be attributed precisely from those aggregate logs alone.
- Before the second pass, `debris_batches.lua` grouped 256-unit XYZ cells by material **and
  color**, uploaded at most 6,000 vertices, and `debris_mesh.lua:57` called `LocalToWorld`
  twice per transformed vertex. A controlled 2,000-quad/50-location LuaJIT sample allocates
  41,624 KiB while settling, including 288,000 Vector and 144,000 Angle constructions.
  This is a concrete source of later GC pressure; engine/Remix spikes still need game attribution.
- Consolidating into offset 1024-unit cells by material, with vertex colors preserved and one
  shared 24,000-record upload pool, reduces the same sample from 15 to four settled draws and
  to 14,209 KiB allocated, 47,952 Vector constructions and **zero** Angle constructions while
  settling. A warmed rebuild allocates no vertex vectors. The color/grid-zero regression puts
  all 2,000 pieces into four draws in one area. Source-basis position/normal comparisons pass.
  GPU releases now spread across frames; transforms have count and measured time caps. These
  measurements use engine/physics doubles, QPC and stopped GC; actual uploads/GPU costs are absent.

## G1-A client/update fix pass: final offline evidence (2026-11-01)

- Implementation anchors: `damage.lua:65` (side/proximity contact), `server.lua:86` (quiet outputs),
  `server.lua:151` (incoming/base-velocity sweep), `server.lua:286` (targeted sync), all under
  `glass/addon/lua/nlglass/`. Fracture anchors there: `fracture.lua:104` (capped crack floor),
  `:258`/`:286` (complete-group coarsening/local refinement), `:343`/`:451` (apply/crack caches).
  Client anchors: `client.lua:22`/`:50`/`:162` (pose cache/build/draw), `protocol.lua:13` (snapshot).

- `glass/addon/lua/nlglass/client.lua` retains matrices/entity validation and refreshes transforms
  only after a pose change. The draw harness checks 20 frames with zero new Matrix, LocalToWorld
  or class calls; far/rear panes are skipped. A break builds prediction physics once and at most
  one pane/crack mesh pair. Pending weak energy builds neither. Initial sync is client-ready only;
  a mismatch requests one pane and two different panes can repair in the same frame.
- The corrected 40-sample handler benchmark restores fresh server/client records before each
  sample (so stale revisions cannot short-circuit later samples). Same 100 preparation hits,
  493/502 cells before/after. Mean ms before/after: server hit 14.2875/5.3019; server break
  18.9326/10.3577; client hit 45.3190/27.7840; client break 84.1545/23.7365. p99 ms:
  39.5452/16.4711; 37.8406/25.0744; 73.6096/52.1866; 118.3529/46.5227 respectively.
  These include Lua mesh/convex construction and mock overhead/GC, not actual engine/GPU physics,
  transport, debris/Jolt or Remix. They do not establish game frame-rate acceptance.
- Final pure-fracture 80-sample means: new hit 0.8426 ms, repeat 0.0961 ms, break 0.6749 ms;
  p99 2.6709/0.6155/1.9264 ms. Existing before means were 12.5675/13.6601/14.5538 ms.
- [Entity:SetVelocity](https://wiki.facepunch.com/gmod/Entity:SetVelocity) sets base velocity,
  added to player movement; [GetBaseVelocity](https://wiki.facepunch.com/gmod/Entity:GetBaseVelocity)
  exposes it. The QA runner's scripted push needs this in addition to CMoveData velocity. Tests
  cover ordinary incoming motion with stopped entity velocity and zero movement velocity with a
  500-unit/s base impulse. The old logs have no Touch/velocity trace, so exact engine callback
  timing is still a game check. Native-removal blast order is separately tested with deferred breaks.
- Full `tools/test.ps1 -Config Release`: 25 CTests, 448 Python tests (28 gmapack, 25 steam,
  395 tools; two existing skips), including 45 G1-A glass cases. Output and before-failure/timing
  evidence are under this worktree's ignored `out/g1a/`; original QA evidence was read only.

## G1-A incremental fracture probes (2026-11-01)

- `tools/tests/nlglass_fracture_harness.lua` now reproduces lost hit location at the fourth
  separated impact against 3096b2e, sub-floor energy loss, full tempered grid cracks, a 1/1024
  clipped edge and border cracks. All fail before the fix and pass after it. The 180-seed edge
  probe checks 36,015 generated edges at or above 1/256. The 100-hit coarsening probe peaks at
  512 cells with area error 0.01414 on a 32,768-unit² pane; another preserves an existing hole.
- The same 80-sample high-resolution near-cap workload (100 preparation hits outside timing)
  measured before/after mean new-hit 12.5675/1.1596 ms, repeat 13.6601/0.1359 ms and break
  14.5538/0.8603 ms. Before/after p99: hit 20.8927/2.7537, repeat 23.7746/1.4296, break
  23.1292/3.1285 ms. Prepared cell counts: 493/502. These are LuaJIT fracture CPU times;
  no GMod, native debris, physics initialization, rendering or network transport is measured.
- `tools/tests/nlglass_engine_harness.lua topology` round-trips 501 live cells and 47 complete
  subdivision groups in 16,721 bytes, then compares the next break's polygons. Remaining/crack
  caches avoid repeated support passes; only a breakout needs adjacency/support traversal.

## G1-A contact and hidden-surface output investigation (2026-11-01)

- In the read-only `out/qa-poc/g1/02-qa/console.log`, the 40-pane falling scene reports mean
  17.66 ms, p99 292.93 ms; empty 8.33 ms, settled 8.88 ms, all on the 64-piece VPhysics fallback.
  The QA player step supplies 500 units/s toward an upright 64×96 pane but leaves it intact.
  `tools/qa/nlglass_qa/lua/autorun/nlglass_qa.lua` sets that velocity before the mover stops it;
  `glass/addon/lua/entities/nlglass_pane/init.lua` previously relied only on Touch/GetVelocity.
  This explains a missed incoming velocity path; actual callback timing still requires game QA.
- [Facepunch SetupMove](https://wiki.facepunch.com/gmod/GM:SetupMove) runs before engine movement.
  [EntityKeyValue](https://wiki.facepunch.com/gmod/GM:EntityKeyValue) captures repeated output keys;
  [GetKeyValues](https://wiki.facepunch.com/gmod/Entity:GetKeyValues) does not expose all keys;
  [TriggerOutput](https://wiki.facepunch.com/gmod/ENTITY:TriggerOutput) is a scripted-base helper,
  not direct access to the native brush's output objects.
- [Valve func_breakablesurf.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/func_breakablesurf.cpp)
  lines 562–579 play PhysBreakSound and fire inherited OnBreak. InputShatter (668–715) calls
  Die and ShatterPane. NoDraw cannot suppress these events. The surface datadesc (143–172) adds
  no OnShatter output. The replacement now mirrors captured OnBreak keys to an unused native user
  channel, preserving raw parameter/delay/count strings instead of requesting engine fracture.

## G1-A glass: offline executable evidence (2026-10-31)

- `glass/addon/lua/nlglass/damage.lua:58` reads `CollisionData.HitObject` as the PhysObj itself,
  including `GetMass`; relative velocity uses `TheirOldVelocity - OurOldVelocity`. The mocked
  PhysObj deliberately has no `GetPhysicsObject`. A 120 kg hitter at relative 180 units/s produces
  1,944,000 game energy, identically for a prop and ragdoll. `:65` admits moving players, NPCs and
  vehicles, excludes slow/tangential contacts and tests the remaining polygons to avoid ghost hits
  in holes. The server defers physics reconstruction outside PhysicsCollide callbacks.
- `glass/addon/lua/nlglass/fracture.lua:87` supplies the tunable 450,000 reference breaking threshold
  (96×64, thickness 1, annealed, strength 1), 8% crack threshold and 3.5× tempered threshold. The
  pure LuaJIT probe `out/g1-a/fracture-smoke.lua`, seed 100, returns 58 cells after a 180,000-energy
  centre hit, 86 visible crack segments then 109 after the second hit; the third releases 40 cells
  and leaves 18 in the frame. Their full area sums to 6144. These are synthetic energy/geometry
  measurements, not observed damage from the game's pistol.
- `fracture.lua:2`, `:233` cap impacts at eight and cells at 512; nearest-centre merging preserves
  energy and the seed/cuts. Snapshot replay and fresh-process outputs match. The pure harness
  disables global random, sin/cos and sqrt; no libm call controls tessellation. Crack edges from
  the first hit occur in the final cells. Shared-edge connectivity releases unsupported islands
  and keeps support across an edge subdivided by another cut.
- `glass/addon/lua/nlglass/protocol.lua:3` encodes an impact in 148 bits (19 rounded-up bytes):
  24-bit x/y at 1/1024 units, 31-bit energy/seed, two-bit kind, three signed 12-bit directions.
  With pane ID, revision and three flags, the ordinary event is 215 bits (27 bytes). Breaks carry
  the prior bounded state; a test deliberately misses the create packet and removes the entity
  before client replay, yet all pieces reach the debris stub. Late join creates no old debris.
- `glass/addon/lua/nlglass/client.lua:17` mirrors remaining frozen convexes for prediction, attaches
  after late entity networking and rejects an index reused by an unrelated class. The wire carries
  entity-local frame offsets, so delayed client poses do not introduce a permanent geometry offset.
- `glass/addon/lua/nlglass/server.lua:76` retains the original hidden/non-solid surface brush and
  fires one covering Shatter input on first breakout; the harness proves bypass/routing and that
  a partial pane remains. It does **not** prove Source's Hammer output semantics for a hidden brush.
  Native `func_breakable` retains engine health/collision; `:152` sends pieces once across break
  events/removal, using last damage, breaker pose/velocity or a nominal centre impact. `:241`
  invalidates pending native removals during cleanup. Restored panes keep their output bridge;
  duplicates do not take it from the original.
- The companion relocates category `Glass Rewrite Remixed` to Water and glass
  (`companion/nativeloader/lua/autorun/client/nativeloader_menu.lua:20`). G1 retains that category
  and `GlassSettings` (`glass/addon/lua/nlglass/menu.lua:72`) plus `glass_open_panel` and
  `rtx_glass_player_break_speed`, avoiding an orphaned settings page. Non-English MIT catalogs are
  newly agent-written and await human review. Actual weapon tuning, engine outputs, prediction,
  Remix frosting and the 50-window performance baseline remain game acceptance.

## G1-B: dedicated glass world and offline measurements (2026-10-31)

- Final QA refinement (2026-11-01): the 4,000-piece benchmark now reserves **8192** bodies, exactly
  as the manager does, rather than reserving only 4000. With that reserve it still slept in
  **11.0167 simulated seconds**: spawn **42.35 ms**, simulation **6.384 s wall / 31.281 s process
  CPU**, fixed-step **9.657 ms mean / 17.063 ms maximum**, settled step+poses **0.1225 ms**.
  The fixture uses axis-aligned rectangular shards and zero initial spin/velocity. These are
  core-test figures, not game/rendering figures; evidence is `out/native-tests-qa.log`. Compressed
  `sprp` tests now exercise both directory-length conventions, and the displacement fixture also
  verifies omission of an authored hole. The earlier 4000-reserve measurements below are retained.

- Pinned Jolt `v5.3.0`: the only downloaded archive was
  `https://codeload.github.com/jrouwe/JoltPhysics/zip/refs/tags/v5.3.0`, SHA-256
  `ee47dbd3de026829bc9734eeed960118c3d0a1a61b16e172009731a407d1466a`. All 444 vendored
  upstream files were compared directly against the archive and matched; our README is separate.
- Source's collision-lump LZMA wrapper is treated as 17 bytes: `LZMA`, original size, packed size,
  five decoder properties; it is not the loader's 13-byte standalone LZMA header. The reader limits
  expanded sizes and dictionary before calling the existing SDK decoder
  (`glass/native/bsp.cpp:36`). Generated compressed-leaf and damaged-input tests cover this path.
- The importer traverses model 0's world tree, rather than importing the brush lump wholesale:
  nodes are 32 bytes, leaves v0/v1 are 56/32 bytes, models 48 bytes, brushes 12 bytes and sides
  8 bytes. `0x400b` selects solid/window/grate/moveable contents; playerclip/water/entity-only
  brushes are excluded (`glass/native/bsp.cpp:78`). Displacement records are 176 bytes, vertices
  20 bytes, faces 56 bytes; surface-tagged triangles from powers 2-4 collide on both sides
  (`glass/native/bsp.cpp:121`, `glass/native/world.cpp`). These are offline-supported layouts;
  real mounted-map compatibility remains game QA, not a claim that every Source derivative works.
- `sprp` origin/angles/model/solidity use byte offsets 0/12/24/30; supported records have strides
  56-80 bytes (v4-11), with v11 uniform scale at 76. Compressed child lumps can advertise packed
  or original directory length (`glass/native/bsp.cpp:169`). The generated fixture includes a
  scaled solid prop and a non-solid decoration; native tests also drop bodies onto that prop and
  onto the generated displacement, proving collision rather than just parser counts.
- Jolt's fixed-only `TempAllocatorImpl` explicitly calls `std::abort()` on exhaustion
  (`third_party/jolt/Jolt/Core/TempAllocator.h`); this module uses
  `TempAllocatorImplWithMallocFallback` instead. Main physics/contact capacities remain bounded
  and contact overflow is a controlled error; a 128-body overlapping fixture tests both overflow
  and the piece-collision-off filter (`glass/native/tests/test_glass.cpp`).
- Release, Ryzen 9 9950X3D (16 cores/32 hardware threads), eight Jolt workers: 4,000 4x4x0.6-unit
  shards in four layers, against each other and the generated room, all slept after **11.0167 s
  simulated**. Isolated final implementation run: **42.67 ms spawn**, **5.531 s simulation wall**,
  **28.766 s process CPU** (`GetProcessTimes`, sum over all threads), **8.367 ms mean / 13.596 ms
  maximum fixed step**. Once asleep, 120 calls to step plus pose output averaged **0.0908 ms**.
  Test bounds are 15 simulated seconds, 30 wall seconds and 120 process CPU seconds. This is a
  physics/core measurement, with no game or Remix draw cost (`glass/native/tests/test_glass.cpp`,
  evidence `out/native-tests-impl.log`).
- The `ILuaBase` double executes the actual callbacks and refuses metamethod/engine-call paths;
  `ReadPoses` creates no Lua tables or Vector/Angle userdata. The real Lua manager/probe execute
  under LuaJIT with mocks, including cleanup, batch invalidation and preserving edits made during
  a probe's temporary convar override (`tools/tests/glass_debris_harness.lua`).

## C-16: in-game tuning of the eye whites (2026-10-31)

- Client Lua may not run `lua_run`: `RunConsoleCommand("lua_run", ...)` prints
  `[ERROR] RunConsoleCommand: Command is blocked! (lua_run)` (the first probe's console). The same
  line sent as console text works: `poc_session.py --console` posts it with `WM_COPYDATA`
  (`tools/poc_session.py:635-653`) after the map and before `--lua` files (`:1047-1051`); Source only
  splits it at `;` and cuts it at `//`.
- Model Hotloader's server ignores a requested position: `mmdhl/server.lua:143-149` spawns at the
  player's eye trace (`HitPos + HitNormal * 3`, refused beyond 4096 units or on the sky), turned
  toward the player (`settings.lua:35-41`). Client Lua removes what it spawned with
  `mmdhl.Action("remove", nil, ent)` (`client.lua:173`, served at `server.lua:162`).
- gm_construct's spawn points used: (831, 576), (952, -512) and (823, -210), all at z -143.08, yaw
  180, pitch 0; the eye trace lands 3,250-3,460 units west on the field. The landing spot changes the
  light, not only the framing: at (952, -512) Robin's cheek measured 0.0072 at night, at (831, 576)
  0.0140. Placing the player on (831.235, 576, -143.08) at angles (0, 180, 0) reproduced the head
  position to 0.01 units and the frame with no pixel shift.
- Under Remix, `render.GetLightColor` returned 0 at every candidate interior point on gm_construct,
  so it cannot rank how dim a room is. `util.IsInWorld` is server-only; on the client
  `util.PointContents(pos)` without `CONTENTS_SOLID` stands in. A floor point under a full roof (no sky
  straight up or 45 degrees up in eight directions) with walls on seven sides found 15 rooms within
  6000 units of (831, 576); most are one building east of the spawn, floor z -144, ceiling 176-192
  (for example (1227, -1669, -144), walls 267-700 units away). A looser test (sky only straight up)
  picked (-1386, -2067, -128), an alley under an overhang, where the spawned ragdoll was not valid on
  the client three seconds after `ready`.
- The runtime's exposure (`auto_exposure.comp.slang:86,147-150`) is `0.18 / (Yf + 0.0032)`, capped
  at `rtx.autoExposure.maxExposure` (16 in the package); patch 0016's `adapted_yf` is that frame's
  centre-weighted geometric mean, while the exposure is smoothed (tau 0.15 s brightening, 0.75 s
  darkening, `rtx_auto_exposure.h:132-144`). At night the log showed `adapted_yf` 0.00046-0.00069 at
  exposure 16.
- Patch 0016's packing is lossless in this fork: the DLSS control mask's alpha byte is always `0xff`
  (`rtx_materials.h:982-986`), and the invalid subsurface index `SURFACE_INDEX_INVALID` is
  `0x001FFFFF` (`common_binding_indices.h:162`), inside the 24 bits kept.
- The eye white over the cheek (Robin, the probe's framing) is linear in the adaptive ratio in every
  condition. Per `1/0.18` of ratio: noon 0.107, golden hour 0.223, dusk 0.083, night 0.11; the
  intercepts (the eye's lit part alone) 0.51, 0.39, 0.40 and 0.20. Ratio 25 then gives 0.98, 1.38,
  0.77 and 0.70 (measured; interpolation predicted 0.99, 1.39, 0.77, 0.70). Fixed emission gave 0.69,
  0.52, 0.88 and 46 ([ADR 0069](decisions/0069-tuned-adaptive-eye-emission.md)).

## C16-B: publishing scene-adaptive eye emission (2026-10-31)

- `skills/mmd-remix-pbr/tool/rpai/compose.py:618-630` normalises the emissive map by its largest
  class weight `S`; `cli.py:411-420` restores `S * I` at publish and now writes adaptive intensity
  `(S * I) * R` for cached maps whose coverage includes `sclera`, `eye` or `highlight`. No maps
  or class weights need regeneration. `config.py:59` sets provisional `R = 1 / 0.18`.
  Class coverage at `cli.py:324` is rounded to four decimals, but its keys include every present
  class, so publish tests key presence even when a tiny eye region's coverage rounded to zero.
- `packages/runtime/layers/classic_remix_defaults.conf:59` sets `targetAdaptedYf = 0.18`
  (`maxExposure = 16` at line 146). Using the C16 plan's exposure equation, mid exposure 1 gives
  `L_mid = 0.18`, ignoring noise. Thus `M * (F / 0.18) * L_mid = M * F`: the old eye-white
  `C * 0.025 * I` at that reference. This is a derivation, not an in-game brightness measurement.
- Read-only PoC pack inventory: `pbr_robin/models/robin_r18_f9c3e4b4.usda:136-191` has three
  emissive overrides (`203355325A5208A0`, `70EC49FA6891154F`, `06DDF9D48A2DC2B1`), all fallback
  0.6. Evernight's `models/evernight_cf3eec2f.usda:64-69` has `596BBF16AC554B2E` at 0.6;
  March 7th's `models/model_e2c25f9e.usda:50-55` has `175BEFCBA6AE4083` at 0.04. Guinaifen's
  `models/new_mmd_model_1c2ed2fc.usda:93-123` has `4D84DF2D4E18DDE1` and `C8A78C7CF9EE33F2`
  at 0.6. The different normalisations require a per-fallback ratio when migrating together.
- Demonstrated `set_adaptive_emission.py --multiplier 5.555555555555555` on copies under
  `out/c16-b/packs/`: seven inputs added across four model layers, values 3.33333333 (fallback
  0.6) and 0.222222222 (fallback 0.04). All 157 original files (32/79/46 by pack) were hashed
  before copying and after the demonstration; their hashes and modification times match.
  Dry runs and repeat runs preserve every copied byte/timestamp; only the seven inserted lines
  change layer bytes, with `mod.usda` touched for reload. Evidence: `out/c16-b/demonstration.json`
  and per-pack command logs. No game was launched or install written.
- `scripts/package_characters.py:74-78` within the skill copies and checks USD layers byte for
  byte, retaining adaptive and fixed inputs. `scripts/set_adaptive_emission.py:44-118` masks
  literals/comments and edits byte ranges; `:138-174` preflights every layer before writes,
  reports changed material names and touches the existing root only after an actual edit.

## R6 T3: independent-review fixes (2026-10-31)

- At base `7759c43`, `loader/core/src/config.cpp:52,78` permits neither a top-level `diagnostics`
  nor `remix.performance_tier`; `loader/core/src/startup.cpp:132-135` turns configuration errors
  into `may_activate = false`. Workshop companion updates therefore gate new instructions on
  the additive I2 capability, not their own version. `dist/native-loader/config.json:1-6` has only
  schema and allow, so fragment-only examples neither describe the shipped file nor preserve trust.
- The fixes' `source/remixapi/remixapi.cpp:1311-1325` warns on every unavailable/failed VRAM API
  request; `resource_lua_bindings.cpp:38-71` returns nil for it. Three consecutive failures now
  stop automatic calls until an off/on retry or a map/start; late API availability stays supported.
- `skills/mmd-remix-pbr/tool/rpai/cli.py:391-418` replaces the model layer and prunes its unused
  DDS files under the chosen mod. `--mod` at `cli.py:621` supplies that folder name. A 2048 px
  publish must use a separate mod to preserve a larger variant's published textures.
- Full-access re-check reproduced the guard fixture's 262-character path failure in unchanged
  `test_early.cpp:198`; its shorter-output executable passes all 22 guard cases. The sandbox-only
  observations in the original T3 notes below are historical, not current access restrictions.
- The byte-identical default-layout guard executable (SHA-256 `698ce23a0abff6c8f90334f01f6864a2697c783e940bbc5ec9c4bfbb0cc928aa`)
  passes all 22 cases from `out/r6-t3-fix/guard-short`; full-access `tools/test.ps1 -Config Release`
  passes all 23 CTests and 288/28/25 tools/gmapack/Steam Python tests. The old registry/Git errors
  did not recur. Receipts are in `out/r6-t3-fix/`; no native source was changed.

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
- Source recheck: patched R6 T4 snapshot `29546f3566a676a1318b799fb8ddd01b2a110058`, C++ paths
  below relative to `src/dxvk/rtx_render/`. OMM's free-memory growth calculation includes the
  default 384 MiB buffer (`rtx_opacity_micromap_manager.h:58-64`, `.cpp:175-182`): medium/low
  leave 1408 MiB when calculating new growth budget, not 1024 MiB. Existing budget is retained
  between soft/hard limits; it is recalculated below 1024 MiB. `lowMemoryGpu` also halves the OMM
  VRAM percentage (`.cpp:162-173`), skips the top streamed replacement-texture mip
  (`rtx_texture_manager.cpp:1623`), and sets the low-memory AS build flag
  (`rtx_accel_manager.cpp:292-293`).
- A bounce-cap stop is not an NRC query:
  `src/dxvk/shaders/rtx/algorithm/integrator_indirect.slangh:860-885` resolves NRC termination first,
  then stops at the query path's bounce cap without
  querying the cache there. `rtx_neural_radiance_cache.cpp:697` sets NRC `maxPathVertices` from
  `trainingMaxPathBounces`. Mirror/transmission paths can lose light beyond the tier cap.
- **Changing `lowMemoryGpu` does not issue an incompatible AS UPDATE.** Automatic graphics
  selection writes it (`rtx_options.cpp:419-461`); the ordinary-GPU decision defaults false
  (`rtx_gpu_profile.h:55`) and sets true for at most 8 GiB (`:61`, `.cpp:212-220`). Both BLAS
  UPDATE sites guard with `validateUpdateMode` (`rtx_accel_manager.cpp:892-895,1258-1262`), whose
  flag comparison rejects the change (`:2011-2016`). The affected BLAS builds on next use instead;
  TLAS always uses BUILD (`:1946-1951`), as does the one-time intersection BLAS (`:296-312`).
  Expect rebuild/allocation work per affected BLAS, not an invalid UPDATE. Timing remains unmeasured.
  PoC tuning question: class-limited low on an RTX 3060 12 GB or 4060 Ti 16 GB still gets the top-mip
  drop despite its larger memory. On modern_house the switch saved about 226 MiB of replacement
  textures (ADR 0064); it stays, and following the VRAM tier instead needs a loader change.
- **The sky LOD argument is conditional.**
  `src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_sky.slangh:408-439` uses real texture width/height.
  Halving them subtracts one from
  unclamped LOD, preserving samples only when original LOD >= 1. With native 3840 × 2160,
  90-degree horizontal FOV and zero mip bias, `pixel = 2/3840`: stars' minimum radial stretch
  from `:365-366,404-409` gives LOD >= 2.21; galaxy `:427-429` gives 1.03; nebula `:435-439`
  gives **0.44**, blending the missing original mip 0. The pixel angle includes FOV, traced height
  and mip bias (`rtx_atmosphere.cpp:2914-2916,2934-2941`; `rtx_scene_manager.cpp:320-346`).
  Narrow FOV/negative bias can expose mip 0 too. Medium therefore retains all original sky images
  pending PoC comparison; switching all three would save 160 MiB of texels but is not guaranteed
  visually identical even at a normal FOV in 4K.
- `tools/tests/test_runtime_tiers.py` pins the tier option types/ranges/enums to those patched
  declarations and their UI limits (including the six sky-probe extents in
  `src/dxvk/imgui/dxvk_imgui.cpp:3390-3399`). Every layer is parsed; classic/compiler bytes are pinned
  separately because classic contains 15 obsolete options with no matching current declaration
  (old exposure/localtonemap/bloom keys, `rtx.occluderTextures`, `rtx.tonemap.finalizeWithACES`).
  The source's `RtxOptions.md` SHA-256 is
  `4a457a8d1e3bb6dbf00efe05720fd9c8c4ea8621509fa72c6621313eb685cc57`. This avoids inventing
  runtime support for old high-tier keys while rejecting any new or misspelt tier key.
- PoC measurements of the tiers (2026-10-31, 4K, RTX 5090): medium and low 5-9 % faster than high,
  170-750 MiB less VRAM, identical pinned runs within 4.5 %; low now uses 8 bounces. Numbers and
  method in ADR 0064.
  [ADR 0064](decisions/0064-performance-tier-defaults.md) records the tuning and acceptance checks;
  run-specific history is in the [handover status](handover/R6-T6-performance-tiers.md#status).

## R6 T2 evidence boundaries (2026-10-31)

- The stock menu's [`lua/menu/mainmenu.lua`](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/menu/mainmenu.lua#L23-L32)
  quotes string arguments to `lua.Run` and exposes `pnlMainMenu:Call` through `QueueJavascript`
  (lines 156-159, read 2026-10-31). R6 uses that bridge for bounded DATA reads and JSON-encodes parsed
  results again; it never concatenates raw file text into executable JavaScript.
- `loader/proxy/ui/mainmenu.js:30-63` validates creation-time tokens and a 30-second snapshot age,
  consumes a RAM warning only while visible before the first map, and acknowledges it in the menu
  Lua realm. `loader/core/src/memory.cpp:72-74` uses strict, overflow-safe 32-GiB/70-percent thresholds.

- `loader/core/src/memory.cpp` dynamically resolves `K32GetProcessMemoryInfo` and
  `K32GetPerformanceInfo` from KERNEL32 and converts performance-info page counts to bytes. DXGI
  is loaded from System32 and queried through `IDXGIAdapter3::QueryVideoMemoryInfo`; no PSAPI/DXGI
  import library is linked. Release's `check_imports.py` still reports only `KERNEL32.dll`.
- CSV rows use optional counters so an unavailable GPU query stays blank rather than appearing as
  zero usage. Two 360-row/256-KiB segments bound default history to about one to two hours. The
  latest system commit snapshot is independent of CSV history, so the RAM warning can work with
  `diagnostics.memory_telemetry: "off"` without recording process/GPU data.

- Release fixture measurement (30 consecutive empty collections on this machine): mean 0.556 ms,
  maximum 0.883 ms (a previous run averaged 1.419 ms, maximum 8.056 ms during concurrent work).
  Session-start metadata uses an atomic rename without the deployment journal's
  write-through flushes; its loss after a power failure falls back to the older loader record.
  Empty/clean starts do not re-hash old archives; retention runs only when a new archive is saved.
  A later measurement during concurrent Release checks averaged 1.145 ms, maximum 1.658 ms.

- The long T2 worktree makes the unchanged early-guard idempotence test's cache path 261 characters.
  `test_early.cpp:198` uses plain `std::filesystem::last_write_time` and fails there, despite the file
  existing and system `LongPathsEnabled=1`. An archived, rebuilt original commit `7759c43` fails at
  the same line; its identical executable passes when copied to the shorter worktree `out` path.
  T2's Release check uses a local CMake output-directory override only for that test executable;
  test sources and coverage are unchanged. No system setting or other worktree was changed.

- Runtime fork `src/util/log/log.cpp:75-94` opens `remix-dxvk.log` with a plain `std::ofstream`:
  starting the runtime truncates it. R6's worker signals readiness only after the log copy/fallback
  is secure, and bootstrap waits before runtime activation (`loader/proxy/startup.cpp`).
- The fork has no general clean-exit log marker. `src/dxvk/rtx_render/rtx_context.cpp:945-953`
  logs `RTX: Terminating application` only for its deliberate delayed termination after captures/
  exports finish. FSR `onDestroy`/context-destroyed lines are resource lifecycle messages and do
  not establish a clean process exit. Unmarked sessions remain `unknown`.
- Engine OOM text can be ASCII or UTF-16 LE inside a dump. R6 scans bounded, copied game-root
  dumps in 64 KiB chunks with a 64-byte overlap; it does not load the dump into memory or execute it
  (`loader/core/src/evidence.cpp`, `loader/tests/test_evidence.cpp`).

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
  for the verified runtime rebuild. The fresh runtime tree also needed seven unit/app test sources
  omitted by the snapshot's ignore rules, read from the existing verified tree to finish Meson
  setup; these do not enter the runtime DLL. R6's review below distinguishes staged additions from
  untracked local copies.

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

Source references below are to patch 0015 on the recorded fourteen-patch tree. The review fixes
supersede the initial runtime commit `86ac49e9`; the final identity is in
[runtime/README.md](../runtime/README.md#r6-t4-rebuild-2026-10-31). The user's fork checkout was not changed.

- `DxvkSubmissionQueue::handleDeviceLost` (`src/dxvk/dxvk_queue.cpp:407`) is shared by the submit
  and fence-finish loss paths (`:307`, `:357`).
  It retains the single-handler gate and calls `onGpuCrash(reason)` inside it. The first diagnostic
  work in `onGpuCrash` (`:148`) logs/writes the memory snapshot with the supplied queue reason before
  the crash-state recorder and either Aftermath wait. The bridge notification precedes it and
  returns immediately on the inactive GMod x64 bridge. Another loss thread cannot reach
  Sentry/termination while the first is recording crash state.
  No GPU synchronization is added by diagnostics.
- The VRAM API's collection previously lived in `rtx_fork_api_entry.cpp:864-893`. It now calls
  `RtxMemoryDiagnostics::capture` at line 864. `rtx_memory_stats.cpp` collects all driver heaps,
  bounds the heap loop by the snapshot array's size, labels each with `device_local` (`:43`), and
  sums driver budget/use, DXVK allocations/use and eight categories only across device-local heaps.
  The serialized `driver` totals are the API's
  `driverBudgetBytes`/`driverAllocatedBytes`. It does not
  read the render-owned texture table; the API still adds its cache count separately.
- `DxvkAdapter::getMemoryHeapInfo` (`dxvk_adapter.cpp:79-108`) queries physical-device memory
  properties, rather than waiting for GPU work. With `VK_EXT_memory_budget`, budget/use are driver
  values; without it, budget is heap size and usage is DXVK's tracked heap allocation counter.
  Snapshots preserve those semantics and are approximate cross-thread observations.
- `RtxContext::onPresent` (`rtx_context.cpp:919`) polls a device-owned steady-clock schedule, giving
  one sample per cut frame and every five minutes while frames are presented. Camera cuts do not
  reset the periodic deadline (`rtx_memory_stats_data.h`). The first deadline is five minutes
  after device creation. Cut samples show the outgoing scene before the delayed cut-driven clear
  (`rtx_scene_manager.cpp`, `m_enqueueDelayedClear`). A stopped render loop cannot log a periodic sample.
- OMM is recreated at cuts (`rtx_scene_manager.cpp:3134-3152`), so its two one-minute warning limits
  belong to the device (`rtx_memory_stats.h`). The next eligible occurrence reports the suppressed
  count; no background thread flushes idle warnings (`rtx_memory_stats.cpp`). Device-loss snapshots
  also include both pending counts in `omm_suppressed`, read atomically across threads. The
  budget-dropped branch runs only after its budget is zero, so `getAvailable()` and the new budget
  carry no information there. It now passes `m_vidmemFreeSize`, `m_prevBudget`, `m_used` and the
  hard/soft free-VRAM limits to `logOmmBudgetDropped`, before invalidating the free-VRAM sample
  (`rtx_opacity_micromap_manager.cpp:175-195`). The warning names all five values and their byte units.
- The crash marker uses the same `RtxFileSys::Logs` directory as `remix-dxvk.log`, including
  `DXVK_LOG_PATH` (`src/util/util_filesys.h:65`). `rtx_memory_stats_data.cpp` checks `WriteFile`,
  `FlushFileBuffers` and `CloseHandle` on `last_gpu_crash.<pid>.tmp` before `MoveFileExW` replacement.
  Sharing violations/access denial receive at most three replacement attempts and two 10 ms sleeps;
  write/replacement failure deletes that process's temporary file. A different process's temporary
  file is left alone. `onDeviceLoss` logs first and still attempts the marker if logging throws.
  A failed write keeps the old marker; timestamps must be checked by the next-start reader.
  The timestamp belongs to the captured snapshot, so the marker and log line match even if the
  write crosses a second boundary. The optional `reason` appears identically in the log and marker,
  with quotes, backslashes and control bytes JSON-escaped. Logging and file failures cannot unwind
  through `onDeviceLoss`.
- Patch 0001's snapshot omitted five unit-test sources that its Meson file names:
  `test_particle_system_schema.cpp`, `test_hot_reload.cpp`, `test_rtx_option_dynamic.cpp`,
  `test_gpu_profile.cpp`, `test_gpu_overrides.cpp`; and `apps/RemixAPI/remixapi_medium_test.cpp`.
  All six are tracked, staged additions in the user's mid-merge fork index, not ignored local
  copies. The `.gitignore:63` wildcard hid them from the snapshot operation. Patch 0015 now records
  their staged bytes read with `git show :<path>` and removes the six silent source guards.
  The five unit sources total 3,008 lines; the medium API app is another 377 lines. It is a
  standalone GPU/rendering app, not one of Meson's registered CPU unit tests.
- The development-only GPU crash trigger is real GPU work:
  `rtx_context.cpp:498-503` dispatches `metaGpuCrash()` after Ctrl+Shift+Alt+G when armed by
  `RTX_ENABLE_CRASH_HOTKEY=1` (`rtx_options.h:1092-1105`). It is compiled out without
  `REMIX_DEVELOPMENT` and was not exercised by T4.
- The fork's `scripts-common/install_file_in_dir.bat:2-12` enables delayed expansion before
  assigning its arguments; `install_usd_plugins.bat` also enables it around paths. A source path
  containing `!` is stripped during unit dependency staging. T4 used literal-path PowerShell
  copies into its own unit build after that helper failed. The initial 22-test suite passed; the
  review build passes 27/27 with the five restored unit sources.

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
  The PM later fetched it into the fixes checkout as `codex/r6-no-memory-limits`; the PDB matching
  the shipped DLL is kept in the main checkout's `out/fixes-memory-limits-build`.

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

### R6 T1 independent-review corrections (2026-10-31)

The local runtime fork at `6f2dbd79` routes Aftermath files into its existing Sentry GPU report:
`src/dxvk/dxvk_instance.cpp:392` calls `queueGpuCrashReport`; `src/util/util_sentry.cpp:447-496`
attaches the dump to the event and captures/flushes it, and `:858-863` applies the runtime's
consent flow. Dumps written under the loader's local folder may therefore be uploaded when the
player accepts Remix crash reporting. R6 does not alter that reporting policy.

The two new DXVK paths and their commas add exactly 67 characters: tier.conf plus diagnostics.conf.
Regression tests combine them with package copies and a user-supplied DXVK list at 259 (accepted)
and 260 (warning that Remix ignores the list) characters. RTX 5090 D uses the consumer class rule;
GTX 1080 Ti and RTX A2000 Laptop GPU use VRAM alone. The Laptop adjustment runs only after a
consumer RTX class is recognized. Invalid UTF-16 descriptions can throw from filesystem UTF-8
conversion; the startup adapter reader now keeps vendor/VRAM with an empty name instead.
- The second review's offline scratch setup uses the same direct Python/Meson command as
  `runtime/build_runtime.ps1` after `Enter-VsDevEnv`. All 95 recorded build options match the real
  `_CompRelease_x64`, including optimization 3 and the release DLL CRT. Only Meson's compiler
  probes ran; no runtime targets compiled. The scratch folder was deleted after comparison
  (`out/tmp/runtime-review2-setup-comparison.json`).
- T2's reader on integration commit `1dc93125` (`loader/core/src/evidence.cpp:188-202`) parses the
  marker and reads only a string `event`; its JSON parser stores arbitrary object members without
  a field allowlist. Unknown `device_local`, `driver`, `omm_suppressed` and `reason` fields are
  ignored. Its existing `loader/tests/test_evidence.cpp:36-52` checks a minimal device-loss marker,
  optional/unrelated fields and malformed JSON. No loader code or tests changed in this T4 pass.

### R6 harness device-loss freeze (2026-10-31)

Read-only PM evidence in the main checkout's `out/qa-poc/r6/tiers-pinned/session.json`, record
`04-house-auto-pin`, starts at `2026-11-01T00:52:47Z` and finishes at `02:48:47Z`: 6,960 seconds
(1 h 56 min), with `map_loaded: true`, `seconds_to_map: 7.5`, failed mount/map/camera/FPS steps and
exit 3489660927 (`0xCFFFFFFF`). That step's `remix-dxvk.log:990` records
`DxvkSubmissionQueue: Command submission failed: VK_ERROR_DEVICE_LOST`. The old harness only declined
prompts inside startup/map waits and called `PrintWindow` synchronously; a GPU-crash dialog could
therefore outlive those waits and block evidence capture. The R6 harness change checks the current
run's log, watches prompts through exit and bounds capture/shutdown; regression tests use fakes.

## C-16: scene-adaptive emission

Runtime paths below refer to the isolated source built from `runtime/base.json` plus patches
0001-0016; the source is under this task's `out/runtime-src`.

- `src/dxvk/shaders/rtx/pass/tonemap/auto_exposure.comp.slang:143-170` computes the actual
  geometric-mean Yf before the cone-noise division and exposure cap, then smooths exposure in log
  space. Patch 0016 writes `(adaptedYf, exposure)` to an eight-byte buffer at `:170`. This preserves
  the statistic in capped scenes instead of reconstructing it from exposure.
- `src/dxvk/rtx_render/rtx_auto_exposure.cpp:78-122` checks completed readbacks at a minimum age of
  two frames, selects the newest, clamps the effective luminance and logs the source frame/age,
  Yf and exposure at cuts/five-minute intervals. `:260-264` queues a copy only into an idle slot.
  `DxvkContext::copyBuffer` (`src/dxvk/dxvk_context.cpp:779-843`) records transfer/host access
  barriers and tracks the destination as a GPU write. `DxvkResource::isInUse`
  (`src/dxvk/dxvk_resource.h:38-43`) includes pending writes, so the CPU never reads or overwrites
  an outstanding transfer. No wait or game-side readback stall is introduced.
- `src/dxvk/shaders/rtx/pass/instance_definitions.h:142-143,167-168` limits material indices to
  21 bits. The 32-bit subsurface index therefore has a free high byte. The opaque CPU packer
  (`src/dxvk/rtx_render/rtx_materials.h:737-744,983-987`) also always sets DLSS mask alpha to 255.
  Those bytes hold a split half-float, with the second XORed by 255 to preserve the legacy bytes
  for input zero. Shared helpers live in `src/dxvk/shaders/rtx/utility/adaptive_emission.h`.
  Shader accessors (`surface_material.h:110-120` in `concept/surface_material`) mask the index,
  restore alpha and recover the half. Both the packed 64-byte record and the CPU object's
  168-byte size are unchanged; the added CPU float consumes existing alignment space.
- The new X-macro input (`src/dxvk/rtx_render/rtx_material_data.h:60`) participates in USD loading,
  defaults, range sanitization, serialization and hashing. The GPU hash includes it at
  `rtx_materials.h:873,910,946`; `rtx_remix_api.cpp` preserves it through texture preload and uses
  zero for the unchanged public API, and terrain baking uses zero.
- `src/dxvk/shaders/rtx/concept/surface_material/opaque_surface_material_interaction.slangh:557-560,950-957`
  covers the Source-eye override and general opaque evaluation. The latter keeps
  `emissiveBlendOverrideInfluence` intact. The G-buffer decode at `:1035-1054` reads already
  evaluated radiance; scaling it again would apply adaptation twice. Decals and polymorphic
  conversions likewise carry evaluated radiance. Subsurface and RTXCR readers use decoded indices.
- The runtime part's index has no `AperturePBR_Opacity.mdl`. The combined package carries one in
  `packages/fixes/garrysmod/rtx-remix/mods/base_mod/breakable_glass/assets/remix_materials/`.
  Its `AperturePBR_Opacity.mdl:162-170` now declares the input (zero default, 0..65504 hard range,
  description); the MDL preview continues to use fixed intensity. This one plain-text input was
  reimported through `tools/inputs.py`, without changing the other fixes inputs.
- A copied configured tree also needs its shader `.d` files relocated. In
  `scripts-common/compile_shaders.py:75-108,193-201`, timestamp checks follow those stored include
  paths, so removing `_built_shaders.txt` alone can reuse old SPIR-V while reading the original
  tree's unchanged includes. C-16 relocated 694 dependency files in each copied configuration.
  The final Release log records actual shader compilation; disassembly confirms binding 4 and an
  eight-byte `OutAdaptation` stride. `out/tmp/c16-embedded-shaders.json` proves the freshly compiled
  5,888-byte auto-exposure SPIR-V and 74,616-byte opaque G-buffer SPIR-V occur byte-for-byte inside
  the final DLL (offsets 380,900,976 and 12,898,160 respectively). No source or build output in the
  R6 tree or the user's fork was changed.

## G1-B fix pass: real-map collision findings (2026-11-01)

- Read-only gm_construct probe (36,735,656 bytes): baseline considered 2,095 brushes, clipped
  2,092, skipped 3; Jolt refused one hull and aborted the entire world in 55.38 ms. Double clipping
  reduces the maximum hull from 46 to 24 vertices; cooking skips/counts the one remaining refusal.
  The corrected world has 2,094 static bodies (2,091 brush bodies + three terrain mesh batches),
  20,992 displacement triangles, four prop metadata entries (not cooked by the offline probe).
  Initial corrected parse/build: 46.98 ms, standalone parse 14.25 ms. Evidence stays under this
  worktree's ignored `out/g1-native-fix/`; QA logs 01-qa and 02-qa were read only.
- The installed map's displacement tags are 6 (20,801), 2 (122), 0 (69): **zero** SURFACE bits.
  Requiring bit 0 silently discarded all terrain. The local Source SDK reference's
  `public/bspfile.h:624-629` names SURFACE/WALKABLE/BUILDABLE/REMOVE (bits 0/1/2/5).
  Import now omits only REMOVE-tagged triangles; generated tests cover tags 0, 2, 6 and holes.
- The same local reference's `public/builddisp.cpp:1918-1994` interpolates rows along 0->1 and
  columns along 0->3 (`ndx = i * postSpacing + j`); our parser had those swapped. The uneven
  generated fixture now asserts a raised vertex at (200,210,1.25), never its transposed position.
  This was read for format facts only; no GPL implementation was copied.

## G1-B fix pass: background work and pile cost (2026-11-01)

- `glass/native/world.cpp` now snapshots Jolt's old/new active IDs across an update, uses exclusive
  NoLock body access and a dense pose queue, and counts contact/manifold/pair/constraint saturation
  instead of throwing. A generated 128-body overlap saturates the cache and remains ready; the
  ordinary 4,000-body benchmark reports zero overflows. A measured 4 ms catch-up budget permits at
  least one step and at most four, discarding whole excess steps. At 4,000 bodies a .25-second
  dispatch ran one substep and counted .233333 dropped seconds.
- Same-machine pre-fix core baseline: 4,000 live / 8,192 slots, eight workers, 11.0167 simulated
  seconds to sleep, 2.706 s wall / 18.797 s process CPU, 4.094 ms mean / 7.380 ms max active step,
  .0640 ms settled step+poses. Corrected synchronous diagnostic: 11.0167 seconds to sleep,
  3.295 s wall / 22.703 s CPU, 4.983 ms mean / 7.874 ms max, .00162 ms settled. Active worker
  throughput did **not** improve in that comparison; moving it off the client thread is the material
  change. Async dispatch averaged .0134 ms (max .0605); polls averaged .00296 ms (max .0203), while
  the worker averaged 5.434 ms/update. These are native-only measurements, not game frame times.
- `Init(8192)`/map cooking now reserve **zero simulation scratch**, rather than 144 MiB. The first
  active step sizes scratch to live demand and observed peak with a non-aborting fallback. Pair /
  contact capacities are max(1024,budget*8) / max(1024,budget*4). The 4,000-body test held 34 MiB
  scratch and peaked at 30,234,553 requested bytes (28.83 MiB). Doubling contact capacity used
  56 MiB with no useful throughput gain, so the smaller bounded table is retained.
- `module.cpp` Begin/Poll entry points copy BSP bytes before a worker parses/cooks them, and
  asynchronously optimize the final broadphase and step physics. Busy access refuses immediately;
  Stats returns a pre-dispatch snapshot. Cleanup/shutdown joins before freeing the world. Generated
  core and actual binding callbacks cover pending polls, no concurrent mutation, worker exceptions,
  teardown while importing/stepping and foreign realms.
- Read-only gm_construct final probe: 2,095 considered / 2,092 clipped brushes, 3 clipping skips,
  1 Jolt refusal, 20,992 triangles, zero refused mesh batches, four prop records, 2,094 static bodies.
  Standalone parse 15.98 ms, Init .91 ms, parse+cook+finish 53.62 ms. Async enqueue including the
  36,735,656-byte copy took 4.80 ms; maximum poll 1.41 ms; total 78.11 ms. The VFS read still runs
  on the engine thread; this offline probe excludes it and excludes engine prop model extraction.
- LuaJIT mocked-physics comparison of the original 3096b2e helpers against corrected helpers:
  4,000 active manager Think calls .165 -> .135 ms mean; settled .130 -> .026 ms. These include
  the same mock pose filling but exclude real physics, engine mesh uploads and rendering. Spawn
  still constructed all 4,000 meshes in 108 -> 111 ms CPU in this synthetic burst; initial mesh
  creation is not claimed to be cheap. Settled chunk count grows from 3 to 25 in this deliberately
  single-area pile, bounding replacement/wake work. Ordinary game piles span multiple areas.
- `debris_batches.lua` transforms up to 1,800 vertices/frame, accumulating at most 6,000 per mesh
  and uploading one mesh/frame. Valid old chunks remain until the complete replacement exists;
  wake/removal hides only its affected chunk. New arrivals request a later snapshot; removals cancel
  stale staging; failed GPU builds retain old geometry. The Lua harness covers stale unchanged pose
  rows, staged replacements, upload failure/retry, busy-world queues and complete mesh cleanup.

- Final import polling additionally releases its large owned BSP buffer on the worker before
  publishing completion (`World::begin_load`), avoiding a client-side deallocation stall. Final
  gm_construct receipt: synchronous parse/cook/finish 46.60 ms; async owned-copy enqueue 3.79 ms,
  max poll .0069 ms, total 76.12 ms. Geometry counts are unchanged. An unchanged pile area now
  leaves the rebuild work set entirely; only dirty/staged areas enter Think.

## G1 integration: glass in the game (2026-11-01, Claude)

PoC, 1920x1080 windowed, RTX on; runs under the main checkout's `out/qa-poc/g1/`.

- **GMod takes the run speed from the user command's buttons.** A server `SetupMove` hook that adds
  `IN_FORWARD | IN_SPEED` to the move data and sets `SetMaxClientSpeed`/`SetMaxSpeed` to the run speed
  still tops out at the walk speed, 200 units/s (run 06). A `StartCommand` hook in both realms that
  sets the command's buttons and forward move reaches 400 (run 07).
- **Archived Lua convars outlive their add-on.** GMod keeps them in `garrysmod/cfg/server.vdf` (server
  realm) and `client.vdf` (client realm) and restores a value when a later add-on creates a convar of
  the same name, over that add-on's default. The PoC still had Glass-Rewrite-Remix's
  `rtx_glass_player_break_speed "80"`, `rtx_glass_velocity_transfer "2.000000"`, `rtx_glass_rigidity`,
  `rtx_glass_shard_count` and others; with the new system the 80 let a 200-unit/s walk break glass
  (run 08: one impact, 14 % of the pane left). After the one-time reset (run 10) the file holds 250,
  1 and `rtx_glass_settings_version "1"`, and the walk leaves the pane whole.
- **50 panes broken by blasts, same view** (frame mean / p99): old system (run 12, published package
  `0.0.0-dev.20261101052452+2768a059`) empty 8.87 / 10.20 ms, falling 18.18 / 109.13 ms with 361 shard
  entities, settled 10.89 / 14.49 ms with 302; new system (run 10) before 8.75 / 11.77 ms (787 settled
  pieces present), falling 25.31 / 113.22 ms (2,000 live, 1,236 moving; manager 1.69 ms think, 6.99 ms
  draw; Jolt step 1.50 ms), settled 9.74 / 16.39 ms (62 batches; manager 0.16 ms).
- One annealed 96x64 pane breaking into 161 pieces gives a 62 ms frame (run 10 `bullet_break` p99),
  while its fracture costs about 0.7 ms offline: most of the spike is piece creation or Remix taking
  in new geometry.
- modern_house (run 11): the map alone runs at about 19 ms per frame here; 44 native glass panes; a
  window broken by rounds gives 203 pieces; a ragdoll burst 391 live, 25.83 / 161.8 ms while falling.

## R7: alpha in GMod RTX (2026-11-01, Claude)

PoC, gm_construct, noon, 1920x1080; runs under the main checkout's `out/qa-poc/r7/`.

- **GMod RTX draws models with Source's fixed-function shaders**: `Material(...):GetShader()` returns
  `VertexLitGeneric_DX7` and `UnlitGeneric_DX6` although `mat_dxlevel` is 90.
- **Alpha-tested lit materials cut at about 0.7.** Plates with a 16-band alpha ramp (`04-ramp`): every
  `VertexLitGeneric` alpha-test variant (`$alphatestreference .5`, `.2`, with or without
  `$allowalphatocoverage` or `$vertexcolor`) shows only the top bands; `UnlitGeneric` near 0.5. The runtime
  takes the draw's `D3DRS_ALPHAREF` (`src/d3d9/d3d9_rtx_utils.cpp` `setLegacyMaterialState`), so Source's
  DX7 path sends a fixed reference, not `$alphatestreference`.
- **Blended draws are opaque only above `rtx.stochasticAlphaBlendOpacityThreshold`** (0.79 in
  `packages/runtime/layers/classic_remix_defaults.conf`, 0.95 the runtime default) and a stochastic dither
  below. A blended opacity in (`resolveTransparencyThreshold`, that threshold] is skipped by primary rays
  (`shaders/rtx/algorithm/resolve.slangh`, the stochastic early out), while visibility rays attenuate by
  `1 - opacity` (`shaders/rtx/algorithm/visibility.slangh`).
- **Model Hotloader's soft alpha** (`mmdhl_soft_alpha`, default on) draws triangles with partly transparent
  texels blended in the opaque pass under Remix (`native_render.lua`). Columbina's mask (bars 0.65, panes
  0.26) therefore vanished and shadowed her face (`03-columbina`); a root `rtx.conf` threshold of 0.5 drew it
  as in MMD (`05-columbina-thr05`).
- `SetMaterial` on a client-side model did not change what drew in this setup (`01-plates`); a
  `RenderOverride` with `render.MaterialOverride` did (`02-plates`).
- A field game started without `-console` ignored `WM_CLOSE` on its `Valve001` window for 45 s.

## R7-C: one-way bodies and subsequent debris damage (2026-11-01)

- `glass/native/world.cpp:124,223,401` confines body response to kinematic mirrors and coalesces hard
  contact energy in a bounded atomic queue. Jolt sees Source's sampled transforms/masses; Source
  receives nothing. Pair layers keep mirrors away from map/other mirrors and preserve piece-piece off.
- `glass/addon/lua/nlglass/debris_scene.lua:129` extends only living mirrors eight units below their
  feet. A generated native regression with an exact flat-bottomed hull failed to move thin floor
  glass; the extension moves both large and minimum-size pieces while retaining the prescribed path.
  This is an approximation requiring game tuning, not a change to Source movement/collision.
- `world.cpp:465,505,526` prioritizes 32 live-piece regions near the eye, raycasts local glass and
  transactionally bisects convex prisms. Polygon clipping preserves area and thickness; children
  inherit point velocity. `debris.lua:247` stages one replacement/frame, budgeted oldest first;
  `debris_expiry.lua` preserves the original deadline without scanning normal settled pieces.
- [Facepunch's PostEntityFireBullets contract](https://wiki.facepunch.com/gmod/GM:PostEntityFireBullets)
  supplies final per-pellet traces/damage, avoiding callback replacement or predicted duplicates.
  `debris_bullets.lua:38` bounds inspection (256/s), forwarding (64/s globally, 16/s/firing entity),
  recent interest and PVS. Source trace endpoints retain gameplay occlusion; there is no piece stream.
- Offline feature costs on this machine: 96 warm native mirrors plus 2000-piece interest 0.108 ms,
  ray 0.00102 ms mean, native can-split/replacement 0.0197 ms mean / 0.0344 p99; two maximum-input
  shapes cost 2.644 ms, excluding engine extraction. These do not establish RTX frame parity.
  See the [report](handover/R7-C-report.md) for repeat counts, starting/current comparisons, caps,
  evidence paths, limitations and Claude's acceptance steps. G1 run 10 was read only.

## R7-A: Model Hotloader alpha, 2026-11-01

- Read-only verification of Columbina's existing PoC `materials-v5.gma` confirms
  `materials/mmd/275705586db7e069/yan_zhao_16.vmt` binds
  `mmd/t/2c7b2c8505cc6a6e`, with `$alphatest 1`, `$alphatestreference .5`,
  `$allowalphatocoverage 1`, `$translucent 0`, `$vertexalpha 0`. The registered public name
  therefore need not match the texture's own path. Both are in `mmd/`; shared `mmdhl/scmi`
  normal/lightwarp/phong textures are not base-texture candidates.
- The imported hotloader's `lua/mmdhl/native_render.lua:122` builds the soft recipe with the
  source base texture; lines 150-156 bind that texture to the blended copy and create an opaque
  core only outside Remix. Lines 165-166 put decoded metadata in `mmdhl.assets`. Discovering
  those public material paths covers the current Remix soft pass without changing the add-on.
- Claude's supplied `out/qa-poc/r7/04-ramp/console.log:610` reports
  `VertexLitGeneric_DX7`, and line 614 reports `UnlitGeneric_DX6`. The supplied
  `03-columbina/shot-01-noon.png` visibly has the lattice shadow without its surface;
  `05-columbina-thr05/shot-01-noon.png` has white lattice bars and open holes. These are existing
  observations, not a game run by R7-A.
- In the applied runtime, `opaque_surface_material_interaction.slangh:803` calls the shared
  opacity evaluator after texture/vertex operations; `bake_opacity_micromap.comp.slang:131` calls
  that same evaluator for OMM baking. This is the common point at which promoting coverage to
  1 affects both lighting/visibility and micromap classification. Primary-only threshold changes
  leave indirect opacity throughput and visibility attenuation at the old partial value.
- The GPU surface's `data13.z` uses bits 0-15 for existing texture/eye flags and bits 17-18 for
  texgen. Patch 0017 uses bit 16 plus bits 19-30 for MMD alpha and the fixed-point cutoff; the
  256-byte CPU packing contract remains unchanged. `AlphaState` grows from 9 to 12 explicitly
  initialized bytes. Rearranging explicit OMM hash padding retains the 128-byte hash-source
  contract, with materialHash at byte 88 and no implicit padding.
- The existing ADR 0048 BLAS path compares cached geometry flags, combines shared geometry as
  opaque only when every instance is opaque, and rebuilds on incompatible flags. R7-A does not
  mark a partly opaque mesh fully opaque: only the sampled final coverage is promoted.

## R7-C: fast-body discovery and thin-floor contact (2026-11-01)

- Read-only PoC evidence `out/qa-poc/r7/11-interact/console.log:656–662` shows the 30 kg drum
  crossing nine settled pieces with zero movement/body splits. `debris_scene.lua:12,27,57` now
  widens spatial discovery before testing a 0.25 s/192-unit velocity sweep, inspects at most 512
  entries and prioritizes fast bodies before truncating to 128 candidates/96 mirrors. Fast cold
  physics boxes bypass mesh extraction until slowing (`glass/addon/lua/nlglass/debris_scene.lua:128`).
- Earlier Lua capture alone still fails the real Jolt sleeping-floor-box replay. Jolt's
  `third_party/jolt/Jolt/Physics/PhysicsSystem.cpp:1564` limits CCD to dynamic bodies. Native
  `glass/native/world.cpp:236` now sweeps actual mirror translations against glass, with 16 casts,
  eight hits/cast and 64 transfers/snapshot; mirrors still follow Source exactly. The regression
  fails on the starting executable even with earlier captured rows, and passes with both fixes.
- Three interleaved offline comparisons: crowded Lua capture 0.1563 -> 0.1959 ms mean; warm native
  96 mirrors/regions 0.06035 -> 0.05966 ms; single fast box native sync 0.0011–0.0033 ms mean;
  the 96-mirror/128-leaf, 64-transfer stress snapshot 0.0693 ms median. The unchanged 4000-piece
  benchmark settles in 11.0167 simulated seconds, with identical scratch use/zero overflows.
  These are doubles/generated rooms, not game frames; detailed costs and limits are in the
  [fix report](handover/R7-C-report.md#r7-c-fast-body-fix-pass-r7-glass-fix).

## R7 integration: glass capture in the game (2026-11-01, Claude)

- **Vector reads.** Reading a component of a Source `Vector` from client Lua costs **35.3 ns** in
  game: 100,000 reads of `v.x`, against 0.5 ns for a Lua local (PoC, `out/qa-poc/r7/25-probe`).
  R7-C's region test read every bound through vectors. 512 bodies that miss 32 regions took
  **3.128 ms** that way, and **0.300 ms** with the same test on plain numbers.
  - At 10 Hz, the 50-pane field scene's manager think rose from 0.02 ms (interaction off, run 21)
    to 0.49 ms (on, run 24) with nothing moving, with think peaks of 18.6 and 26.4 ms.
  - The offline doubles are plain Lua tables and cannot show this cost.
- **`PhysObj:GetAABB()` is in the object's own frame.** A client prop (`ents.CreateClientProp`, the
  oil drum) at 831, 400, −100, angles 0, 37, 20, reported −14, −14, 0 .. 14, 14, 45.
  - Server props have no physics object on the client: the drum, the couches, the table and the
    companion doll all give an invalid `GetPhysicsObject()` there. Capture uses their oriented
    `OBBMins`/`OBBMaxs` box.
  - Client ragdolls and client props do have one. Capture took their local box as world bounds, so
    the boxes landed near the map origin and the region test dropped them.
- **After the fix.** Frame mean / p99 in ms, manager think in brackets. Same build, interaction off
  (run 27), then on (run 28):

  | Scene | Interaction off | Interaction on |
  |---|---|---|
  | Before the panes | 8.96 / 12.81 (0.02) | 8.85 / 16.58 (0.18) |
  | While 2,000 pieces fall | 26.28 / 134.30 (1.79) | 28.60 / 134.33 (2.61) |
  | Settled | 9.17 / 14.66 (0.02) | 9.32 / 17.25 (0.26) |

  G1 run 10, the old baseline: 25.31 / 113.22 ms falling and 9.74 / 16.39 ms settled. The falling
  p99 is the second-worst of about 150 frames: 113, 134 and 142 ms across runs 10, 27 and 21.

R8-G evidence (2026-11-01): R7 read-only `27-field-off/console.log` and `28-field-on/console.log`
under the main checkout's `out/qa-poc/r7/` record 26.28/134.30 and 28.60/134.33 ms falling
mean/p99, settled 9.17/9.32 ms. Lua draw costs about 6.9 ms at roughly 1330 moving draws; the
remaining engine/Remix ingestion/instance-update costs are not separated by those counters.
The preserved before/after replay now retains 2000/1998 original fragments in 2000/348 rigid
draws (four settled batches on both sides). Exact compound creation is in
`glass/native/world.cpp:409`; split paths reject groups before convex-only access.
`glass/addon/lua/nlglass/debris_detail.lua:20` plans groups without changing polygons;
`debris_mesh.lua:53` recentres the same triangles/sub-hulls. Native body origin includes the
shape COM offset (`third_party/jolt/Jolt/Physics/Body/Body.h:268`), matching the render frame.
Source collision flags are enforced at `glass/native/world.cpp:474`; changing them invalidates
Lua shape cache too. The old server router used 32 fixed recent-break spheres/120 seconds;
`debris_bullets.lua` now takes renewable per-client regions. `debris_melee.lua` observes actual
SWEP traces/stock swings, keeps the wider line/hull result (stock fists use that pattern), then
re-clips a containing Source box before the native sphere cast. Numeric region loops remain.
Primary three-run offline costs and all limits are in [the R8-G report](handover/R8-G-report.md);
raw logs/data stay in `out/r8-g/release-costs`. No RTX game improvement is claimed from doubles.

## R8: noise on Model Hotloader characters after R7 (2026-11-01, Claude)

- **What discards history.** `geometry_resolver.slangh` (fork, `e9460a14`) sets
  `discardRRHistory = surface.hasMaterialChanged || (animated water and the option)`; the pixel then
  writes the DLSS-RR disocclusion value `log(10000)` (RR) or uses the alternate disocclusion threshold
  (NRD) into `PrimaryDisocclusionThresholdMix`. Remix's debug view 128, "Primary Alternate Disocclusion
  Threshold", shows that buffer: white where history is thrown away. `DXVK_RTX_DEBUG_VIEW_INDEX=128` in
  the game's environment turns it on for a whole session; `poc_session.py` passes its environment on.
- **Patch 0017's comparison.** `InstanceManager::updateInstance` set `hasMaterialChanged` also when the
  instance's stored `surface.alphaState` differed from the new draw's in `isMmdAlpha` or the cutoff.
  That stored state is written by `mergeInstanceHeuristics` for a later draw of the same frame (the
  "opaqueness takes priority" merge), and a new instance starts with a default (untagged) state; only
  these two writes exist (`rtx_instance_manager.cpp:954`, `:1149`). The material-hash comparison next to
  it was guarded by `m_materialHash != kEmptyHash`; the alpha comparison was not.
- **Measured on the PoC** (Robin face up on gm_construct, pinned camera, share of the frame centre
  that discards history): G1 runtime 0.0 %; R7 runtime with the companion 37.1 %; R7 with the companion
  stopped before the spawn 0.0 %; R7 with Robin's 166 materials tracked but nothing tagged 0.0 %; R7 with
  Robin's 15 texture hashes tagged by hand 31.4 %; patch 0018 0.0 %. Frame-to-frame difference inside the
  character's surfaces (two consecutive shots, DLSS on): R7 shows a grain over dress, arms and hands
  that G1 and patch 0018 do not (`out/qa-poc/r8/noise-compare.png`).
- **API notes.** `RemixConfig.GetConfigVariable` returns an empty string for the hash-set option
  `rtx.gmod.mmdAlphaTexturesForSession`. Setting it to `""` or to a single dummy hash at runtime did not
  remove tags already applied in these runs (the character stayed white), while adding hashes took effect
  within seconds; treat runtime removal from that set as unreliable.
- **Unit tests.** The fork's Release build includes `tests/rtx/unit`; run them with
  `python -m mesonbuild.mesonmain test -C _CompRelease_x64 --no-rebuild` inside `Enter-VsDevEnv`. Tests
  that load `d3d9.dll` (`test_remix_categories`) need the runtime's NVIDIA/USD DLLs next to
  `_CompRelease_x64\src\d3d9\d3d9.dll`; staged from a deployed runtime folder, all 29 pass.

## R8 integration: two facts from the game (2026-11-01, Claude)

- **`net.WriteVector` is compressed.** Each vector takes 3-66 bits (per component a presence bit, then
  integer and fractional coordinate bits), so a region of a vector and a 32-bit float takes 35-98 bits. A
  receiver that requires 128 bits per region refuses every real message; glass interest did until R8
  (PoC `21-glass-r8`: forwarded hits 0 → 1/6 after the fix).
- **Session cheat variables in the field.** `r_forcehwlight` (created by `gmcl_RTXFixesBinary`, flags 0,
  default 0) breaks GPU-skinned characters only together with `mat_softwareskin 0`: on the PoC, with
  `sv_cheats 1` and `mat_softwareskin 1`, a Lua `r_forcehwlight 1` left Kleiner, Alyx and a citizen right
  (`18-vanilla-control`); R3-016 saw the break once `sv_cheats` had gone 1 → 0 and reset the cheat
  variable. The field's own `autoexec.cfg` line `r_forcehwlight 1` never applies (the variable does not
  exist yet when it runs).

## R8 follow-up: "Not Responding" during long loads (2026-11-01, Claude)

- **What the user saw.** During a long field load the game still drew and its menu updated, yet Windows
  marked the window "Not Responding". GMod's main thread reads no window messages while it remounts
  Workshop add-ons or loads a map: gm_br_complex with 765 add-ons takes minutes. `IsHungAppWindow`
  turns true once a window's thread has gone 5 s without reading messages. Windows then hides the window
  behind a **ghost**: a top-level window of class `Ghost`, owned by `dwm.exe` on this Windows 11 build
  (26300), with the game's title and, once marked, " (Not Responding)". The ghost offers to close the
  program; 0xCFFFFFFF is the exit code of a program closed that way.
- **The ghost needs no input.** On the PoC (`out/r8-ghosting/poc`, run `a-kept`, with
  `NATIVE_LOADER_WINDOW_GHOSTING=1`), a 25 s client-Lua busy loop made the window hung for 20.1 s. A
  ghost was there 0.25 s after `IsHungAppWindow` turned true, before the watcher's first invalidation.
  A 2.3 s hang during start-up had a "(Not Responding)" ghost too.
- **`DisableProcessWindowsGhosting`** (user32, no arguments) turns ghosting off for the calling process
  for the rest of its life. `IsHungAppWindow` still reports the hang, so `poc_session.py`'s hang grace
  works unchanged. The loader calls it at start-up, before the engine creates its window. It resolves the
  function at run time, as `activate.cpp` does for user32, so the bootstrap's import table stays
  KERNEL32-only. PoC run `b-fixed` (loader 0.12.1, the same stall): hung for 20.1 s, three invalidations,
  **no ghost window**, a normal quit; loader note `window ghosting off`.
- **In the field, with the player's saved video settings** (`out/qa-field/r8-ghost`, gm_br_complex, 765
  add-ons): with `NATIVE_LOADER_WINDOW_GHOSTING=1`, 5 hang episodes (longest 8.0 s) and 5 ghosts; with
  the fix, 6 episodes (longest 12.1 s) and none. The Workshop mount and map load took 29.8-37.7 s in these
  runs, against minutes earlier the same day.

## R8 CI: glass mirrors behind dropped catch-up steps (2026-11-01, Claude)

- **Symptom.** `build.yml` failed on four of the five pushes to `main` after the R7 merge (runs
  41308841564, 41347922720, 41354364348 and 41355549858; 41357362175 passed), each time in
  `nl_glass_tests` with a few misses of `test_interaction.cpp:166` (three, and two, in the logs read):
  the Source mirror within .01 units of the synced box after `step`. Two of those runs also failed
  `nl_exit_observer_integration` separately: its loader log had no `exit observer ready` note (the
  loader waits 3 s for the observer, `loader/proxy/observer.cpp:175`). This fix does not cover that.
- **The runner.** This private repository's `windows-2022` runner has 2 vCPUs: `hardware_concurrency()`
  is 2, so `world.cpp:181` starts one Jolt worker (the G1-B benchmark line reads `workers=1`), and
  CTest runs `nl_glass_tests` beside five other tests. Pinning a local run's affinity to two cores
  leaves `hardware_concurrency()`, and so eight workers, unchanged.
- **Cause: the 4 ms catch-up budget, not the worker count.** `step_impl` always runs one 1/60 s substep
  and further catch-up substeps only while the measured `elapsed + last_fixed_ms` stays under 4 ms
  (`world.cpp:704`); a whole step still due is discarded (`dropped_seconds`). At dt 1/30 a first substep
  over about 2 ms, such as a preempted thread on a busy machine, dropped the second, and the mirror's
  kinematic interpolation (`m.remaining`, the snapshot interval; `world.cpp:708`) stopped halfway.
- **Reproduced on Linux** (clang 18 with the module's Jolt options, the unchanged test file, under the
  git-ignored `out/repro-glass`): pinned to one CPU that a busy loop shares, one to four misses per
  run, with two workers. Each was a 1/30 s frame with `substeps` 1, `step_ms` 4.2-6.2 and 1/60 s dropped,
  and the miss was exactly half a frame: 650/60 = 10.83 or 3600/60 = 60 units. There were none unloaded.
- **The game hit it too.** The add-on syncs and steps with one interval (`debris_scene.lua:246`,
  `debris.lua:495`), so a loaded 30 FPS client takes the same path. With every catch-up step dropped
  (budget 0, 36 snapshots at 30 Hz), the old code left the mirror a whole frame behind (21.67 units
  at 650 units/s). It moved the mirror at twice Source's speed in simulated time, and the next sweep
  counted the backlog as speed. At 3600 units/s the backlog took every second snapshot over the
  128-unit teleport limit (`world.cpp:544`): 18 of 36 snapshots were never swept.
- **Fix.** Discarded catch-up time now moves each mirror through the same share of its sampled motion
  as a pose correction (`skip_mirrors`, `world.cpp:288`); the snapshot's sweep had already covered that
  path. Budget 0: no lag, and 36 of 36 snapshots swept. Contended runs at the default 4 ms: one to six
  drops per run and no misses (before: one miss per drop).
- **Tests stop racing the clock.** `World::set_catch_up_budget` (C++ only, 0-1000 ms) lets a test run
  every catch-up step (1000) or drop every one (0). The fast-box case runs both. A new case checks the
  snapshot clock, including a .045 s snapshot (2/60 of its motion done, the rest kept for the next step).
  The `substeps==4` check in `test_glass.cpp` had the same race and now pins 1000. Without the fix the
  pinned cases fail on an idle machine (108 and 10 misses).
- **The same race in the Lua scene harness.** Main's run 41359603305 also failed the Python test
  `test_collision_flags_default_living_exclusion_and_independent_categories` at
  `glass_interaction_harness.lua:157` ("flag changes resend cold native shapes"). `debris_scene.lua:170`
  cooks a second shape in one snapshot only while the capture has taken under 0.5 ms, and the harness's
  `SysTime` was `os.clock()`, which is wall time on Windows. A simulated clock that gains 1 ms per call
  reproduces the failure on Linux (0.3 ms passes), and only `scene_flags` depends on it. The harness now
  answers `SysTime` with its Source clock, as `glass_debris_harness.lua` already did. `sceneperf` still
  measures QueryPerformanceCounter, and the game's budget is unchanged: a slow frame cooks that shape in
  the next snapshot.

## R8 CI: the exit observer and the coarse clock (2026-11-02, Claude)

- **Symptom.** `nl_exit_observer_integration` failed in five CI runs since R7 (41308841564,
  41354364348, 41359603305, 41359867098 and 41362392767), each time in one case of 16 (a different one
  in the runs read). The loader log
  had no `exit observer ready` note, so start-up had waited out its 3 s budget. The cloud session's
  probe (`claude/sweet-cori-iqcvoh`, run 41362889676) showed readiness is fast on the runner, even
  beside the other CTests: 45 of 45 ready in 14-226 ms. Slowness was not the cause.
- **Cause: two clocks.** The observer refused a session start earlier than the game's creation time
  (`observer.cpp`, `start < created`). The loader records the start with `GetSystemTimeAsFileTime`
  (`evidence::now_filetime`), which moves once per clock tick. `GetProcessTimes` reports a creation
  time that is not on that tick grid. On this machine the timer runs at 1 ms (`NtQueryTimerResolution`:
  current 10000, coarsest 156250, finest 5000, in 100 ns units), and a tiny program's coarse clock at
  `main` led its creation time by 1.2 ms or more in 400 of 400 starts (`out/r9-ci/clock_race.c`), so
  it never failed here. A runner at Windows' default 15.625 ms tick reads a start up to 15.6 ms behind.
  A loader that records its session within one tick of process creation therefore lost its observer.
- **Fix.** `exit_report::session_after_creation` allows two coarsest ticks (31.25 ms). The other
  identity checks still pin the game: pid, exact creation time, inherited handle, parent process and
  image path. A refusal now exits with `0x4E4C0000` plus its reason, and start-up waits on readiness
  *or* the observer's exit.


## R9-G: glass fracture, latency and environment (2026-11-02, Codex)

- `glass/native/fracture.cpp:50` implements seeded oblique hit-centred 2-6-way clipping down
  to one square unit, replacing longest-axis binary cuts and a four-unit size floor.
  Across 40 Lua seeds per kind, smallest initial annealed/tempered fragments measure
  0.030804/6.674136 units^2; repeated native polygon cuts retain area within 0.02 units^2 on 3072.
- `glass/native/world.cpp:278` marks mirror overlaps; pose corrections include the next swept
  shard extent. An initial reproduction still reversed 7/672 samples at -112.717 units/s when
  a mirror corrected ahead of a previously swept shard; swept-extent suppression removes that
  path. Final generated free-flight fixtures report 0/672 reversals with exact Source targets.
- The real gm_construct BSP has one water brush: min(-3072,1985,-960), max(1856,6464,-160).
  `nl_glass_import_probe <map.bsp> --water` parses/prints it read-only. `world.cpp` applies Jolt's
  submerged-volume impulse at density ratio 0.4, linear drag 1.4 and angular drag 0.08. In the
  PoC, 25 pieces entered water; mean vertical speeds were -125.234 before entry (0.2 s),
  -22.691 at 0.5 s and -32.099 at 1 s, rather than continuing a free fall.
- Valve's [basegrenade_shared.cpp](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/basegrenade_shared.cpp)
  sets ReportedPosition to the thrower's location, not the explosion. The old fallback preferred
  it. R9 uses the inflictor or an exact API origin/radius. Five PoC routes reached glass without
  relying on damage victims: util blast, explicit env_explosion, native grenade, barrel and RPG.
  Contrary to a source-only assumption about direct C++ InputExplode calls, GMod's AcceptInput
  observes the native barrel/RPG env_explosion too. No polling or save-field guess is required.
- Vanilla GMod resolves all six glass_impact_soft/hard1-3.wav and glass_sheet_break1-3.wav files.
  Native events cap at 128; the client limits 4/frame, 24/s burst 24, 0.12 s/piece and 1536-unit
  distance. Event callbacks never invoke Lua/Source. Empty reads avoid Lua table allocation.
- `tools/tests/test_render_guard_addons.py:111` checks an exact source inventory. New helpers
  must remain in existing trusted paths: Preview in debris_detail.lua, Audio in debris_draw.lua
  and blast observation in server.lua. The loader inventory and trust rules were left intact.

Raw/paired evidence: this worktree's `out/qa-r9/trusted-feature-costs`, `trusted-load-costs`,
`native-frozen-evidence.log`, `latency-summary.json` and owned PoC sessions. See
[the R9-G report](handover/R9-G-report.md) for the full numbers, QA and limits.

## R10-H: PMX identities, expression meanings and map readiness (2026-11-02)

- In nanoem `30acffaa29f5d2eb9e997d69418f2e4b97b5894f`,
  `nanoem/nanoem.c:5962-5980` reads a VMD morph's 15-byte field as CP932;
  `nanoemBufferGetStringFromCp932` (`:699`) ends at NUL.
  `emapp/src/Model.cc:3777` visits each model morph with its original Japanese
  name, and `emapp/src/model/Morph.cc:179` finds/interpolates motion keys by that
  exact name. Windows `nanoem/ext/mbwc.c:98,212` uses
  `MultiByteToWideChar(932,0)` and `wcscmp`, with no NFKC/case/prefix folding.
  Sources: [VMD parser](https://github.com/hkrn/nanoem/blob/30acffaa29f5d2eb9e997d69418f2e4b97b5894f/nanoem/nanoem.c),
  [model synchronization](https://github.com/hkrn/nanoem/blob/30acffaa29f5d2eb9e997d69418f2e4b97b5894f/emapp/src/Model.cc),
  [Windows strings](https://github.com/hkrn/nanoem/blob/30acffaa29f5d2eb9e997d69418f2e4b97b5894f/nanoem/ext/mbwc.c).
  A local Windows API probe checked all 60 lead bytes × 255 non-NUL followers:
  valid Python CP932 mappings agree; every invalid pair produces U+30FB and
  consumes both bytes. A dangling lead at byte 15 also becomes U+30FB. This
  matters when a long VMD name ends halfway through a Japanese character.
- The hotloader's native `rig.cpp:405` retains `{mmd,name,original,displayName,
  namingSource,native}`, disambiguates duplicate English names with index
  suffixes, then assigns at most 96 native controllers. Packaged
  `carrier.lua:GetMorphWeight/SetMorphWeight/SetMorphWeights` (baseline
  `1c12083:126-156`) already reads/writes overflow weights via NW2 and native
  SetMorph; the motion importer had only used Source Get/SetFlexWeight.
- The importer had discarded custom VMD identities in
  `cl_import_bake.lua:flex_tracks_of` and merged by English `track.g`. R10 keeps
  every decoded identity and merges by `track.m`. The existing `sh_core.lua`
  implements exact identity and the overflow adapter; `carrier.lua`
  reads bounded PMX side summaries without changing native controller names.
- Corpus statistics count each NFKC name once per model (first occurrence),
  preserving exact names for binding. Of 1,009 models with 笑い, 999 move both
  sides, one the left, nine have no measurable geometry. ウィンク moves left
  in 971 models and right in 21; ウィンク右 moves right in 955 and left in 22.
  ウィンク2 moves left in 945 and right in 34; ウィンク2右 moves right in 920
  and left in 34. Different duplicate/whitespace policies explain small
  differences from the brief's initial tally. All 345 `EL_Happy_l_CLO` instances
  move character-right, and all 345 `_r_` instances move character-left.
  The [user's reference table](https://github.com/Sinsax/mmd-facial-expression)
  uses opposite-looking wink-side descriptions; geometry supplies our sides.
- Unit-weight standard group recipes link 笑い to the two `EL_Happy_*_CLO`
  halves in 336 models, まばたき to `biyan` in 336, and the vowels to
  `jawOpen_a/yi/wu/ei/o` in 336. The 48-file offset sample corroborates several
  of those and finds 悲しい equivalent to 困る in three models. The generated
  table accepts 62 unambiguous aliases with >=3 observations. These are model
  observations, not a count of independent authors. Raw evidence and rejected
  candidates stay in `out/r10/corpus-analysis.json`; only aggregate fixtures ship.
- Across 1,225 models × 19 unique morph labels retained in the user's Robin
  built cache: exact 15,930/23,275 (68.443%), meaning 234 (1.005%), unresolved
  7,111 (30.552%). A built header cannot include discarded/unresolved source
  tracks, so this is illustrative unweighted label coverage. Both actual PoC
  characters resolve the required expressions by original identity; the
  baseline/after table is in [the report](handover/R10-H-report.md).
- `actors.lua:RegisterActor` used to publish entries without checking material
  mounts or explicitly populating the new server's modelprecache table. GMA
  mount state and that table have different lifetimes. The new `ReadyActor`
  gate checks mounts and server precaching before registration or factory spawn.
  The mount memo now rechecks a visible file, and the actor requires its exact
  carrier model. Group sides combine signed vectors before measuring, so
  cancellation cannot make a one-eye group look bilateral. Bone/UV/material/
  stepped flip effects remain unknown for semantic side selection.
  [IsValidModel](https://wiki.facepunch.com/gmod/util.IsValidModel) also depends
  on server precaching; [PrecacheModel](https://wiki.facepunch.com/gmod/util.PrecacheModel)
  is server-only. The baseline PoC spawned successfully after map transitions;
  a later full-map baseline session exited `0xC0000374`. Neither fact is a
  reproduced model-not-found message. The offline regression isolates readiness
  by resetting precache while leaving archives mounted.

R10-H final PoC: `out/r10/qa-certified` records successful stock-menu and actual
client library RequestSpawn/status spawns across construct/flatgrass/construct,
a fresh flatgrass start and a two-slot listen server. The cold Workshop baseline
also succeeds with March 7th's first NPC after a map change; the field error is
still not reproduced. `out/r10/qa-expression-clean` has six real v2/_fm2 builds,
eight screenshots and 201 server ticks each. Exactly the requested original
morph ends at 1, other observed controls at 0; max ramp error is 4.85e-8.
Final cold byte-snapshot geometry reads are 36.2/140.0 ms for Guinaifen/Robin,
versus the first file-call implementation's 2395/3721 ms; cached reads are
0.001–0.002 ms. Exact binding does not scan geometry. Final sessions exit 0,
normally, with zero Lua errors; see [the report](handover/R10-H-report.md).

## R11-A automatic PBR (2026-11-02)

- The shipped ToPBR worker called `ExtractMaterialPBR`, which resolves live IMaterials. The R11
  fixes branch now snapshots one name per client frame, with two ready jobs and an 8192-name cap;
  decoding/writing use value-only jobs. Source material-name negatives are session-local. Output
  keys include source bytes and the scalar/string recipe, rather than size/time alone.
- The old `rtx_topbr_stats` called removed Lua methods and failed on the PoC. Disabling conversion
  stopped work but left USD replacements active. Complete atomic snapshots now support updates,
  removals and independent world/game switches. Native generated USD edits are preserved before
  replacement. Full dependency verification matched 2,334 files after checkout line-ending
  normalization, restoring 59 omitted build files under the isolated out tree.
- [EndfieldLitInput.hlsl](https://github.com/congyuxiaoyoudao/Endfield_Character_Rendering/blob/master/Assets/Shaders/Library/EndfieldLitInput.hlsl)
  lines 287?304 use P red for cloth metallic, alpha for smoothness, **blue for AO**, and separate
  hair/skin rules. Treating it as HDRP's green-AO layout would be wrong. This is a community shader
  reconstruction, not an official game specification.
- [HoyoToon's WuWa shader](https://github.com/Hoyotoon/HoyoToon/blob/main/Shaders/Wuthering%20Waves/Include/HoyoToonWutheringWaves-program.hlsl)
  reads RG normals, uses diffuse alpha for shadow/hair masks, and uses normal alpha to attenuate
  specular. Those masks are not assumed to be plain metallic/roughness. R11 uses RG relief plus
  named PMX material classes, retaining original diffuse/coverage.
- A 512-pixel blurred curl check on the sampled normal maps favored DirectX Y for WuWa
  (DX/GL error ratios 0.446?0.875) and Silver Palace (0.477?0.900), but OpenGL Y for Endfield
  (1.532?1.766); R11 flips Endfield green. These are measured inferences, not official shader
  documentation. The raw observations are in `out/r11-autopbr/normal-conventions.json`.
- PMX `first`/`count` material spans and vertex UVs distinguish shared cloth/metal from skin.
  The native converter bounds the file/vertex/index/string counts and raster work, preserving
  original-class texels in overlaps. Shader maps are at most 2048, decode sources at most 4096,
  and new DDS output at most 1 GiB per module session, with a 64 MiB free-space reserve.
- A read-only scan of 730 installed Workshop GMAs covered 21,101 VMTs. It found MWB/BFT candidates
  (notably items 2459720887 and 3333148722), but no ExoPBR/GPBR matches. Those formats therefore
  have generated-fixture channel tests; absence of a local sample is not rendered acceptance.
- Runtime `rtx_asset_replacer.cpp:getReplacementMaterial` returns the first matching mod, while
  `rtx_mod_manager.h:ComparePtrs` uses path order for equal priority. The fixes API exposes no
  fallback rank. Polling USD files can suppress known conflicts, including a Unicode-later folder,
  but cannot guarantee priority at an asynchronous runtime swap. This remains the R11 integration
  blocker ([ADR 0091](decisions/0091-automatic-pbr-fallbacks.md)).

The final QA measurements, limitations, artifact identity and evidence paths are in the
[R11-A report](handover/R11-A-report.md). No model or generated game texture is committed.

R11-A profiling follow-up: Construct's 45-material conversion p99 fell from 23.472 to 9.133 ms,
and maximum main-thread snapshot from 23.553 to 0.830 ms, after worker-side VMT preparation and
companion probing. Steady medians were 7.270 ms off / 7.213 ms on / 7.374 ms restored, within
run-to-run variation. Measurements use wall clock, not GMod's 100 ms-clamped frame value.

The valid Unicode-later authored fixture hot-reload removed overlap hash `C5E74CB23318460D` in
0.805 s; subsequent captures render the authored red atlas. This measured delay is why the
fixes-side exclusion cannot be claimed as instantaneous runtime precedence. The earlier invalid USD
fixture was rejected and is not rendered acceptance.

R11-B second review (2026-11-02): fixes `633fd5e` puts the identity cache in production
`game_registry.h:83` (`GameRegistry::Session`), instantiated in `to_pbr.cpp:4707` for each worker.
`ClearCache` calls `CancelPendingWork`, which joins/stops that worker before clearing registrations;
the next invocation therefore gets a fresh cache while the persistent registry survives. Its native
regression makes both DDS and registry unavailable after the first resolution and still reuses the
result for new live hashes; distinct identities and no-maps/rejected results have separate coverage.

The former USD ownership map was a function-static process-local table, so a new process could not
recognize its predecessor's generated bytes. `usda.cpp:154-207` now reads/writes a versioned
`.last-published` byte-count/FNV-1a record beside each USD target, after successful replacement.
The production USD regression republishes in separate child processes with no new backup, then
checks same-size edits, missing/damaged/stale records and real sharing violations on USD/sidecar
replacement. DLL: 5,167,104 bytes, SHA-256 `526a6584d4ab68e657b7f1cead25db88beb6cbfa568ad31f92028ddc3345f792`;
build, regressions and Release evidence are in `out/r11-b/second-review`. The GPL source copy and
cumulative patch reconstruct 23 changed files from `7094baf` after CRLF normalization.

The second-review PoC pair (`09-second-source` / `10-second-missing`) publishes the same 7/0/7;
fresh conversions are 7/0 and cached restorations 0/7. Alf's two hair materials share live identity
`mmd/t/222255a4ff9840e9` and `Textures\T_AlfDefault_Hair01_A_D.png`, with one conversion line.
The restarted source-hidden session leaves the entire materials-backup inventory unchanged.
On-state USD stays 6,574 bytes (`97a0f545...`), registry 1,879 (`615a9d85...`), and actor/camera
bounds match the accepted pair. Both exit 0 with no Lua errors or device loss. The field activity
gate waited ten minutes before the first launch; neither preflight found a field game running.
Steam's Workshop package had advanced since the PoC's previous deployment, so restoration used
`nlctl rollback` (generation 145), verifying all 1,871 deployed files against actual pre-pair hashes
instead of applying the newer archive. All 191 snapshot files and 2,877 depot files validate; the
same `autoexec.cfg` user-config difference remains. The PoC lock is released.

## R14-H: capturing the guide's pictures (2026-11-03, Claude)

**The spawn menu's tool panels.** `spawnmenu.GetTools()` is a list sorted by tab name, and the tool
menu keys its panels by place in it (`toolmenu.lua:24-46`), so `GetToolMenu():GetToolPanel("RTX Remix")`
is nil; look the place up by `Name`. `spawnmenu.ActivateTool(<item>)` (`includes/modules/spawnmenu.lua:101`)
opens an item's panel as a click on it does, and highlights it without unfolding its group. A click on
a group's header (`DCategoryHeader`) folds the group instead: the header of Start here has the same text
as its item, which is why the first pass's label clicks left the previous panel showing.
`DHorizontalDivider:SetLeftWidth` applies at the next layout, and the spawn menu's first layout after
opening puts back the cookie's share (`dhorizontaldivider.lua:85-98`); set it, `InvalidateLayout(true)`,
and set it again a moment later. A 640-pixel tool half shows the RTX Remix panels without most of their
wrapping at 1920x1080 (the default is the 460-pixel minimum).

**GMod blocks** `showconsole` and `hideconsole` from `RunConsoleCommand` ("Command is blocked!").

**Remix's menus (Alt+X) from outside.** `RemixConfig.SetConfigVariable("rtx.showUI", "1"/"2"/"0")`
opens the simple menu, the developer menu, or closes them (the option is NoSave). Mouse messages posted
to the game window do not reach them while the real cursor is elsewhere: the ImGui backend polls
`GetCursorPos` and `TrackMouseEvent` reports the mouse leaving. Posted keyboard messages do (Path A of
`rtx_fork_overlay.cpp:115-126`, keyboard navigation is on at `dxvk_imgui.cpp:664`), and Page Down pages
the developer menu down to its Settings Management section (`dxvk_imgui.cpp:1166`); but the keys also
reach the game's binds (the field's `config.cfg` binds End to `quit`, the arrows turn the view).
- The simple menu is **User Graphics Settings**, tabs General, Graphics, Content, Permissions
  (`rtx_user_menu.cpp:214-241`); its buttons are Developer Settings Menu, **Save Settings** (saves the
  user layer, user.conf; orange while it has unsaved changes, `rtx_user_menu.cpp:261-292`) and Delete
  All User Settings. Graphics Preset is on its Graphics tab; DLSS Preset (Disabled, Enabled, Custom)
  on General.
- The developer menu ends with **Settings Management** (`dxvk_imgui.cpp:1166-1290`): "User Settings
  (user.conf):", View Changes (only with unsaved changes), Save, Discard Changes, Delete All, Remove Dupes
  (`rtx_option_layer_gui.cpp:289-350`), then "Developer settings to migrate: N" and the yellow Migrate
  button only when user.conf holds developer settings (83 on the PoC), then the same for "Remix Config
  (rtx.conf):".

**The guide's pictures in the game.** A JPEG material drawn with `surface.DrawTexturedRect` at its own
size and an integer position is pixel-exact (`out/r14-guide/s7/check` in the r14-guide worktree):
pictures are captured at 1920x1080, cropped and never scaled, and are at most 900 pixels wide, the
guide page's width in a 1280x720 game.

**The PoC's characters.** Of the PoC library's nine characters, Karin (`c329babf`) is an Endfield
character with game maps (`t_actor_karin_hair_01`) whose `目白` the eye-white rules detect; 鳴潮_白蓮's
`eye` and `eye+` are not detected.

## R15: painted shadows and alpha on hair (2026-11-04, Claude)

**Where an imported part's alpha goes.**
- The Model Hotloader's AssetInfo (`native.AssetInfo`, `module.cpp:242`) gives per part `base` as the
  cached texture's SHA-256 (`''` when untextured), `alphaTexture` from the texture cache
  (`assets.cpp:393`), `translucentTexture` (partial texels over a tenth of the visible ones,
  `assets.cpp:439`) and `softTriangles`. The texture's path in the model is only in the asset's
  `data/mmd_hotloader/assets/<id>/manifest.json` (`materials[i].base`, keys sorted, 3-350 KB in the
  field library).
- The rig's materials (`rig.cpp:422`) have the same order as the asset's: slot `i`, bodygroup `i+1`,
  `defaultHidden` for authored alpha 0.
- `mmdhl.SyncMaterialState` (`materials.lua`) re-sends the per-part `visible` array every 8 frames per
  character and right after a local edit; the native renderer draws only visible parts in every pass,
  so leaving a slot out there changes the draw and nothing else.
- In GMod, `IMaterial:GetInt("$alphatest")` returns nil for the hotloader's VMTs; the state is in
  `$flags`: `MATERIAL_VAR_ALPHATEST` 256, `MATERIAL_VAR_TRANSLUCENT` 2097152. `Material("!mmdhl_soft_v1_...")`
  returns the procedural soft copy. Laevatain's hair (PoC, `out/r15/alpha2`): public flags 536881424 ->
  536881168 and soft copy 2107408 -> 10256 made its bangs clean, as the user's removal of `$alphatest` did.
- ADR 0081's runtime category replaces the alpha-test reference of categorized MMD draws with
  `rtx.mmdAlphaCutoff` (0.5), so a lower reference on the material does not reach the ray tracer. Only
  a draw without alpha state is opaque there.

**Hair textures in the field library** (159 models, read only; `out/r15/scratch/partial_runs.py` in
the `r15` worktree):
- Laevatain's `T_actor_laevat_hair_01_D.png` (2048²): clear 3.6 %, alpha 9-127 1.6 %, 128-246 3.4 %,
  opaque 91.4 %. Its partial texels lie at the strands' ends and in spots inside them.
- In every hair texture with partial alpha, 85-100 % of the partial texels are in horizontal runs of 16
  texels or more, and 0-3.8 % of them touch a clear texel: masks and fades, not anti-aliased strand edges.
- Reading the whole 2048² VTF (22 MB) in Lua took 8 ms and sampling a 256² grid 1 ms (PoC); the
  controller reads only the sampled rows (8 KB each) through `file.Open`/`Seek`/`Read`.

**Painted shadows in the field library** (6,684 parts): the rules hide 92, all of them shadows: 目影
untextured black at alpha 0.2-0.5 (Endfield, Wuthering Waves) or painted from 黑.jpg/灰.jpg (Star Rail),
发影/髮影/髪影, まぶた影 and 表情_影 painted from the face atlas (LycoReco), Tda's `hairshadow` from the face
texture, SilverWolf999's 陰影 parts, Laevatain's `Moyin` (name) and `Hair+` (untextured, black, alpha 0.5,
0.039 % of the indices). Kept: Evanescia's lavender `Mat_EyeShadow_01` (alpha 0.76), two 眼影 painted
from a coloured texture, and parts hidden as authored. Fifteen models (Star Rail's `眼睛1` at alpha 0.3
from 脸.png) have a part that only the texture's path could decide; none of them is a dark image.

**The render guard's table** held 351 paths at `main` 786d9a9, not the 345 its docs said; with R15's
three companion files it holds 354.

**Client modules.** `nativeloader_eye_whites.lua` `include`s `nativeloader/eye_white_names.lua` and
`eye_white_vtf.lua`, which no `AddCSLuaFile` sent; a client joining a server did not have them. R15's
`nativeloader_i18n.lua` sends them with its own two rule modules.

## R16: the sky at a map's start (2026-11-04, Claude)

- Remix API option writes go to the **User layer**: `remixapi_SetConfigVariable` calls
  `option->readOption(newSetting, RtxOptionLayer::getUserLayer())` (fork `c6b48ed1`,
  `src/dxvk/rtx_render/rtx_remix_api.cpp:1730`). The layers, weakest first: dxvk.conf, the built-in
  per-application config, rtx.conf, a base game mod's rtx.conf, the derived, environment and quality
  layers, then the User layer (user.conf), the strongest (`rtx_option_layer.cpp:637-690`). So a value
  saved in `rtx.conf` never outranks the companion's live writes; one in `user.conf` is in the same
  layer and is replaced by the next write.
- `rtx.autoUnblockOptionEdits` concerns only edits made in the Remix menu that a stronger layer
  overrides: they clear the stronger value instead of asking (`rtx_option_blocking_popup.cpp:92`).
- The RTX fixes' light updater (`rtx_lightupdater 1`) writes `rtx.ignoreGamePointLights`,
  `...SpotLights` and `...DirectionalLights` `False` 0.5 s after InitPostEntity
  (`cl_rtx_settings.lua:307-354`); their map configs (`data/remix_map_configs/<map>.txt` or
  `default.txt`) load 1 s after it (`cl_remix_map_configs.lua:437-455`). The companion's own 5 s re-send
  puts the directional lights back to `True` for the physical sky.
- A trace of every sky option write (time, value, result, caller; `out/r16/skytrace` in the main
  checkout) with the field player's settings showed the sky sent at InitPostEntity (2.1-2.6 s after the
  client's Lua started) and kept on a new game, a map change, a listen server and with the field's
  `rtx.conf`; in the field on gm_construct too. On `modern_house`, Modern House RTX loads after
  InitPostEntity (`MHRTX_Config` absent then), sets its afternoon 3 s after its own start (5.8 s in the
  trace: sun 21 degrees at 222, its clouds and fog) and again 20, 40 and 60 s later; its
  `M.Start` calls `M.ApplySettings()` through the table, so a wrapper installed before then sees every
  call.

## R16: where the package's binaries come from (2026-11-04, Claude)

The survey behind [ADR 0106](decisions/0106-the-rtx-package-built-on-github.md) (full notes:
`out/r16/binary-sources.md` in the main checkout). `packages/` indexes 54 native binaries: 41 in the
runtime (1.03 GB), 5 in the fixes, 5 of the Model Hotloader, one each of ReShade, the glass and the
material editor.

- **RTX fixes module** (5,491,712 bytes, `447b9dde...`): built from the fixes fork's unpushed commit
  `913bb6b` (`claude/r13-maps`, 23 local commits above the pushed `f28bd5a9`). The four GPL patches in
  `packages/fixes/licenses/oversized-skinning` (`oversized-hw-skinning.patch`, `memory-limits/`,
  `backrooms/`, `autopbr/`), applied to the index of public `f28bd5a9` with
  `--include=source/* --include=premake5.lua --include=public/*` (their `README.md` hunks do not apply),
  give `913bb6b`'s `source/`, `premake5.lua` and `public/` exactly. Built with premake 5.0.0-beta2 (5.0.0
  is incompatible with garrysmod_common `a854f237`) and MSBuild `ReleaseWithSymbols`/x64: garrysmod_common's
  configuration with optimisation off, which is what ships. The fork's `.gitmodules` points
  `source/debug` at the private debug module's repository, so a recursive checkout needs a token;
  `premake5.lua` builds the debug project only when `source/debug/premake_project.lua` exists.
- **RTX Water module** (274,944 bytes): byte-identical to the fixes checkout's
  `x86_64\Release\gmcl_rtxwater_win64.dll` of 2026-10-26 16:41; native Version 4, first committed in
  `b5c194ec` 10 minutes later. The base `f28bd5a9` has Version 5 (`SetCameraInWater`; only `rtxwater.cpp`
  differs), which the packaged Lua would detect and use: a behaviour change.
- **Debug module**: the complete source copy in `packages/fixes/licenses/rtxdebug/checkout` builds it;
  under a path with `!` the pinned generator writes a wrong absolute IntDir (build the helper libraries,
  then the module with `BuildProjectReferences=false -p:IntDir=obj\Release\`).
- **Material editor bridge** (316,416 bytes, `aeb5de42...`): byte-identical to a local build of the
  private repository's `native/rtx_bridge` at `8ece1415` (CMake, Visual Studio 17 2022, Release). Its
  writer test fails once `%TEMP%` is longer than about 75 characters (74 passes, 78 fails, measured with
  the R16 build): the test's game root lives under `%TEMP%`, and the material with every texture role
  then passes MAX_PATH in the bridge (`aperture152Apply.ok` false, `writer_tests.cpp:1097`). A real game
  root of up to about 115 characters is safe by the same measure.
- **`stdshader_dx6.dll`** (437,248 bytes, `4bf218db...`, Obsoletium 1.3.2.1081, linked 2026-08-11):
  built by sambow23 from source that was never pushed (sambow23/obsolete-source-engine was last pushed
  2026-03-21); the binary is committed in Xenthio/garrys-mod-rtx-remixed `74d9f3b6` and SheepyLord's fork
  `d958da61`. Valve's Source 1 SDK licence.
- **Model Hotloader natives**: byte-identical to the build in `ipg\!GMHLVK\wt-full-textures-props`
  (branch `feat/gravity-buoyancy-settings` at the pushed `ecd7c426`) of 2026-10-26, whose 41 staged,
  uncommitted changes hold `SetSecondaryWater`, `SetSecondaryBuoyancy` and `secondaryGravity`, which the
  shipped DLL exports and the packaged Lua uses; no commit has them. The add-on's `native_policy.lua` and
  `mmdhl-native-release.json` pin the four natives' and `lib_coacd.dll`'s SHA-256, so a rebuild needs
  new records there too. `lib_coacd.dll` (`a32e801d...`) is the file in CoACD 1.0.14's PyPI wheel
  `coacd-1.0.14-cp39-abi3-win_amd64.whl` (`6b548f44...`), as the hotloader's `scripts/bootstrap.py`
  takes it.
- **Runtime**: the fork's `_output` (`meson install --tags output`) holds all 189 files the runtime part
  ships under `files/` (except `files/atmosphere/`) and nothing else besides symbols: `d3d9.dll` and the
  two Remix USD plugins compiled, 38 vendor binaries brought by packman, submodules and clones. A full
  local build is 8.9 GB (`_CompRelease_x64`) plus 1.07 GB of `_output`. `meson setup` runs
  `scripts-common/update-deps.cmd`, which pulls every dependency of `packman-external.xml` into
  `PM_PACKAGES_ROOT`. The build finds `vulkan-1.lib` and the Vulkan headers in the fork's own `lib` and
  `include`, and glslang, slang and spirv-val in packman's `external/`.
- **GitHub runners**: `windows-2022` has Visual Studio Enterprise 2022 17.14 (MSVC folder 14.44.35207),
  Windows SDK 10.0.26100.0, CMake 3.31, Ninja 1.13, Python 3.12, Git LFS, `core.autocrlf true` in the
  system git config, no Vulkan SDK and no premake. A private repository's standard runner has 2 cores,
  8 GB and about 14 GB of SSD for the workspace.
- **The first runs on GitHub** (2026-11-05, runs 41962240202 and 41962824677): the `windows-2022`
  runner of this private repository had 2 processors and 8 GB, **81 GB free on C:** and 72.9 GB free on
  D: (the workspace), git 2.56.0, PowerShell 7 (pwsh) for `shell: pwsh` steps. The fork's clone, its
  worktree with the 30 patches, its submodules and the DLSS and SHARC clones took about 90 s and 2.6 GB
  with `--filter=blob:none`.
- **PowerShell 7.5 keeps an empty environment variable.** PowerShell passes `$null` to a .NET `string`
  parameter as `""`; Windows PowerShell 5.1 (.NET Framework) deletes a variable set to `""`, .NET 9 keeps
  it empty. `runtime/build_runtime.ps1` restored `GIT_OBJECT_DIRECTORY` that way after its scratch index,
  and every later git call failed with "gitfile does not point to a valid repository" (git checks that
  variable's folder before a worktree's own). Remove unset variables with `Remove-Item Env:NAME`.
- **`git restore --source=<commit>` in a blob-filtered clone** did not fetch the blobs it needed ("unable
  to read sha1 file of source/rtx_water/rtxwater.cpp"); `git checkout <commit>` (whole commits) does fetch
  them in batches. The fixes are cloned whole in CI (about 300 MB).
- The RTX fixes module built on the runner is 5,492,224 bytes (512 more than this machine's build: the
  runner's `cl` is 19.44.35229, this machine's 19.44.35228, and the paths differ).
- **The Model Hotloader's native source** (ADR 0107): `ipg\!GMHLVK\wt-full-textures-props` is at the
  public `ecd7c426` with 41 changes staged (34 modified, 7 added) and none unstaged; no file the native
  build reads is newer than the shipped `gmcl_mmdhl_win64.dll` (2026-10-26 16:21:10 -0700). Its CMake
  build reads `CMakeLists.txt`, `native/`, `shaders/vulkan/solver.comp` (compiled to SPIR-V by the pinned
  glslang) and every C++ test source (the test targets are declared unconditionally); ICU is for Linux
  only. The build identity is `git rev-parse --short=12 HEAD` of the source folder plus the UTC configure
  time (`CMakeLists.txt:13-20`). `scripts/native_manifest.py` asks `mmdhl_worker.exe --version` for the
  release and build, hashes the five native files of the bin folder and rewrites that release's entry of
  `native_policy.lua`; the part's installation override (`overrides/installation.lua`) accepts installed
  natives only by that entry's size and SHA-256. It imports `compatibility_profiles.py` beside it, so it
  must run without `python -I` (isolated mode leaves the script's folder off `sys.path`).
- A build from the copied source with the worktree's fetched dependencies took 5 minutes on 8 jobs:
  client, server and worker are the shipped sizes, the runtime 512 bytes larger.

## R17: clouds and the sun (2026-11-05, Claude)

### What Numos had before R17 (PoC, `gm_construct`, `out/r17/base1`)

- **One cloud layer, too thin to shade.** Every weather preset (`rtx_weather.h`,
  `WEATHER_PRESET_VALUES_*`) set the one low layer only: `cloudDensity` 0.4 to 3 against the option's
  default 4. The layer's base, cell size and edge detail were not preset fields (`cloudAltitude` 1.3 km,
  `cloudCellSizeKm` 2, `cloudDetailStrength` 0 for every weather), and the second deck was off. A
  sweep on partly cloudy (`out/r17/ab-density`): density 6 with detail 0.8, base 0.9 km, depth 1.6 km,
  type 0.85 and cells of 1.2 km reads as fair-weather cumulus with shaded undersides.
- **Overcast never closed.** The cloud body (NVDF) bakes at `nvdfNominalCoverage`, 0.65 by default (0
  would track the weather in 0.25 steps), and the live cover only moves its surface by
  `(cover - nominal) * nvdfCoverageOffsetKm` = 0.2 km per unit (`cloud_nubis3_common.slangh` step 4):
  cover 1 grows the bodies by 70 m. A column exists where the placement field F clears 1 - cover:
  `presence = saturate((F - (1 - cover)) / cloudColumnFeather)` (`computeCloudColumn`,
  `atmosphere_common.slangh`), so baked at 0.65 only F > 0.35 has cloud; the fork's overcast preset
  had cover 0.64 and rain 0.95, with km-wide gaps either way.
- **The presets dim the sun under cloud** rather than relying on the clouds' shadow: `sunIlluminance`
  20 when clear, (9, 9, 9.5) overcast, (2.5, 2.8, 3.4) in rain, (17, 16, 14) hazy; the hazy preset also
  lowers the Rayleigh coefficients and raises the aerosol (1.9) for its grey-brown sky.
- **No sun disc** outside an eclipse (`evalSolarEclipse`, patch 0004, is the only disc): the sun was the
  Mie aureole of the sky-view LUT, g = 0.8, which keeps half its peak 10 degrees out.
- **Twilight:** the sky LUT is faded out by `smoothstep(-0.09, 0, sun.y)` (gone 5.2 degrees down; the
  fork's note: its multiscattering leaves a residual glow at night), and the night-sky image (stars,
  galaxy band, nebula) fades in by `smoothstep(0.02, 0.15, -sun.y)` (full 8.6 degrees down).
- **The echo deck** shares the low layer's body field: its cover spread is forced to 0 (a uniform
  sheet) and its extinction pinned to 1.8 times `cloudLayer2DensityScale` (`cloud_march_common.slangh`).
- **The fork's translations:** release builds refuse a `.po` without every msgid of `remix.pot`, and
  `update_strings.py` also brought in three option descriptions of earlier patches (the memory census
  request, adaptive emission's enable and scale) that `remix.pot` had missed.

### What the research found (sources)

- **Heights** (WMO International Cloud Atlas, levels): low 0-2 km, middle 2-7 km, high 5-13 km in
  temperate latitudes; Met Office bases: Ac 2.1-5.5 km, As 2-6, Ns 0.6-3, Sc 0.37-2, St 0-0.37, Cu
  0.37-2, Cb 0.34-2 with its top through the troposphere.
- **Cirrus** (Sassen and Campbell 2001, ten years of lidar in Utah): base 8.8 km, top 11.2 km on
  average; optical depth mean 0.75, median 0.61. Cirrocumulus elements are under 1 degree wide (WMO),
  under 120 m overhead at 7 km, and without shading; cirrostratus is a transparent veil "often
  producing halo phenomena"; altostratus shows the sun "as through ground glass" and no halo;
  nimbostratus is "thick enough throughout to blot out the Sun".
- **Optics** (Kokhanovsky 2004): water cloud extinction 0.005-0.1 per m, single-scattering albedo about
  1, asymmetry g about 0.85 for droplets and 0.75 for ice; stratocumulus optical depth 7-23.
- **Real-time practice:** Horizon Zero Dawn (Schneider and Vos 2015) marches the low layer (64-128
  samples, about 2 ms on PS4) and draws "alto and cirro clouds above 4,000 m as 2D scrolling
  textures"; Frostbite (Hillaire 2016) uses a two-lobe Henyey-Greenstein phase (g 0.8 and -0.5) and an
  energy-conserving step integral; Hillaire 2020 notes clouds without multiple scattering "look like
  dark smoke".
- **The sun:** radius 0.2665 degrees at 1 AU (NASA); limb darkening at 550 nm I/I0 = 0.30 + 0.93 mu -
  0.23 mu^2 (Allen, the edge 30 % of the centre), or mu^a with a = 0.41/0.51/0.64 at 680/550/440 nm
  (Hestroffer and Magnan 1998); its colour is the transmittance along its ray (Bruneton, Hillaire); the
  real narrow aureole is about 1 % of the disc's radiance at the limb (Buie 2003), so engines draw the
  disc at its true size and leave glare to bloom.

### Measured in R17 (PoC, `gm_construct`, evidence in `out/r17`)

- **Frame time at 1600x900 does not move.** Every view of every weather and hour took 7.3-7.8 ms
  (`r17c`, 54 views; 1 s averages of `RealFrameTime` before each shot). The game is CPU-bound there
  (`fps_max` 300, no frame limiter, Reflex low latency only), so the sky's GPU cost hides in headroom.
- **At 3840x2160 the GPU binds.** Means over one second, about 100-120 frames each, roughly 0.2 ms
  noise; each A/B in one session (`perf-new`), the published runtime in another (`perf-old`):

  | Weather, view | R17 | R17 without the high layer | R17 without the middle deck | before R17 |
  |---|---|---|---|---|
  | partly cloudy 15 h, sun / away / high | 8.89 / 10.00 / 8.80 | 8.66 / 10.16 / 8.80 | 8.53 / 9.40 / 8.73 | 8.51 / 9.34 / 8.58 |
  | hazy 11 h, sun / away / high | 8.03 / 8.84 / 8.32 | 7.96 / 8.85 / 7.80 | (none) | 8.42 / 9.45 / 10.73 |
  | overcast 14.5 h, sun / away / high | 8.47 / 10.47 / 8.83 | (none) | 8.25 / 9.28 / 8.58 | 8.61 / 9.49 / 8.68 |

  The 2D high layer costs nothing measurable, and up to 0.5 ms where the veil fills the view. The
  middle deck's march costs 0.3-1.2 ms where it is drawn, most toward the horizon; it is skipped
  where the low layer is opaque (transmittance under 0.01) and, since R17, where its cover is 0. The
  overcast row is from before its deck was thickened to 1.8 km.
- **The sun disc's size on screen:** 0.545 degrees is about 11 pixels across at 1600 pixels and 80
  degrees of horizontal field; no ringing next to it in the upscaled shots (`r17b-sun.png`).
- **Cloud cover against the bake cover** (`r17b`, `r17c`, `r17d`):
  - Baked at 0.65 (the old pin), cover 0.92-1 left km-wide gaps.
  - Baked at 1, rain and snow (decks of 2.5-3.5 km) closed. Overcast, drizzle and fog (1, 0.8, 0.5 km)
    kept blue holes, because the noise erosion carves through a slab thinner than about twice
    `nvdfProfileDepthKm` (0.6 km).
  - Baked at 1.35-1.6, every column is present; the decks are thickened to 1.2-1.8 km in this model,
    which is optically thinner than real cloud.
- **The hazy veil and colour:** with the cirrostratus veil, the hazy sky away from the sun measured
  (132, 130, 126) in sRGB against (111, 131, 150) without it: the same brightness, desaturated and warm.
  Composited over only the third of the skylight made above 9 km, with its own light dimmed by the
  air in front of it only, it measured (135, 136, 137): neutral and milky.
- **Twilight on the presets' date** (sun elevation by hour): 18.9 h 5.3 degrees, 19.35 h 0.7, 19.5 h
  -0.8, 19.8 h -3.6, 20.4 h -9.1, 21.0 h -14.0. Before R17 the nebula of the night-sky image was
  already plain at -3.6 degrees. It now starts at 8 degrees down and is full at 17.5 (`deepNight` in
  `evalStarMap`); the single stars keep their fade.
- **The runtime grew** from 397,908,992 to about 414,400,000 bytes. The geometry resolver and the
  indirect integrator, which include `atmosphere_sky.slangh`, compile in many permutations, and each
  carries the high layer.
- **Translations:** 42 entries in each of the six catalogs: the R17 menu text and option descriptions,
  and the three earlier option descriptions `remix.pot` had missed.
  - The first answer from the translator wrote every non-ASCII character as `?`, and its own check
    (keys, empties, printf) passed anyway.
  - The check now also requires the script of each language. The files are written as ASCII JSON with
    `\u` escapes.

## R18: thin decks, the middle deck, ice halos, haze and twilight (2026-11-05, Claude)

### Why thin decks broke up (R17's runtime, `out/r18/e1`, options set live)

- **The profile depth.** `cloud_nubis3_common.slangh` step 7: `profile = saturate(-sdfLive /
  nvdfProfileDepthKm)`, then `valueErosion(profile, erosion)` with the wispy edge cut
  `nubis3EdgeErosion * 1.5 * wispy^2 * (1 - profile)` (2.28 by default). A deck's middle is at most half
  its depth from the surface, so at the default 0.6 km anything under about 1.2 km never reaches profile
  1. Overcast at 0.9 km: km-wide gaps at 0.6, closed at 0.25 km (`e1`, `thin06` and `thin025`).
- **The shape displacement.** Step 6e pushes and pulls the body surface by `wobbleMid *
  nubis3ShapeVarietyKm` (1.11 km by default, wobbleMid in [-0.5, 0.5] for wispy types) at 2.4 km
  wavelengths. On a 0.6 km drizzle deck it still cut smooth km-wide holes with the profile at 0.18 km and
  every column whole (bake cover 2; `e3`, `drizzle-13.0-high`). R18 scales it by
  `saturate((nvdfProfileDepthKm - 0.1) / 0.5)`: all of it for the cumulus weathers (0.6), 30 % for
  overcast, 16 % for drizzle, 10 % for fog.
- **Columns:** with the bake cover above 1 (`computeCloudColumn`), presence is
  `saturate((F + cover - 1 + carve) / 0.35)` with the body carve `carve` up to +-0.375; at 1.5 a few
  columns still fall to presence 0.36 (top at about a third of the slab). At 2 every column is whole.

### The middle deck before R18

- `marchEchoDeck` read layer 1's body field (`AtmosphereCloudNvdfSdf`) at the deck's height through
  `samplePos + (31.7, 0, -17.3) * cloudLayer2NoiseSeed`, its cover spread forced to 0. So its cloudlets
  were layer 1's bodies at layer 1's bake cover and cell size (1.3 km in partly cloudy, about 18 degrees
  overhead at 4.2 km), and it was closed wherever layer 1 baked a closed deck. Its cover only moved the
  surface by `(cover - nominal) * 0.2 km`.
- WMO: altocumulus elements are 1-5 degrees wide seen more than 30 degrees above the horizon
  (cirrocumulus under 1, stratocumulus over 5), in patches, sheets or layers, often in rows.

### Ice halos (plate and column crystals; geometry `out/r18/halo_geometry.py`)

- Ice's refractive index: 1.3072 (656 nm), 1.3104 (about 550 nm), 1.3160 (450 nm).
- **22 degree halo** (60 degree prism, random columns): minimum deviation 21.63 / 21.87 / 22.30 degrees.
  **46 degree halo** (90 degree prism): 45.14 / 45.82 / 47.04, much fainter and rarer.
- **Parhelia** (plates falling level, 60 degree prism, light at elevation e): the light's projection on
  the horizontal plane meets an effective index n' = sqrt(n^2 - sin^2 e) / cos e (Bravais), and the sun
  dog sits at the light's height at an azimuth of 2 asin(n' / 2) - 60 degrees from it:

  | Sun elevation | Azimuth from the sun (green) | Angle from the sun | Circumzenithal arc elevation (green) |
  |---|---|---|---|
  | 0 | 21.9 | 21.9 | 57.9 (none: too faint) |
  | 10 | 22.5 | 22.2 | 59.8 |
  | 20 | 24.6 | 23.1 | 66.0 (46.0 above the sun) |
  | 30 | 28.8 | 24.8 | 79.6 |
  | 50 | 51.6 | 32.5 | none |

  They vanish above 60.7 degrees (n' = 2); red 60.9, blue 60.4.
- **Circumzenithal arc** (plates, light in through the top face, out through a side face, a 90 degree
  prism): elevation asin(sqrt(n^2 - cos^2 e)), none above 32.1 degrees (green; red 32.7, blue 31.2),
  brightest at a sun of about 20 degrees; red toward the sun.
- In R18's shots (`out/r18/e2`, `e3`, hazy at 17.5 h, sun at 20.3 degrees, and 18.3 h, 11.6 degrees):
  the sun dogs sit just outside the 22 degree halo with a red inner edge and a white tail, and the arc
  is an upside-down rainbow above, red at its lower edge.

### Haze

- The runtime's aerosol: `mieScattering` 3.996e-3 and `mieAbsorption` 4.4e-3 per km (Hillaire 2020,
  Table 1), a single-scattering albedo of 0.48, both times `aerosolDensity`; `mieAnisotropy` 0.97 (the
  option's default; Hillaire's is 0.8). R17's hazy had aerosol 1.9, air (7, 11, 20)e-3 and a sun of (17,
  16, 14): a dark grey-brown sky (`out/r17/final`, `hazy-11.0`).
- Haze is "an opalescent appearance" of dry particles (WMO). Water-soluble and sulfate aerosol scatter
  about nine tenths of what they meet (albedo about 0.9-0.95); soot absorbs.
- `out/r18/e1`, hazy at 11 h with aerosol 2.6, `mieAbsorption` 0.5e-3 (0.11 of the default) and the
  clear sky's air and sun: g 0.97 gave a bluer sky, 0.8 a milkier one, 0.7 about the same as 0.8.
- **The aerosol is optically thin in this model:** `mieScattering` 3.996e-3 per km over a scale height
  of 1.2 km (`kMieScaleHeight`) is a vertical optical depth of 0.0048 per unit of `aerosolDensity`, about
  0.014 at hazy's 3 (real haze: 0.3-1). `out/r18/e5`: 10 and 25 made the sky only a little whiter
  overhead (sRGB away from the sun (131, 139, 148) at 3, (143, 146, 149) at 25), so hazy keeps 3.
- **Auto-exposure evens out the brightness:** in the same view, R17's hazy sky measured (118, 119,
  120) away from the sun and R18's (113, 121, 131): the change on screen is the colour, from a neutral
  grey to a pale bluish white. R17's darker look came from the sun-facing views, where the bright halo
  sets the exposure.

### Twilight

- `evalSkyRadiance` multiplied the sky LUT by `smoothstep(-0.09, 0, sun.y)`: half at 2.6 degrees down,
  black at 5.2. With R18's fade at 18 degrees (`e2`, `fade18`), the LUT's own sky at 12.4 and 15.5
  degrees down is black (no glow, no blobs): its twilight falls by orders of magnitude by then.
- With the LUT kept whole to 8 degrees down and faded out by 16 (`e3`): at 4.1 degrees down a purple sky
  over an orange band; at 6.3 a deep blue with an orange glow over the sunset; at 7.8 and 9.1 the glow
  only; at 10.8 night, the galaxy fading in.

### Cost at 3840x2160 (`out/r18/perf-new`, `perf-old`)

Means over about a second (76-95 frames) before each shot, the same spawn and views in both sessions
(`perf-framing.jpg`), about 0.2 ms of noise. The R17 column is the published R17 package in a second
session with the same states; the "R18, feature off" column switches one R18 feature off in the R18
session (the middle deck's cover to 0 in partly cloudy, `cirrusArcStrength` 0 in hazy at 17.5 h).

| Weather, view | R18 | R18, feature off | R17 |
|---|---|---|---|
| partly cloudy 15 h, sun / away / high | 11.30 / 11.97 / 11.26 | 11.01 / 11.78 / 11.11 (no middle deck) | 11.40 / 12.01 / 11.57 |
| overcast 14.5 h, sun / away / high | 11.45 / 13.31 / 12.03 | | 11.56 / 12.29 / 12.10 |
| drizzle 13 h, sun / away / high | 11.65 / 11.90 / 11.63 | | 11.85 / 12.31 / 12.31 |
| foggy 10 h, sun / away / high | 11.87 / 11.88 / 11.16 | | 11.62 / 12.00 / 11.31 |
| hazy 11 h, sun / away / high | 11.13 / 11.44 / 11.18 | | 11.61 / 11.66 / 11.48 |
| hazy 17.5 h, arcs / sun | 11.26 / 11.13 | 11.15 / 11.27 (no halos of plates) | 11.28 / 11.75 |

- **On average R18 costs what R17 did:** 11.62 ms over these 17 views against 11.77.
- **The middle deck:** 0.15-0.3 ms where drawn, as R17's (0-0.33 ms in the R17 session).
- **The sun dogs and the arc:** within the noise (+0.11 and -0.14 ms).
- **Overcast toward the horizon costs 1 ms more** (13.31 against 12.29 ms; the views toward the sun and
  overhead are the same). The march takes as many steps across the 0.9 km deck as across R17's 1.8 km
  one, so a grazing ray meets twice as many dense samples, each one lit, before it turns opaque.
- **Memory:** no texture, buffer or grid is added; `AtmosphereArgs` (also inside the ray-tracing,
  composite and debug-view constants) grows by one 16-byte row. The DLL grew from 414,372,864 to
  417,072,128 bytes, the shaders that include the sky (many permutations).
- The frame times are about 2.5 ms higher than R17's own 4K table (8.5-10.5 ms), for both runtimes
  alike: another day's machine state; the comparison holds within the session pair.

## R19: the pre-release review's fixes (2026-11-05, Claude and seven Claude subagents)

The verified review is [R19-review.md](handover/R19-review.md); each part's report holds its full evidence.

- **Steam's `subscribedby`** (`WorkshopItemDetails` in `appworkshop_4000.acf`): comma-separated decimal
  account ids. This library: 817 items installed and in the details; 777 have `subscribedby` (744 with
  three ids, 22 with four, 10 with one, 1 with two); 40 have none, holding `manifest`, `timeupdated`,
  `timetouched`, `latest_*` and sometimes `ugchandle`: what `steamworks.DownloadUGC` leaves (M6 measured
  that it installs an item without a subscription; ADR 0015). None of the 40 holds a native package.
- **GMod's Lua clock.** `bin\win64\lua_shared.dll` imports only `tier0.dll`, `vstdlib.dll` and
  `KERNEL32.dll`, so it links the C runtime statically: LuaJIT's `os.clock()` counts from when that DLL
  loads, after the loader's start-up, not from the process start. The UCRT's `clock()` is QPC wall time
  since its CRT's initialization (Windows SDK 10.0.26100 `ucrt\time\clock.cpp`). So the render guard
  cannot date a status report from Lua; it uses a marker file held for the life of the game process.
- **A file held with `FILE_FLAG_DELETE_ON_CLOSE` and read sharing only:** `GetFileAttributesW`,
  `FindFirstFileW`, `std::filesystem::exists` and Python's `os.stat` see it; another `DeleteFileW` fails
  with a sharing violation, a second `CREATE_ALWAYS` fails; it is gone moments after the holding process
  is killed (`test_status.cpp`, `activation_integration.py`).
- **System32 `winmm.dll`'s imports** (10.0.26100.1): statically only `ntdll.dll` and API sets; WINMMBASE,
  the `api-ms-win-mm-*` sets, AudioSes, the `ext-ms-win-ntuser-*` sets, OLEAUT32 and the COM sets are
  delay-loaded. So the proxy's load of it under the loader lock waits on no other thread (review F-08).
- **The fixes' native Lua surface.** `gmcl_RTXFixesBinary` registers `MaterialPipeline`, `RemixMaterial`,
  `RemixLight`, `RemixConfig` and `RTXWaterNative` in the real `_G`, so any server's client Lua calls them.
  Source's `IFileSystem::Open` opens an absolute or UNC path as given, whatever the path ID; before R19 the
  VTF reader (`vtf_parser.cpp:232` at `913bb6b`), ToPBR's `ParseVMTFile` (`to_pbr.cpp:1855-1859`) and
  `ReadVMTShaderName` (`auto_categorisation.cpp:312`) fell back to the bare name.
  `RemixConfig.SetConfigVariable` writes any option to the User layer; the path-valued ones are the
  atmosphere textures (`rtx_atmosphere.cpp:880-883`), `rtx.cameraSequence.filePath`
  (`rtx_camera.cpp:1159-1176`), NRC's CUDA DLL folder (`rtx_nrc_context.cpp:251-256`) and Nsight's paths.
- **The patched fixes' trees.** Replaying `build_modules.ps1`'s index steps, the four pre-R19 patches on
  `f28bd5a` give exactly `913bb6b`'s object ids (`source` `aa6ed7d1`, `public` `7165af4d`, `premake5.lua`
  `b308ed2f`); RTX Water's `b5c194e` `source/rtx_water` is `b3547296`. `pins.json` now records the
  patched ids, so the check holds without a pushed commit.
- **The material editor's bridge** resolved a texture source (`std::filesystem::canonical`) before its
  root check, so a UNC source contacted its host first (the same class as ToPBR's folder); its writer test
  needs `%TEMP%` of at most about 75 characters (76 fails at `writer_tests.cpp:1152`, 50 passes; R16
  found the same limit). GMod's duplicator calls entity modifiers without `pcall`, so one modifier's error
  stops the rest of a paste.
- **The Model Hotloader's dependencies** fetched with `git fetch --depth 1 <repo> <sha>` and `git archive`
  (with `core.autocrlf=false`, `core.eol=lf`) are byte-identical to GitHub's codeload archives of the same
  commits (R16's vendor folder); with Git for Windows' default `core.autocrlf=true`, `git archive` writes
  CRLF. `sv_commands.lua`'s main chunk holds 196 locals (LuaJIT refuses past 200).
- **Glass map imports.** vbsp gives each leaf its own range of the leaf-brush lump (gm_construct: 5,002
  leaves whose ranges sum to exactly its 6,386 references; gm_flatgrass 3,610 and 2,855; none shared), so a
  world walk visits each reference at most once. The walk costs 5.5 ms per 8,388,480 references, so the
  former unbounded 2^36 was about 45 s on the import worker. A crafted 99 KiB map of 7,000 brushes sharing
  one prism parses and cooks in 6.0 s; with R19's cancellation the destructor returns 0.75 ms after its
  stop request. gm_construct with the R19 reader: parse 13.8 ms, asynchronous total 64.8 ms. A near-cap
  pane snapshot is 5,686 bytes in the engine harness.
- **GLI** (`include/gli`): `gli::load` tries a file as DDS, then KMG, then KTX, whatever its name, and the
  KMG and KTX readers copy what their headers claim; GLI's texture cache keeps 16 levels in fixed arrays
  (`texture.hpp:289-290`); `GLI_ASSERT` and the runtime's `assert` are empty in release builds;
  `block_size(FORMAT_INVALID)` reads before the format table. The texture manager makes every replacement
  texture a 2D image at the extent of its first loaded mip, so a side past the GPU's limit fails only when
  the larger mips stream in (an open item).
- **Runtime build time.** A change to `rtx_option.h` recompiles 251 objects in about 2 minutes with 4 jobs.
  The fork's `.gitignore` ignores `tests/rtx/unit/*` except a few names: new test sources need `git add -f`.
- **GitHub Actions storage.** About 1.2 GB of the 2 GB was in use with one package artifact (about 0.84 GB),
  so the package workflow keeps deleting the older package before uploading its own (review F-07).
