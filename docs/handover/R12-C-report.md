# R12-C: VRAM attribution and demand loading (report)

Completed on `r12-vram`, from `2dd3033`: attribution, demand allocation, draw-gated alpha,
runtime rebuild/import, GPU/game QA and Release checks. **App textures fall 13.51 → 0.91 GB
(93.3%, 11.74 GiB saved)** in the copied field-cache replay, with every actor registration kept.
No push, merge or publication was performed. All times below are UTC on 2026-11-03.

## Findings already established

- `companion/nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua` loaded every generated
  library material through `Material()` before reading its draw hashes. The fix reads and validates
  the existing draw records first. The real Lua script's 4,096-material cold-library regression
  records zero material, VMT or tracking loads, then classifies only a newly drawn material.
- R11-B `QueueGameMaterial` calls native `FindMaterial` before `CollectMaterialFrameHashes`
  (`packages/fixes/licenses/oversized-skinning/autopbr/source/material_pipeline/to_pbr/to_pbr.cpp:4513`).
  R12-B owns that fix. A Lua-only gate is an experimental control, not a substitute shipped here.
- Eye-white discovery covers all `mmdhl.assets`; `prepare()` calls `Material(state.name)` even if
  no entity uses that asset (`nativeloader_eye_whites.lua:135`), then creates source/proxy materials
  and warms their textures on an offscreen target. It holds those textures in `atlases` for the
  Lua realm's lifetime. R12-D owns that file. Proposal: require a live imported entity (including
  native draw/material metadata for soft-only surfaces) before preparation; drop unused states,
  restore borrowed bindings, unbind helper textures and stop warm jobs after the last use. Lua
  table pruning alone does not prove that Source/CreateMaterial or native tracking released VRAM.
- Read-only field Windows GPU-process counters at 2026-11-03 approximately 01:35 UTC report
  **25,904,726,016 dedicated bytes** and **15,130,427,392 shared bytes** for game PID 8488 on the
  NVIDIA adapter. These are WDDM counters, not a D3D9-category breakdown or a synchronized
  physical-residency measurement. Evidence: `out/r12-vram/field-gpu-processes.json`.
- The current disk inventory is larger than the plan's earlier active-library estimate. There
  are **175** historical material archives (**69,259,030,903 bytes**) in the field cache. Selecting
  the latest numbered archive per asset finds **146** archives (**57,712,639,369 bytes**) and
  **1,244** distinct supported RGBA8888 VTF records with **45,853,418,624 logical texel bytes**.
  These are disk/logical sizes, not measured loaded textures; deleted, historical or unused assets
  cannot be attributed to VRAM just because they remain on disk. Evidence:
  `out/r12-vram/library-inventory.json`, `field-vtfs.json`, `poc-vtfs.json`.

## Implementation and offline checks

- [ADR 0096](../decisions/0096-demand-loaded-character-classification-and-memory-census.md).
- Runtime patch 0021: manually requested NoSave allocation snapshots from the existing opt-in
  profiler, including D3D9 size/format/pool/mips, with complete integer byte accounting.
- Local-only PoC Source debug-texture census module, field activity gate, evidence validator and
  header-only VTF inventory. No diagnostic module or additional native permission is shipped.
- Release runtime built with `runtime/build_runtime.ps1 -NoImport` in this worktree's own
  `out/runtime-src`; DLL **397,861,888 bytes**, SHA-256
  `7163e7666755607293558d02bf60738dd5e6456ea5b51ea54482a3d773ab9a83`.
  Seven relevant CPU runtime tests pass (memory diagnostics, texture upload/hash, MMD alpha,
  eye whites, model layers and fallback mods). The Release loader passes all 26 CTests.
  The final import, game checks and full Release results are recorded below.
- Runtime patch 0022: **demand allocation for unused static managed GMod textures**, default on
  for `gmod.exe` only, with `d3d9.deferManagedTextures` / `DXVK_DEFER_MANAGED_TEXTURES` override.
  Descriptions, CPU data, mip levels and LOD stay unchanged; only GPU use/upload/`PreLoad` creates
  the original image. Default/system pools, other texture types/usages, shadows, conversion
  formats and `evictManagedOnUnlock` retain their old paths. Initial clears and uploads are ordered
  on one command stream. No image compression, resizing or texture-hash migration is involved.
  Candidate DLL: **397,862,912 bytes**, SHA-256
  `e6dbf96d89cde7a836bea14ef9b033c3d38b18ccb2f033a802d933da4fe273b9`.
