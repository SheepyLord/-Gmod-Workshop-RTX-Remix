# R13-P: can character PBR maps stream instead of preloading? (report)

Status: **done, generators unchanged**: streaming shows a visible difference (Claude, 2026-11-03).
Brief: the R13 open item "Preloaded Remix mods" ([R13 report](R13-report.md#open-items-and-follow-ups),
[R13-B report](R13-B-report.md) sections 4 and 5). Decision record:
[ADR 0102](../decisions/0102-character-pbr-maps-stay-preloaded.md). Branch `r13-preload` (documents
only). Evidence and lab: `out/worktrees/r13-preload/out/r13-p/` (git-ignored; below `r13-p/`).

## In short

- **Memory.** On the PoC, streaming the four test characters' maps held **2.23 GB less** of
  replacement textures at idle (2.66 to 0.43 GB), 1.64-1.71 GB less driver VRAM and 1.70 GB less
  private bytes. The working set was unchanged. In the field the same flag holds 11.05 GB of files.
- **The settled image is the same.** Final images and debug views 25, 16 and 94 differ between the
  variants about as much as between two sessions of one variant (at or below in 20 of 23 views, the
  rest by edges only). Fine detail agrees within 1.1 %.
- **Streaming is visible at every first appearance.** A streamed character appears with its maps'
  smallest mips. The first upgrade lands 2-5 frames after the first draw and the last 155-880 ms
  (10-50 frames) after it, on an NVMe drive with the files cached; a slower disk takes longer.
  At full resolution Robin's treble-clef emblem is a flat grey shape when she appears, and her bodice is
  still smeared at +138 ms. Preloaded, she is complete in her first frame.
- **Removal drops the maps at once** (1.39 GB within about 105 ms), so a respawn pops in again
  (155-158 ms). A cut to a close-up streams more mips for 0.19-0.32 s, but the films show no
  difference there beyond the cut's own one-frame smear, which preloaded sessions have too.
- So, as the brief says for a visible difference, I stopped there: rpai, ToPBR and the user's mods are
  unchanged. Two ways to the memory without a visible change are in section 5 for the user to decide:
  a runtime patch that loads a preload on its first draw instead of at mod start, and removing the
  field's duplicate mods (1.16 GB is a byte-identical copy).

## 1. How Remix streams a replacement texture (brief item 1)

Runtime source `out/worktrees/r12-vram/out/runtime-src` at `403b2336` (patches up to 0028).

- **The flag.** `inputs:preload_textures` is read per shader (`rtx_mod_usd.cpp:697`, `:733-736`) and
  passed to `preloadTextureAsset` as `forceLoad` (`:759`, `:678`). With it the texture is pinned
  (`m_canDemote = false`) and every mip is loaded synchronously when the mod loads
  (`rtx_texture_manager.cpp:1888-1894`). Without it the texture starts at its smallest mips: one is
  requested, and the DDS loaders upload at least the five-mip tail, 16x16 down to 1x1 for a 4096 map
  (`kMipLevelsToCache`, `rtx_asset_data_manager.cpp:35`, `:354`; `clampMipCountToAvailable`,
  `rtx_texture.cpp:164-178`).
- **Sampler feedback.** Only the primary and mirror (PSR) passes write it
  (`RAY_TRACING_PRIMARY_RAY`, `opaque_surface_material_interaction.slangh:727-740`). Each pixel writes
  the mip level it needs, measured against a fixed 4096 texture, to its material's stamp with an atomic
  minimum (`:443-467`). A material's stamp is that of its **first replaced texture** in the order
  albedo, roughness, metallic, secondary, normal, tangent, height, emissive. The others are associated
  with it, at most 8 per stamp (`rtx_scene_manager.cpp:1824-1841`, `:2215-2229`).
- **From feedback to mips.** The host reads the previous frame's buffer (`copySamplerFeedbackToHost`,
  `rtx_texture_manager.cpp:1448-1474`). The needed count is the stamp owner's mip count minus the level
  read, copied to the associated textures (`fetchNoisyMipCounts`, `:1500-1561`). Each texture keeps the
  largest count seen; it is reset only after budget pressure (`accumulateMipCounts`, `:1563-1588`).
  `garbageCollection` (`:1590-1746`) requests that count for every texture an instance holds, best
  first, within the budget. **A texture no instance holds drops to its tail at once** (`:1676-1682`).
  - Because the count is relative to the owner's own mip count, an owner smaller than 4096 asks for one
    level less than the screen needs per halving (2048: one, 1024: two). In `ai_pbr` 29 of 219
    materials have such an owner. The settled A/B, which includes 9 of them, showed no measurable loss
    in close-ups or the lineup at 3840x2160.
