# R20-F: published-package field QA

Branch `r20-field`, from `8332e03`; [brief](R20-F-field-qa.md), [shared plan](R20-plan.md).
**Field sign-off withheld: the live toolgun display is nearly black in the actual field profile.**
Live QA stopped at the brief's failure boundary. Only this report is committed; scratch drivers
and evidence stay under this worktree's `out/r20f/`. No product code or package input changed.

## Baseline and decisions

The task-specific field-launch permission supersedes the shared plan's earlier PoC-only launch
rule. The existing game, Workshop content and standalone add-ons are exercised in place. No
loader installation, loader-config replacement, graphics-option change or publication is performed.

The field has the actual release loader **0.14.0**, SHA-256
`256f245fbb6dde4b2b41cba070c1a4fcc4a88110865941ce781ea065cad40e5b`, matching R19's
release receipt and its previous `status.json`. Its `bootstrap-install.json` still says 0.13.0;
that stale receipt is recorded, not rewritten. The published receipt names
**`0.0.0-dev.20261106164627+a3df3af8`**, 1,955,100,507 bytes, archive SHA-256
`71aa0745f72da9ff6e69e14834c8c3d41cfe85d006406593974ea4f6a31c72a3`.
Steam initially had the older `20261106004558_ad5cf8e8` archive. The first start downloaded R20
while running that older deployment; the second start deployed the published version, generation
**66**, with **567** changes and no skipped package or status error. The downloaded archive's
full hash matches the publication receipt. Its inventory is **1,459 files**, including **54**
native binaries. The deployed runtime's SHA-256 is
`00124bf6009ee6acb2b2ffbc64d8a724aeb0ed700fa88b0dc4dbb7a8720b05a1`, the final Q runtime.

No `gmod.exe` or shared PoC lock was present at baseline. Field settings, the loader and watched
files were copied and hash-checked into `out/r20f/before/`; the registry was exported read-only.
The standalone Dynamic Toolgun Screen and Blood Overhaul contain **34** and **267** files,
respectively, indexed by SHA-256. Each game start held the shared lock exclusively to prevent a
PoC lab from ending this field test; the PoC itself was untouched. Holds were **2.20** and **2.81**
minutes. Both games and their helpers ended normally; the lock was released after each.
No pre-existing game was ended and no user console history was read: session logs are only the
bytes appended after each driver's saved offset.

## Checks

Evidence paths below are relative to this worktree's `out/r20f/`.

| Item | Result | Evidence |
|---|---|---|
| Steam depot files, before and after | **Pass.** Both verify **2,877 files / 7,282,813,551 bytes**, zero missing, size/hash, reparse or unverified failures. Only the same permitted `autoexec.cfg` user-config difference. | `verify-{before,after}.json`, `verify-{before,after}.log` |
| Loader / published deployment / RTX / status | **Pass.** Actual release loader 0.14.0; second start activates the exact published R20 runtime. All **207** payload files match the archive. **1,159** root files match; the **92** differences are inventoried separately below. Zero status errors and zero Lua errors in either session. | `before.json`, `published.json`, `downloaded-package.json`, `downloaded-SHA256SUMS.txt`, `deployed-package.json`, `session.json`, `02-published-ui/{status.json,loader.log,modules.json,console.log}` |
| 45 startup hint, real live settings | **Pass for this profile.** Real effective **1/1**, DLSS and DLSS-G on, all three capability flags true; **457 ready / 0 pending** reads while the sky runs. Saved **`cl_showhints=0`** is respected: no observed hint, with the process-specific marker consumed. Neither Remix settings nor hint preferences were changed; feature-off cases are Q's evidence, not a new field claim. | `02-published-ui/console.log`: `R20F_FIELD_START`, `R20F_FIELD_FINAL`; `shot-01-field_actual_settings.png` |
| 49 sky time / retained day length | **Pass.** Field already chose **1/20**; marker says `kept player settings`. The clock advances **20.267500 to 21.181679 hours in 45.713974 seconds**, approximately **1.2 game hours/minute**, a 20-minute day. No forced migration or time change. | `02-published-ui/console.log`: `R20F_FIELD_FINAL`; `before/garrysmod/cfg/client.vdf`, `audit.json` |
| 48 unique RTX panels with both standalone copies | **Pass.** Exactly **one** `bloodoverhaul_settings` under RTX Remix / Blood and **one** `dynamic_toolgun_screen` under RTX Remix / Rendering; zero `dts_settings` shortcuts. Bundled blood reports `packaged=true`. | `02-published-ui/console.log`: `R20F_PANELS`; `shot-02-rtx_blood_panel.png`, `shot-03-rtx_toolgun_panel.png` |
| 48 live upscaled toolgun display | **Failed visual acceptance; live updates pass.** Real ready 1/1, **512x512** `dtscreen_screen512`; screen frame **5,130 to 5,416** between captures, with **464 captures / 232 redraws** at the first status check and no recorded screen error. Nevertheless both world-display captures are nearly black and their text is difficult to read. | `02-published-ui/shot-04-live_toolgun_first.png`, `shot-05-live_toolgun_second.png`, `console.log`: `R20F_SCREEN_BEFORE`, `R20F_SCREEN_AFTER`, toolgun status |
| 48 citizen/ragdoll pistol/shotgun impacts; floor/wall stains | **Not run after stop.** No field combat or stain acceptance claimed. | `live_ui.lua` is the executed probe; `combat_server.lua` was prepared but never delivered or run |
| 44 Physics Blood coexistence | **Startup coexistence passes; pools/flows visual check open.** Actual ABL **1.0.0**, HGC **0.1.0**, core active/loaded, and packaged impacts enabled together, with zero Lua errors. The empty initial **0 pools / 0 droplets** is not a visual-effects test. | `02-published-ui/console.log`: `R20F_FIELD_START` and Physics Blood initialization lines; `session.json` |
| 51 stock two-prop dupe / icon | **Not run after stop.** No stock save or icon acceptance claimed. No test dupe was created. | `audit.json`: unchanged dupe listing |
| 3840x2160 stability / heaviest-scene frame time | **Bounded startup/UI stability passes; heavy-scene timing open.** Both maps loaded at actual 3840x2160 and quit normally, no device-loss/allocation-failure markers or new crash dump recorded. No heavy effect scene or frame-time distribution was sampled. The screen's FPS readout/overlay is not used as a substitute. | `session.json`, both sessions' `remix-dxvk.log`, native-size screenshot hashes in `audit.json` |
| Settings / standalone preservation | **Pass.** See audit below. | `audit.json`, `final-state.json`, `01-download-receipt.json`, `02-published-ui-receipt.json`, `before/`, `after-registry.reg` |
| Release repository gate | **Both initial and final `tools/test.ps1 -Config Release` pass, exit 0**, ending `All checks passed.` Each runs 27 CTests and **710 Python tests** (655 tools, 29 gmapack, 26 Steam; two existing optional-environment skips). | `release-initial.log`, `release-final.log`, `release-final-summary.json` |

