# 0064: Package performance tiers and smaller night-sky images

- Status: R6's tier/storage decision accepted 2026-10-31; tuning values below are **provisional,
  awaiting PoC measurements**. Do not treat T6 as accepted for integration yet.
- Decided by: the user's R6 performance/stability request and the choices in
  [R6-plan.md](../handover/R6-plan.md). Amends [0051](0051-path-bounce-defaults.md) only for the
  conditional lower tiers; high keeps the classic 1–12 bounce defaults.

## Decision

Keep `classic_remix_defaults.conf` byte-identical as high. Ship optional `medium.conf` and `low.conf`
in the runtime part, at `config/dxvk-tiers/<tier>.conf`. They contain only `rtx.*` assignments, each
with a reason. They are hashed ordinary payloads, absent from `remix.dxvk_conf_layers`; no schema,
kind or loader requirement changes. Old loaders retain classic settings. R6 T1 selects one tier
before the classic layer; user `rtx.conf` and `user.conf` still have priority. Hardware detection
and the config override belong to T1, not the packager.

Candidate values, relative to classic plus the packaged runtime's defaults:

| Key (`rtx.` prefix) | High | Medium | Low | Cost / expected saving |
|---|---|---|---|---|
| `pathMaxBounces` | 12 | 8 | 4 | Bound query paths; mirror/transmission chains lose light beyond the cap unless NRC already terminated the path |
| `neuralRadianceCache.qualityPreset` | 2 (Ultra) | 1 (High) | 0 (Medium) | Fewer training records and bounces, coarser cache; less responsive/detailed indirect light |
| `skyProbeSide` | 2048 | 1024 | 1024 | Probe storage 96 to 24 MiB: 72 MiB less |
| `volumetrics.froxelGridResolutionScale` | 4 | 8 | 8 | About a quarter of the XY froxels; preserve 48 depth slices; coarser fog |
| `opacityMicromap.cache.maxBudgetSizeMB` | 1536 | 1024 | 512 | Upper bounds, not actual allocation; smaller OMM caches may slow alpha-heavy scenes |
| `opacityMicromap.cache.minFreeVidmemMBToNotAllocate` | 512 | 1024 | 1024 | With the default 384 MiB buffer, growth budgeting leaves 896 / 1408 / 1408 MiB free; existing budget has hysteresis down to the hard limit |
| `terrainBaker.cascadeMap.levelResolution` | 4096 | 2048 | 2048 | Quarter-sized atlas when terrain baking runs; coarser terrain materials |
| `lowMemoryGpu` | False | unchanged | True | Halve the micromap VRAM percentage, skip the top streamed replacement-texture mip and request lower-memory acceleration structures |
| `atmosphere.starMap{,Galaxy,Nebula}Texture` | original DDS | unchanged | corresponding `_4096.dds` | Exactly 160 MiB fewer compressed texels, with no re-encoding |

NRC's own preset callback sets the training parameters. Ultra/High/Medium respectively use
4/3/2 target iterations, 9/7/6 training bounces, 0.01/0.04/0.06 m cache detail and
0.1/0.03/0.001 termination thresholds (`rtx_neural_radiance_cache.cpp:379–422` at `6f2dbd79`).
Under Custom it writes these derived settings into the User layer. Do not duplicate those keys in
the tier: they cannot win over the callback, and a user's selected NRC preset must remain coherent.

Leave DLSS/upscaler/quality, frame generation (off), visibility/category hashes, anti-culling,
denoiser gradients/confidence, separate denoising, ReSTIR bias correction, and texture-manager
budgets as they are. Their quality/performance trade-offs have not been measured. Texture budgets
remain adaptive rather than imposing one machine-independent fixed budget. No high-tier setting
was found and measured to be universally harmful, so none changes.

## Consequences and tuning questions

The bounce cap does not itself query NRC: `integrator_indirect.slangh:860-885` handles NRC's own
termination before stopping at `pathMaxBounces`. NRC's `maxPathVertices` is the training bounce
count (`rtx_neural_radiance_cache.cpp:697`), not a guarantee that a capped query path gets cached
light. Long mirror/transmission chains can lose light beyond the cap; evaluate this in PoC images.

`lowMemoryGpu` halves the OMM percentage (`rtx_opacity_micromap_manager.cpp:162-173`), drops the
top streamed replacement-texture mip (`rtx_texture_manager.cpp:1623`) and adds
`VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR` (`rtx_accel_manager.cpp:292-293`). Automatic
graphics selection can replace the layer's value (`rtx_options.cpp:419-461`): ordinary GPUs above
8 GiB get false (`rtx_gpu_profile.h:55,61`, `rtx_gpu_profile.cpp:212-220`). This is safe for
acceleration-structure updates: both BLAS UPDATE paths check `validateUpdateMode`
(`rtx_accel_manager.cpp:892-895,1258-1262`), which rejects changed build flags (`:2011-2016`);
TLAS always uses BUILD (`:1946-1951`). A flip therefore costs a rebuild on the next use of each
affected BLAS, potentially with an allocation/frame-time spike, rather than an invalid UPDATE.
The one-time intersection BLAS also uses BUILD (`:296-312`). These are source-verified properties,
not an in-game performance measurement. References are to the patched R6 T4 runtime snapshot
`29546f3566a676a1318b799fb8ddd01b2a110058`; C++ paths are under `src/dxvk/rtx_render/` and the
integrator is under `src/dxvk/shaders/rtx/algorithm/`.