- The isolated GPU regression compares **the original diagnostic runtime**, the new eager control
  and deferred mode. Four 1024-square managed textures allocate **22,376,448 / 22,376,448 / 0**
  bytes through creation/metadata/CPU read-write/LOD queries. `PreLoad` creates exactly one
  **5,594,112-byte** image in deferred mode. Preload and first-draw hashes match exactly
  (`93e625c1683421dc`), partial-write hashes match (`655231f5133bd2cc`), and mip-1 RGB is exactly
  **0x112233** in all three controls. First draw without preload, unwritten-image zero contents,
  default/system pools, managed cubes and invalid managed/dynamic combinations pass. The host's
  existing common-device-object teardown warning is present in the original binary too; this
  is recorded separately from the successful allocation/pixel/hash assertions. Receipts:
  `gpu-probe-result.json`, `gpu-original-parity.json`, `gpu-test-{0,1}`, `gpu-original`.

## Game evidence

Every launch passes the activity gate and uses `-multirun`. The shared exclusive PoC lock is
held only for each prepared case, then snapshot restoration and release. Busy locks retry at
two-minute intervals; a busy field retries at five minutes. The original field game was never
ended, focused or sent input. Its user exited it before the first PoC hold. All scratch, copied
metadata, builds and evidence are below this worktree's `out/`.

### The main source: saved actor registration

The field's **50 approved assets** were copied read-only into `out/r12-vram/field-cache`:
**2,991 files / 16,280,987,154 bytes**, with every source/copy SHA-256 equal. Copies include
current material archives/model data, published rig carriers and small metadata; original source
folders and the field install remain untouched. The PoC swaps this copy into its cache only while
locked and restores its original cache afterward.

`04-field-cache-q1` / `05-field-no-actors-q1` use gm_construct, **3840×2160**, high, no Workshop,
stock Kleiner, no active imported character, and all three suspect Lua helpers disabled. Both
retain **49 visible library entries**. The first publishes **68** cached actor registrations;
the control's copied `approved.rigs` is empty, so it publishes **0**. This is an experimental
control, not a product behavior change.

| Cold copied field cache, late snapshot | Registered | Registration control | Difference |
|---|---:|---:|---:|
| D3D9 app texture allocation bytes | 13,511,942,144 | 1,065,893,888 | **12,446,048,256** |
| Source `mmd/t/` logical byte estimates | 12,432,024,184 | 0 | **12,432,024,184** |
| Source other texture estimates | 900,475,060 | 900,475,060 | **0** |

This isolates the large unused-model component without relying on archive totals. The actor
readiness path mounts saved carriers and calls `util.PrecacheModel` / `util.IsValidModel`
(`actors.lua:87-103`, publication from `sharing.lua:237`); a listen server uses the real shared
material system, creating managed images before an imported character is active. This explains
most of the field's roughly 13 GiB app-texture category. The copied-cache cold run is distinct
from the user's active session: its Workshop/current playermodel/history and replacement usage
are not the same.

Patch 0022 addresses the GPU backing in R12-C's owned runtime paths while preserving registration
and NPC readiness. A later hotloader change could also avoid the CPU model/texture work, but
must preserve the R10/R12-A first-spawn and post-map readiness guarantees. Proposed exact scope:
metadata-only catalog publication, validated mountable carrier identities, target-only readiness
before the first spawn/SetModel, and cached 2D menu icons; do not merely delete the precache call
and retain `IsValidModel`, or remove NPC entries as the experimental control does.

The allocation census also resolves the pool/format question for the copied field replay:
**12,788,286,464 bytes are D3DPOOL_MANAGED**, **722,470,912 default pool**, and **1,184,768**
have no D3D9 metadata. A8R8G8B8 accounts for **7,947,673,088** and X8R8G8B8 **5,093,258,752**
bytes: uncompressed managed color atlases dominate, rather than an opaque replacement cache.

| Largest managed groups | Mips | Count | Allocation bytes |
|---|---:|---:|---:|
| 4096×4096 A8R8G8B8 | 8 | 30 | 2,684,405,760 |
| 2048×2048 X8R8G8B8 | 7 | 97 | 2,170,018,816 |
| 2048×2048 A8R8G8B8 | 7 | 94 | 2,102,904,832 |
| 4096×4096 X8R8G8B8 | 8 | 14 | 1,252,722,688 |
| 8192×8192 X8R8G8B8 | 9 | 3 | 1,073,746,944 |
| 8192×8192 A8R8G8B8 | 9 | 2 | 715,831,296 |
| 4096×2048 A8R8G8B8 | 7 | 14 | 626,375,680 |
| 11059×8847 A8R8G8B8 | 10 | 1 | 530,540,544 |

