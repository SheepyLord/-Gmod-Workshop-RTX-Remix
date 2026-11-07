# R21-C: the GPU timeout at a map's first ray-traced frames at 3840x2160

Worktree `out/worktrees/r21-device-loss`, branch `r21-device-loss`, from `main`. Implementer: Codex
(gpt-6.1-sol). ADR number if a decision is needed: **0128**. Read first:
[R21-plan.md](R21-plan.md) ("Rules for every task" apply to you, with the changes below),
[AGENTS.md](../../AGENTS.md), `tools/poc_session.py.md`, the 4K parts of
[R20-A-report.md](R20-A-report.md) and [R20-Q-report.md](R20-Q-report.md) (device losses and the
follow-up 4K runs), `docs/RESEARCH.md` sections on device loss (search `DEVICE_LOST`).

## The user's words

> The active Gmod session, when I removed everything to simulate for a fresh install, is now stuck on
> map load. Investigate the cause.

and, after Claude's first findings below: "Yes, reproduce it" (reproduce at 4K in the PoC with
Aftermath to find the failing GPU pass).

## What is known (Claude's investigation, 2026-11-06)

Evidence copied to `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\field-stuck-20261106\` (the
loader's log, `last_gpu_crash.json`, `remix-dxvk.log`, `memory.csv`, `state.json`).

- The field (3840x2160, RTX 5090, driver 32.0.16.1742) started 22:57:15 local with everything the
  loader deploys removed and no `rtx.conf`/`user.conf`: the loader redeployed in 35 s and activated the
  published package `0.0.0-dev.20261107011558+809ceec2` (Workshop item 3829070317 as of R21). The map
  was **gm_poolrooms** (from `garrysmod/data/rtx_water/originals.json`), with the user's content
  packages (`rtx-remix/mods/gm_poolrooms_rtx`, `modern_house_rtx`) and add-ons.
- `remix-dxvk.log`: 22:59:41.785 Opacity Micromap enabled; 22:59:41.876 NRC context initialized;
  22:59:42.157 "Integrate Indirect Mode: Neural Radiance Cache - activated"; 22:59:44.751 "[RTX Opacity
  Micromap] Instance requires more texel taps to resolve opacity than allowed"; 22:59:50.285
  `DxvkSubmissionQueue: Command submission failed: VK_ERROR_DEVICE_LOST` (frame 4529, about 6.5 GB of
  32 GB device-local in use, reason "queue submission"). Windows: nvlddmkm event 153 at 22:59:45 and
  22:59:47; this machine's WER LiveKernelEvents for these are code 141 (video engine timeout, a TDR).
  Remix then showed its "RTX Remix Crash Report" GPU-crash prompt (`util_sentry.cpp`
  `promptGpuCrashConsent`), which held the game on the loading screen.
- **Two earlier identical losses**, R20-A's open item: 2026-11-06 03:51 and 03:54 in the PoC at 3840x2160
  with an older package (`out/worktrees/r20-menu/out/r20a/post-test-trees/native-loader/logs/sessions/
  2026-11-06T105147.581Z-52300-device_lost` and `...105434.943Z-68860-device_lost`): in both, NRC
  activated, then the GPU error within 1-3 s (once right after an Opacity Micromap message), then
  `VK_ERROR_DEVICE_LOST`. R20-Q's four later 4K gm_construct loads and R20-F's field checks had none.
  nvlddmkm logged 74 such errors on this machine in 14 days.
- Ruled out: memory (6.5 GB of 32 GB), the fresh deployment (it completed and activated), R21's changes
  (the runtime `d3d9.dll` is unchanged since R20, and the earlier losses ran an older package).
- Leads, not proven: (1) Opacity Micromap baking on the first frames; (2) NRC's first frames;
  (3) the package defaults that a fresh install runs instead of the user's old `rtx.conf`
  (`out/worktrees/r20-field/out/r20f/before/rtx.conf` had `rtx.volumetrics.enableAtmosphere = False`,
  `rtx.atmosphere.cloudVoxelShadowsEnable = True` and other sky values; the package's
  `config/dxvk/01_classic_remix_defaults.conf` has the atmosphere on); (4) 4K itself; (5) the map's
  content (gm_poolrooms: large water and alpha surfaces) or the user's characters restored at map start.

## What to do

1. **Reproduce in the PoC at 3840x2160**, as close to the field's failing start as the PoC allows: the
   same package (`out/workshop/gmod-rtx-remix-0.0.0-dev.20261107011558_809ceec2.gma`, the uploaded
   build), a fresh loader deployment, no `rtx.conf`/`user.conf`, gm_poolrooms (the PoC sees the
   account's Workshop subscriptions; copy what else the field's start needs read-only from the field,
   for example the `gm_poolrooms_rtx` add-on), RTX on, from the main menu to the map like a player.
   Turn on **Aftermath** for these runs (`dxvk.enableAftermath = True` in a PoC `dxvk.conf` you add and
   remove; dumps are `<exe>_..._aftermath.nv-gpudmp`, see `src/dxvk/dxvk_instance.cpp:359` in the
   runtime source at `out/worktrees/r17/out/runtime-src`). The failure is intermittent: repeat cold
   starts until you have losses or a clear count without (decide a bound such as 15 loads, record it).
2. **Read the dumps.** The runtime ships `GFSDK_Aftermath_Lib.x64.dll`; its GPU crash dump decoder API
   (`GFSDK_Aftermath_GpuCrashDump_CreateDecoder`, `..._GenerateJSON`) gives the device state, active
   shaders and any page fault. Build a small decoder under `tools/` (with its `.md`) if none exists;
   map active shader hashes to Remix passes where you can.
3. **A/B the leads** one at a time with the same count: Opacity Micromaps off
   (`rtx.opacityMicromap.enable = False`), NRC off (`rtx.integrateIndirectMode = 1`), the volumetric
   atmosphere off, 1600x900 instead of 4K, and gm_construct instead of gm_poolrooms, as far as the
   evidence needs. Stop when the cause is clear.
4. **Fix it if a safe fix exists** (a runtime patch under `runtime/patches`, recorded as
   `pending_patches` in `runtime/base.json` and built and imported once; or a package default), with a
   test where one is possible, evidence that the losses stop at the same count, and ADR 0128. If the
   cause is the driver or the hardware, say so with the evidence and propose the mitigation instead of
   changing anything.
5. **The prompt that looks like a hang.** The GPU-crash prompt kept the field on a frozen loading
   screen; the user reported it as stuck. Find out whether the prompt was visible over the 4K
   borderless window (it is `MB_TOPMOST` but has no owner and no `MB_SETFOREGROUND`), and if it is not,
   propose the smallest change that makes a GPU crash obvious to the player.

## Rules beyond R21-plan's

- **Never change Windows' TDR settings or any other system setting**, even to test: report what a
  change would show instead.
- A GPU timeout resets the display driver for the whole machine. Before each 4K run, check that no field
  game (`H:\SteamLibrary\steamapps\common\GarrysMod\bin\win64\gmod.exe`) is running. The user allows
  ending a field game a test needs (console quit first); do it only if one blocks you, and record it.
  Never launch the field game; read the field only.
- The Remix crash prompt: `tools/poc_session.py` declines it (never set
  `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES`). Keep each lost session's logs and dumps under your
  worktree's `out\r21c\`.
- H: has about 265 GB free: delete PoC snapshot copies once a restoration is verified.
- Finish with `docs/handover/R21-C-report.md` (what failed, how often in which configuration, what the
  dumps show, the cause or the best-supported lead, the fix or the proposal) and
  `tools\test.ps1 -Config Release` passing if you changed code. Commit as SheepyLord
  `<37598021+SheepyLord@users.noreply.github.com>` with the trailer
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`. Do not merge, push or publish.
