# R5: stability on 8 GB GPUs and 16 GB machines (proposal)

A proposal for the maintainer, from read-only research on 2026-10-31. Nothing here is implemented.
It answers four questions: what the tester's GPU device loss involved, where GPU memory goes and
which switches cap it, what happens on device loss or allocation failure, and what uses system
memory. Then it proposes changes, in priority order, and lists the decisions they need.

- Branch `r5-stability`, worktree `out\worktrees\r5-stability`, from `main` at `df80147`.
- Inputs: the tester's logs as Codex extracted them (`C:\Users\matt-peng\Desktop\logs_investigation_20261031`),
  the dump the user attached (`C:\Users\matt-peng\Desktop\8d0eac58-9cd7-4df3-8e87-fbd8db8c1293.dmp`), the
  runtime fork (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`), the RTX fixes' source
  (`H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`, at `fc478c0`) and this repository.
- The tester's files were read as data only, with `python -I` scripts kept apart from them; nothing
  was extracted into the evidence folders. The scripts and two split Sentry envelopes are in this
  worktree's git-ignored `out\tmp` (`scripts\`, `extract\`).

**Citations.** Runtime paths are relative to the fork and were read from git objects at `6f2dbd79`,
the runtime this repository packages ([runtime/README.md](../../runtime/README.md)). The tester ran a
build labelled `f2068a98`; every runtime line cited here is the same there, with two exceptions:
`rtx_options.h:868` (section 1.4) and `rtx_option_layer.cpp`, whose lines after 400 sit 24 lines
earlier there (671 is 647, 700-706 is 676-682) with the same content. Repository paths are at
`df80147`.

**Tags.** **[M]** measured: read from the tester's files, the dumps, or files on this machine.
**[D]** derived: arithmetic on measured values and the cited code. **[C]** read in the code.
**[I]** inferred: a likely explanation that the evidence does not show.

## Summary

- **The device loss is real; its cause is not in the evidence.** Aftermath was off, so there is no
  fault type, address or shader. The last warning before it was the Opacity Micromap (OMM) cache
  reaching its own budget: about 1 GiB in use on an 8 GB GPU. The driver still reported at least
  512 MiB of the process's VRAM budget free at that point [D]. The leads are OMM, VRAM paging that
  ended in a GPU timeout, and frame generation, in that order [I].
- **The attached dump is not the device loss.** It is the GMod crash dump of the "Venti NPC" crash
  on 2026-10-30, byte-identical to the copy Codex analysed then. It confirms system commit
  exhaustion: 3.96 MiB of commit left out of 46.74 GiB, against a 21.3 MiB texture-read buffer [M].
- **Every GPU runs the RTX 5090 install's settings.** The package pins `rtx.graphicsPreset = 4`
  (Custom), which turns off the runtime's own 8 GB rule (`rtx.lowMemoryGpu` and a lower preset). It
  also doubles the sky probe and quadruples the froxel grid. The companion loads 213 MiB of night-sky
  images day and night.
- **The loader's own Remix layer loses to the package's for `rtx.*` keys** [D]. The first entry of
  `DXVK_CONFIG_FILE` is the strongest for them, and the loader lists its layer after the package's.
  So the non-NVIDIA preset of ADR 0030 has most likely never taken effect, and a low-VRAM layer
  must be listed first.
- **The rejected `rtx.resourceLimits.*` keys come from the package itself.** The RTX fixes module
  sends them at every map load. No version of the runtime ever had them.
- **The evidence of a crash is lost at the next start.** Remix truncates its log at every start,
  and its crash prompt deletes its dumps when the player answers No, which is the default.
- **Proposed first:** fix the layer slot, add an automatic low-VRAM layer, keep the last session's
  evidence at the next start, a one-start Aftermath switch, and memory telemetry for testers.

## 1. The evidence

### 1.1 Sessions and machine

Three sessions are in the evidence. The tester's clock is UTC+8: the three dumps' time-zone records
say China Standard Time [M].

| | A | B ("Venti NPC") | C (device loss) |
|---|---|---|---|
| Time (UTC) | 2026-10-29 14:19:56-14:20:39 | 2026-10-30 14:39:38-15:46:06 | 2026-10-31 about 13:19:55-13:32:59 [I] |
| Tester's clock | 22:19 | 22:39-23:46 | 21:19:55-21:32:59 |
| Runtime label | `remix-main+c6b48ed1` | `remix-main+d1f0f2be` | `remix-main+f2068a98` |
| Package | not checked | `0.0.0-dev.20261030122153+28f76600_10` | `0.0.0-dev.20261031061257+f2ffc9ff_14` |
| Sentry session | `d83199db-...` | `1a9a29f2-...` | `5ec1085a-...` |
| How it ended | crashpad dump `d34a4e0b`, 43 s after start: `c0000409`, fail-fast code 5, at `engine.dll+0x34b67c` | engine "OUT OF MEMORY!"; GMod dump `8d0eac58` (the attached one); crashpad dump `1f5b9ed4` of the same PID one second later: `c0000409`/5 at `engine.dll+0x34b67c` | `VK_ERROR_DEVICE_LOST`; the runtime ended the process |
| Commit at start | 18.76 / 34.82 GiB | 22.14 / 34.82 GiB | 15.09 / 34.82 GiB |

Session C's date is not in its log. The extracted log's file time on this machine, 2026-10-31
06:32:59 UTC-7, is the same instant as its last line in UTC+8 [I].

The machine [M]: RTX 4060 Laptop GPU (`0x28e0`), device-local heap 7956 MiB, system heap 8100 MiB;
memory type 4 is device-local and host-visible, so resizable BAR is on [I]. Driver 621.1.0, Vulkan
1.4.357, Ryzen 7 7435H (16 threads), 15.82 GiB RAM, Windows build 26200, 1920x1080 windowed.
Implicit Vulkan layers: NVIDIA Optimus and present, OBS hook, Steam fossilize and overlay, the
loader's ReShade. OBS's `graphics-hook64.dll` and the Sogou input method are loaded in the game.

### 1.2 Session C: timeline

| Tester's clock | Log line | Event |
|---|---|---|
| 21:19:55.668 | 7 | runtime `remix-main+f2068a98` |
| 21:19:57.323 | 457 | 8.04 / 15.82 GiB physical in use, 15.09 / 34.82 GiB committed |
| 21:21:05.488 | 942-943 | `rtx.resourceLimits.maxCacheSize` and `.maxVRAM` rejected (first map load) |
| 21:21:36.866 | 960 | OMM enabled: the first ray-traced frame |
| 21:21:37.100-.380 | 966-970 | Moon and night-sky textures loaded (three at 8192, 14 mips) |
| 21:28:37.847 | 981-982 | map-exit purge: 698 replacement textures released; D3D9 textures stay at 615,050,240 bytes (586.6 MiB), buffers at 20,271,360 |
| 21:29:48.118 | 983-984 | the two keys rejected again (second map load) |
| 21:30:16.653 | 986-989 | camera cut; OMM manager recreated; NRC context re-created |
| 21:32:37.103 | 990 | `[RTX Opacity Micromap] Out of memory budget. Requested: 87571836 bytes. Free: 67811140 bytes, Budget: 1130574688 bytes` |
| 21:32:52.552 | 991 | `DxvkSubmissionQueue: Command submission failed: VK_ERROR_DEVICE_LOST` |
| 21:32:56.353 | 992 | Sentry GPU crash event `e83af9ea-...` "(no dump)" |
| 21:32:59.785 | 993-994 | "uploaded"; "Exiting after GPU device loss" |

### 1.3 Session C: what it shows

1. **The device was lost at a queue submit or a present** [C]. Both reach the same handler,
   `src/dxvk/dxvk_queue.cpp:297-306`, so the log cannot tell which. The runtime then ran its
   device-loss path (`:143-171`, `:407-431`): the Sentry GPU-crash event, then `TerminateProcess` with
   exit code `0x60D0DEAD` (`src/util/util_crash_report.h:35`, `src/util/util_env.cpp:316`).
2. **Aftermath was off, not failed** [M][C]. The run's Sentry state has the tag `aftermath: disabled`.
   The runtime writes "disabled" only when the option is off, and "failed" when it was on and failed
   (`src/dxvk/dxvk_instance.cpp:663-668`). "(no dump)" means no Aftermath dump was queued
   (`src/util/util_sentry.cpp:491`).
3. **The OMM cache held about 1 GiB** [D]. Budget minus "Free" is 1,062,763,548 bytes (1013.5 MiB).
   That count includes releases still pending for frames in flight
   (`src/dxvk/rtx_render/rtx_opacity_micromap_manager.cpp:112-118`).
4. **The driver gave the process a 7188 MiB VRAM budget** [D]. The OMM budget is
   `min(0.15 x device-local budget, 1536 MiB)` (`:162-173`). 1,130,574,688 bytes is exactly the float
   0.15 of 7188 MiB, so the cap applied, and `rtx.lowMemoryGpu` was off (it halves the 0.15,
   `:164-167`). The budget comes from the driver's numbers through `VK_EXT_memory_budget`. That
   extension never appears under "Enabled device extensions", because DXVK queries it without
   enabling it (`src/dxvk/dxvk_extensions.h:309`, `dxvk_extensions.cpp:44-50`); NRC requires it and
   ran (`src/dxvk/rtx_render/rtx_nrc_context.cpp:180-196`).
5. **VRAM was not exhausted at 21:32:37 by the driver's count** [D]. When free VRAM is under 512 MiB,
   the budget is recomputed down to what OMM already uses
   (`rtx_opacity_micromap_manager.cpp:180-183`). It was still at the cap, so at
   least 512 MiB of the budget was free at the start of that frame, unless OMM's use equalled its cap
   to the byte at that moment.
6. **No Vulkan allocation failed outright** [M][C]. The log has no "DxvkMemoryAllocator: Memory
   allocation failed" (`src/dxvk/dxvk_memory.cpp:476-499`). A failed device-local allocation would
   first be retried in system memory without any log (`:464-474`), so a silent spill is possible.
7. **The OMM lines are printed once per process** (`ONCE`, `rtx_opacity_micromap_manager.cpp:190`,
   `:199`) [C]. Any later denials in the last 15 seconds are not in the log.

### 1.4 Session C: what it does not show

- The GPU fault: page fault, timeout or out of memory; the address, resource or shader.
- VRAM and paging at 21:32:52, a TDR (no Windows event log or `LiveKernelReports`), the frame rate,
  the map, or what the player did at the time (no console log, no action log).
- System commit at the time. The only memory figures are from the start.
- The runtime binary's identity. It was not supplied. Its list of non-default options omits
  `rtx.pathMaxBounces`, although the package's layer sets 12. Either the binary's default was already
  12, which `f2068a98` does not have (`src/dxvk/rtx_render/rtx_options.h:868` is 4 there; 12 arrived
  with `d4921fcb`), or the player's `user.conf` held 4 [D]. The label alone does not identify the
  binary.

**Leads** [I], most likely first:

1. **OMM.** It held about 1 GiB and was building. Upstream's own comments record two earlier OMM
   device-loss bugs (`src/dxvk/rtx_render/rtx_accel_manager.cpp:1256-1257`,
   `rtx_opacity_micromap_manager.cpp:690-694`). One coincidence: once over budget, OMM evicts only
   entries unused for 900 frames (`rtx.opacityMicromap.cache.minUsageFrameAgeBeforeEviction`,
   `rtx_opacity_micromap_manager.cpp:2481-2487`), which is 15.4 s at 58 fps, the gap seen here. The
   frame rate is not in the log, so this is a test to run, not evidence.
2. **VRAM paging that ended in a GPU timeout.** Session B logged "Free Vidmem dropped below a limit.
   Setting budget to 0." at 22:59:38, so these sessions do run out of VRAM. Frame generation and the
   OBS hook were on, on an 8 GB GPU.
3. **Frame generation, a driver fault, or a renderer bug unrelated to memory.** The player's
   `user.conf` turned DLSS frame generation on (1.6), and DLFG threads ran in sessions A and B.

### 1.5 The attached dump

Read with a read-only parser (`out\tmp\scripts\dump_r5.py`) [M]:

- **Identity.** 1,234,344 bytes, SHA-256 `67b5eb7d3ad1f7ca6595c9a22970c44f037120d973933be9597161fbad0ffbdb`.
  Byte-identical to `C:\Users\matt-peng\Desktop\crash\8d0eac58-9cd7-4df3-8e87-fbd8db8c1293.dmp`, which
  Codex analysed on 2026-10-30 (`crash\analysis\investigation.txt`). It belongs to session B, not to
  the device loss.
- **Writer and time.** GMod's own crash handler (tier0 through dbgcore 10.0.26100.9549). GMod writes
  these as `<game root>\crashes\<guid>.dmp` with a `.txt` of Lua stacks beside it, as the PoC's
  `crashes` folder shows. Written 2026-10-30 15:46:05 UTC (23:46:05 on the tester's clock). PID 33224,
  started 14:39:38 UTC, 66 min 27 s earlier. Its modules name package `20261030122153+28f76600_10`.
- **Exception.** Code `0xc0000025`, address 0, no parameters, thread 28788, context in
  `tier0.dll+0x1d9c5`. The dump writer made this record; it is not a hardware fault (as Codex's static
  analysis of tier0 found).
- **Threads.** 157, among them Remix's (`dxvk-submit`, `dxvk-queue`, `dxvk-cs`, 14 `dxvk-shader`,
  `rtx-texture-async`, `geometry-processing`), DLSS frame generation's (`dxvk-dlfg-present`,
  `dxvk-dlfg-pacer`: frame generation was on), Chromium's and Sentry's.
- **Text on the stacks.** `***** OUT OF MEMORY! attempted allocation size: 22369844 ****` three times,
  `gmod_spawnnpc "venti_kk_friendly" "none"`, `models/npc/venti_kk_npc.mdl` and
  `materials/tex/smalldream/venti(kk)/clothes.vtf`. The `.txt` beside it stops at `SetModel` in
  Sandbox's `commands.lua:484`.
- **Memory** (SystemMemoryInfo and ProcessVmCounters, revision 2, decoded with the Windows SDK's
  layouts). Physical 15.82 GiB, 169.7 MiB available, file cache 6.5 MiB. Commit 46.740 of
  46.744 GiB: 3.96 MiB left for a 21.33 MiB request. GMod: private 11.44 GiB (peak 12.32), working
  set 3.46 GiB (peak 4.63), virtual 53.0 GiB. The process's job: private commit 38.80 GiB (peak
  39.11), no limits; the dump does not say which processes share the job.

So Codex's conclusion for session B holds: system commit ran out during an NPC model's texture
read. One correction to the brief: `engine.dll+0x34b67c` / `c0000409` is not this dump. It is
crashpad's dump of the same process one second later (`1f5b9ed4`), and the same engine site also
ended session A, 43 s after a start at which 18.8 of 34.8 GiB were committed. It is the engine's
general fatal-exit point, not a sign of exhausted memory by itself [D].

**The process's memory map at that moment** (crashpad's dump `1f5b9ed4` carries one,
`out\tmp\scripts\meminfo_hist.py`) [M]:

| Committed private memory | Session B, after 66 min | Session A, after 43 s |
|---|---|---|
| Total | 11.13 GiB | 3.2 GiB |
| Write-combined (`PAGE_READWRITE \| PAGE_WRITECOMBINE`) | 6.24 GiB: 123 regions of exactly 32 MiB (3.94 GiB), 52 of 8.4 MiB, one of 320 MiB | 1.94 GiB: 20 regions of 32 MiB |
| Ordinary read-write | 4.25 GiB: 20 regions of 128 MiB, one of 608 MiB, many small | 1.13 GiB |

Write-combined memory is typically memory a graphics driver maps for the CPU [I]. The 32 MiB regions
are not the runtime's `RtxStagingDataAlloc` buffers: those are 32 MiB too
(`src/dxvk/rtx_render/rtx_staging.h:22`), but every user asks for host-cached memory, which is not
write-combined (`src/d3d9/d3d9_rtx.cpp:31`, `rtx_geometry_utils.cpp:242-251`,
`rtx_nrd_context.cpp:196-199`) [C]. Their owner is unknown. The two sessions ran different runtimes
and content, so the growth from 20 to 123 regions is a lead, not a measured leak.

### 1.6 Settings in effect in session C, and where they came from

The log prints the merged `dxvk.conf`-style layers and `rtx.conf` (lines 27-252), then, after
`user.conf`, every option that differs from its default (lines 269-392;
`rtx_option_manager.cpp:240-250` at `f2068a98`). A key that changes between the two came from `user.conf` [D].

| Setting | Value | From |
|---|---|---|
| `rtx.graphicsPreset` | 4 (Custom) | the package's layer (`packages/runtime/layers/classic_remix_defaults.conf:172`) |
| `rtx.integrateIndirectMode`, `rtx.neuralRadianceCache.qualityPreset` | 2 (NRC), 2 (Ultra) | package (`:221`, `:185`) |
| `rtx.upscalerType`, `rtx.qualityDLSS`, `rtx.dlssPreset` | 1 (DLSS), 1 (MaxPerf: about 960x540 at 1080p [I]), 2 (Custom) | package (`:217`, `:175`, `:177`) |
| `rtx.skyProbeSide` | 2048 (runtime default 1024) | package (`:72`) |
| `rtx.volumetrics.froxelGridResolutionScale`, `.froxelDepthSlices` | 4, 48 (defaults 8, 64) | package (`:204`, `:230`) |
| `rtx.skyMode` | 1 (the physical sky) | package (`:163`) and the companion |
| `rtx.atmosphere.starMapEnable` | True (night-sky images) | the companion at run time (`companion/nativeloader/lua/autorun/nativeloader_sky.lua:442`; default `nativeloader_sky_stars map`, `:26`) |
| `rtx.frameGenerationType` | 1 (DLSS frame generation) | the player's `user.conf` (the package sets 0, [ADR 0037](../decisions/0037-frame-generation-off-by-default.md)) |
| `rtx.lowMemoryGpu`, `rtx.opacityMicromap.*` | runtime defaults (off; 15 %, 1536 MiB) | nobody |

Replacement mods in the session (asset search paths, lines 694-912) [M]: `!advanced_material_editor`,
`Emissives`, `base_mod`, `gm_poolrooms_rtx`, `modern_house_rtx`, `pbr_guinaifen`, `pbr_robin`,
`rtx_water`, `~gmod_topbr`.

### 1.7 Capturing the next one

For a dedicated repro on the tester's machine. Keep the map, mods and settings of the failing run
for the first try, so the same fault can recur.

1. **Turn on Aftermath.** Create `GarrysMod\dxvk.conf` (the tester has none: log line 22) with:

   ```
   dxvk.enableAftermath = True
   dxvk.enableAftermathResourceTracking = True
   rtx.enableGpuCrashState = True
   ```

   These are read once, when the runtime starts (`src/dxvk/dxvk_options.cpp:36-39`); for `dxvk.*`
   keys the last file wins, and the root `dxvk.conf` is last. The log then says "Aftermath enabled"
   (`dxvk_instance.cpp:539`). On a device loss it logs `Aftermath detected a crash (<reason>: <access>
   <fault type> at 0x<address> from <engine>/<client>)`, each faulted resource (marked "already
   destroyed" when freed) and each active shader (`:361-383`). The reasons are Timeout, OutOfMemory,
   PageFault, DmaFault and others (`src/util/util_aftermath.cpp:43-53`). That line alone settles most
   of section 1.4.
2. **Log memory during the run.** In the game console, type `rtx_vram_stats` every few minutes and
   just before risky actions. The RTX fixes module registers it; it prints the driver's budget and
   use, DXVK's totals and each category: replacement textures, geometry, buffers, acceleration
   structures, OMM, render targets, D3D9 textures and buffers (`garrys-mod-rtx-remixed`
   `source/module.cpp:83-107`, `176-181`). In a Windows terminal, before starting the game:

   ```
   typeperf "\Memory\Committed Bytes" "\Memory\Commit Limit" "\Memory\Available MBytes" "\GPU Process Memory(*)\Dedicated Usage" "\GPU Process Memory(*)\Shared Usage" "\GPU Adapter Memory(*)\Dedicated Usage" -si 5 -o memory.csv
   ```

   Note the frame rate when the warning appears (lead 1 depends on it).
3. **After a crash, before starting GMod again**, copy these. The next start truncates
   `remix-dxvk.log` (`src/util/log/log.cpp:72-79`), and answering No at Remix's crash prompt deletes
   its dumps ([RESEARCH.md](../RESEARCH.md) section on minidumps and the declined prompt):
   - `GarrysMod\rtx-remix\logs\`, all of it, with `.sentry-native`;
   - `*.nv-gpudmp`, `shaderDebugInfo\*.nvdbg` and `gmod_*_gpucrash_state.log`/`.bin`. Without
     `DXVK_AFTERMATH_DUMP_PATH` they go to the working directory (`dxvk_instance.cpp:353-359`,
     `rtx_gpu_crash_recorder.cpp:933-941`), which is the game folder when Steam starts the game [I];
   - `GarrysMod\crashes\` (the newest `.dmp` and `.txt`);
   - `GarrysMod\native-loader\logs\loader.log`, `native-loader\status.json`,
     `garrysmod\data\native-loader\session.json`;
   - the root `rtx.conf`, `user.conf` and `dxvk.conf`; `garrysmod\console.log` if started with `-condebug`;
   - Windows: Event Viewer, System log, sources `nvlddmkm` and `Display` around the time (a TDR shows
     as event 153 or 14), and `C:\Windows\LiveKernelReports\WATCHDOG\` (a GPU hang);
   - `memory.csv`.
4. **Then change one thing per run, at least twice each:** OMM off (`rtx.opacityMicromap.enable = False`
   in the root `rtx.conf`, removed afterwards); frame generation off; OBS closed.

The uploaded event `e83af9ea` is in the Sentry project whose address is compiled into the runtime
(`src/util/util_sentry.cpp:70`). That line came from upstream's commit `2b0d394` by an NVIDIA author
and the fork never changed it, so the maintainer most likely cannot open the event [I]. A local
copy of the evidence is the reliable route.

## 2. Where GPU memory goes, and what caps it

The runtime has a rule for 8 GB GPUs. Under the Auto preset, a device-local heap of 8 GiB or less
lowers the preset one step (Ada: High to Medium) and sets `rtx.lowMemoryGpu`
(`src/dxvk/rtx_render/rtx_gpu_profile.cpp:212-221`, threshold `rtx_gpu_profile.h:61`). The rule runs
only for Auto (`rtx_options.cpp:419-461`). The package pins Custom
([ADR 0021](../decisions/0021-remix-defaults-in-one-low-layer.md), layer line 172), so on every GPU
the classic install's settings, tuned on an RTX 5090 (`tools/remix_defaults.py:60-61`), run with
`rtx.lowMemoryGpu` off. Section 1.3's arithmetic confirms it
for the tester. `rtx.lowMemoryGpu` (`rtx_options.h:401`, default False) halves the OMM percentage,
loads every streamed replacement texture one mip smaller (`rtx_texture_manager.cpp:1621-1623`) and
builds acceleration structures with `VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR`
(`rtx_accel_manager.cpp:292-294`).

| Consumer | Size in these sessions | What caps or reduces it (key = default, where) | Notes |
|---|---|---|---|
| Opacity micromaps | about 1013.5 MiB used, budget 1078.2 MiB [D] | `rtx.opacityMicromap.cache.`: `maxVidmemSizePercentage` = 0.15, `maxBudgetSizeMB` = 1536, `minFreeVidmemMBToNotAllocate` = 512, `freeVidmemMBBudgetBuffer` = 384, `minBudgetSizeMB` = 128, `minUsageFrameAgeBeforeEviction` = 900 (`rtx_opacity_micromap_manager.h:56-69`); `rtx.opacityMicromap.building.subdivisionLevel` = 8 (`:111`); `rtx.opacityMicromap.enable` = True, environment `DXVK_ENABLE_OPACITY_MICROMAP` (`rtx_options.h:1167`) | Under pressure the budget only stops growing. It never drops below what is in use, so the cache gives nothing back (`rtx_opacity_micromap_manager.cpp:180-187`, `2450-2494`) [C]. The manager is recreated at every camera cut (`rtx_scene_manager.cpp:3133-3146`). |
| Replacement textures | this machine's copies of the same mods: `modern_house_rtx` 3,169 MiB on disk (118 files at 4096 px: 1,856 MiB), `pbr_guinaifen` 640 MiB (35 at 4096), `pbr_robin` 368 MiB, `gm_poolrooms_rtx` 143 MiB, `~gmod_topbr` 136 MiB, uncompressed [M] | `rtx.texturemanager.budgetPercentageOfAvailableVram` = 50 (`rtx_options.h:1224`); `.fixedBudgetEnable` / `.fixedBudgetMiB` = False / 2048 (`:1230-1231`); `rtx.lowMemoryGpu`. No size cap exists. | Budget: 50 % of (driver budget minus other use, plus current texture use) (`rtx_texture_manager.cpp:1817-1873`); textures over it are demoted (`:1631-1638`). DDS files are mapped from disk and unmapped after upload (`rtx_asset_data_manager.cpp:286-330`): they cost VRAM, not commit. The tester's copies were not checked. |
| Game (D3D9) textures and buffers | 516-587 MiB and 19-35 MiB at map exits [M] | Nothing caps their VRAM. `d3d9.evictManagedOnUnlock` = False drops the system-RAM copy, not the VRAM (`src/d3d9/d3d9_options.cpp:74`, `d3d9_device.cpp:4697-4702`). | GMod's texture detail (`mat_picmip`) would shrink them, but it changes the uploaded data and so, most likely, Remix's texture hashes: replacements and texture categories stop matching [I]. |
| Night sky and Moon | 213.3 MiB + 4.0 MiB, every mip resident ([RESEARCH.md](../RESEARCH.md) records 223.7 MB and 4.2 MB) [M] | `rtx.atmosphere.starMapEnable` = False; paths `starMapTexture`, `starMapGalaxyTexture`, `starMapNebulaTexture` (`rtx_atmosphere.h:529-540`). No size option. | Stars and galaxy are DXT5, the nebula BC7, 8192 px [M]. The companion turns them on by default. They load at the first physical-sky frame, day or night, and are released only when a path changes (`rtx_atmosphere.cpp:731-741`, `848-859`). |
| Cloud volumes | about 68 MiB [D] | none | Created the first time ray tracing binds its common resources, also with `rtx.skyMode 0` (`rtx_context.cpp:1638`, `rtx_atmosphere.cpp:2949-2950`, `261-276`; sizes `rtx_atmosphere.h:1209-1229`). |
| Sky probe | 96 MiB at 2048 (the runtime's own menu label, `dxvk_imgui.cpp:3391`) | `rtx.skyProbeSide` = 1024 (`rtx_options.h:1307`) | package: 2048 |
| Froxel grid | about 39 MiB at 960x540 with scale 4 and 48 slices; 10 MiB at scale 8 [D] | `rtx.volumetrics.froxelGridResolutionScale` = 8, `.froxelDepthSlices` = 64 (`rtx_global_volumetrics.h:97`, `:99`) | 26 bytes per froxel (`rtx_global_volumetrics.cpp:979-984`); package: 4 and 48 |
| Terrain baker | not seen in these logs; up to 576 MiB per RGBA8 layer at 8 cascades [D] | `rtx.terrainBaker.enableBaking` = True; `.cascadeMap.maxLevels` = 8; `.cascadeMap.levelResolution` = 4096 (`rtx_terrain_baker.h:136-143`) | Active only where a `rtx.terrainTextures` hash is drawn (the package lists one). The atlas is ceil(sqrt(levels)) tiles of 4096 per side, RGBA8 for albedo, normal, tangent and emissive, R8 for the rest (`rtx_terrain_baker.cpp:60-84`, `1014-1041`, `1122-1139`). |
| Acceleration structures, geometry | unknown | no cap; `rtx.lowMemoryGpu` sets the low-memory build flag | The session's `r_lod 0`, `r_staticprop_lod 0` and `r_novis 1` (the fixes' `autoexec.cfg` RTX section) put the whole map at full detail into the BVH. Path tracing needs that; it costs memory [I]. No change proposed. |
| NRC, DLSS, Ray Reconstruction, frame generation | unknown | `rtx.integrateIndirectMode`, `rtx.neuralRadianceCache.qualityPreset`, `rtx.qualityDLSS`, `rtx.frameGenerationType` (0 none, 1 DLSS, 2 FSR; `rtx_options.h:133-137`, `576`) | Their driver-side memory is outside DXVK's statistics. `remixapi_VramStats` says so: the difference between `driverAllocatedBytes` and `totalAllocatedBytes` is "DLSS/NGX internal buffers, ..., NRC CUDA" (`public/include/remix/remix_c.h:1035-1041`). |
| Render targets | unknown; small at 960x540 [I] | follow the render and output resolutions | |

The Model Hotloader's characters count twice: their game-side copies (up to 4096 px, see
[skills/mmd-remix-pbr](../../skills/mmd-remix-pbr/SKILL.md)) are D3D9 textures, and their AI PBR maps
are replacement textures (`pbr_guinaifen` above).

### 2.1 Where the `rtx.resourceLimits.*` keys come from

From the RTX fixes, which the package ships [M][C]:

- `ResourceManager::SetMemoryLimits(maxCacheSize, maxVRAM)` sends `rtx.resourceLimits.maxCacheSize`
  and `rtx.resourceLimits.maxVRAM` through `remixapi_SetConfigVariable` (`garrys-mod-rtx-remixed`
  `source/remixapi/remixapi.cpp:1329-1334`).
- The module calls `SetMemoryLimits(256, 1024)` every time it opens (`source/module.cpp:431`), which
  is every map load: 21:21:05 and 21:29:48 in session C, three times in session B. Lua can also call
  it as `RemixResource.SetMemoryLimits` (`source/remixapi/resource_lua_bindings.cpp:74-94`); no Lua
  in the fixes does.
- Added in `c361cd8`, "module: expand remix API", 2025-07-14, in the fixes' history before this
  project. The packaged `packages/fixes/modules/gmcl_RTXFixesBinary_win64.dll.xz` contains both
  strings.
- The runtime has no such key. None of the fork's 7,574 commits on all refs, upstream NVIDIA's
  history included, contains `resourceLimits` (`git log --all -S`). An unknown key goes to
  `validateDynamicKey`, which prints the warning and returns failure
  (`src/dxvk/rtx_render/rtx_remix_api.cpp:1782-1791`, `rtx_option_dynamic.cpp:238`).

So the keys were invented in the fixes and have never done anything. They are not from a guide, an
add-on or another Remix version.

## 3. What happens today on device loss and allocation failure

**Device loss** [C]:

1. `onGpuCrash` (`src/dxvk/dxvk_queue.cpp:143-171`) records the acceleration-structure crash state
   if `rtx.enableGpuCrashState` is on, and waits up to 5 s for an Aftermath dump if Aftermath is on.
2. `handleDeviceLost` (`:407-431`): another Aftermath wait; then Sentry's step. The player sees a
   message box: an OK box if crash reports are already allowed, otherwise Yes/No with No as the
   default. With permission the event is captured and uploaded, waiting up to 30 s; with No nothing is
   captured (`src/util/util_sentry.cpp:286-306`, `828-867`, `77`). In session C the event was
   uploaded, and the 3.8 s before its line fits a click [I]. Then "Exiting after GPU device loss" and
   `TerminateProcess` with `0x60D0DEAD`.
3. GMod gets no shutdown. Nothing marks the event for the next start: the log is truncated then, a
   killed process is not a crash to crashpad [I], and the runtime has no safe mode or start-up crash
   check (a code search for one found none).

**Allocation failure** [C]:

- DXVK's allocator retries without a dedicated allocation, without hints, then without
  `DEVICE_LOCAL` (system memory), all without logging (`src/dxvk/dxvk_memory.cpp:448-474`). Only when
  every try fails does it log the heaps and throw (`:476-499`).
- Thrown on the CS thread, where Remix renders, the error shows a message box, "Exception on CS
  thread: ... The game will exit now.", and calls `exit(1)` (`src/dxvk/dxvk_cs.cpp:203-212`). On the
  texture streaming thread it logs "Exception on rtx-texture-async thread!" and the thread ends
  (`rtx_texture_manager.cpp:683`).
- OMM and the texture manager keep soft budgets of their own (section 2); they never fail an
  allocation on purpose.
- The engine, when `malloc` fails: tier0 prints "OUT OF MEMORY!", writes `crashes\<guid>.dmp` and
  `.txt`, and the process ends (session B).

**What the next start can still find:** `rtx-remix\logs\remix-dxvk.log` until the runtime opens it;
`.sentry-native\reports\*.dmp` and `last_crash` for CPU crashes, until the prompt is answered No;
`crashes\*.dmp` and `.txt` from the engine, which nothing deletes. The loader reads none of them.

## 4. System memory and commit

**Measured** [M]:

- Session B ran out of commit: 46.74 of 46.74 GiB, GMod 11.44 GiB of it, 35.3 GiB elsewhere. The
  commit limit was 34.82 GiB at every session start and 46.74 GiB at the crash, so the page file grew
  by about 12 GiB during the session and then stopped. Why it stopped (disk space, a size cap) is not
  in the evidence.
- The machine already held 15-22 GiB of commit before GMod loaded a map (section 1.1).
- The maintainer's own RTX session holds about 17 GB ([QoL handover](QoL-handover.md), "Memory"),
  more than a 16 GB machine's RAM.

**What uses host memory in an RTX session** [C], from the code:

- D3D9 keeps a system-RAM copy of every managed texture (`src/d3d9/d3d9_device.cpp:4697-4702`).
  GMod runs D3D9 without Ex (`mat_disable_d3d9ex 1` in the fixes' `autoexec.cfg`), so its textures
  can use the managed pool [I]. That is roughly the D3D9 texture total again (0.5-0.6 GiB here) [I].
- DXVK's host-visible memory comes in 128 MiB chunks (`dxvk.otherMemoryChunkSizeMB`,
  `src/dxvk/dxvk_options.cpp:65`): staging, readback, upload rings, mapped buffers.
- The write-combined 32 MiB regions of section 1.5 (3.9 GiB at the crash), owner unknown.
- Replacement DDS files are mapped from disk, not committed (section 2). The night sky's top mips
  each pass through a one-off staging buffer (up to 64 MiB, briefly) [I].
- The engine's model, material and sound caches (the Venti VTF read buffer was 21.3 MiB), the Model
  Hotloader, Lua, USD stages for each mod, NRC's CUDA, the in-process part of Chromium.
- Whether Windows also charges GMod's commit for its VRAM allocations, which it may evict to system
  memory, is not established [I]. Proposal 5's sampler would show it.

**What can reduce it:** a page file that can grow (system-managed, on a drive with room); closing
browsers and OBS recording; fewer heavy NPC and character textures; `d3d9.evictManagedOnUnlock`
once tested (proposal 10); finding the 32 MiB regions' owner (proposals 5 and 10). On the GPU side,
everything that lowers VRAM also lowers what can spill into system memory.

## 5. Proposed changes, in priority order

Effort: S is up to a day, M two to four days, L a week or more. "Effect" is derived from the code
and the numbers above; none of it was measured on an 8 GB GPU, which this machine does not have.

### 1. List the loader's own Remix layers first

- **What.** In `DXVK_CONFIG_FILE`, put loader-written layers that set `rtx.*` keys before the package's
  copies: `native-loader/remix/<loader layer>.conf,native-loader/remix/dxvk-1.conf,...,dxvk.conf`.
  For `rtx.*` keys the first entry is the strongest: entries are named `00_DXVK Config`,
  `01_DXVK Config`, ..., and the last plain `DXVK Config` (`src/dxvk/rtx_render/rtx_option_layer.cpp:51-61`,
  `671-672`); one priority sorts by name, ascending (`rtx_option_constants.h:159-162`); the first layer
  holding a value wins (`rtx_option.cpp:1156-1186`, the map at `rtx_option.h:303`). This is
  [RESEARCH.md](../RESEARCH.md) section 19's finding, still true at `6f2dbd79`. For `dxvk.*` and `d3d9.*`
  keys the last file wins (the merged config, `rtx_option_layer.cpp:700-706`), so a loader layer with
  such keys goes after the package's copies. Keep the two kinds in separate files.
- **Why.** The loader lists its layer after the package's (`loader/core/src/activate.cpp:34-43`,
  `276`), believing the list is low priority first. So `non-nvidia.conf`'s `rtx.graphicsPreset = 5`
  ([ADR 0030](../decisions/0030-non-nvidia-gpus-and-late-runtime-dlls.md)) loses to the package
  layer's `rtx.graphicsPreset = 4` [D]. ADR 0030 was never checked in a session on a GPU that is not
  NVIDIA's (R3 triage, "Not run on a GPU that is not NVIDIA's").
- **Component.** Loader C++ (`activate.cpp` `layer_list`, `add_layers`); `loader/tests/test_activate.cpp`;
  `loader/proxy/tests/activation_integration.py`; [ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md); a new ADR
  amending ADR 0030's placement.
- **Effect.** Non-NVIDIA players get Remix's Auto preset, as ADR 0030 intended. Proposals 2 and 7
  depend on it; proposal 4's layer takes the other slot. None on NVIDIA players today.
- **Effort** S. **Risk** low; it changes settings only where a loader layer is written.
- **Verify.** Unit tests on the list order. One PoC session with a test layer holding a non-default
  value such as `rtx.skyProbeSide = 512`: the log's "Effective RtxOption values" must show it.
- **Decision.** Approve the amendment to ADR 0030.

### 2. An automatic low-VRAM layer

- **What.** At RTX activation the bootstrap reads `DedicatedVideoMemory` of the NVIDIA adapters
  through DXGI. `graphics_adapters()` already enumerates them for their vendor ids
  (`loader/core/src/activate.cpp:172-196`), and the menu panel already reads their memory
  (`loader/proxy/diagnostics.cpp:45-63`). With 8 GiB or less on the largest NVIDIA adapter, the
  runtime's own threshold, it writes `native-loader/remix/low-vram.conf` like `non-nvidia.conf`
  (`loader/proxy/runtime.cpp:208-213`) and lists it first (proposal 1). Existing runtime options only:

  ```
  rtx.lowMemoryGpu = True
  rtx.opacityMicromap.cache.maxBudgetSizeMB = 512
  rtx.skyProbeSide = 1024
  rtx.volumetrics.froxelGridResolutionScale = 8
  rtx.terrainBaker.cascadeMap.levelResolution = 2048
  ```

  Optional: `rtx.opacityMicromap.cache.minFreeVidmemMBToNotAllocate = 1024` (OMM stops growing
  earlier), and the night-sky paths of proposal 6. `rtx.lowMemoryGpu` is NoSave: Remix never writes
  it to a file (`rtx_option.cpp:549-552`), but it reads it from one like any option [D]. Under Custom
  nothing else sets it (`rtx_options.cpp:461` runs only for Auto). Report `activation.low_vram` and
  the adapter's memory in `status.json`, `nlctl activation` and the menu panel. Add an override in
  `native-loader/config.json` (`auto`, `on`, `off`).
- **Not proposed:** `rtx.graphicsPreset = 5` on 8 GB GPUs. It would give the runtime's Medium preset,
  which changes the look, and presets write above even `user.conf`
  ([ADR 0021](../decisions/0021-remix-defaults-in-one-low-layer.md)). Keep it as the alternative.
- **Component.** Loader C++ (activation plan, bootstrap, status, nlctl, tests);
  [ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md); a new ADR. The values could live in a generated text in
  the loader, as `non_nvidia_layer_text()` does, or as a second layer in the package that the loader
  lists only on low-VRAM machines.
- **Effect on 8 GB GPUs** [D]. OMM: at most 512 MiB instead of about 1013 MiB in use. Sky probe: -72 MiB.
  Froxels: -29 MiB at 960x540. Replacement textures: 4096 px textures stream at no more than 2048 px,
  a quarter of their top-mip bytes. Modern House's 118 such files are 1,856 MiB on disk; they would
  need at most about 464 MiB. Terrain atlases: a quarter. Players whose own `rtx.conf` or `user.conf`
  sets one of these keys keep their value. On 16 GB machines: indirect only.
- **Effort** M. **Risk:** softer textures on 8 GB GPUs; a smaller OMM cache can cost ray-tracing
  speed in foliage and fences [I]; a DXGI failure writes no layer, which is today's behaviour.
- **Verify.** Unit tests (threshold, list position, override). A PoC session with the override on:
  the effective values in the log, and frame time with `rtx_agent_frames`. Screenshots for texture
  sharpness. A tester run on an 8 GB GPU with proposal 5's telemetry, against a run without the layer.
- **Decision.** The threshold (8 GiB, or a second tier for 10-12 GiB). The values. On by default.

### 3. Keep the last session's evidence at the next start

- **What.** Before it loads the runtime, which truncates the log, the bootstrap:
  1. reads the last lines of `rtx-remix/logs/remix-dxvk.log` and classifies the previous session:
     device lost (`VK_ERROR_DEVICE_LOST`, "Exiting after GPU device loss"), CS-thread exception,
     "Memory allocation failed", or nothing found;
  2. looks for files newer than the previous start: `rtx-remix/logs/.sentry-native/last_crash` and
     `reports/*.dmp`, `crashes/*.dmp` and `*.txt` (the text "OUT OF MEMORY!" in such a dump marks
     exhausted commit), `*.nv-gpudmp`;
  3. copies the log, and the dumps if the player allows it, into
     `native-loader/logs/sessions/<UTC time>-<reason>/`; keeps the last five, at most 200 MB; never
     deletes or moves an original;
  4. writes `previous_session` (reason, time, folder) into `status.json`. `nlctl` prints it, and the
     menu panel ([ADR 0050](../decisions/0050-startup-text-and-main-menu-diagnostics.md)) shows one
     line with the folder.
- **Component.** Loader C++ (bootstrap start-up, status, nlctl); the menu panel's text in seven
  languages; the companion guide's troubleshooting page.
- **Effect.** None on memory. It stops evidence from vanishing (section 3) and feeds proposal 7.
- **Effort** M. **Risk** low: reads and bounded copies. Dumps hold process memory, so they stay local
  and are never uploaded.
- **Verify.** Unit tests on fixture logs (device loss, CS exception, clean end). An integration test
  with fixture files in a temporary game root.
- **Decision.** Keep dumps by default, or only the log unless the player opts in. Retention.

### 4. A one-start GPU diagnostics switch

- **What.** `native-loader/config.json` `diagnostics.gpu_crash_dumps` (`next_start`, `always`, `off`),
  and later a button in the menu panel. The loader then writes `native-loader/remix/diagnostics.conf`
  (`dxvk.enableAftermath = True`, `dxvk.enableAftermathResourceTracking = True`,
  `rtx.enableGpuCrashState = True`), listed after the package's copies because these are read from the
  merged config, where the last file wins (`src/dxvk/dxvk_options.cpp:36-39`). It also sets
  `DXVK_AFTERMATH_DUMP_PATH` to the absolute path of `native-loader\logs\gpu\` for that process (the
  runtime puts the path in front of the file name as given, `dxvk_instance.cpp:353-359`). Proposal 3
  collects the dumps.
- **Component.** Loader C++, config schema, docs.
- **Effect.** The next device loss names its kind and the faulting resource and shaders, in the log
  itself (section 1.7).
- **Effort** S. **Risk:** Aftermath slows rendering somewhat (the runtime says "may have a small
  performance overhead", `src/util/util_crash_report.h:89`), so it is off by default. Dumps hold GPU
  state.
- **Verify.** A PoC session with the switch: "Aftermath enabled" in the log and the Sentry tag
  `enabled`; the switch resets after one start.
- **Decision.** Config only, for testers, or also a menu button.

### 5. Memory telemetry for testers

- **What.**
  1. A low-priority bootstrap thread appends a line every 10 s to `native-loader/logs/memory.csv`:
     the process's private bytes and working set (`K32GetProcessMemoryInfo`); system commit, its limit
     and available RAM (`K32GetPerformanceInfo`); this process's GPU local and non-local use and
     budget (`IDXGIAdapter3::QueryVideoMemoryInfo`, DXGI loaded at run time as `activate.cpp` does).
     It flushes each line, so a crash keeps the last one, and keeps the last two hours.
  2. The companion, when `RemixResource.GetVramStats` exists (the fixes module), writes Remix's
     categories every 30 s to `garrysmod/data/native-loader/vram.csv` (fields:
     `public/include/remix/remix_c.h:1025-1053`).
  3. The testing guide documents `rtx_vram_stats`, `rtx_agent_health` (the fixes' `rtx_agent`
     add-on) and `dxvk.hud = memory` in the root `dxvk.conf`.
- **Component.** Loader C++ (a thread in the bootstrap; its import table stays KERNEL32-only), the
  companion Lua, [TESTING.md](../TESTING.md).
- **Effect.** It shows where memory goes on testers' machines, whether something grows over a
  session (the 32 MiB regions), and whether GMod's commit follows its VRAM.
- **Effort** M. **Risk** low: one DXGI call and two kernel calls per sample; about 1 MB per two hours.
- **Verify.** A PoC soak (`rtx_agent_exercise`, map changes) plotted against Task Manager.
- **Decision.** On for everyone or a tester switch. Whether proposal 3's bundle includes it.

### 6. Smaller night-sky textures on low-VRAM machines

- **What.** One of:
  - (a) the companion defaults `nativeloader_sky_stars` to `procedural` when `status.json` reports
    low VRAM: -213 MiB, a different look;
  - (b) the package ships 4096 px versions (the same files without mip 0: about 53 MiB resident), and
    `low-vram.conf` points `rtx.atmosphere.starMapTexture`, `starMapGalaxyTexture` and
    `starMapNebulaTexture` (`rtx_atmosphere.h:534-540`) at them: -160 MiB. At 1080p with DLSS
    Performance the star layer is sampled near its second mip anyway (RESEARCH.md's mip formula:
    `2 tan(fovY / 2) / downscaled height`, times `2^mipBias`), so (b) should look the same except when
    zoomed in [D].
- **Component.** (a) companion Lua; (b) `tools/sky` (the generator), `packages/runtime` (imported
  with `tools\inputs.py`, about 12 MB more in Git LFS [I]), the low-VRAM layer.
- **Effort** S. **Risk:** (a) look; (b) little.
- **Verify.** Screenshots at night at a pinned camera, 8192 against 4096, normal view and zoomed;
  VRAM through proposal 5.
- **Decision.** (a) or (b).

### 7. A one-start safe mode after an abnormal end

- **What.** When proposal 3 finds a device loss, the next start offers, or applies once, a
  `native-loader/remix/safe-mode.conf` listed first: `rtx.opacityMicromap.enable = False` plus the
  low-VRAM values. It tells the companion through `status.json` to use the procedural night sky. The
  notice names the player's own saved values that no loader layer can override, such as frame
  generation in `user.conf`: `rtx.conf` and `user.conf` are above every loader layer
  (`rtx_option_constants.h:186-194`). The start after it is normal again.
- **Component.** Loader C++; the companion and the menu panel's notice.
- **Effect.** One start with up to 1 GiB less VRAM (OMM off) after a device loss; a clear message.
- **Effort** M. **Risk:** OMM off slows alpha-heavy scenes; a player who does not read the notice may
  think the look changed for good.
- **Verify.** Fixture log, then the next start has the layer and the one after it does not.
- **Decision.** Automatic or on a prompt. What goes in it.

### 8. Make the runtime's logs self-describing

- **What.** A runtime patch (0015):
  1. at device loss, before the Sentry step, log the driver's budget and use per heap and DXVK's
     categories (the numbers `remixapi_GetVramStats` returns);
  2. log the same line at each camera cut and every five minutes;
  3. replace `ONCE` on the two OMM budget lines (`rtx_opacity_micromap_manager.cpp:190`, `199`) with
     once a minute plus a count;
  4. write `rtx-remix/logs/last_gpu_crash.json` (time, reason, those numbers) before
     `TerminateProcess`, so proposal 3 need not parse text;
  5. optional: request `VK_EXT_device_fault` where the driver offers it and log
     `vkGetDeviceFaultInfoEXT` after a loss. The fork never references it today.
- **Component.** Runtime fork, then a rebuild ([runtime/README.md](../../runtime/README.md)) and an
  import of a new `d3d9.dll` (about 363 MB).
- **Effort** S to M, plus the rebuild. **Risk** low.
- **Verify.** Runtime unit build; a development build's GPU-crash trigger.
- **Decision.** Bundle it with the next runtime rebuild, or wait.

### 9. Drop the fixes' memory-limit call

- **What.** In the user's fork of the RTX fixes, remove `SetMemoryLimits(256, 1024)` at module open
  (`source/module.cpp:431`), and `RemixResource.SetMemoryLimits` or make it a documented no-op. Do
  not replace it with real budget options set from Lua: `remixapi_SetConfigVariable` writes into the
  User layer (`rtx_remix_api.cpp:1798`), which Remix's Save writes into `user.conf`.
- **Component.** `garrys-mod-rtx-remixed` (GPL-2.0), then a rebuild of `gmcl_RTXFixesBinary` and an
  import into `packages/fixes/modules`.
- **Effect.** Two fewer warnings at every map load, and no false belief that VRAM is capped at 1 GB.
- **Effort** S. **Risk** none: the call does nothing today.
- **Verify.** No `[RTX Option]: 'rtx.resourceLimits...` line in a session log.
- **Decision.** Approve the change in the fixes.

### 10. Test OMM, then decide on the runtime

- **What.** Ask the tester for the runs of section 1.7, step 4. If losses repeat, one more with OMM
  on and `rtx.opacityMicromap.cache.minUsageFrameAgeBeforeEviction = 3000`: if the gap from the first
  budget warning to the loss moves with it, eviction is implicated. If OMM is implicated, change the
  runtime so the OMM budget shrinks and evicts when free VRAM falls below the hard limit; today it only
  stops growing (`rtx_opacity_micromap_manager.cpp:180-187`). Separately, test
  `d3d9.evictManagedOnUnlock = True` on the PoC: process commit before and after, and whether
  replacement textures and texture categories still match.
- **Component.** Tester runs; the runtime fork; a PoC test.
- **Effort** tests S, runtime change M. **Risk:** OMM off costs speed; `evictManagedOnUnlock` may
  interact with Remix's hashing.
- **Decision.** Whether to ask the tester, and who contacts them.

### 11. Tester guidance and RAM warnings

- **What.**
  - A troubleshooting page for 8 GB and 16 GB machines: a system-managed page file on a drive with at
    least 30 GB free; close browsers and OBS recording; watch Task Manager's Committed; frame
    generation off; keep GMod's texture detail at its highest (the `mat_picmip` caveat in section 2).
  - The menu panel warns when the commit limit is under 32 GB, or when more than 70 % of it is in use
    before a map loads (`K32GetPerformanceInfo`).
  - [skills/mmd-remix-pbr](../../skills/mmd-remix-pbr/SKILL.md): publish with `--max-size 2048` for
    characters meant for 8 GB players.
  - `~gmod_topbr` ships uncompressed textures (136 MiB); BC7 would cut that by about three quarters.
- **Component.** Docs, the companion guide, the menu panel, the skill.
- **Effort** S each. **Risk** low.
- **Decision.** Which of these, and whether the RAM warning shows for every player.

## 6. Open questions for the user

1. May the loader's own layers go first in `DXVK_CONFIG_FILE` (proposal 1)? Non-NVIDIA players would
   then get Remix's Auto preset, as ADR 0030 intended.
2. The low-VRAM layer: 8 GiB or less only, or a second tier for 10-12 GiB? On by default, with an
   opt-out?
3. Its values: is a 512 MiB OMM cap and one mip less for replacement textures acceptable on 8 GB GPUs,
   keeping the classic look otherwise? Or Remix's Auto preset there instead?
4. Local crash data: keep dumps by default, or only the log text unless the player opts in? How much,
   for how long?
5. Safe mode after a device loss: automatically once, or only when the player agrees? With OMM off?
6. Night sky on 8 GB GPUs: the procedural sky, or shipped 4096 px images?
7. Sentry: keep uploading, with consent, to the address compiled in from upstream, change it, or turn
   uploading off and rely on local bundles?
8. Should someone ask the tester for the dedicated runs of section 1.7?
9. Approve removing the fixes' `SetMemoryLimits` call?
10. Worth a PoC test of `d3d9.evictManagedOnUnlock`?

## Not verified

- No 8 GB GPU is available here. Every VRAM saving above is derived, not measured.
- The cause of the device loss; whether a TDR happened; the frame rate.
- The tester's mod files: the sizes are of this machine's copies of the same mods.
- The owner of the write-combined 32 MiB regions, and whether Windows charges GMod's commit for VRAM.
- Whether the terrain baker ran in these sessions.
- The non-NVIDIA layer's failure (proposal 1) is derived from the code, not seen in a session.
- `rtx.lowMemoryGpu` being read from a layer is derived from the code; the first test session should
  show it in "Effective RtxOption values".
- That `mat_picmip` changes Remix's texture hashes is inferred, not tested.
- The page file's settings and free disk space on the tester's machine are not in the evidence.

## Method

- Dumps: `out\tmp\scripts\dump_r5.py` (header, streams, MiscInfo with the time zone, exception,
  threads and names, modules, the memory streams decoded with `minidumpapiset.h` from the Windows SDK
  10.0.26100.0, strings) and `meminfo_hist.py` (the committed regions by size and protection).
- Logs: `logview.py`; `config_diff.py` compares the two option prints; `envelope_split.py` split the two
  cached Sentry envelopes into `out\tmp\extract\`.
- Textures: `dds_header.py` (the night sky, from the xz inputs); `dds_census.py` (this machine's mods).
- Runtime: `git show` and `git grep` at `6f2dbd79` and `f2068a98` (`gitlines.py` numbers the lines).
  Two read-only surveys of the fork were checked against the code for every line cited here.