- **Loading.** One lowest-priority thread reads each requested mip range from the memory-mapped DDS
  into a 96 MiB staging ring (`stagingBufferSizeMiB`), at most 32 uploads per frame. The render thread
  copies them in at the next frame's `submitTexturesToDeviceLocal` (`:472-706`, `:1051-1085`).
  A texture whose whole chain does not fit the ring is loaded whole and pinned
  (`WAR_doesAssetFitIntoFixedAllocator`, `:1822-1840`, `:1880-1885`).
- **Does a drawn streamed texture reach its full chain, and how fast?** Yes, to what the screen needs.
  The first upgrade needs the feedback round trip, two to five frames, and the rest arrives as the
  thread reads it: 251-464 MB per character in 0.15-0.88 s here (section 3). Off-screen instances are
  kept by anti-culling (`rtx.antiCulling.object.enable`, `classic_remix_defaults.conf:98`), so turning
  away loses nothing.
- **ToPBR's reason** ("generated normals have no replacement stamp to inherit", fixes
  `to_pbr/usda.cpp:350-357`) does not hold on this runtime: a game-albedo material's stamp comes from its
  roughness, metallic or normal map. 19 of the 64 test materials have that shape (normal and roughness,
  some metallic, no albedo) and streamed to the same settled look.

## 2. The A/B (brief item 2)

- **Variants.** A preloads, B streams. Both are the three Workshop character packs (Robin RTX,
  Guinaifen RTX, Evernight & March 7th RTX) as local dev packages with their own ids. They are rpai's
  output, the same files as `ai_pbr`'s folders for these characters. B differs only in the 64 removed
  `bool inputs:preload_textures = 1` lines (`r13-p/make_packs.py`; both manifests validate with
  `nlctl`). Same runtime and package for all: the published `0.0.0-dev.20261103172411+a911b59a`, pinned
  as a copy.
- **Scene.** The PoC with the copied field library (`out/r13/field-cache`, swapped in as R13-B did), on
  gm_flatgrass at 3840x2160, high tier, ReShade off. GMod picked another spawn point in `a1` than in
  `b1`, so from `a2` on the player is placed at `b1`'s (640, -192). Characters are spawned frozen
  through the library's own route at fixed aims, so `b1` to `b3` put them at the same coordinates.
- **Probe** (`r13-p/r13p_probe.lua`) and driver (`r13-p/lab.py`, which runs `tools/poc_session.py`):
  - idle;
  - first draw of Robin and Guinaifen in a close-up (filmed);
  - Evernight and March 7th first drawn small in a wide view;
  - the lineup;
  - a cut to each of their close-ups (filmed);
  - 12 s looking away, and back (filmed);
  - everything removed, then Robin again (filmed).
- **Measured.** Each settled view has screenshots of the final image and debug views 25 (roughness), 16
  (shading normals) and 94 (base reflectivity). Remix's replacement-texture bytes are read every frame
  around each event (`RemixResource.GetVramStats`). The driver films the window between the probe's
  marks, and a RAM sampler runs every second. `tools/qa/memory_report.py` runs on each session.
- **Sessions** (all quit normally, no Lua error, PoC restored exactly):

  | Hold | Variant | Films | Note |
  |---|---|---|---|
  | `a1` | A | aimed wrong | another spawn point; settled shots and memory only |
  | `b1`, `a2` | B, A | top-left quarter, half size | the lab process was not DPI-aware |
  | `b2` | B | full frame, half size | |
  | `a3`, `b3` | A, B | full frame, half size, plus the middle third at full size | the decisive pair |