All remaining groups are retained in `04-census.json`; image slices include Vulkan alignment,
and Source logical mip/format byte estimates are a distinct measure.

### Demand allocation: measured result with registrations preserved

`16-field-lazy-q5` replays the same copied field cache at 4K/high with all **68 registrations**,
**49 visible library entries**, stock Kleiner and no active imported character. The default
GMod path enables demand allocation; there is no forced quality or model-catalog reduction.
Final candidate at this point is **397,862,912 bytes**, SHA-256
`466f139afe797cce380f5f798a05c6b830d6198604682acabecbb3340a772bea`.

| Late snapshot | Original eager runtime | Demand allocation | Saved bytes |
|---|---:|---:|---:|
| App textures | 13,511,942,144 | 908,630,016 | **12,603,312,128** |
| DXVK used | 18,094,716,224 | 5,490,795,072 | **12,603,921,152** |
| DXVK allocated | 19,494,161,920 | 6,682,587,648 | **12,811,574,272** |
| Driver allocated | 20,776,869,888 | 8,171,347,968 | **12,605,521,920** |
| Replacement textures | 2,656,725,504 | 2,656,725,504 | **0** |
| Remix render targets | 1,333,341,184 | 1,333,341,184 | **0** |

App textures fall **93.3%**, saving **11.74 GiB**. Source still reports the same
**12,432,024,184 logical `mmd/t/` bytes**: its CPU/catalog objects remain loaded, while their
unused Vulkan backing is absent. This also demonstrates why Source byte estimates must not be
substituted for actual allocation counters. The tiny difference in other Source rows is one
262,144-byte font page, not imported content. Both early and settled captures show the reduction.
The game quits normally with zero Lua errors and the original cache/config/deployment snapshot
is restored exactly; no Source actor/readiness code is modified.

### Independent eager helper costs

The nine-asset PoC metadata control mounts its real GMA files and publishes only material metadata
to `mmdhl.assets`, without spawning a character. All other suspect helpers are disabled. This
isolates eager lookups in a fresh process from both actor registration and previously used models.

| Helper control (1280×720, high), app bytes | Before metadata | After metadata | Added |
|---|---:|---:|---:|
| Original MMD alpha (`02h-alpha-old-library-q4`) | 1,659,630,080 | 3,613,383,168 | **1,953,753,088** |
| Draw-gated MMD alpha (`03-alpha-new-library-q2`) | 1,659,630,080 | 1,659,630,080 | **0** |
| Original game-PBR queue (`06-pbr-old-library-q1`) | 1,659,630,080 | 3,613,383,168 | **1,953,753,088** |
| Draw-gated queue control (`07b-pbr-gated-library-q1`) | 1,659,630,080 | 1,659,630,080 | **0** |
| Eye-white helper only (`08-eyes-library-q1`) | 1,659,630,080 | 1,765,904,896 | **106,274,816** |

Both have 9 assets / 366 metadata materials after injection. The new script's source texture
set remains unchanged; the old script loads the remaining `mmd/t/` bases. The saving is
**1.82 GiB**, with no content/hash change. The three helper savings overlap and must not be
added together. Actor precache also overlaps the same identities.

The PBR control adds only the draw-hash gate in its scratch Lua caller; it measures the proposed
lookup ordering, not R12-B's final native DLL. Eye-white source rows add **72,691,712** proxy bytes
and **33,550,336** previously unloaded MMD-base bytes (logical estimates); no character is spawned.
Those warm draws are explicit GPU uses, so runtime demand allocation alone cannot remove them.

### Character contents, hashes and lifetimes

`15-spawn-eager-q2` / `17-spawn-lazy-q1` spawn the same cached Robin carrier
`models/mmd/5725aac3e27fbf70/robin.mdl`, freeze it, capture its face/body, remove it and call the
existing `RemixResource.ForceCleanup`. The new run uses the new alpha classifier and the same
eye/PBR helpers. All **39** observed material/hash sets match exactly (`character-hash-parity.json`),
the character's captured materials/geometry remain intact, removal succeeds and both sessions
quit normally with zero Lua errors. The spawn points/backgrounds differ, so these screenshots
are visual inspection, not a pixel-difference claim. The isolated GPU readback provides exact
pixel/hash parity under identical test input.