For PoC tuning, should class-limited low on an RTX 3060 12 GB or 4060 Ti 16 GB retain
`lowMemoryGpu`? It drops replacement detail even though those cards are not memory-limited by
the tier's VRAM rule. Leave it true for now; measure its detail/memory trade-off and the cost of
switching to Automatic before changing the candidate.

## Night-sky files: measured bytes, derived GPU storage

`tools/sky/drop_top_mip.py` edits the DDS header and drops mip 0 only. It verifies mip 1 and every
retained block, preserves format/colour space/alpha mode, and refuses unsupported shapes and damaged
chains. Generated fixtures cover legacy and DX10 formats. The original mip chains remain shipped.
The existing `atmosphere/CREDITS.txt` covers the derived copies too.

| File | Source | Result | Mips | Result bytes | xz/LFS bytes |
|---|---|---|---|---:|---:|
| `stars_4096.dds` | 8192 × 8192 DXT5 | 4096 × 4096 DXT5 | 13 | 22,369,776 | 2,091,640 |
| `galaxy_4096.dds` | 8192 × 4096 DXT5 | 4096 × 2048 DXT5 | 13 | 11,184,976 | 2,046,012 |
| `nebula_4096.dds` | 8192 × 8192 BC7 UNORM | 4096 × 4096 BC7 UNORM | 13 | 22,369,796 | 10,673,456 |

Combined retained payload: **55,924,144 bytes (53.33 MiB)**, versus 223,696,304 bytes (213.33 MiB).
The dropped top mips total **167,772,160 bytes (160 MiB)**. This is texture data size, not a measured
driver allocation: alignment/driver overhead is excluded. Additional LFS storage is **14,811,108
bytes (14.13 MiB)**, above the proposal's 12 MB estimate. The galaxy is rectangular; `_4096` names
its width. The runtime resolves relative paths against its own DLL folder
(`rtx_atmosphere.cpp:652–672`, `loadSkyTexture:731–813` at `6f2dbd79`), so the low-tier paths are
`atmosphere/<name>_4096.dds`, beside the originals, independent of the working directory.

Medium keeps the original three skies pending PoC comparison. All three shader LOD formulas use
the image's real dimensions (`atmosphere_sky.slangh:408-439`); halving both dimensions subtracts
one from the unclamped LOD. Original LOD >= 1 therefore samples the same retained data. The stars
argument holds at ordinary FOV, but does not establish equivalence for all three images: at native
3840 × 2160, **90 degrees horizontal FOV**, zero mip bias, `pixel = 2/3840` radians gives original
star LOD >= 2.21, galaxy LOD 1.03 and **nebula LOD 0.44**. The nebula still blends original mip 0
with mip 1; the smaller image must clamp to its own mip 0 (original mip 1). The input pixel angle
also includes FOV and clamped total mip bias (`rtx_atmosphere.cpp:2914-2916,2934-2941`;
`rtx_scene_manager.cpp:320-346`). Narrow FOV, negative mip bias or higher resolution can expose
the missing level. The 160 MiB texel saving is real, but a three-image medium switch is a visual
tuning question, not a byte-identical 4K substitution.

## PoC measurements pending

The values are candidates: **no frame-time, VRAM, visual or stability result is claimed**. The six
required map/tier runs, night-sky comparison and 8 GB hardware validation remain open. The offline
size arithmetic above is not a substitute. Follow the
[T6 brief](../handover/R6-T6-performance-tiers.md#3-measure-poc). Until T1 is available, temporarily place the
tier's lines in the PoC root `rtx.conf`, restoring it after each run. Use identical cameras,
1280 × 720 output, ReShade off, 60 s settling, `--fps 30`, `fps_max 0` and
`engine_no_focus_sleep 0`; sample `rtx_vram_stats` after settling as well as before quitting. On
modern_house mount 3495468649 and change map as in the brief. Compare high/low night skies at
normal and zoomed FOV, including 4K nebula detail and the candidate medium three-image switch,
changing only the resolution for the sky-only comparison. Record warm
repeats: a single shader-cold frame-time sample is insufficient. Revisit the candidate bounce/NRC
choices if lighting degrades or gains are within run-to-run noise.

## Reproduction and offline validation

Stage changed text and derived DDS files under `out/` and import only those inputs with
`tools/inputs.py import runtime --file <staged-source>=<part-path>`. Derive each smaller sky with
`python tools/sky/drop_top_mip.py <original.dds> <copy_4096.dds>`.
`inputs.py verify --deep` checks all ten parts. The combined package build regenerates and hashes
its file list and is validated by the worktree's Release `nlctl.exe`. Automated coverage and the
remaining acceptance checks are in [TESTING.md](../TESTING.md#r6-t6-performance-tier-payloads).

The source-pinned tier test rejects unknown keys and invalid types/ranges/enums; the accepted
classic/compiler inputs are pinned unchanged. DDS fixtures cover every accepted legacy FourCC
and DX10 BC format, including block and linear sizes. Session evidence and import history belong
in the [handover status](../handover/R6-T6-performance-tiers.md#status).