## 3. Results

### Memory (GB; `r13-p/compare/summary-all.json`)

| | A (`a1`, `a2`, `a3`) | B (`b1`, `b2`, `b3`) | B - A |
|---|---|---|---|
| Replacement textures, idle | 2.657 | 0.427 | **-2.23** |
| Driver VRAM, idle | 8.155-8.189 | 6.477-6.545 | -1.64 to -1.71 |
| Private bytes, idle | 17.27-17.30 | 15.58-15.60 | **-1.70** |
| Working set, idle | 9.09-9.23 | 9.06-9.09 | none |
| Replacement textures, four characters drawn | 2.657 | 1.607-1.610 | -1.05 |
| Driver VRAM / private bytes, four drawn | 10.17-10.21 / 22.39-22.51 | 9.50-9.57 / 21.81-21.82 | -0.6 to -0.7 each |
| Peak private bytes | 23.45-23.54 | 22.56-22.91 | -0.6 to -0.9 |
| Seconds to the map | 19.7-22.7 | 18.7-23.7 | none at 2.4 GB of preloads |

With all four characters drawn, B still holds 1.05 GB less: the maps of parts never seen stay at their
tails. In the field the flag holds 11.05 GB of files at every start (`ai_pbr` 8.50 GB, the three
`pbr_*` mods 2.22 GB).

### Transitions (B; A had no change in any track; `r13-p/compare/tracks-table.json`)

