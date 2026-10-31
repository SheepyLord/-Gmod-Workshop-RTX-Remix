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
| `pathMaxBounces` | 12 | 8 | 4 | Bound long query paths; may reduce multi-bounce reflection/transmission quality |
| `neuralRadianceCache.qualityPreset` | 2 (Ultra) | 1 (High) | 0 (Medium) | Fewer training records and bounces, coarser cache; less responsive/detailed indirect light |
| `skyProbeSide` | 2048 | 1024 | 1024 | Probe storage 96 to 24 MiB: 72 MiB less |
| `volumetrics.froxelGridResolutionScale` | 4 | 8 | 8 | About a quarter of the XY froxels; preserve 48 depth slices; coarser fog |
| `opacityMicromap.cache.maxBudgetSizeMB` | 1536 | 1024 | 512 | Upper bounds, not actual allocation; smaller OMM caches may slow alpha-heavy scenes |
| `opacityMicromap.cache.minFreeVidmemMBToNotAllocate` | 512 | 1024 | 1024 | Stop growth earlier; does not reclaim already allocated micromaps |
| `terrainBaker.cascadeMap.levelResolution` | 4096 | 2048 | 2048 | Quarter-sized atlas when terrain baking runs; coarser terrain materials |
| `lowMemoryGpu` | False | unchanged | True | Skip the largest streamed replacement mip and request lower-memory acceleration structures |
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

## PoC measurements pending

Evidence is in this worktree's ignored `out/t6-evidence/`. On 2026-10-31, the high/gm_construct
baseline launched through `tools/poc_session.py` at 22:27:49 UTC. The new package deployed and the
runtime initialized (`remix-main+6f2dbd79`, RTX 5090), but the game stopped at:

> Failed to initialize Steamworks API. Could not determine Steam client install directory.
> Make sure Steam is running and is up to date!

Captured in `startup-error-full.png`. The run's `session.json` records `map_loaded: false`, no
console window, no FPS sample, exit 1. The owned blocked process was terminated with the harness's
creation-time-checked `terminate` helper; no other game process was ended. Steam settings, the field
install and every `user.conf` remained untouched. Further launches were stopped rather than
changing Steam configuration to work around this execution context.

Restoration: 2,808 files in the PoC's pre-existing loader/runtime, add-on, data and settings trees
were copied and hash-checked before the session, then restored and hash-checked afterwards. The
standard snapshot rollback also restored the bootstrap, root files/configs and shared settings:
`snapshot/rollback.json` reports `clean: true`, with all 2,877 depot files matching. The prior
allowlist, deployment generation and data are back; the attempted session's changed trees are kept
under `out/t6-evidence/trees-after/`, not deleted. No root `rtx.conf` was added for the high baseline.

On resuming as the user, Steam is running and the earlier sandbox limitation no longer applies.
The field game is also running (PID 24620). T6's explicit one-game-at-a-time rule prevents a PoC
launch, and its field-install prohibition prevents closing that session. The user was asked to
quit it normally; no PoC files have been changed by this resumed attempt. The benchmark probe
and new backup helper are prepared under `out/t6-live/`, and the offline checks now pass.

**No frame-time, VRAM, visual or stability result is claimed.** The six required map/tier runs,
night-sky comparison and 8 GB hardware validation remain open. The offline size arithmetic above
is not a substitute. Resume the [T6 brief](../handover/R6-T6-performance-tiers.md#3-measure-poc)
in a process that can use the running Steam client. Until T1 is available, temporarily place the
tier's lines in the PoC root `rtx.conf`, restoring it after each run. Use identical cameras,
1280 × 720 output, ReShade off, 60 s settling, `--fps 30`, `fps_max 0` and
`engine_no_focus_sleep 0`; sample `rtx_vram_stats` after settling as well as before quitting. On
modern_house mount 3495468649 and change map as in the brief. Compare high/low night skies at
normal and zoomed FOV, changing only the resolution for the sky-only comparison. Record warm
repeats: a single shader-cold frame-time sample is insufficient. Revisit the candidate bounce/NRC
choices if lighting degrades or gains are within run-to-run noise.

## Reproduction and offline validation

All staged sources were under this worktree's `out/t6-stage/`. The exact import was:

```powershell
python tools/inputs.py import runtime --file out/t6-stage/layers/medium.conf=layers/medium.conf --file out/t6-stage/layers/low.conf=layers/low.conf --file out/t6-stage/atmosphere/stars_4096.dds=files/atmosphere/stars_4096.dds --file out/t6-stage/atmosphere/galaxy_4096.dds=files/atmosphere/galaxy_4096.dds --file out/t6-stage/atmosphere/nebula_4096.dds=files/atmosphere/nebula_4096.dds
```

Each sky source was made with `python tools/sky/drop_top_mip.py
out/inputs/runtime/files/atmosphere/<name>.dds out/t6-stage/atmosphere/<name>_4096.dds`.
`inputs.py verify --deep` checks all ten parts. The combined package build regenerates and hashes
its file list and is validated by the worktree's Release `nlctl.exe`. Automated coverage and the
remaining acceptance checks are in [TESTING.md](../TESTING.md#r6-t6-performance-tier-payloads).

Validation after resuming as the user: the required `tools\test.ps1 -Config Release` passes
(conventions, 23/23 CTests and Python groups of 28/25/287 tests, two expected skips). This includes
all 19 focused DDS/packager tests. The combined package build with `--require-nlctl` passes;
deep verification reports ten parts and zero problems. Logs are `out/t6-release-resumed.log`,
`out/t6-package-resumed.log` and `out/t6-inputs-resumed.log`. The earlier sandbox registry/Git
failures in `out/t6-release-tests.log` are superseded. Git commits can now be created normally;
no registry policy, ACL or global Git settings were changed. Game measurements remain required.
