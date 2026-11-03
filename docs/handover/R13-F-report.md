# R13-F: material preloads load at their first draw (report)

Status: **done** (Claude, 2026-11-03). The user accepted the hitch the A/B measured (0.11-0.32 s), and
again the 0.20-0.58 s the check sessions on the merged build found in a later machine state (section
9); runtime patch 0030 merged into `main`. Brief: [R13-P report](R13-P-report.md) section 5.1 and
[ADR 0102](../decisions/0102-character-pbr-maps-stay-preloaded.md) ("Load a preload on its first
draw"). Decision record: [ADR 0103](../decisions/0103-material-preloads-load-at-their-first-draw.md).
Branch `claude/vibrant-perlman-d01bce` (worktree `.claude/worktrees/vibrant-perlman-d01bce`); runtime
branches `claude/r13-first-draw` (measured, on 0028) and `claude/r13-first-draw-0030` (shipped, on
R13-D's 0029) in `out/worktrees/r10-eyes/out/runtime-src`. Evidence and lab: `out/r13-f/` in that
worktree (git-ignored; below `r13-f/`).

## In short

- **Runtime patch 0030** (measured as 0029 on 0028): a USD material's `preload_textures` no longer
  loads every mip when its mod loads. The texture waits at its smallest mips; the first frame that
  draws the material pins it and loads every mip synchronously, before that frame is traced.
  `rtx.texturemanager.preloadOnFirstDraw` (default on) turns it off.
- **The look is unchanged.** R13-P's lab, today's runtime (A) against the patched one (F), three PoC
  sessions each, same preloading packs. At full resolution, aligned on the hotloader's crossfade,
  every F film shows Robin's emblem, brooch and bodice complete in its first crossfade frame, as A's do;
  the streamed variant's grey emblem does not appear. With F the replacement textures change once per
  character, by its whole maps, one frame after it is presented. Settled views stay within run-to-run
  noise.
- **Start-up memory:** 2.39 GB less of replacement textures at idle (2.657 to 0.266 GB), 1.64-1.70 GB
  less driver VRAM, 1.7-2.5 GB less private bytes, about what R13-P's streaming saved. In the field the
  flag holds 11.05 GB of files at every start; scaled, about 7-8 GB less VRAM and commit at idle.
- **The hitch:** the frame that first draws a character lasts 0.11-0.32 s instead of today's
  0.04-0.11 s at that moment (0.31-0.53 GB of maps staged in 0.10-0.20 s). Later in the day, with the
  machine in another state, the same staging took 2-3 times as long and the frame 0.20-0.58 s, while
  today's runtime stayed at 0.07-0.11 s (section 9). The picture stops on the
  hotloader's stand-in for that frame. Once per character and session: a respawn costs nothing more.
  For scale, the same first spawn already freezes twice for 0.8-1.3 s while the hotloader loads the
  model, about two seconds earlier, with either runtime. From the drive instead of the file cache
  (after a reboot) the frame would take about 0.3-0.7 s on this NVMe drive.
- **Map load:** 20.8-21.6 s with F, 22.2-30.8 s with A, within the run-to-run variation R13-P saw.
- **Decision:** the user accepted the hitch the A/B measured (section 5). R13-D's option lock had merged
  first as 0029, so this patch is rebuilt as 0030 on top of it and checked in PoC sessions (section 9);
  those found the larger range above, which the user confirmed before the merge. The A/B's control,
  today's runtime at the time, was 0028; the option lock does not touch texture loading.

## 1. The change: runtime patch 0030

`runtime/patches/0030-Load-material-preloads-at-their-first-draw-instead-o.patch`, runtime commit
`dc537fd2` on R13-D's 0029 (`a816a673`); measured as patch 0029, commit `e3d0f95a` on 0028 (`403b2336`),
with the same diff:

- **At mod load** (`RtxTextureManager::preloadTextureAsset`): a texture that a USD material's
  `preload_textures` asks for no longer requests every mip. It is created as a streamed texture would
  be: `m_canDemote` true, one mip requested, so the DDS loaders upload its five-mip tail. It is marked
  `m_preloadOnFirstDraw` and `m_preloadYields` (patch 0026's preload).
- **At its first draw** (`RtxTextureManager::addTexture`, which `SceneManager::trackTexture` calls for
  every texture of a material an instance draws): it is pinned (`m_canDemote = false`), every mip is
  requested, and `scheduleTextureLoad(tex, false)` stages them synchronously on the render thread.
  That is the path `addTexture` already takes for a purged preload. The staged chain is uploaded with
  the frame's other uploads in `submitTexturesToDeviceLocal`, which `RtxContext::injectRTX` calls
  before `prepareSceneData` and the trace (`rtx_context.cpp:658`). So the frame that first draws the
  material already samples every mip, as a preload at mod load did.
- **Afterwards** nothing differs from a preload at mod load: pinned, outside the streaming lists,
  released by patch 0026 only when undrawn for 10 s under real VRAM pressure, and restored when drawn.
- **A load already in flight at the first draw** makes `scheduleTextureLoad` leave the texture alone.
  Remix builds a mod's materials on a worker thread and the render thread publishes them, so a
  material drawn in the frame its mod (re)loaded can find the upload of its smallest mips still
  waiting. That upload is replaced by one of every mip (`AsyncRunner::replaceReadyWithSync`, as
  `queueAdd`'s CI path replaces one), uploaded with that frame's: whole in the first frame, as a preload
  at mod load would be. Only a load still on the worker thread (after an explicit texture purge) is
  listed instead, and `garbageCollection` loads it synchronously in the next frames (one frame at its
  tail at most).
- **Unchanged:** textures too large for the streaming staging buffer
  (`WAR_doesAssetFitIntoFixedAllocator`), preloads that are not a USD material's (dome lights, the Remix
  API's: they never pass `preloadYields`), and every preload while
  `rtx.texturemanager.neverDowngradeTextures` is on load whole with the mod, as before.
- **Off switch:** `rtx.texturemanager.preloadOnFirstDraw` (default True; RtxOptions.md regenerated).
  Off, every preload loads with its mod again. It applies to materials loaded after a change.
- **Log:** an `[RTX Preload]` line for each frame with first draws: the frame, how many textures and
  bytes, the time their synchronous staging took, and how many still wait.
- **Rule and unit check:** `preloadWaitsForFirstDraw` in `rtx_texture_budget.h`, five checks in
  `test_texture_budget_pressure`.
- **Build:** `runtime\build_runtime.ps1 -Fork <r10-eyes tree> -Worktree <r10-eyes tree> -NoImport -Jobs 8`
  in `out/worktrees/r10-eyes/out/runtime-src`, an idle clone, so R13-D's tree stayed untouched
  (`r13-f/build2.log`): the tree is base `c6b48ed1` plus the 29 patches (tree `e0cfdb34`, which
  `-Verify` confirms); `remix-main+e3d0f95a`, `d3d9.dll` 397,907,456 bytes, SHA-256
  `3907ec2ccfe958cc223f7d253b2db2dbfcd7aa8cc6a90576182d5aa7b7ad23ec`, the DLL imported here. All 33
  runtime unit tests pass (`r13-f/unit-tests2.log`), including `test_documentation` (RtxOptions.md) and
  `test_texture_budget_pressure`.
- **Two builds were measured.** The first (`a94451b8`, `d3d9.dll` `b8140c09...`, `r13-f/build.log`)
  listed a texture with any load in flight for the next frames; the in-flight replacement above came
  after `f1` and `f2`, which ran that build. Nothing else differs, and no session here reached that
  path: every `[RTX Preload]` line reports `"pending":0`. `f3` ran the final build.

## 2. The A/B

R13-P's lab, copied to `r13-f/` with three changes: the variant is the runtime (`--runtime A|F`), both
variants use R13-P's preloading packs (its variant A), and the probe also records every frame's time
during each track (`R13P_FRAMES`).

- **Runtimes.** A is today's: R13-P's pinned copy of the published package
  `0.0.0-dev.20261103172411+a911b59a` (patch 0028, `d3d9.dll` `91f0696c...`). F is the same `.gma` with
  only `native/payload/runtime/d3d9.dll` replaced by patch 0029's build and its manifest entry and
  version changed to match (`+a911b59a.r13f` with the first build, `.r13f2` with the final one;
  `r13-f/make_runtime_package.py`; every other entry is byte for byte the same; `nlctl manifest`
  accepts both).
- **Packs.** The three Workshop character packs (Robin RTX, Guinaifen RTX, Evernight & March 7th RTX)
  as R13-P's dev packages, unchanged: every material has `preload_textures = 1`.
- **Scene, probe and driver** as in R13-P (its section 2): the PoC with the copied field library on
  gm_flatgrass at 3840x2160, high tier, ReShade off; the player pinned at (640, -192); the same spawns,
  cameras, films and settled screenshots (final image and debug views 25, 16, 94). The lab process is
  DPI-aware, and the films hold the full frame at half size plus the middle third at full size.
- **Sessions:** `a1`, `f1`, `f2`, `a2`, `a3`, `f3`, in that order (A first, so the packs' files are in
  Windows' file cache for every F session, as R13-P's B sessions had them). `r13-f/cpu.csv` logged the
  machine's CPU use and busy processes every 2 s during the holds.

## 3. Results

### First appearance (the user's rule)

Films and zooms in `r13-f/preview/`; the films hold about one frame per 110-140 ms. Each character's
first spawn goes: the hotloader's dark stand-in appears, about two seconds later the crossfade starts
(the character under the stand-in, then a light stripe across it, then the character alone).

- **Robin's emblem, full resolution** (`zoom-emblem-all.jpg`: one row per hold, the first three film
  frames from the crossfade; also `zoom-emblem-a1-f1-a3-b3.jpg`, `zoom-emblem-f2.jpg`):
  - A (`a1`, `a2`, `a3`): at +0 ms the treble-clef emblem, the star brooch and the bodice's trims are
    complete under the dark stand-in; at +120-140 ms the crossfade's wipe crosses the costume (a smeared
    sleeve or a light stripe, in A as well); settled from about +250 ms.
  - F, `f2`: its film caught the first stage too, and it is the same: complete emblem, brooch and trims
    under the stand-in at +0 ms, then the wipe and the settled character.
  - F, `f1` and `f3`: their first captured crossfade frame is a later stage (the stripe in `f1`, the
    settled character in `f3`), with the complete emblem and brooch. The capture before it (138 and
    117 ms earlier) still shows the stand-in alone, and the one before that came 392 and 390 ms earlier:
    the window did not update during the first draw's long frame, and the crossfade's first stage then
    showed for less than a capture interval (`zoom-emblem-f3.jpg`).
  - R13-P's streamed `b3`, the positive control: at +0 ms a flat grey treble clef without the brooch.
- **Fine detail over time** (`detail_curve.py`, the same 500x600 box, as a percentage of the film's
  settled value; `compare/detail-curve-first-robin.json`): at the crossfade's first stage A shows
  59-62 % (the stand-in darkens it), `f2` 61.8 %, and the streamed `b3` 32.3 %. The first frames of `f1`
  and `f3`, at later stages, show 91.6 and 88.6 %, as A's frames of those stages do (91.3-99.7 %).
  Every hold, `b3` included, then climbs the same way to 100 % by about +700 ms, as the crossfade and
  the denoiser settle.
- **Guinaifen and the respawn:** at this capture rate neither film caught Guinaifen's crossfade, in A
  or F, and the detail measure does not separate the variants there (A alone spans 79-99 % at the first
  frame after the stand-in). Every captured frame that shows her is complete in both runtimes.
- **Residency, per frame** (the probe's `usedMaterialTextureBytes` track): with F the replacement
  textures change once per character, one game frame after the hotloader's presentation, by its whole
  maps (+366, +534, +453, +313 MB for Robin, Guinaifen, Evernight, March 7th), the same in every F hold.
  R13-P's streamed variant took 10-50 increments over 0.15-0.9 s. A never changes (2.657 GB from the
  start). The runtime's `[RTX Preload]` lines agree: 34, 32, 28 and 17 textures, staged in the frame
  that first drew each character.
- **So the first frames match today's.** What F adds is time: the frame that first draws a character
  is longer (next section). The picture stops on the stand-in for that frame, and the crossfade, which
  runs on game time, then continues from a later point.

### The hitch

Frame times from the probe (`hitch.py`; "at the presentation" is the longest frame from 2 frames
before the hotloader's presentation to 10 after it; the whole track also covers the model's own load,
about two seconds earlier):

| Event | A: longest frame at the presentation, `a1` / `a2` / `a3` (ms) | F: `f1` / `f2` / `f3` (ms) |
|---|---|---|
| Robin, first draw, close-up | 97 / 107 / 84 | 269 / 220 / 237 |
| Guinaifen, first draw, close-up | 72 / 67 / 72 | 324 / 246 / 265 |
| Evernight, first draw, wide | 96 / 98 / 95 | 267 / 265 / 254 |
| March 7th, first draw, wide | 37 / 37 / 75 | 120 / 112 / 118 |
| Robin again after removal | 85 / 77 / 86 | 80 / 78 / 75 |
| Longest frame of each first spawn's track (the model's load, about 2 s before) | 235-1434 | 245-1274 |

- With F, the frame after the presentation takes 0.11-0.32 s (it draws the character for the first time
  and stages its maps). Today the same moment has two or three frames of 37-107 ms. F adds about
  0.04-0.08 s for March 7th, 0.13-0.17 s for Robin and Evernight, 0.18-0.25 s for Guinaifen.
- The extra time is mostly the synchronous staging, which the runtime logs (`[RTX Preload]`):

| Character | Textures | Whole maps (MB) | Staging, `f1` / `f2` / `f3` (ms) | Still waiting afterwards (textures, MB) |
|---|---:|---:|---|---|
| Robin | 34 | 365 | 159 / 120 / 149 | 136, 2,016 |
| Guinaifen | 32 | 529 | 201 / 173 / 190 | 104, 1,487 |
| Evernight | 28 | 453 | 152 / 157 / 150 | 76, 1,034 |
| March 7th | 17 | 313 | 108 / 101 / 107 | 59, 721 |

  That is 2.3-3.1 GB/s (median 2.9) on one thread, from the file cache.

- **Once per character and session.** A respawn after removal costs the same with both runtimes
  (77-85 ms): the maps stay pinned (0026 releases them only under real VRAM pressure, after 10 s
  undrawn). A camera cut to a close-up of a character already drawn costs nothing either.
- **Context:** with either runtime a character's first spawn already freezes twice for 0.8-1.3 s
  (Robin, Evernight) or 0.2-0.3 s (Guinaifen) about two seconds before it appears, while the hotloader
  loads its model (R13-A's "characters load on first use").
- **Cold files.** These sessions read the maps from Windows' file cache (A had just read them). From
  the drive, the same read takes longer: copies of Robin's and Guinaifen's maps written unbuffered
  (`xcopy /J`, so not cached) read through a file mapping at 0.69-0.89 GB/s against 1.34-1.39 GB/s cached
  (`cold_read.py`, `compare/cold-read-*.json`): 0.4-0.7 s per GB more on this NVMe drive (Samsung 980
  PRO, where the field and the PoC are). A character's first draw after a reboot would then take about
  0.3-0.7 s; on a SATA SSD (0.5 GB/s) about 1 s, on a hard disk several seconds. Today the same cold read
  happens at start-up instead, for every preloaded map.

### Memory and the map's load

At idle, 20 s after the probe starts, before any character is drawn (GB; `compare/hitch-all.json`):

| Hold | Runtime | Replacement textures | Driver VRAM | Private bytes | Working set | Peak private | Seconds to the map |
|---|---|---:|---:|---:|---:|---:|---:|
| `a1` | A | 2.657 | 8.155 | 17.25 | 9.17 | 23.49 | 24.7 |
| `a2` | A | 2.657 | 8.153 | 17.27 | 9.19 | 23.58 | 22.2 |
| `a3` | A | 2.657 | 8.180 | 17.95 | 9.90 | 23.97 | 30.8 |
| `f1` | F | 0.266 | 6.477 | 15.50 | 9.00 | 22.83 | 21.6 |
| `f2` | F | 0.266 | 6.509 | 15.47 | 8.96 | 22.94 | 20.8 |
| `f3` | F | 0.266 | 6.503 | 15.59 | 9.08 | 22.96 | 21.2 |

- **Start-up:** F holds 2.39 GB less of replacement textures at idle (2.657 to 0.266 GB: the packs'
  170 preloaded textures sit at their tails), 1.64-1.70 GB less driver VRAM and 1.7-2.5 GB less private
  bytes (1.7-1.8 GB against `a1` and `a2`). The working set barely changes. These are R13-P's streaming
  savings at idle (2.23 GB, 1.64-1.71 GB, 1.70 GB).
- **With all four characters drawn** F holds 1.93 GB, A 2.66 GB: 59 preloaded textures (0.72 GB) belong
  to parts the probe never draws, and stay at their tails.
- **Peak private bytes** 0.5-1.1 GB lower with F (22.83-22.96 against 23.49-23.97 GB).
- **Map load:** 20.8-21.6 s with F, 22.2-30.8 s with A. R13-P measured 19.7-22.7 s with A on the same
  scene, so at 2.4 GB of preloads the difference is within run-to-run variation; staging 2.4 GB at the
  rate above takes about 1 s.
- **In the field** the flag holds 11.05 GB of files (R13-B). With F, a start-up holds none of it until
  a character is drawn; scaled by this A/B (about 1.7 GB of VRAM and commit per 2.39 GB of textures),
  that is about 7-8 GB less driver VRAM and commit at idle, less what the session draws, and about 4 s
  less of mod loading from the cache (8-11 s from the drive).

## 4. Settled image

The probe's 23 settled views (final image and debug views 25, 16 and 94 of each close-up, the lineup,
idle, the turn back and the respawn), for the 9 pairs across the runtimes against the 6 within one
(`pairs_stats.py`, `compare/pairs-stats.json` and `pairs-stats-aligned.json`; mean of each pixel's
largest channel difference over the middle of the frame, 0-255):

- **Debug views.** Raw, Robin's roughness differed most (1.45 across, 0.80 within). Its difference
  image is edges only (`preview/robin-roughness-diff-a1f1-vs-a1a2.png`): `f1`'s close-up was framed 2
  px off, since the close-up camera is placed from the character's bounding box, which hair and cloth
  physics move a little per session. Aligned by phase correlation first, 10 of the 15 debug views are
  at or below the within-runtime mean. The other 5 exceed it by 0.06-0.19, and their pairs overlap
  completely, for example Evernight's normals from 0.09 (`a3`-`f2`) to 3.9 across and within.
  Guinaifen's reflectivity, the largest relative gap (0.56 against 0.37), is edges of her dangling
  ornaments, in F against F as much as in A against F, and nearly nothing between `a1` and `a2`
  (`preview/guinaifen-reflectivity-diffs-a1f1-f1f2-a1a2.png`). No difference shows inside a surface,
  where a texture of another resolution would.
- **Final images** differ by session, not by runtime: `a2` is as close to every F hold (0.75-1.26) as
  the F holds are to each other (0.62-1.38), while `a1` and `a3` differ from all of them and from `a2`
  (1.3-3.9). The idle view, with no character in it, splits the same way.
- **Fine detail** (mean absolute Laplacian over the same region) differs by -0.3 to +0.6 % between
  the runtimes (F slightly higher in 19 of 23 views); R13-P's settled A/B differed by -0.6 to +1.1 %.

## 5. The user's decision

The look is unchanged; the cost is one long frame when a character first appears in a session. Asked
whether to accept that hitch and merge, the user answered "Yes, merge it" (2026-11-03). Section 9 has
the merge's preparation, and the larger range its check sessions found; asked again with that range,
the user answered "Yes, merge it". The choices that were not taken, for later:

- **Shorten the hitch** (not built): keep a staging pool for these loads, so the frame does not allocate
  fresh memory (section 9); stage a frame's first-draw textures on several threads (one thread stages
  2.3-3.1 GB/s in a good state; the upload itself is short); or prefetch a character's maps when the hotloader
  starts its spawn, about two seconds before the first draw (a Remix API call and a hotloader change).
  The latter would hide the load behind the stand-in entirely.
