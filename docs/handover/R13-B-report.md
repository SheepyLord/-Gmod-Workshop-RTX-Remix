# R13-B: the runtime's memory (report)

Status: done (Claude subagent, 2026-11-03), with the review's fixes (patch 0028, section 11). Branch
`r13-runtime`; runtime source
`out/worktrees/r12-vram/out/runtime-src`, branch `claude/r13-runtime`. Decision record:
[ADR 0100](../decisions/0100-one-copy-and-idle-release-of-game-textures.md). Evidence and scratch
tools: `out/worktrees/r13-runtime/out/r13-b/` (below, `r13-b/`).

## In short

- **Account.** The field's 17.3 GB of read-write committed memory is DXVK's host-cached memory type,
  almost all of it the CPU copies of managed game textures (`d3d9 texture copy`), plus about 2.6 GB of
  the game's own heaps. Its 11.0 GB of write-combined memory is not DXVK's: the NVIDIA driver maps the
  process's VRAM into its address space as committed write-combined memory, so it is the game's VRAM
  in use, which therefore also holds system commit.
- **Six runtime patches**, 0023-0028: the host census; one copy and idle-image release for game
  textures (automatic for gmod.exe); replacement textures within the driver's live budget; undrawn
  preloaded textures giving way under the same pressure; counters of what creates game texture images;
  and the fixes an independent review found (a hash race, the terrain baker's sources, unmarked writes,
  the pass in other games).
- **The lag trigger, on the new runtime** (R13-A's `item_ammo_ar2_altfire` precache, made by a plain
  Combine soldier): game textures jump 0.96 -> 17.08 GB as before, and come back to the managed budget
  75 seconds after the trigger with this computer's automatic budget (8.58 GB) and about two minutes
  after it with the minimum profile's 2 GiB (2.34 GB), where the original runtime keeps all 17.08 GB.
  Private bytes fall with them (43.69 -> 35.22 GB, or 27-30 GB on the minimum profile, against
  43.69-44.12 GB kept by the original).
  The driver stayed within its budget throughout. The burst's images are all made by draws
  (`PrepareTextures`), none by `PreLoad`, views, flushes or mip generation. Section 2.
- **The lag report's 10.3 GB of replacement textures were preloads.** rpai, ToPBR and the material
  editor set `preload_textures`, which pins every map at every mip from the moment the mod loads, drawn
  or not; no budget touches them. The field's mods preload 11.05 GB of files (10,537 MiB, against the
  report's 10,320 MiB), 2.22 GB of it the same character files loaded twice from two mods. Patch 0026
  lets the undrawn ones go under pressure; a test-budget session shows 87 of them released in one
  pass, which brought the process back under its budget. Section 4.
- **The main session's preload questions:** they did not give way under 0025 (pinned); 0026 is the
  small change. Section 5.
- **Hashes and visuals:** the fixes' draw tracker reported the same 74 texture hashes for the spawned
  characters before release, after re-upload and on the original runtime; the GPU probe's pixels and
  hashes are identical in every variant.

## 1. The account (brief item 1)

Patch 0023 extends the opt-in census (`rtx.profiler.memory.requestSnapshot`, patch 0021) with
`[RTX Host Memory]` rows: per memory type the chunks and dedicated allocations with their used bytes;
each host-visible memory object's address range; the process counters; and the committed private
address space by protection, with the part DXVK's own mappings cover. Allocation groups carry the
memory flags they received, whether the application released the image while Remix still holds it,
and the allocation's name (texture copies are now named `d3d9 texture copy`).
[`tools/qa/host_memory_census.py`](../../tools/qa/host_memory_census.py.md) turns a session log into an
account.

This machine's memory types: heap 0 (VRAM) type 1 `DEVICE_LOCAL` and type 4
`DEVICE_LOCAL|HOST_VISIBLE|HOST_COHERENT` (resizable BAR); heap 1 (system) type 2
`HOST_VISIBLE|HOST_COHERENT` (write-combined) and type 3 `HOST_VISIBLE|HOST_COHERENT|HOST_CACHED`
(read-write). DXVK takes device-local memory in 320 MiB chunks and the others in 128 MiB chunks; a
request of a chunk or more gets its own memory object.

**PoC at idle** (gm_construct, 1920x1080, the copied field library, no Workshop add-ons, nothing
spawned; `r13-b/holds/a2-min-1080/account.json`, frame 1893):