| App-texture bytes | Eager | Deferred |
|---|---:|---:|
| Before spawn | 1,659,630,080 | 169,718,784 |
| Character drawn | 1,665,739,264 | 663,211,008 |
| Character removed | 1,665,739,264 | 663,211,008 |
| Explicit resource cleanup | 1,665,739,264 | 663,211,008 |

Used managed images remain in Source's native caches after removal; this is explicitly **not**
an immediate GPU-eviction implementation. The explicit cleanup drops replacement allocation
**2,656,725,504 → 265,225,728 bytes** in both runs, while leaving the app images alone. It also
temporarily moves released replacement memory into allocator retention (up to 3,176,501,312 in
the deferred sample), so a purge is not equivalent to freeing all driver allocations immediately.
Do not prescribe periodic global purges as a fix for the app-texture category.

### Proposals outside this change

1. **R12-B lookup order:** move validated draw-hash collection ahead of `FindMaterial` in
   `TextureProcessor::QueueGameMaterial`; keep manual mappings/hash identities intact. The
   nine-asset control saves **1.82 GiB** on the original runtime, and avoids unnecessary CPU
   material work even with demand allocation.
2. **R12-D eye preparation:** gate `prepare()` and helper warming on an actually presented
   imported material/entity, including the soft-only path; cancel unused warm jobs and restore
   only owned bindings/aliases. The nine-asset control contributes **101.35 MiB** of unused
   app allocation. Retain proxy identity/canonical-hash behavior for visible and manually
   assigned eye whites. Source-held material references mean Lua table pruning alone is not a
   measured GPU release.
3. **Hotloader CPU/catalog work:** the exact registration proposal above can avoid substantial
   RAM/I/O too. It is outside R12-C's assigned `actors.lua` / persistence / server paths, and
   cannot regress R10/R12-A NPC readiness. Demand allocation already addresses its large GPU
   cost without changing that code.
4. **Used-texture lifetime:** measure Source model/material ownership and the fixes' retained
   draw-tracker references before implementing targeted eviction after last use/map teardown.
   Preserve live Source overrides and Remix's cached/anti-culled surfaces. Do not drop backing
   solely from Source's last-bind counter or force global model/material reloads on removal.
5. **Replacement history / allocator retention:** investigate bounded idle mip demotion through
   existing texture-manager feedback and trim fully empty chunks after retirements. The explicit
   cleanup control shows about **2.39 GB** of releasable replacement residency in this workload,
   but also shows why immediate driver savings cannot be inferred from a category decrease.
   Current replacement budgets and high-tier quality are unchanged here.

Downsampling/re-encoding existing VTFs is not used: it changes content/captured hashes and can
break authored replacements/categories. The runtime fixes preserve those identities.

The earlier `01d-alpha-old-library` validated the native Source reader but is **not** a helper
measurement: its absolute `game.MountGMA` injection was refused. The fixture now uses the
hotloader's normal `MountPackage` path and requires an explicit 9-asset injection receipt plus
normal exit, zero Lua errors and active RTX. Its valid early source reading finds **49**
`mmd/t/` textures / **1,329,810,028 logical bytes** despite zero active assets; every one has
the Source last-bound-frame sentinel `UINT32_MAX`. Source estimates and actual Vulkan allocation
bytes are intentionally reported separately.

### Startup fault retained and excluded

`07-pbr-gated-library-q1` exited **0xC0000005** after nine seconds, before client Lua/probe startup,
using the **old diagnostic runtime**. The exception is in `nvoglv64.dll+0xe6230a`, a read from
`0xffffffffffffffff`; the dump and decoded module/register facts are retained in the session's
`crash-reports` and `07-crash-summary.json`. Stack values are only scanned candidates, not a
recovered unwind or proof of cause. The runtime's last lines include unsupported shader-model
messages. This observation does not establish a cause and is not counted as a memory result.
The same original PoC snapshot was restored exactly and its lock released at `02:52:30Z`.