`acceptance.json` indexes the screenshots with their native dimensions and SHA-256, verifies the
recorded functional/preservation assertions, and explicitly records **`field_signoff: false`**.

## Stop finding and the difference from Q

The executed probe only opened the existing panels, selected the toolgun and held its existing
inspect action. It made **no `RemixConfig.SetConfigVariable` call**, no sky/profile edit and no
layout/theme switch. The saved screen preferences are already **`dts_backlight=1`**,
**`dts_bg_dim=0`**, **`dts_enabled=1`**, **`dts_resolution=512`** and
**`nativeloader_toolgun_screen=1`**, Pocket PC / `winmobile`; the active tool is Duplicator.
Those preferences remained unchanged. The two native-size pictures show the scrolling bottom
hint moving, consistent with the advancing screen frame counter. They also show the central
display and most of its text nearly black, while the frame and surrounding world remain visible.
The RTX panel's preview is readable. Low brightness is the visual rejection; this does not prove
an upscaling blur or stale-render-target defect.

Q's accepted toolgun view used a **fixed daytime** scene and explicitly set backlight 1 / dim 0.
This field profile starts at its retained **19.370001-hour** setting and naturally advances into
night; observed clock values span approximately 20.27-21.18. It also retains the user's actual
Remix settings, mods and hundreds of other mounted add-ons. The changed conditions matter:
Q's daylight result does not establish readability here. The cause has **not** been isolated
between scene lighting, retained replacements/settings, or the rendering/screen implementation.
No graphical option, material, standalone file or packaged code was changed to improve the view.

The brief explicitly says: **"if something is broken, record the evidence and stop: report it rather
than fixing it in this task."** The second session had already quit normally when its native-size
captures were inspected. No further field start followed. Combat, Physics Blood pools/flows,
dupe saving and heavy-scene timing remain unexecuted for that reason. The generic release-record
checks pass for both runs; they do not override this visual failure.

## Restoration and package differences

`audit.json` records unchanged hashes for `user.conf`, `rtx.conf`, the loader DLL/PDB, its config
and install receipt. `final-state.json` additionally verifies their original modification times
and the restored client.vdf timestamp. The registry exports match byte for byte. Both normal quits report
`settings_back=restored`; config.cfg, client.vdf and server.vdf have **zero changed, added or
removed setting values**. The explicitly authorized client.vdf backup was restored byte for byte
after each quit. The game-created sky-migration and startup-hint markers were retained as normal
companion state; they are listed as new watched files rather than silently called unchanged.

All **34 + 267** standalone files retain their original hashes. Dupe and game-screenshot listings
have zero additions, removals or changes. All six captured PNGs are in the worktree's evidence
folder, so no generated test item required removal. No Steam depot file, Steam setting, launch
option or `user.conf` was written by this task. The game/loader itself performed its normal
Workshop download, journaled deployment and normal session writes. There is no remaining game
or task lock. No push, merge, tag, upload or workflow was performed.

The archive/root comparison is **not** reported as complete root-byte equality: **85** differences
are under the field's `rtx-remix/mods/~gmod_topbr`, and **seven** are the existing translated
startup-message files. `deployment-differences.json` records every archive/current hash and its
manifest ownership policy: **all 92 are create-only**. The loader explicitly notes preservation of
the changed create-only `materials.usda` and existing `topbr_generation.txt`. The actual runtime payload is exact.
These retained field differences are relevant context for a later controlled screen diagnosis;
this task does not replace them or assert they caused the problem.

Both runtime logs also contain **69** other `err:` lines, including missing/corrupt Poolday texture
assets, already present in the first, older-package session. They are retained and counted in
`audit.json`; "no status error" and "no device loss" do not mean an entirely error-free runtime
log. The guard reports early installation, zero errors/cleanup errors and one blocked entry;
that entry's identity was not collected, so a fully empty guard-block list is not claimed.

## Open

The owning screen/rendering task should diagnose the unreadable night display with the retained
field profile and replacements. After review/fix, repeat that view and complete the unrun field
combat/stain, Physics Blood pool/flow, stock-dupe/icon and heavy-scene timing checks. Full field
acceptance is **open**, despite passing repository checks and clean shutdowns. Q's darker stock
ragdoll cloud and unisolated historical 4K cause also remain its documented review items; neither
was retested or resolved here.