| Part | Bytes | What |
|---|---|---|
| Private bytes | 27.07 GB | working set 20.50 GB |
| Read-write committed | 19.87 GB | |
| - DXVK type 3 (host-cached) | 17.27 GB | 98 chunks (13.15 GB, 12.55 GB used) and 16 dedicated (4.11 GB) |
| -- texture CPU copies | 16.41 GB | 8,135 buffers: the managed textures of every library character, created at load; patch 0022 gave their images memory only on use |
| -- staging and Remix uploads | 0.25 GB | `RtxStagingDataAlloc: D3D9` 100.7 MB, `RtxStagingRing` 100.7 MB, geometry 33.6 MB, D3D9 staging 4.8 MB |
| - not DXVK's | 2.60 GB | the game's heaps (Source, Lua, the hotloader, CEF) |
| Write-combined committed | 6.84 GB | |
| - DXVK's own mappings | 0.87 GB | type 2 staging chunks (0.54 GB, 14 MB used) and the type 4 chunk (0.34 GB) |
| - not DXVK's | 5.96 GB | the driver's mapping of VRAM in use (driver usage 6.27 GB) |
| VRAM | 6.27 GB | replacement textures 2.43 GB in 691 images (2.66 GB by Remix's count), game textures 0.67 GB |

The GPU probe isolates the two effects: releasing four 89.5 MB images lowered write-combined commit
and private bytes by 358 MB with read-write unchanged; releasing their CPU copies lowered read-write
commit by 402 MB (`r13-b/probe-final/summary.json`). The sessions below show the same at scale: the
17.08 GB burst raised write-combined commit by 15.36 GB (7.41 -> 22.77 GB).

**The field's idle census** (`out/r13/field/vm-idle.json`: 28.36 GB private, 17.33 GB read-write,
11.02 GB write-combined, largest blocks 697.4, 521.8, 391.4, 335.5, five of 268.4 and many 134.2 MB)
reads the same way: read-write is the CPU copies of the library's textures plus the game's heaps;
write-combined is the VRAM in use (at 4K, with 10.3 GB of preloaded replacement textures) plus DXVK's
staging. 134.2 MB is a 128 MiB chunk, 335.5 MB a 320 MiB device-local chunk mapped by the driver,
268.4 MB the dedicated mip 0 of an 8192-square A8R8G8B8 texture's copy, 391.4 MB the 11059x8847 one.

## 2. The lag trigger on the new runtime (the main session's acceptance test)

R13-A found the trigger: the first `item_ammo_ar2_altfire` precache of a session, which every
`npc_combine_s` makes. The sessions spawn a plain Combine soldier (`gmod_spawnnpc npc_combine_s`, AI
off, everything removed 15 s later) after two library characters were spawned and removed, wait 180 s,
then spawn the characters again. PoC, 1920x1080, the copied field library, the current package with
only `d3d9.dll` changed (`r13-b/lab.py`, `r13-b/r13b_probe.lua`).

| GB | idle | characters | removed | **triggered** | **+180 s** | characters again |
|---|---:|---:|---:|---:|---:|---:|
| **Original runtime** (`b3-orig-1080`) | | | | | | |
| game textures (`usedAppTextureBytes`) | 0.29 | 0.96 | 0.96 | **17.08** | **17.08** | 17.08 |
| private bytes | 26.95 | 27.98 | 28.27 | **43.69** | **43.69** | 44.12 |
| driver usage / budget | 5.91 / 32.95 | 6.50 | 6.84 | 22.20 | 22.20 | 22.57 |
| **New, this computer's defaults** (`r1-default-1080`: CPU copies kept, budget auto 8,046 MiB) | | | | | | |
| game textures | 0.29 | 0.96 | 0.96 | **17.08** | **8.58** | 8.58 |
| private bytes | 26.93 | 28.19 | 28.27 | **43.69** | **35.22** | 35.65 |
| write-combined / read-write | 6.47 / 20.09 | 7.28 / 20.54 | 7.41 / 20.49 | 22.77 / 20.52 | 14.32 / 20.52 | 14.70 / 20.57 |
| driver usage / budget | 5.91 / 32.95 | 6.50 | 6.84 | 22.20 | 13.75 | 14.12 |
| **New, the minimum profile's values** (`b5-min-1080`: CPU copies released, budget 2,048 MiB) | | | | | | |
| game textures | 0.29 | 0.96 | 0.96 | **17.08** | **2.34** | 2.34 |
| private bytes | 26.95 | 28.22 | 28.51 | **27.35** | **30.08** | 29.58 |
| write-combined / read-write | 6.47 / 20.11 | 7.28 / 20.57 | 7.62 / 20.52 | 22.77 / 4.21 | 11.32 / 18.39 | 10.77 / 18.44 |
| texture CPU copies | 16.79 | 16.14 | 16.14 | 0.04 | 14.76 | 14.76 |
| driver usage / budget | 5.91 / 32.95 | 6.71 | 7.05 | 22.20 | 10.75 | 10.20 |

