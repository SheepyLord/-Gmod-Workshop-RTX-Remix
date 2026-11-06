# R20 report: the user's report of 2026-11-06 (items 44-51)

Claude was the project manager and reviewer; Codex (gpt-6.1-sol, reasoning effort max, priority
tier, as the user asked) wrote the code in five tasks and ran the integration QA in a sixth.
[Plan](R20-plan.md) (with the user's words) and the task reports: [R20-A](R20-A-report.md),
[R20-B](R20-B-report.md), [R20-C](R20-C-report.md), [R20-D](R20-D-report.md), [R20-E](R20-E-report.md),
[R20-Q](R20-Q-report.md). Loader **0.15.0**; integrated on `r20-int` in `out/worktrees/r20`.

## What the user asked for, and what was built

| Item | Built | Decisions |
|---|---|---|
| 44 vanilla particle and decal add-ons (Physics Blood) | The companion observes the textures Lua particles, sprites, beams and decals draw and tags them for the session only (NoSave runtime categories joined with the player's saved ones); runtime patches 0034 and 0035 keep effect colours, draw offscreen alpha canvases natively and translate premultiplied transmission filters, so Physics Blood's pools, flows and stains render without black rectangles. No add-on registers anything | [0121](../decisions/0121-source-effect-categories-for-the-session.md), [0122](../decisions/0122-raster-canvases-keep-their-native-draws.md) |
| 45 a hint to turn on upscaling or frame generation | A sandbox-style hint once per game start, after the map is unobstructed, naming what is off and where to turn it on (only what the GPU supports; `cl_showhints 0` and an RTX tab checkbox turn it off). It reads the runtime's live effective state: patch 0040 publishes it, the fixes' module returns it as `RemixConfig.GetUpscalingState()` | [0117](../decisions/0117-startup-upscaling-hint-and-sky-defaults.md), [0123](../decisions/0123-live-upscaling-readback.md) |
| 46 remind players to update an outdated loader | The package records the newest released loader (`companion/nativeloader/resource/loader-release.json`, set by hand after a GitHub release). Loader 0.15.0 shows a window on the main menu when the record is newer (download page, Later, Don't remind me about this version); loaders before 0.15.0 get the same reminder in game from the companion. Only the RTX package's own unchanged record counts | [0115](../decisions/0115-released-loader-record-and-reminders.md) |
| 48 Dynamic Toolgun Screen and Blood Overhaul in the package, settings in the RTX tab, realistic blood impacts | Two new parts, `toolgun-screen` and `blood-overhaul-rtx` (only what this project made: the eighteen generated patterns, their PBR, the user's Lua and colour schemes; none of Crunchy's files or anything derived from them, his add-on credited and optional). Their settings are in RTX Remix / Rendering and RTX Remix / Blood. A client blood impact effect for bullet hits on NPCs, players and ragdolls (back spatter, forward spray, mist, droplets that stain floors and walls), with hard budgets; off gives the stock effect | [0118](../decisions/0118-bundled-toolgun-screen-and-owned-blood-patterns.md), [0119](../decisions/0119-client-blood-impacts-with-bounded-spatter.md) |
| 49 time passes by default, a 20-minute day | New defaults; players who still had the old ones (time stopped, 30 minutes) get the new ones once | [0117](../decisions/0117-startup-upscaling-hint-and-sky-defaults.md) |
| 50 a warning before the server browser | Loader 0.15.0 shows it on every way into the server browser, in the main and the pause menu: servers may forbid Remix and ReShade, no guarantee of performance or stability (especially without the map's PBR resources), no responsibility taken. I understand, continue / Back; "Don't show this again" is remembered | [0116](../decisions/0116-multiplayer-entry-warning.md) |
| 51 `cam.End underflow` when saving a dupe | The companion's guard now tracks `cam.End` and every camera closer per its native mode, so the stock icon's 32 camera pairs per prop no longer exhaust its stack; the saved icon is readable and coloured | [0120](../decisions/0120-camera-closers-share-the-guards-stack.md), 0122 |

The repository was renamed to https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix (public); 206
links were updated, and runtime patch 0034 carries the renamed fallback link of patch 0012.

## How it was run

Five Codex tasks in parallel worktrees (A loader and menus, B companion QoL, C blood and toolgun,
D rendering compatibility), then E, added when B found Lua could not read the runtime's live
settings. Claude reviewed every commit as it landed, merged the branches on `r20-int` (rebuilding
the translation catalogs from the merged Lua with every branch's translations: 507 companion texts,
all six languages complete), reset commit authors to the user's noreply identity, and built the
runtime once with all R20 patches. D's own runtime import and a first combined import (built before
QA found the readiness bug) were taken out of the history before any push, so only one new
`d3d9.dll` (SHA-256 `00124bf6...`, 58.5 MB compressed) enters Git LFS this round.

Integration QA (R20-Q) refreshed the PoC to the field's GMod build 26439081 (46 depot files that
Steam's update had changed), built the merged package and loader 0.15.0, and tested every item.
It found two defects, both fixed:

- **Patch 0040's readiness was starved by the sky**: every option write invalidated it, and the sky
  writes about 50 a second. R20-E scoped invalidation to the 19 options the state depends on; with
  the sky running, 3,514 of 3,515 reads were ready (the one pending read was a real change).
- **A stale RTX multiplayer bootstrap** in the package inputs: `gmsv_nlrtxclient_win64.dll` was the
  R4 build, which rejects R6's `remix.performance_tier`. Local builds (and so development uploads)
  shipped it; release builds on GitHub compile it from source. Rebuilt and imported once.

Final QA results (all in the PoC, RTX on, 1600x900 unless noted; evidence under
`out/worktrees/r20-qa/out/r20q/afterfix/`): the hint matrix (both off, upscaling off, frame
generation off, both on, `cl_showhints 0`, the checkbox off); wall and floor stains; the dynamic
toolgun screen sharp under DLSS; the menu reminder, its choices and the in-game fallback in English
and Simplified Chinese; the multiplayer warning from both menus, remembered across restarts; dupe
icons; Physics Blood and two other effect add-ons; four 3840x2160 RTX loads of the new and the
v0.14.0 package without device loss. `tools\test.ps1 -Config Release` passes on the integrated
branch: 27 native tests, 710 Python tests.

## Open items and follow-ups

- **The darker stock ragdoll blood cloud under RTX** (Client Ragdoll Blood's `blood_impact_red_01`):
  shapes and fades are right, colour and intensity are not equal to D3D9. A renderer review item.
- **R20-A's two 4K device losses** happened on the older PoC build with the v0.14.0-era package and
  were not reproduced in four later 4K loads; their cause is not isolated.
- **The Model Hotloader's compatibility notice**: its native release lists tested engine hashes that
  predate GMod build 26439081 (Steam's update of 2026-11-05), so it shows a notice and runs anyway.
  Validating its natives on the new build and regenerating that evidence is a task of its own.
- **Modules built from this repository** (`repository_builds` in `tools/ci/pins.json`) have no record
  tying the stored input to its source, unlike the runtime's `base.json` `packaged`; nothing caught
  the stale bootstrap. A check like the runtime's would.
- **Release**: tag v0.15.0 (the GitHub release carries the loader), then set the loader record to
  0.15.0 and push `main`, then the package workflow's build to the Workshop (the user approved both
  on 2026-11-06 for this release).