- **Today's behaviour** stays one setting away: `rtx.texturemanager.preloadOnFirstDraw = False`.

## 6. Evidence and how to rerun

- `r13-f/holds/<hold>/`: `case.json`, `results.json` (phases, tracks, frame times, spawns),
  `ram.csv`, `bursts/<event>/` (films), `session-record.json`, `restoration.json`, `memory-report.json`.
- `r13-f/sessions/<hold>/`: console, `remix-dxvk.log` (with the `[RTX Preload]` lines), screenshots.
- `r13-f/compare/`: `hitch-all.json`, `pairs-stats*.json`, `first-robin-*.json`, `cold-read-*.json`.
- `r13-f/preview/`: the strips and zooms named above.
- Tools, in `r13-f/`: `lab.py <hold> --runtime A|F` and `run_holds.py`; `r13p_probe.lua`;
  `make_runtime_package.py` (the F package); `hitch.py` and `tables.py`; `first_frames.py`, `zoom.py`,
  `detail_curve.py`, `pair.py` (films); `pairs_stats.py --align`; `cold_read.py`; `cpu_watch.ps1`;
  `write_packaged.ps1` (R13-D's import record); and `build.log`, `build2.log`, `unit-tests.log`,
  `unit-tests2.log`, `test-release.log`.
- The packages: the control is R13-P's pinned package, hard-linked into `r13-f/pinned/A/`. The two F
  packages were deleted afterwards to free the nearly full drive; their records are in
  `r13-f/pinned/F-b8140c09/` (first build, `f1`, `f2`) and `r13-f/pinned/F/` (final, `f3`), and
  `make_runtime_package.py <control> r13-f/runtime-F/d3d9.dll|runtime-F2/d3d9.dll <out> --suffix
  r13f|r13f2` makes them again in seconds (the DLLs and PDBs are kept).
- Rerun: from this worktree, `python out/r13-f/run_holds.py a4:A f4:F` (each hold waits for the PoC
  lock, takes about 5 minutes and restores everything).

## 7. PoC holds

Lock `out\r10\poc.lock`, task `R13-F` (UTC):

| Hold | Runtime | Held | Session |
|---|---|---|---|
| `a1` | A | 19:53:42-19:58:52 | quit normally, no Lua error |
| `f1` | F (`b8140c09`) | 19:58:53-20:03:56 | quit normally, no Lua error |
| `f2` | F (`b8140c09`) | 20:03:57-20:08:55 | quit normally, no Lua error |
| `a2` | A | 20:08:55-20:13:54 | quit normally, no Lua error |
| `a3-failed` | A | 20:39:05-20:57:22 | discarded: Model Hotloader could not install the packs' models ("Not enough free disk space for this model transfer"), so no character spawned |
| `a3` | A | 21:01:08-21:06:26 | quit normally, no Lua error |
| `f3` | F (`3907ec2c`, the final build) | 21:06:27-21:11:25 | quit normally, no Lua error |
| `f4` | 0030 build (`a5dbe933`) | 22:35:44-22:41:52 | quit normally, no Lua error; the lab first ended a field game R14 was using |
| `f5` | 0030 build | 22:42:47-22:48:55 | quit normally, no Lua error; the lab first ended R14's field game again |
| `f6` | F (`3907ec2c`) | 22:50:00-22:55:06 | quit normally, no Lua error |
| `a4` | A | 22:55:54-23:00:56 | quit normally, no Lua error |

- R13-D and R14-H used the PoC between `a2` and `a3`. No field game was running at the start of
  `a1`-`f3`, `f6` and `a4`. At `f4` and `f5` the lab, as R13-P's did, ended the running field game: R14's
  check, which it interrupted twice. It now waits for the field game instead.
- Each hold snapshotted the PoC's mutable trees, swapped in its own copy of the field library and wrote
  its own `config.json`. Afterwards it restored all 3,655 files exactly (`restoration.json`: inventory
  exact, no problems), put the PoC's own library back with an identical listing, and checked `user.conf`
  and the video settings. Every hold that quit normally put the field's `config.cfg` back
  (`settings_back: restored`).
- **`a3-failed`.** The hotloader installs the packs' models (125 small files) into the library at each
  session's start, and refuses a file when the drive has less than its size plus 512 MiB free. H: had
  27-31 GB free before and after, so something else filled it for a moment at about 20:40. With no
  spawn the probe waited; I ended that game by force (a closing GMod would have written this session's
  `config.cfg` for Steam Cloud), so it did not reach `settings_back`, and the next two holds put the
  field's `config.cfg` back. The lab now records free space at each hold's start (`disk.json`, 31.2 GB
  for the new `a3`) and refuses to start below 15 GB. To free space I deleted each finished hold's
  `after/native-loader/packages/`: the copy of the deployed RTX package that restoration moves out,
  the same files as the pinned `.gma` (1.27 GB each).
- Lab changes after `a2`: the lock is retried every 15 s instead of 120 s, because releases kept going
  to the other two sessions' retries. Two attempts at `a3` that were still waiting for the lock (nothing
  held) were stopped and cleared; their folders held only the files written before the wait.