The original-runtime `11-resolution-4k-q1` control later hit `VK_ERROR_DEVICE_LOST` at frame 117.
Its crash snapshot reports **9,675,137,024 driver bytes against a 32,945,209,344-byte budget**,
**8,157,252,608 DXVK allocated / 6,844,576,576 used**, frame generation off and only
**28,152,320 OMM bytes**. The evidence does not support VRAM exhaustion as its cause. The marker,
current-session runtime log and failure are retained; this is not counted as a successful
resolution measurement. Restoration completed and the lock was released at `03:32:48Z`.
One bounded old-runtime retry disables only pipeline state-cache precompilation
(`DXVK_STATE_CACHE=0`), which does not change texture/rendering settings.
`11b-resolution-4k-q5` completes normally on that bounded retry; both failed controls remain
archived, not silently substituted for successful measurements.

### Resolution, quality tier, map and menu

| Original eager runtime, late sample | App textures | Remix targets | Replacement textures |
|---|---:|---:|---:|
| 1280×720 high (`00b`) | 1,659,630,080 | 314,949,632 | 2,656,725,504 |
| 3840×2160 high (`11b`, state-cache precompile off) | 2,398,892,544 | 1,333,341,184 | 2,656,725,504 |
| 1280×720 low (`12`) | 1,659,630,080 | 222,076,928 | 2,488,954,880 |

Resolution adds **739,262,464 app bytes** and **1,018,391,552 target bytes** in these controls.
Low saves **92,872,704 target** and **167,770,624 replacement bytes**, while leaving the large
app-texture component exact. OMM settles near 159 MB in both high/low here: the lower cap is not
an actual saving for this small scene. Existing explicit tiers change quality as documented;
this change keeps high and every tier file unchanged.

With the final demand-allocation runtime, the gm_construct → gm_flatgrass control (`13`) loads
the second map normally and settles at **141,632,512 app bytes**, **314,949,632 targets**,
**265,225,728 replacements** and **888,064 OMM bytes**. The first map's scene/replacement residency
returns; cached Source CPU/catalog estimates are not proof that the corresponding GPU images
remain allocated. Used native model caches still explain the character-removal retention above.

Opening/closing the normal spawn menu through `+menu`/`-menu` (`14b`) changes app allocation
**170,070,016 → 171,871,232 bytes**, retained after close; Source lists **4,915,200 logical
spawn-icon bytes**. It does not instantiate another library's worth of GPU images. The first
menu attempt (`14`) called unavailable `spawnmenu.Open/Close` fields, was rejected for two QA
Lua errors and restored exactly; the corrected probe has zero Lua errors and a normal quit.

### Final imported build and restoration

`18-final-package-smoke-q1` loads the **imported e8deaccb... runtime**, default demand allocation,
new alpha classifier and normal original eye/PBR helpers. Cached Robin spawns/draws/removes;
the run quits normally, zero Lua errors, and the original PoC snapshot is restored. The prior
controlled eager/deferred pair matches all 39 live material hashes. This later smoke retains
**38 identical stable hashes**; the one differing entry is the existing synthesized
`rtx_solidcolor_mmd_..._eye_shadow_31_rt` render target (default pool, excluded from deferral),
whose descriptor identity is seeded by the pre-existing render-target creation counter.
It is not a changed source VTF/hash migration; the final executable code matches the tested
candidate exactly, and original/new GPU test data hashes remain exact.

All **23** held PoC snapshots have exact file-hash restoration, unchanged before/after
`user.conf` fingerprints and release receipts (`restoration-ledger.json`). No owned PoC
process remains. Final depot verification reports **2,877 files / 7,279,873,012 bytes OK**,
zero missing/size/hash/reparse/unverified entries, and the same permitted `autoexec.cfg`
user-config difference. The field install, Steam settings/launch options and original model
folders were never written. Build/scratch/evidence stays under this worktree's `out/`.

### Cleared cache and Workshop subscriptions

With all three helpers disabled at 1280×720/high, clearing the PoC's saved cache gives
**326,345,728 app bytes**, against **1,659,630,080** with its normal nine-asset saved cache.
No actor registration is published in the cleared-cache control. Installed content packs
automatically repopulate the empty disk library to five visible entries by the late capture;
this is a **cleared saved-cache control**, not a claim that the catalog stays empty forever.