Time after the character is first drawn (the hotloader's presentation) to the first and last change of
Remix's replacement-texture bytes, in `b1` / `b2` / `b3`:

| Event | First upgrade | Last upgrade | Loaded |
|---|---|---|---|
| Robin, first draw, close-up | 105 / 191 / 188 ms (3 frames) | 450 / 349 / 304 ms (19 / 13 / 10) | 251 MB |
| Guinaifen, first draw, close-up | 156 / 99 / 98 ms (3) | 419 / 396 / 395 ms (19 / 21 / 21) | 464 MB |
| Evernight, first draw, wide | 142 / 142 / 138 ms (3) | 252 / 352 / 313 ms (10 / 16 / 14) | 202-205 MB |
| March 7th, first draw, wide | 82 / 78 / 47 ms (2-4) | 879 / 542 / 832 ms (50 / 30 / 48) | 257 MB |
| Cut from wide to Evernight's close-up | 53 / 70 / 55 ms (4-5) | 212 / 320 / 188 ms (12-20) | 206-209 MB |
| Cut to March 7th's close-up | none | none | 0 |
| 12 s turned away, and back | none | none | 0 |
| Everything removed | 54-56 ms | 103-106 ms | -1,390 MB |
| Robin again after removal | 21-23 ms (2) | 155-158 ms (10) | 257 MB |

The files were in Windows' file cache (an A session had just read them) on an NVMe drive. A cold start
reads them from the disk first: at 0.5 GB/s (SATA SSD) Robin's 251 MB alone adds about half a second.

**What it looks like** (`r13-p/preview/`, built by `pair.py` from the films and aligned on the first
frame of the hotloader's crossfade or on the cut):

- `detail-a3-b3-first-robin-early.jpg` (full resolution, A above, B below):
  - **+0 ms:** A's emblem, star brooch and trims are complete under the dark stand-in; B's treble clef
    is a flat grey shape and the bodice plain.
  - **+138 ms:** A shows the crossfade's stripe over a complete costume; B's bodice is still a smear.
  - **+260 ms:** they match.
- `crossfade-emblem-a3-b2-b3.jpg` (half size, three sessions): at +0 ms both streamed sessions show
  the treble clef as a flat grey outline without the brooch, the preloaded one shows it complete. At
  +120-138 ms the emblem has its colours and B's bodice is still smeared. From +239-278 ms all three
  match.
- `detail-a3-b3-first-robin.jpg`: from +260 ms on, A and B are the same.
- `detail-a3-b3-approach-evernight.jpg`: after the cut to Evernight's close-up, B matches A from
  +111 ms. The frame at the cut itself is a smear in `b1`, `b3` and also the preloaded `a1`, and clean in
  `a2`, `a3` and `b2` (`cut-frame-a1-a2-b1.jpg`, `cut-frame-a3-b2-b3.jpg`). It is the renderer's own
  transient after a cut, caught or missed by the capture's timing, not streaming.
- `b2-first-robin-sheet.jpg` and `pair-a3-b2-first-robin.jpg`: the first appearance at whole-frame scale.

### Settled image (`r13-p/compare/pairs-stats.json`, `pairs_stats.py`)

The five sessions at the same spot give 6 pairs across the variants (A2, A3 against B1, B2, B3) and 4
within one. The difference is the mean over the middle of the frame of each pixel's largest channel
difference (0-255). Fine detail is the mean absolute Laplacian of the luminance there.

| View | A-B, mean of 6 | Within, mean of 4 | Fine detail, B against A |
|---|---:|---:|---:|
| Robin, final | 1.74 | 1.98 | +0.01 % |
| Robin, roughness (25) | 1.13 | 1.22 | -0.22 % |
| Robin, shading normals (16) | 2.99 | 4.06 | -0.01 % |
| Robin, base reflectivity (94) | 0.60 | 0.64 | -0.13 % |
| Guinaifen, shading normals | 4.75 | 6.13 | -0.03 % |
| Evernight, roughness | 0.78 | 0.55 | +0.01 % |
| Evernight, shading normals | 4.44 | 3.76 | +0.01 % |
| March 7th, final | 2.70 | 3.18 | -0.44 % |
| Lineup, final | 1.19 | 1.27 | -0.59 % |
| Idle, no character | 1.05 | 1.20 | +0.12 % |

- In 20 of the 23 views the A-B mean is at or below the mean within one variant.
- The three above it are Evernight's normals (+0.68), Evernight's roughness (+0.23) and the lineup's
  base reflectivity (+0.06). Their difference images are all edges, as are those within A
  (`preview/evernight-roughness-a3-b2-diffs.jpg`, `a2-vs-b2-ctl-a3/close-robin-normals.jpg`): run-to-run
  sub-pixel jitter. Lower texture resolution would show inside surfaces.
- Fine detail differs by -0.6 to +1.1 %, with no consistent sign.

## 4. Decision (brief items 3 and 5)

The user's rule for R13 was "visible quality unchanged". Streaming changes what a player sees whenever
a character appears or reappears, for 0.15-0.9 s on this computer and longer on slower disks. So, as
the brief asks, I stopped:

- rpai (`usda.py:61`) and ToPBR (`usda.cpp:350-357`) keep `preload_textures = 1`;
- no fixes build or import;
- the user's `ai_pbr` and `pbr_*` mods are untouched;
- no migration is proposed for the flag;
- [ADR 0102](../decisions/0102-character-pbr-maps-stay-preloaded.md) records why.

## 5. For the user to decide

1. **Load a preload on its first draw** (runtime; the memory without the look changing). A material
   with the flag would not load at mod start; the frame that first draws it would load every mip before
   rendering, and it would then stay pinned as today, with 0026's pressure rule unchanged. The
   synchronous path exists: `addTexture` already reloads a purged preload that way
   (`rtx_texture_manager.cpp:1111-1125`).
   - Gain: in the field, the start-up VRAM and commit of every character not spawned, most of 11 GB.
   - Cost: a hitch at a character's first draw in a session, in place of the start-up load. That is
     about 0.1-0.3 s for 0.3-0.85 GB from the file cache or an NVMe drive, and seconds from a hard disk.
     It is an estimate to measure with this lab before deciding.
   - No content changes: rpai, ToPBR and the editor keep the flag, and the user's mods need no
     migration.
2. **The field's duplicate mods** (`r13-p/duplicates.json`, read only). Remix keys replacement textures by
   path, so the same files under two mods load twice. For a material two mods both define, the first mod
   in folder-name order wins (`rtx_asset_replacer.cpp:110-121`, mods sorted by
   `rtx_mod_manager.h:130-140`), so `ai_pbr`'s materials render.
   - **Evernight and March 7th:** 76 maps and both layers byte-identical, 1.16 GB loaded twice.
     `rpai remove <their .pmx>` (`ai_pbr` is rpai's default mod) drops `ai_pbr`'s copies, after which
     the Workshop pack's identical ones render: **no visible change**.
   - **Robin and Guinaifen:** 74 maps identical (1.06 GB), but the Workshop packs' layers are newer:
     `emissive_adaptive_intensity = 15` on 5 emissive materials, and two Guinaifen materials `ai_pbr`
     lacks. Today `ai_pbr`'s older layers render the shared materials. Removing `ai_pbr`'s copies would
     show the packs' look (a visible, probably intended, change); keeping both costs 1.06 GB.
   - Unsubscribing from a pack instead would also remove its Model Hotloader add-on; not examined.

## 6. Evidence and how to rerun

- `r13-p/holds/<hold>/`:
  - `case.json`; `results.json` (the probe's phases, tracks and spawns); `ram.csv`;
  - `bursts/<event>/` (the films, with `index.json`);
  - `session-record.json`, `restoration.json`, `memory-report.json`, `telemetry/`.
- `r13-p/sessions/<hold>/`: console, Remix log and screenshots.
- `r13-p/compare/`: `summary-all.json`, `tracks-table.json`, and per pair the `A | B | |A-B| x4` sheets
  with `compare.json`.
- `r13-p/preview/`: the strips named above.
- Tools, in `r13-p/`:
  - `make_packs.py`: the B packs;
  - `lab.py <hold> --variant A|B`: a hold, with the lock, snapshot, swap, session, films and
    restoration;
  - `r13p_probe.lua`: the probe;
  - `analyze.py summary|compare|bursts`; `pairs_stats.py`: every settled view across all A-B and
    within-variant pairs; `events.py`: finds the cut or the appearance in a film;
  - `pair.py`: aligned A/B strips; `sheet.py`: contact sheets; `duplicates.py`: the field check.
- Rerun: `python out/r13-p/lab.py <new-hold> --variant A`, then `--variant B`, from the worktree. Each
  takes about 5 minutes, waits for the PoC lock and restores everything.

## 7. PoC holds

- Lock `out\r10\poc.lock`, task `R13-P`:
  `a1` 18:25:15-18:29:51, `b1` 18:32:07-18:36:55, `a2` 18:37:03-18:41:56, `b2` 18:42:03-18:47:04,
  `a3` 18:47:11-18:52:04, `b3` 18:52:05-18:57:00 UTC.
- No field game was running at any start.
- Each hold snapshotted the PoC's mutable trees (large files as hard links: the loader only creates new
  files and renames over old ones; small files copied with their SHA-256). It swapped in the library
  copy and wrote its own `config.json`. Afterwards it restored all 3,633 files exactly, put the PoC's
  own library back with an identical listing, checked `user.conf` and the video settings, and checked
  the shared field-cache's sizes.
- Every session ended through `poc_session.py`, so the field's own `config.cfg` reached Steam Cloud
  (`settings_back: restored`).
- R14-H took the lock 27 s after `b3`. The `_199` package folder in the PoC is that session's, from
  before `a1`.

## 8. Not done, or open

- **Cold-cache timing:** not measured; Windows' file cache was warm in every B session.
- **Albedo-only preload:** not measured (ADR 0102's alternatives).
- **The first-draw runtime variant** (section 5.1): not built. This lab is ready to measure its hitch
  and to show that its first frames match A.
- **The one-frame smear right after a camera cut** happens with either variant (section 3); its cause
  in the renderer was not looked into.
- **ToPBR's source comment** keeps its outdated reason; correcting it needs a fixes commit, which no
  change here justified.