- **Does `usedAppTextureBytes` come back under the managed budget once the idle time passes?** Yes.
  With the automatic budget the runtime released 63 images (8.50 GB; least recently used first, the
  largest first among equals) between 60 and 75 seconds after the trigger: 17.08 -> 8.58 GB, of which
  8.37 GB in the managed class against its 8.44 GB budget (the rest are textures outside the class).
  With the minimum profile's values (copies released, 2 GiB), the copies of all 1,323 resident
  textures were gone 16 seconds after the burst (16.85 GB, 10 seconds after their upload; the working
  set fell to 4.96 GB), then from 61 seconds the idle images were read back and released, about 4 GB
  per 15 seconds: 1,115 images (14.74 GB) by 122 seconds, 2.13 GB resident against a 2.0 GiB budget
  (`[RTX Managed Textures]` lines in each session's `remix-dxvk.log`). The original runtime kept all
  17.08 GB.
- **Do private bytes come down too?** Yes, by the released images: 43.69 -> 35.22 GB with the
  defaults, because the driver maps VRAM as committed write-combined memory (22.77 -> 14.32 GB). On the
  minimum profile the burst moved the data instead of doubling it: private bytes stayed at 27-30 GB
  (copies freed while the images held the data, read back as the images went).
  - What remains above the level before the trigger is DXVK's chunk space: the burst's smaller
    textures were sub-allocated in 320 MiB device-local chunks, and a chunk is freed only when empty.
    After the minimum profile's release the chunks held 9.14 GB with 5.32 GB used (driver 10.75 GB
    against 7.05 GB before the trigger); new textures reuse that space. With the defaults the released
    images were the large dedicated ones (11.99 -> 3.54 GB dedicated), so nothing was stranded.
- **Does the driver stay within its budget?** On this 32 GB card, yes, in every session: 22.20 GB at
  the burst at 1920x1080, 24.80-25.27 GB at 3840x2160 (`a4-min-4k`, `q3-final-trigger`), against
  32.2-32.95 GB. On a smaller card the same burst exceeds VRAM until the release; with R13-A's loading
  on first use the burst itself is 1.9-5.3 GB.
- **At 3840x2160** with the minimum profile's values (`a4-min-4k`) the same happened: game textures
  17.70 -> 2.86 GB, driver 24.80 -> 13.22 GB, private bytes 29.84 -> 32.56 GB (the copies came back as
  the images went), the same 74 hashes as the original runtime.
- **Re-upload:** the characters spawned again after the release re-created their images (4 re-uploads
  with the defaults, 27-28 on the minimum profile) with the same hashes: the fixes' draw tracker
  (`RemixMaterial.GetAllTextureHashes`) reported the same 74 materials and hashes before the release,
  after it, and on the original runtime (`python r13-b/analyze.py hashes b3-orig-1080 b5-min-1080
  r1-default-1080 a4-min-4k`).