## 8. Not done, or open

- **Cold files** were not measured in a session: the loader deploys a package's files with ordinary
  writes, so in the lab Remix always reads them from the cache. The cold estimate above comes from
  unbuffered copies read the way the DDS loader reads.
- **The field** was not changed (no permission to put a test runtime there); its numbers are scaled
  from this A/B.
- **A material drawn in the frame its mod loaded** (the in-flight replacement, section 1) was not
  exercised: no session here loaded a mod while its character was on screen. A hot reload of `ai_pbr`
  with a new character on screen, as rpai's tuning loop does, would.
- **`tools\test.ps1 -Config Release`** (`r13-f/test-release.log`; `test-release2.log` with patch 0030;
  `test-release3.log` on the final tree, after R14's merge): repo conventions and all Python tests (28,
  25 and 539, then 545) pass; 23 of the 26 CTests pass. `nl_render_guard_tests`, `nl_tests` and
  `nl_proxy_tests` fail in this worktree only: their scratch paths outgrow the path limit under
  `.claude\worktrees\vibrant-perlman-d01bce` ("directory is not empty", "file already exists"). The
  same binaries pass from a short drive alias of the worktree (22, 266 and 39 cases, none failed), as
  earlier rounds found for the guard test. No loader code changed; run the gate again from the merge's
  checkout.
