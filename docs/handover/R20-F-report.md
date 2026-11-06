# R20-F: published-package field QA

**Current result: the follow-up field checks pass; loader 0.15.0 remains installed.**
The initial stop below is historical. The authorized follow-up is recorded in
[After the toolgun fix and the 0.15.0 loader](#after-the-toolgun-fix-and-the-0150-loader).

Branch `r20-field`, from `8332e03`; [brief](R20-F-field-qa.md), [shared plan](R20-plan.md).
**Initial field sign-off was withheld: the live toolgun display was nearly black in the actual field profile.**
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

## Open at the initial stop

The owning screen/rendering task should diagnose the unreadable night display with the retained
field profile and replacements. After review/fix, repeat that view and complete the unrun field
combat/stain, Physics Blood pool/flow, stock-dupe/icon and heavy-scene timing checks. Full field
acceptance is **open**, despite passing repository checks and clean shutdowns. Q's darker stock
ragdoll cloud and unisolated historical 4K cause also remain its documented review items; neither
was retested or resolved here.

## After the toolgun fix and the 0.15.0 loader

**The requested follow-up field checks pass. Loader 0.15.0 is left installed.**
The original night-screen rejection above is resolved in the real field view.

Resumed on `r20-field` at **`e94aba0`**, after the manager published [R20-T](R20-T-report.md) and
the real 0.15.0 release record. The follow-up authorizes replacing **only** the field DLL after
the old-loader checks, retaining the new loader. Evidence is under this worktree's
**`out/r20f/afterfix/`**, with the release ZIP/candidate under `out/r20f/release/`.

The new publication is **`0.0.0-dev.20261106175032+169e5e26`**, **1,955,100,824 bytes**,
SHA-256 **`eaeffd3a26f56bc245e0e9de42ebc4d36ba6d8250ec75e6b172a6360aef30efe`**.
Steam fetched it during the first start; the accepted old-loader process deployed **generation
67** and activated it with **loader 0.14.0**. The runtime remains the exact R20 final binary
`00124bf6009ee6acb2b2ffbc64d8a724aeb0ed700fa88b0dc4dbb7a8720b05a1`.
The actual deployed `garrysmod/addons/nativeloader/resource/loader-release.json` says **0.15.0**
and names the real release URL. `deployment-verified.json` and `downloaded-package.json` retain
these checks.

| Follow-up check | Result | Evidence under out/r20f/afterfix |
|---|---|---|
| Before: Steam files, settings, standalone add-ons and dismissal preferences | **Pass.** Fresh independent backup/inventory and depot verification; no existing loader-update ignore file or either menu dismissal cookie. | `before.json`, `before/`, `verify-before.json`, `preferences-before.json` |
| Published package / actual runtime / release record | **Pass.** Exact downloaded archive hash, new deployed version and unchanged final runtime; real 0.15.0 record. | `published.json`, `downloaded-package.json`, `deployment-verified.json`, `04-reminder-night/status.json` |
| 0.14.0 companion reminder | **Pass in the accepted map session.** One actual reminder, current/latest 0.14.0/0.15.0, one observed **Later** click; no ignore preference written. | `04-reminder-night/shot-01-update_reminder_014.png`, `console.log`: `R20F2_REMINDER_*`, `R20F2_LATER_CLICK` |
| Toolgun at the retained field night | **Pass.** Bright, readable, live 512x512 display in the same inspect view, real ready DLSS/DLSS-G 1/1; frames **2,293 to 2,593**, backlight 1 / dim 0, clock approximately **20.54-20.66**. No corner-preview draw, brightness gain or graphics/sky change. | `04-reminder-night/shot-02-fixed_night_toolgun_first.png`, `shot-03-fixed_night_toolgun_second.png`, `console.log`; `04-reminder-night-receipt.json` |
| Citizen/ragdoll pistol and shotgun | **Pass for actual weapon/effect dispatch.** Clean pistol/shotgun citizen hits and ragdoll pistol hit; the first ragdoll shotgun spread missed and is excluded. A closer stock-shotgun repeat records actual ragdoll pellet hits and **seven** ragdoll impact events / **140** particle admissions. No getter/effect stub or simulated status. | `05b-effects-clean/shot-04-citizen_pistol.png` through `shot-06-ragdoll_pistol.png`, `console.log`: `R20F_BULLET`, `R20F2_HIT_*`; `05c-ragdoll-shotgun/shot-02-ragdoll_shotgun_close.png`, `R20F2_SG_AIM`, `R20F2_SG_PELLET`, `R20F2_SG_FINAL` |
| Floor/wall stains and Physics Blood coexistence | **Pass for the exercised scene.** Visible world stains and pools/body flow together with packaged impacts. **55 wall / 329 floor** decal calls, zero landing trace misses; up to **420 droplets / 28 pools**, active body flow. Clean guard and zero Lua errors. No D3D9 colour/intensity parity claimed. | `05b-effects-clean/shot-02-physics_pools_droplets.png`, `shot-03-physics_bodyflow.png`, `shot-08-wall_stains.png`, `shot-09-floor_stains.png`; `R20F2_COMBAT_FINAL`, `controlled_flow.lua` |
| Stock two-prop dupe / icon and cleanup | **Pass.** Actual stock copy/save of a drum and crate joined by one weld, readable coloured **512x512** JPEG, no `cam.End underflow`. Accepted clean run plus the earlier probe-correction run each generated one pair; both pairs were hash-checked into evidence and removed from the field. | `05b-effects-clean/dupes/`, `shot-10-stock_dupe_saved.png`, `console.log`: `R20F_DUPE_COPY`, `R20F2_DUPE_BYTES`, `R20F2_DUPE_SAVED`; both `*-dupe-cleanup.json` receipts |
| Heaviest combined scene at 3840x2160 | **Pass for this bounded stress.** **493 frames / 10.011967 s**, median **19.8082 ms**, p99 **38.2395 ms**, maximum **47.2586 ms**, mean **49.2411 rendered FPS**; real ready DLSS/DLSS-G 1/1, normal timescale 1.0. No device loss/allocation-failure marker, Lua error or guard/cleanup error in the accepted run. | `05b-effects-clean/shot-11-heavy_combined_scene.png`, `console.log`: `R20F2_HEAVY`; `remix-dxvk.log`, `old-loader-acceptance.json` |
| Verified release ZIP and installed DLL | **Pass.** ZIP SHA-256 matches GitHub's release-asset digest. Installed DLL is **1,662,464 bytes**, SHA-256 `0999cd017515a37de8ec86112f104f54ad8761baf766a13a4b13fc9f6c2d8418`. Old DLL/PDB are backed up; only the DLL was copied. | `release-metadata.json`, `release-verification.json`, `loader-installed.json`; ZIP in `../release/`, backups in `../before-loader/bin/win64/` |
| 0.15.0 main menu / warning | **Pass.** No update window; Find Multiplayer Game opens the actual warning; **Back** returns home. No checkbox or Continue action. | `06-loader015-ui/main_menu_clear_no_update.png`, `main_multiplayer_warning.png`, `main_back_home.png`, inbox receipts |
| 0.15.0 pause warning / no in-game reminder / status | **Pass.** Pause-menu Find Multiplayer Game opens the warning; **Back** returns to the pause home page. No dismissal/Continue action. Zero update frames during the 30-second in-game observation and at the final check; old-loader seen marker stays on the prior process's token. Status says **0.15.0 / active / no errors**. RTX tab still has one Blood panel and one Dynamic Toolgun Screen panel, zero old shortcuts. | `06-loader015-ui/pause_home.png`, `pause_multiplayer_warning.png`, `pause_back_home.png`, `shot-01-loader015_no_ingame_reminder.png`, `console.log`: `R20F2_LOADER015_*`; `ui-observations.json`, `preferences-after.json` |
| Final preservation/depot audit | **Pass.** Before/after **2,877 files / 7,282,813,551 bytes**, only the permitted unchanged `autoexec.cfg` difference. Settings and registry preserved, all 301 standalone file hashes unchanged, no generated dupe/screenshot file remains in the field. Only the authorized loader DLL changes among protected files. | `verify-{before,after}.json`, `audit.json`, `acceptance.json`, `preferences-after.json`, `before/`, both `*-dupe-cleanup.json` |
| Release gate | **Both initial and final `tools/test.ps1 -Config Release` pass, exit 0**, ending `All checks passed.` Each runs **27 CTests / 710 Python tests** (655 tools, 29 gmapack, 26 Steam; two existing optional-environment skips). Final documentation and whitespace checks also pass. | `release-initial.log`, `release-final.log`, `release-final-summary.json` |

The ZIP digest supplied by GitHub is
**`7f0258207d82aa754a941614b592eeaff1d3a815dd8b58c760ef01fa41f391e7`** for
`gmod-native-loader-0.15.0+9abffb71.zip` (**753,836 bytes**). Only the DLL is extracted into
the evidence candidate directory; the bundled default config is not used.

The first fetch start is **excluded from acceptance**: its scratch command named a nonexistent
probe path. This was caught during the run; a separate settings-back execution succeeded, then
the standard harness's exception cleanup ended its owned game. Two earlier rescue attempts
declined input while the Workshop update/map load had the window busy; a later quit request also
raced the map load. `03-fetch-driver.log`, `03-fetch-rescue.json` and `03-fetch-recovery.json`
retain the exact distinction. The game had written an intermediate config without its bindings;
no settings were manually overwritten to conceal that. Subsequent drivers use the fresh original
config backup as their settings-back source. The accepted **04** session quit normally and
`04-config-restored.json` verifies **zero changed, added or removed settings**, bindings included.
Its client.vdf was restored byte for byte and its lock released. No product failure is attributed
to the mistyped QA path. The launcher now checks fixture existence before acquiring the lock.

The first combat probe (**05**) passed the boolean returned by `ABL.FlowCore.Active` to
`math.max`; the guard contained and then quarantined that test timer. Its Lua/guard-clean claims
are excluded. `05-combat-executed.lua` preserves it; `combat_clean.lua` corrects only that probe's
active-flow indicator. The accepted **05b** run has zero Lua and guard errors. The field visually
replaces the first disposable `male_07` flow model with a character, so `controlled_flow.lua`
uses a distinct stock **`models/monk.mdl`** fixture to inspect flow placement. Only that disposable
client fixture changes; the real citizen/ragdoll weapon targets retain the field's replacements.
Their appearance and body-overlay alignment are not a new imported-character parity claim.
The closer **05c** shotgun case replaces an observed miss, not a product failure.

The heavy scene continuously spawns Physics Blood droplets and flow alongside six packaged blood
effect dispatches per rendered frame. Its particle admissions and stains reach the package's
budgets; the reported **4,611** admissions are cumulative, not 4,611 simultaneous particles.
Frame intervals come from `PostRender` / `SysTime`, excluding screenshot time, with
`engine_no_focus_sleep 0`, `fps_max 0` and the original settings restored at normal quit. These are
application-frame measurements on the field's RTX 5090 and full mounted add-on set, not generated
display FPS or an isolated PoC benchmark.

The dupe collector verifies the observed compressed-data SHA-256 after the native file's **DUP3**
prefix, and the JPEG SHA-256 with the same native filename stem. It refused ambiguous identical
icons before deletion; matching the compressed dupe first disambiguates the pairs. Copies are
verified before the two exact source files are removed. No directory is recursively deleted and
no pre-existing dupe is removed.

The pause menu was opened with the normal `gameui_activate` console command after injected
Escape produced no visible UI change. Both Find Multiplayer Game clicks and both Back clicks
used the real observed UI; no menu route/state stub was supplied. Neither reminder ignore nor
multiplayer dismissal preference existed before, and both remain absent afterwards. No server
browser Continue action or server connection was made.

The manual update deliberately leaves the old PDB and the already-stale 0.13.0 installation
receipt unchanged: the user authorized copying **only** `bin/win64/winmm.dll`. The original
allowlist/config and `user.conf` are hash-checked before and after that copy. Actual DLL identity
and the running status, rather than that stale receipt, establish the installed 0.15.0 version.

`acceptance.json` indexes **24 native-size 3840x2160 PNGs** across four accepted game processes:
**04, 05b, 05c and 06**, all normal exit 0, `settings_back=restored`, zero Lua/status errors, no
device loss and no new crash dump. Their locks were held **2.43, 8.29, 6.44 and 6.78 minutes**,
then released; the PoC was never launched or modified. The earlier 03/05 fixture errors and the
missed 05b shotgun volley remain explicitly excluded. No unrelated running game was ended.

The final audit verifies hashes **and original modification times** for `user.conf`, `rtx.conf`,
the PDB, loader config/receipt and restored client.vdf. Config.cfg, client.vdf and server.vdf have
zero changed, added or removed setting values, the video-registry exports match, and both
standalone add-ons retain all **34 + 267** hashes. The new native-loader/status/session files,
per-process hint/reminder markers and ordinary caches/logs are game-created state. The only
manual field changes were the authorized client.vdf restoration, removal of the exact test dupe
pairs, and the verified DLL update; the standard driver's temporary settings-back cfg was removed.

All **207** runtime payload files match the new archive. **1,159** root files match; the same
**92 create-only** paths retain their field copies, verified against this publication's manifest
in `deployment-differences.json`. No attempt was made to replace the user's retained ToPBR maps
or startup-message files. The existing Poolday asset errors and occasional stock Workshop HTML
messages are preserved in the session logs. No new product fault was established in the requested
paths; colour/intensity equivalence, substituted-character body-overlay alignment, and the wider
R2 field-parity/earlier Q review limits remain outside this bounded acceptance.

No product source/package input changed, no native binary was imported into git, and no push,
merge, tag, Workshop operation or GitHub workflow was performed by this task. Only this report is
committed. The release DLL remains in the user's game; its old DLL/PDB backups stay in
`out/r20f/before-loader/`.