`10-workshop-q1` mounts **767 of 768 subscriptions** (the distribution native package itself
is correctly outside GMod's content whitelist), with `--workshop --addons`, the same nine cached
assets and stock Kleiner. App textures are **2,195,956,224 bytes**, **536,326,144** above the
non-Workshop control; DXVK allocation is **6,377,769,984**. It has two additional entities and
there are no Lua errors. The map/probe starts only after the Workshop remount, so the measurement
is later in process time than the non-Workshop control. Existing add-on diagnostic messages
(including the older native-menu config parser) are retained without changing those add-ons.
The game quits normally and the full snapshot is restored, releasing the lock at `03:31:10Z`.

### Release and package gates

The final runtime is **397,862,912 bytes**, SHA-256
`e8deaccbbe33f40876528b12bc5150c6e5868af745878e6650e901ed48ad841a`, from source commit
`fc62f44f` in this worktree's `out/runtime-src`, patches 0001–0022. Its executable `.text` section
is **byte-identical** to the game-tested `466f139a...` candidate (`final-code-parity.json`),
and the final binary passes the GPU assertions in both the API factory and the game's standard
`Direct3DCreate9`/draw-conversion path. The last rebuild contains comment/provenance/include
ordering cleanup and updated version/debug metadata; it does not change rendering instructions.

Imported **exactly once** through `runtime/build_runtime.ps1` / `tools/inputs.py import runtime`:
**1 file stored, 0 removed**; `runtime/base.json` records the final DLL and every patch hash.
`inputs.py verify --deep`: **11 parts, 0 problems**. The combined package is accepted by `nlctl`:
**1,091 files**, version `0.0.0-dev.20261103033001+4d540aaa`, content digest `1752e36d84749042...`.

`tools/test.ps1 -Config Release` passes **26 CTests + 562 Python tests** (509/28/25, the two
existing skips), `All checks passed.` Separate companion alpha regressions pass **21/21**.
The first full run caught a GMA import-name collision in the new inventory tool; it was fixed
for both vendored import forms and the full Release suite rerun successfully. No checks were
disabled or altered to conceal a failure. Receipts: `runtime-final-import.log`,
`release-tests-final.log`, `inputs-final-verify.log`, `final-package.log`.

### Active field: read-only category attribution

The existing companion telemetry supplies the category breakdown without a launch or console
input. At `2026-11-03T01:40:49Z` (`field-active-vram.json`), with the pinned shipped runtime/fixes:

| Category | Bytes | GiB |
|---|---:|---:|
| D3D9 app textures | 14,380,545,024 | 13.393 |
| Replacement textures | 5,856,326,144 | 5.454 |
| Remix render targets | 1,417,882,624 | 1.321 |
| Opacity micromaps | 603,456,768 | 0.562 |
| Remix buffers | 397,831,744 | 0.371 |
| Acceleration structures | 153,115,392 | 0.143 |
| D3D9 app buffers | 49,139,712 | 0.046 |
| Replacement geometry | 0 | 0 |
| **DXVK used (exact category sum)** | **22,858,297,408** | **21.288** |
| Allocator retained (additional to used) | 1,181,703,616 | 1.101 |
| **DXVK allocated (used + retained)** | **24,040,001,024** | **22.389** |

The driver reports 25,935,142,912 allocated bytes and a 31,739,682,816-byte budget; those are a
different observation from the DXVK category sum. Replacement textures alone are about 5.45 GiB,
so freeing all 1.10 GiB of retained allocation could not account for the main texture use.

### Instrument validation

`00-census-smoke` was rejected as a measurement: the QA manifest used an invalid `kind` key in a
root entry, so no runtime activated. The owned game was quit normally; all **3,729** snapshot files
and `user.conf` hashes were restored exactly. A native `nlctl manifest` preflight now runs before
every lock/launch, preventing that QA packaging error from recurring.

`00b-census-smoke` uses the diagnostic runtime, gm_construct, 1280×720, high tier, no Workshop,
ReShade off and all three suspect helpers disabled. Both its early and 45-second allocation
censuses report **1,659,630,080 app-texture bytes**, exactly matching `GetVramStats`. Its client
reports **zero** active hotloader assets/materials despite the nine cached asset archives.
The largest app group is **seven 4096×4096, eight-mip A8R8G8B8 managed textures**,
**626,361,344 bytes**. That initial baseline cannot be attributed to an active hotloader library.
Other large groups include 12/11 2048-square managed X8R8G8B8/A8R8G8B8 textures
(268,455,936 / 246,084,608 bytes). The Source public debug list returned empty; its name census
was rejected as unavailable, prompting the SHA-pinned read-only registry fallback.
The run quit normally and restored the same **3,729** files exactly, releasing the lock at
`01:46:03Z`. Runtime rows, current-session console, screenshot and receipts remain in
`out/r12-vram/sessions/00b-census-smoke` and `holds/00b-census-smoke`; no evidence was collected
from the user's console history.