- **What the engine calls.** Patch 0027 counts what created each image. Every image of the burst was
  created by the draw path: 1,128 images at the trigger, all `draw` (`UploadManagedTextures`
  from `PrepareTextures`, the upload of a texture bound to a sampler the draw's shaders use, from a
  D3D9 draw or Remix's draw processing), none by `PreLoad`, a sampling view, a flushed upload or mip
  generation (`r1-default-1080`: 1,101 -> 2,229 `draw`, every other cause 0). So the precache makes
  Source issue a draw with each loaded texture bound, about 1,100 draws (R13-A saw the jump within one
  frame). The same happens once while the map loads: 1,064 images (16.91 GB) made by draws
  before the first presented seconds, whose textures Source then destroys and loads again (the
  start-up peak of 40.7 GB private bytes, section 6). The engine was not changed.

## 3. What changed

| Patch | Runtime commit | What |
|---|---|---|
| `0023-Log-host-memory-by-memory-type-mapping-and-purpose-i.patch` | `24d8b928` | The host census above |
| `0024-Keep-one-copy-of-managed-GMod-textures-and-release-i.patch` | `ce35c9e6` | One copy, idle images released over a budget (static managed 2D textures, patch 0022's class) |
| `0025-Let-replacement-textures-give-way-under-real-VRAM-pr.patch` | `d48b7bec` | The replacement budget capped from the driver's live numbers under real pressure |
| `0026-Let-undrawn-preloaded-material-textures-give-way-und.patch` | `68e92970` | Undrawn preloaded material textures give way under the same pressure; streamed textures get the limit less what pinned ones hold; a test budget |
| `0027-Count-what-creates-deferred-managed-GMod-texture-ima.patch` | `d0a60c1e` | Counters of what creates each game texture image |
| `0028-Fix-a-hash-race-baker-sources-and-unmarked-writes-of.patch` | `403b2336` | The review's fixes (section 11) |

`runtime/README.md` describes them; `runtime/base.json` records the import; the runtime part holds the
new `d3d9.dll` (one import). Unit tests: `test_managed_texture_memory`,
`test_texture_budget_pressure`.

### The options (0024)

| Option | Environment | gmod.exe default | Other games |
|---|---|---|---|
| `d3d9.releaseManagedHostCopies` | `DXVK_RELEASE_MANAGED_HOST_COPIES` | Auto: on below 28 GiB of RAM or 15 GiB of VRAM | False |
| `d3d9.managedTextureBudgetMiB` | `DXVK_MANAGED_TEXTURE_BUDGET_MIB` | -1: a quarter of the VRAM (largest device-local heap) | 0 (off) |
| `d3d9.managedHostCopyIdleSeconds` | `DXVK_MANAGED_HOST_COPY_IDLE_SECONDS` | 10 | 10 |
| `d3d9.managedTextureIdleSeconds` | `DXVK_MANAGED_TEXTURE_IDLE_SECONDS` | 60 | 60 |

Explicit values win (the loader's memory layer, R13-C); the environment wins over files. At startup
the runtime logs what it resolved, for example
`[RTX Managed Textures] budget: 8046 MiB (auto: VRAM/4); VRAM 32187 MiB` and
`[RTX Managed Textures] release host copies: off (auto: RAM 63116 MiB, VRAM 32187 MiB; on below 28 GiB RAM or 15 GiB VRAM)`.

- **One copy.** Once a texture's image holds its data and the game has not locked it for 10 presented
  seconds, the CPU copy is freed. A later lock reads the subresource back from the GPU first, exactly
  as DXVK's `evictManagedOnUnlock` path does. Textures that use `AddDirtyRect` keep their copy.
- **Idle images.** Once a second, while these textures' images hold more than the budget, those not
  drawn for 60 presented seconds are released, least recently used first, at most 2 GiB of plain
  releases and 256 MiB of read-backs per pass. Bound, locked and pending textures are never chosen. A
  texture whose copy was freed is read back asynchronously first and released in a later pass if
  nothing used it meanwhile. Every subresource is marked for upload, so the next use creates the image
  again through patch 0022's path.
- **Identity.** The texture keeps its Remix hash while released: `dxvk_GetTextureHash`, the
  hash-on-write rule (`rtx.recomputeTextureHashOnWrite`) and the re-created image all see it. A
  rewrite while released clears it, so the re-upload hashes the new data, as before.
- **Remix's reference** (the brief's "verify that"). The released image is marked
  application-released, so Remix's texture cache frees its slot once no bound instance samples it
  (`releaseApplicationReleasedTextures`); until then the image stays alive and correct and its memory
  goes when Remix lets go. The census reports such images (`released_images_still_held`); it was 0 at
  every census of the sessions above, so Remix had let go of every released image by then.
- **Why 60 seconds:** images go only while the class holds more than a quarter of the VRAM, and a
  minute without a draw covers turning around, menus and short trips, so ordinary play does not
  re-upload; the lag report's burst returns within about 75 seconds.

## 4. Replacement textures (brief item 5)

**How Remix sizes the budget.** `rtx.texturemanager.budgetPercentageOfAvailableVram` (50 %) of the
free VRAM plus what replacement textures hold now, the free VRAM being the device-local heap's driver
budget minus the process's usage; or `rtx.texturemanager.fixedBudgetMiB` when `fixedBudgetEnable` (the
Remix menu's Texture Streaming section sets either, saved in `user.conf`). It is recomputed in every
frame's garbage collection, so the percentage follows the driver's live budget; a fixed budget does not.
Bound textures get the mips sampler feedback asks for, best first, while they fit; the rest drop to
their smallest mip.

**What it never touched.** Textures whose material sets `preload_textures` are pinned: created when the
mod loads, before anything is drawn, with every mip requested; `requestMips` forces every mip while
`m_canDemote` is false, and the budget pass and `manageBudgetWithPriority` skip them. They stay for the
session, also after a USD reload leaves no material referencing them; only the explicit purge (the
fixes' `rtx_flush_textures`, and their map-exit purge) drops their images, which then come back only
when drawn. Who sets the flag: rpai on every material
(`skills/mmd-remix-pbr/tool/rpai/usda.py:61`), the material editor by default, the fixes' ToPBR for
game maps, `gm_poolrooms_rtx`, `rtx_water`, `blood_overhaul_rtx`.

The field's mods, read-only (`r13-b/preload_survey.py`, `r13-b/preload-field.json`):

| Mod | Preloading shaders | Files | Bytes |
|---|---|---|---|
| `ai_pbr` | 219 | 542 | 8,496,386,704 |
| `pbr_evernight_march7th` | 29 | 76 | 1,162,840,352 |
| `pbr_guinaifen` | 18 | 44 | 671,145,736 |
| `pbr_robin` | 17 | 30 | 386,037,296 |
| `blood_overhaul_rtx` | 182 | 177 | 171,647,308 |
| `gm_poolrooms_rtx` | 15 | 16 | 149,599,544 |
| `rtx_water` | 18 | 4 | 11,196,432 |
| **Total** | | 889 | **11,048,853,372** (10,537 MiB) |

The lag report's replacement textures were 10,320 MiB, so the field's replacement texture memory is
its preloads, held from every start whether a character is spawned or not. The three `pbr_*` mods'
150 files have the same names and sizes as `ai_pbr`'s folders for those characters; Remix keys
replacement textures by path (`rtx_asset_data_manager.cpp:85`), so it holds both, 2.22 GB twice. The
PoC's mods preload 170 files, 2,380,819,360 bytes; its idle census held 2.43 GB of material textures.

**0025.** Under real pressure the budget is capped from the largest device-local heap's live numbers:
within a margin below the driver's budget (2 %, at least 256 MiB) replacement textures stop growing;
over the budget they give back the overflow plus the margin. With the margin free nothing changes.

**0026.** Under the same pressure, a preloaded material texture that no instance has drawn for 10
seconds gives up its pin and drops to its smallest mip; textures never drawn go at once. When an
instance draws it again it is pinned and loaded whole again, in the background. "Drawn" is Remix's
instance reference count (every texture of a bound material; an instance goes one frame after its
last draw, hence the 10 seconds, so a character the camera turned away from for a moment stays
whole). With free memory nothing changes, and a released preload stays released until drawn (no
reload of gigabytes nobody draws when the pressure ends). Dome lights, textures too large for the
streaming staging buffer and `rtx.texturemanager.neverDowngradeTextures` keep their pin. And because
0025's limit counts all replacement textures but the budget pass can shrink only those that stream,
under pressure the streamed textures now get the limit less what pinned ones hold.
`[RTX Texture Budget]` lines report the regime, both budgets, what pinned textures hold, the driver's
numbers, the demotions and the preloads released and restored.

**In the PoC** (3840x2160, three characters with preloading PBR mods spawned, a fourth, Evernight,
spawned at the end; `[RTX Texture Budget]` lines via `python r13-b/analyze.py budget <session>`):

- **Free memory changes nothing** (`q1-final-default`): the regime stayed `free`, no preload was
  released, replacement textures stayed 2.66 GB, also with 24 GiB held by another process.
- **A VRAM hog does not make real pressure here** (`q1`, `q3-final-trigger`). With 25.8 GB held by
  `vram_pressure.exe` beside the game, WDDM lowered the game's budget only to its own usage (26.15 GB,
  26.14 GB used after the trigger) and paged the hog instead (its own budget fell to 6.9 GB). So patch
  0026 adds a test budget, `DXVK_TEXTURE_PRESSURE_TEST_BUDGET_MIB`, which caps the budget these rules
  see (the driver's own is unchanged; a warning is logged).
- **Under pressure** (`q4-final-testbudget`, test budget 22,000 MiB, otherwise the defaults): the
  trigger took the process to 22,386 MiB, regime `over`, limit 1,707 MiB. In that pass 87 undrawn
  preloads (Evernight's, `gm_poolrooms_rtx`'s, `rtx_water`'s, and maps of the spawned characters that
  none of their drawn materials use) were released; the next line, 150 ms later, shows replacement
  textures 2,533 -> 1,683 MiB and the process back under the budget (21,550 MiB, regime `free`). The
  preloads the spawned characters draw stayed whole. 60 seconds later 0024 released 70 game texture
  images (9.02 GB): driver 25.17 -> 16.63 GB, private bytes 46.62 -> 38.06 GB. Spawning Evernight
  restored her 28 drawn preloads (replacement textures 1.48 -> 1.93 GB).
- No session showed a missing or low-resolution texture on a drawn character.

**`rtx.*` per profile:** none needs to change (ADR 0100's table): the percentage already scales with
the free VRAM, and 0025/0026 act only under the driver's own pressure. The loader should not write the
texture budget, so a player's choice in the Remix menu stays theirs.

## 5. Preloaded textures: the main session's two questions

1. *Do preloaded replacement textures that no material references any more give way under the
   VRAM-pressure rule, or does preload keep them pinned?* With 0025 alone they stayed pinned at every
   mip: `preloadTextureAsset(forceLoad)` sets `m_canDemote = false`, `requestMips` then forces every
   mip, and both lists of the budget pass (and `manageBudgetWithPriority`) take only `m_canDemote`
   textures. `m_assetHashToTextures` and the sampler-feedback table keep them for the session, and no
   path unpins them; a USD reload that drops their material changes nothing. So R13-M's 705,814,528
   startup bytes (and every orphan of a ToPBR rewrite) stayed resident until the game exited, also
   under pressure.
2. *Is there a small, safe change?* Unpinning only once no material references a texture is not small:
   material references are Rc counts, and the asynchronous USD rebuild creates and reuses textures on
   its own thread, so a correct check needs ordering against that worker, plus re-pinning when a new
   material references the texture again. Patch 0026 is the small change that covers it: under
   pressure, a preload that no instance has drawn for 10 seconds gives way (never-drawn ones at once).
   A texture no material references can never be drawn, so every orphan goes, and so do the preloads
   of characters not spawned, which hold most of the memory (`q4` above). The texture manager change
   is about 90 lines, the rules are pure functions in `rtx_texture_budget.h` with unit checks, and
   every pin change happens on the render thread. With free memory it changes nothing, so the orphans
   still occupy VRAM (and, through the driver's mapping, commit) until the game exits or pressure
   comes.

What is still the content side's (the main session's) call:

- **ToPBR** (R13-M): the startup surplus of a previous session's game maps, and orphans with free
  memory, go only if ToPBR stops preloading (or preloads only what it must). ToPBR preloads so that
  generated maps do not stay at their smallest mip, so streaming them needs that checked first.
- **rpai** writes `preload_textures = 1` on every material; `ai_pbr` alone preloads 8.5 GB in the field.
  The skill's own map guidance already says to stream GB-size mods
  (`skills/remix-map-pbr/SKILL.md:234`). Streaming character maps (sampler feedback promotes them when
  drawn) would cut the field's startup VRAM and commit by most of 10 GB.
- **Duplicates:** the field's `pbr_robin`, `pbr_guinaifen` and `pbr_evernight_march7th` hold the same
  2.22 GB as `ai_pbr`'s folders for those characters, loaded twice. That is the user's content; the main
  session may tell them.
- The fixes' `rtx_flush_textures` already drops every resident replacement image (pinned or not);
  drawn ones come back.

## 6. Other large consumers (brief item 6)

- **The CPU copies of characters never drawn** (16.41 GB in the PoC, most of the field's 17.3 GB): the
  hotloader's library creates every character's textures at load; 0022 kept their images off the GPU,
  but their copies are the only copy of the data, so the runtime cannot drop them. R13-A (load on first
  use) removes them. One copy (0024) frees only the copies of textures whose image holds the data.
- **A start-up peak:** private bytes reach 40.7 GB about 35 s after launch, while the map loads, then
  fall to about 10 GB within five seconds and climb back to 27 GB (every session; 5 s samples in
  `r13-b/holds/*/ram.csv`). Patch 0027's counters name it: 1,064 images (16.91 GB) created by draws
  during the load, the same burst as the trigger, after which Source destroys those textures and loads
  them again. On a 32 GB computer that pages during load. R13-A's loading on first use shrinks it; the
  runtime cannot release images faster than Source destroys them here.
- **DXVK's chunk space:** at idle 0.6 GB of the host-cached chunks and 0.8 GB of the device-local
  chunks were unused; after a burst and its release up to 3.8 GB of device-local chunk space (section
  2). DXVK frees a chunk only when it is empty, and new allocations reuse the space. Not changed.
- **Staging** (`RtxStagingDataAlloc`, `RtxStagingRing`, DXVK's staging): about 0.25 GB of fixed-size
  pools. Not bounded further.

## 7. Must keep (brief item 7)

- **Hashes:** the GPU probe's hashes are identical to the original runtime in every variant (upload,
  released copy, read-back lock, rewrite with `rtx.recomputeTextureHashOnWrite`, release and re-upload,
  device reset). In the PoC the fixes' draw tracker reported the same 74 materials' hashes before
  release, after re-upload and on the original runtime (section 2); 67 in `b2-min-1080`.
- **Device reset:** in the probe's sequence.
- **Remix captures:** not run. A capture exports what the captured frame draws; a drawn texture is
  bound, never chosen for release, and a released one is re-created before it is drawn, so a capture
  sees the same data.
- **The fixes' texture tracking:** `RemixMaterial.GetAllTextureHashes` in the sessions (above).
- **Patch 0022:** unchanged; the probe's R12 sequence is identical.
- **Visuals:** the probe's pixels are identical. The sessions' screenshots show the re-uploaded
  characters textured as on the original runtime (`r13-b/cmp-b5-b3-again.jpg`: `b5-min-1080` after its
  release and re-upload above, `b3-orig-1080` below); the scenes are not pixel-comparable (the
  camera and the characters' poses differ between runs).

## 8. Tests and evidence

- `tools\test.ps1 -Config Release` passes on this branch with the import: the repository checks,
  26 CTests and 583 Python tests (28 + 25 + 530; two skipped) (`r13-b/test-release-final.log`, and
  again after the last documentation edits, `r13-b/test-release-final-2.log`).
- Runtime unit tests (`_CompRelease_x64`): `test_managed_texture_memory` and
  `test_texture_budget_pressure` pass.
- The copied field library (`out/r13/field-cache`, read-only; this task's library copy hard-links its
  large files) is unchanged: all 3,113 files (21.19 GB) match their SHA-256
  (`r13-b/field-cache-verify.json`).
- **GPU probe** ([build_managed_texture_probe.ps1](../../tools/qa/build_managed_texture_probe.ps1.md),
  `r13` sequence; runner `r13-b/run_probe.py`): the original runtime (patches 0001-0022, SHA-256
  `e8deaccb...`) against the new one with both options off, CPU copies released, a 1 MiB budget, both,
  and both with the census. Every run: hashes `0x3b0ee339a0e9da94` (first upload, three more textures
  `0x9ea99543...`, `0xc4d971cb...`, `0x0ef79187...`), `0x7d5f528ad278de3a` after the rewrite, the same
  pixels and sampled texel; the R12 `game` sequence `0x93e625c1683421dc` and pixel `1122867`
  everywhere. Copies released: read-write commit -402 MB. Budget: write-combined commit -358 MB, game
  texture VRAM 359 MB -> 1 MB, 90.5 MB uploaded again on reuse. Run on the imported `d3d9.dll`
  (`r13-b/probe-import/summary.json`) and on the earlier builds (`probe-final`, `probe-2`).
- **PoC sessions** (`r13-b/holds/<name>/` with `summary.json`, `ram.csv`, `case.json` naming the
  runtime and its SHA-256; `r13-b/sessions/<name>/` with the console, the runtime log and screenshots):

| Session | Runtime (SHA-256) | What it shows |
|---|---|---|
| `a2-min-1080`, `a1-off-1080` | 0023-0025 (`72c65701`) | The idle account (section 1); their spawn and touch steps did not work |
| `b2-min-1080` | 0023-0026 candidate (`d1ebbe82`) | One copy in play: 769 copies (750 MB) freed, hashes equal on respawn |
| `q1-final-default` | 0023-0026 candidate (`8445560f`) | Free memory: nothing changes; a hog makes no pressure |
| `b5-min-1080` | 0023-0026 candidate (`8445560f`) | The trigger on the minimum profile's values (section 2) |
| `q3-final-trigger` | 0023-0027 candidate (`59872e82`) | The trigger at 4K with the managed budget off: the burst stays; the driver's budget follows the game's usage beside a hog |
| `r1-default-1080` | final (`8bdd0819`) | The trigger with this computer's defaults (section 2) |
| `q4-final-testbudget` | final (`8bdd0819`) | Replacement textures under pressure (section 4) |
| `a4-min-4k` | final (`8bdd0819`) | The trigger on the minimum profile's values at 4K (below) |
| `b3-orig-1080`, `a3-orig-1080`, `p5-orig-trigger` | original (`e8deaccb`) | The trigger's baseline; two device losses (below) |
| `c1-min-1080-0028` | 0023-0028 (`c4afaa44`, the import's code) | The trigger after the review's fixes, on the integrated package (section 11) |

  The candidates differ from the final source only in what the later amendments added (0026's
  10-second wait, its test budget and teardown fix, 0027's counters). The imported `d3d9.dll`
  (`0c20772f...`, 397,903,360 bytes) differs from `8bdd0819` in 40 bytes: the PE timestamp and
  checksum, the debug GUID and the version string (`remix-main+d0a60c1e`); every code section is
  identical (`r13-b/code-parity-final-vs-import.json`).
- The original runtime lost the GPU device in two of its four sessions (`a3-orig-1080`,
  `p5-orig-trigger`), about 7 seconds after rendering began (frames 104 and 143; the `[RTX Memory]`
  device-lost rows in their logs), with the memory profiler enabled as in every session here; R13-A's
  runs of the same runtime without it did not. The new runtime lost none in nine. Not investigated.

## 9. Session quit times (Steam Cloud)

Every session ran with `+fps_max 60` (the coordinator restores the field's cloud settings). Normal
console quits (UTC, 2026-11-03): 11:48:36 (`a2-min-1080`), 11:54:36 (`a1-off-1080`), 13:37:56
(`b2-min-1080`), 13:48:13 (`q1-final-default`), 13:56:11 (`b5-min-1080`), 14:08:44
(`q3-final-trigger`), 14:18:32 (`b3-orig-1080`), 14:26:31 (`r1-default-1080`), 14:34:02
(`q4-final-testbudget`) and 14:42:09 (`a4-min-4k`). After the review: 15:52:48 (`c1-min-1080-0028`),
which ran the integration branch's `poc_session.py` and so ended with the field's own settings
(`settings_back: restored` in its record). `a3-orig-1080` (11:56:24) and
`p5-orig-trigger` (14:10:35) ended on a GPU device loss without a quit. No field game was started, and
none was running when a session began.

## 10. Per-profile values (R13-C)

| | minimum | recommended | high |
|---|---|---|---|
| `d3d9.releaseManagedHostCopies` | True | False | False |
| `d3d9.managedTextureBudgetMiB` | -1 (VRAM / 4) | -1 | -1 |
| `rtx.texturemanager.*` | not written | not written | not written |

The runtime's automatic values match (Auto turns copies off from 28 GiB RAM and 15 GiB VRAM). Savings
measured on this computer: after the trigger, 8.5 GB of VRAM and of commit back within 75 s with the
defaults; on the minimum profile's values the burst costs no extra private bytes and leaves 2.3 GB of
game textures resident.

## 11. The review's fixes (patch 0028)

An independent review of 0024-0027 found three defects and a nit; all are fixed in
`0028-Fix-a-hash-race-baker-sources-and-unmarked-writes-of.patch` (runtime commit `403b2336`), and the
runtime part holds the rebuilt `d3d9.dll` (SHA-256 `91f0696c8c1ca5c0566c470f55379ed25fcb916ca572cfd2a585fa17d5718e97`, imported once).

1. **The hash API raced the image release** (0024). `dxvk_GetTextureHash` and `GetStableHash` read
   `m_image` and the released hash without a lock; `ReleaseManagedImage` moved the image out, reset the
   views and only then wrote the released hash, and ToPBR calls the API from Lua's thread. A
   memory-managed texture now keeps its hash in `std::atomic<XXH64_hash_t> m_stableHash`, written with
   every hash change (`SetupForRtxFrom`, `ClearHash`, `ReleaseManagedImage` before the image goes; kept
   as it is across the re-creation in `EnsureImage`); for these textures the API and `GetStableHash`
   read only the atomic and never `m_image`. Other textures read as before.
2. **Terrain-bake sources could stay at their smallest mip** (0026). The baker tracks its sources
   through `addTexture` every frame it bakes without retaining them. `addTexture` now stamps the frame
   on the texture, and `textureInUse` (`rtx_texture_budget.h`) counts a texture retained by an instance
   or tracked in this frame or the two before; only a preload not in use for 10 seconds gives way.
3. **Writes without a dirty region could be lost** (0024, copies released). A writable lock with
   `D3DLOCK_NO_DIRTY_UPDATE` now keeps the texture's CPU copy for good (`lockKeepsHostCopy`,
   `d3d9_managed_memory.h`), which also covers an `AddDirtyRect` that comes more than 10 s later.
4. **The pass ran in every game:** `ManageManagedTextureMemory` returns at once when neither option is
   on, so other games take no lock and write no log line.

**Tests.**

- `tools\test.ps1 -Config Release` passes on `r13-runtime` (fast-forwarded to `r13-int` `1a7d8e2`, then
  this round): the repository checks, 26 CTests and 592 Python tests (28 + 25 + 539)
  (`r13-b/test-release-0028.log`).
- Unit checks for `textureInUse` and `lockKeepsHostCopy`; both runtime unit tests pass, and 32 of the
  33 meson tests. The 33rd, `test_remix_categories`, cannot load `d3d9.dll` under meson because its
  test definition leaves the runtime's dependency folders off `PATH`; run with them it passes. This is
  not caused by 0028.
- **GPU probe** (`r13-b/probe-0028`, `r13-b/probe-pre0028`): the `r13` sequence now also runs a second
  thread reading every texture's hash through the API from the idle passes through the re-use, and an
  unmarked write (`D3DLOCK_NO_DIRTY_UPDATE`) that must survive idle passes and draw after a late
  `AddDirtyRect`. On the runtime before 0028 (`0c20772f`) the budget variants failed on wrong hash reads
  and the copy-release variants lost the write. On 0028 every variant passes and matches the original
  runtime: the same hashes and pixels as before, the unmarked texel `3117438` before and `5614131` after
  `AddDirtyRect`, its hash `0x7de71b987af57fd0`, and about 1.2 billion hash reads per run with none wrong.
- **PoC** (`c1-min-1080-0028`: the integrated package from `r13-int` with loader 0.13.0 and R13-A's
  loading on first use, the minimum profile's runtime values, copies released and a 2 GiB budget, the
  trigger at 1920x1080):

| GB | idle | characters | removed | **triggered** | **+180 s** | characters again |
|---|---:|---:|---:|---:|---:|---:|
| game textures | 0.29 | 0.96 | 0.96 | **6.29** | **2.35** | 2.35 |
| private bytes | 15.10 | 17.19 | 17.25 | **16.48** | **16.05** | 16.22 |
| texture CPU copies | 5.04 | 5.36 | 5.36 | 0.04 | 3.97 | 3.97 |
| driver usage / budget | 5.91 / 32.95 | 6.71 | 6.84 | 11.42 | 7.62 | 7.75 |

  It behaves as before: the burst (now 5.3 GB, R13-A's ready set) is back at the 2 GiB budget after the
  idle time (72 images, 4.39 GB, released; 76 read-backs; 7 re-uploads), the copies of the burst went
  and came back as the images went, and the respawned characters have the same 74 hashes as before the
  release and as on the original runtime. Normal quit, no Lua error, the PoC restored exactly. With
  R13-A, private bytes at idle are 15.1 GB against 27 GB before.

**The intermittent option crash** (time-boxed, not fixed; it did not reproduce): an access violation
reading 0x50 in `RtxOptionImpl::resolveValue` under `RtxOptionManager::applyPendingValues`. That loop
holds only the update mutex, while `acquireLayer` and `releaseLayer` hold only `s_layerMutex` as they
insert into and erase from every option's layer queue (`readOptionLayer`, `disableLayerValue`) and call
`markDirty()`, which writes the dirty map without a lock. A layer acquired or released on another thread
during that loop (the graph's option layer actions) would corrupt the queue `resolveValue` iterates. The
dump shows no such thread, so this is a candidate, not a proven cause. A fix would hold the update mutex
in those two loops too (lock order `s_layerMutex`, then the update mutex, as `applyPendingValues` takes
them); `discoverDynamicOptions`, which runs inside, takes only the registry write mutex. Not done: the
change touches option startup and the graph, and the cause is not certain.

## 12. Open items and decisions for the main session

- The content side's preload choices (section 5): rpai, ToPBR, the duplicate `pbr_*` mods in the field.
- The library's CPU copies and the start-up peak: R13-A's loading on first use (section 6).
- What in Source draws every loaded texture on the first `item_ammo_ar2_altfire` precache and during a
  map load (section 2): the draw path is known, the engine function is not.
- Remix captures were not exercised in a session.
- The option crash candidate (section 11) and `test_remix_categories`'s `PATH` under meson.
- Machine load: short incremental runtime builds ran at about 12:09, 12:22 and 12:27 UTC (about a
  minute each) while R13-A's sessions 11 and 12 measured; no GPU work.
- The runtime branch's history was rewritten twice before the import (a control character that a shell
  heredoc had put into a comment of 0024, and the test budget folded into 0026); the patches and
  `runtime/base.json` record the final commits, and nothing was pushed.