- **Shorter hitch** (parallel staging, prefetch at spawn): not built.

## 9. The merge: patch 0030 on R13-D's 0029

- **Runtime.** Runtime commit `e3d0f95a` cherry-picked onto R13-D's `a816a673` as `dc537fd2` (branch
  `claude/r13-first-draw-0030` in `out/worktrees/r10-eyes/out/runtime-src`; no file in common) and
  exported as `0030-Load-material-preloads-at-their-first-draw-instead-o.patch`, the same diff as the
  measured patch. `build_runtime.ps1 -NoImport -Jobs 8` (`r13-f/build3.log`): `remix-main+dc537fd2`,
  `d3d9.dll` 397,908,992 bytes, SHA-256
  `a5dbe933cdb45881e682b52311879f4d83650ba106f5fc5f14fcdc14f4463e80`. `-Verify`: base `c6b48ed1` with the
  30 patches, tree `5013a370`. Runtime unit tests: 34 of 34 (`r13-f/unit-tests3.log`), R13-D's
  `test_rtx_option_threads` included.
- **This branch** was rebased onto `main` (`6f95e6c`) with its own earlier import dropped, and that DLL
  imported once (`packages/runtime`, `runtime/base.json` `packaged`), so only one new DLL reaches Git LFS.
- **Check sessions** (same lab and scene; `f4` and `f5` with this build, `f6` with the measured final
  0029-on-0028 build `3907ec2c`, and `a4` with today's 0028 runtime; held 22:35-23:01 UTC, each quit
  normally, no Lua error, PoC restored exactly):

  | Hold | Runtime | Longest frame at each presentation: Robin / Guinaifen / Evernight / March 7th / respawn (ms) | Staging (ms) |
  |---|---|---|---|
  | `f4` | 0030 build | 360 / 479 / 445 / 214 / 78 | 265 / 359 / 325 / 223 |
  | `f5` | 0030 build | 375 / 488 / 408 / 201 / 82 | 271 / 374 / 302 / 210 |
  | `f6` | measured build (`f3`'s) | 455 / 584 / 532 / 273 / 92 | 349 / 472 / 418 / 286 |
  | `a4` | today's | 106 / 73 / 87 / 65 / 69 | (none) |

  - **The look and the memory are the same as in the A/B:** the first crossfade frames are complete
    (88-90 % of the settled detail at the stages `f1` and `f3` caught), each character's maps are
    staged in one frame, and the idle numbers match (0.266 GB, 6.47-6.50 GB, 15.58-15.59 GB).
  - **The staging was 2-3 times slower than in `f1`-`f3`** for both builds, including `f6`, which runs
    the exact build `f3` measured 1.6 hours earlier; `a4` stayed where `a1`-`a3` were. So the merged build
    is not slower; the machine's state changed. The maps were in the file cache (a mapped read of the
    deployed files ran at 1.27-1.47 GB/s, as warm reads did before), and no other build or game ran
    (`r13-f/cpu.csv`: 14 % mean CPU). What remains is the staging's memory allocation: each texture's
    whole chain gets a new host-visible buffer, which Windows backs with zeroed pages. At the time 9.7 GB
    was on the free list, 21.9 GB on standby and 49.3 GB committed. That cause is likely but not proven.
    Right before `f4` and `f5` the lab force-ended a field game another session (R14's check) had just
    started (3 and 1 processes; `holds/f4/field-games.json`); `f6` and `a4` found none. That game's run
    and end may have left the machine in this state. The lab no longer ends field games: it waits.
  - **So on this computer the frame that first draws a character takes 0.11-0.58 s**, against 0.04-0.11 s
    today, depending on the machine's state as well as the character. A persistent staging pool for these
    loads would take the allocation out of that frame (not built; with the options in section 5).
