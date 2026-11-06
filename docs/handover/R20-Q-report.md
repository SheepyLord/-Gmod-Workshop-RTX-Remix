# R20-Q: merged-package integration QA

Branch `r20-qa`, from `708051b`; [brief](R20-Q-integration-qa.md), [shared plan](R20-plan.md).
**Follow-up checks are complete; see [After the readiness fix](#after-the-readiness-fix).**
The initial run below stopped without sign-off: integration exposed a native readback defect in runtime
patch 0040. The brief says: "A runtime change is not expected; if one is needed, stop and report
instead." Further live QA stopped after isolating that defect. No runtime change, binary import,
merge, push, tag, publication, Workshop operation or GitHub workflow was performed.

## Built and staged

- Release loader **0.15.0**, including all 27 CTests (`out/r20q/build.log`). Each isolated batch
  installed it through `tools/workflow.ps1 -SkipTests -Install`; the installation logs are kept.
- The complete thirteen-part package built from this worktree's `packages/`, validated by this
  branch's Release `nlctl`: **1,458 files**, **1,955,094,883 archive bytes**.
  `out/dist/gmod-rtx-remix-0.0.0-dev.20261106132846_e588b386.gma`, SHA-256
  `31947973987c9bc84b36c07acb5637befe448450eebe779689c16ef3e511777d`.
  Its combined runtime is **417,508,864 bytes**, SHA-256
  `53e387145b24661326dae65d97263441d2929774d15e35dc53466276bdfdc8d0`.
  Receipt: `out/r20q/package-build.log` and the adjacent package summary in `out/dist`.
- Only local/development package allowlisting was used. Temporary QA configurations disable
  `allow.subscribed_content` so unrelated subscribed character/map packages do not enter the test.
  That preference and every original PoC file were restored. No native trust rule changed.
- A synthetic **0.16.0** release record was prepared and hash-indexed in an extracted development
  package, with `nlctl` validation. The repository's real record remains **0.14.0**. It was not
  launched: menu QA was cancelled while waiting for the PoC lock, at the stop boundary.
- Both 4K baselines were prepared, **not executed**: the distributed v0.14.0-era package
  (`b311f0d9` runtime), and a copy with only the exact pre-`32ce8ca` runtime (`34287de8`) substituted
  and indexed. `baseline-package.json`, `baseline-overlay.json` and
  `baseline-overlay-validation.json` under `out/r20q` record the distinction.

## PoC refresh and restoration

The field's current Steam build is **26439081**. Under the exclusive shared lock, the verifier
reported **21 size and 25 hash differences** in the older PoC. Exactly those **46 files** were
archived under `out/r20q/depot-before/`, copied from the read-only, verified field install, and
hash-checked. `depot-refresh.json` records every path and before/after SHA-256; `poc-before.json`,
`field-readonly.json` and `poc-refreshed.json` retain the full verifier results.

The refreshed baseline matches **2,877 depot files / 7,282,813,551 bytes**, with only the permitted
pre-existing `garrysmod/cfg/autoexec.cfg` user-config difference. The requested vanilla refresh is
kept; all subsequent QA snapshots restore to that refreshed baseline, rather than undoing the
requested update. Final verification is `out/r20q/poc-after.json` / `poc-after.log`.

R20-C/D's snapshot strategy and fixtures were reused. Generated directories were first proved to
contain no depot entries, hashed and moved aside; originals returned by rename. Depot settings
files stayed in place; only non-depot settings/extras were restored from copies. Each completed
batch's `restoration.json` checks **4,200 original files**, their timestamps, and the video registry:
zero differences. All holds stayed below ten minutes; no game or task lock remains. Settings from
the field's read-only config and client ConVars were executed before normal quits, to restore
the shared cloud settings. No field game was launched or ended. No Steam settings or `user.conf`
were changed. No gameplay/package binary was added to git.

The final independent audit against the first Q snapshot is `out/r20q/final-restoration.json`:
4,200 file hashes/timestamps match, the original/current video sizes are both 3840x2160, the
registry matches, no `user.conf` exists in the watched trees, and no PoC process remains.

One diagnostic console poll raced restoration and returned eight shutdown lines from the restored
PoC console. They were not used as evidence. Direct polling stopped; subsequent inspection uses
the session owner's copied logs. The original console bytes and timestamps were restored with the
other retained files. The earlier failed runner attempt used the shell's Python without Pillow;
subsequent runners explicitly use installed Python 3.12 and preflight Pillow before acquiring the
lock. One earlier combat run contains an investigator's malformed console command; the clean
daylight repeat, not that run, supplies combat acceptance.

## Item-by-item results

Evidence paths in this table are relative to this worktree's **`out/r20q/`**. All completed live
cases used the merged package, RTX on and native-size **1600x900** captures. `acceptance.json`
indexes the session receipts, measurements and screenshot hashes; normal shutdown alone is not
treated as a successful probe.

| Item | Result | Evidence |
|---|---|---|
| 51, stock two-prop dupe | **Pass.** Actual stock save; readable coloured drum/crate JPEG; zero `cam.End underflow`, Lua errors, guard errors or cleanup errors. | `effects-day/effects-dupe-900/game/console.log`, `effects-day/effects-dupe-900/dupes/` (the `.dupe` and `.jpg`), `shot-05-dupe_saved.png` in that case's `game/` |
| 44, Physics Blood and other add-ons | **Partial visual acceptance; rendering/guard checks pass.** Physics Blood droplets/pools/red body flow/ground stains render without black filter rectangles. Draconic dust and Client Ragdoll Blood/Zippy dispatch run with clean guards; the dust capture is faint and the ragdoll cloud dark, so their full visual parity needs a controlled comparison. Fixed daylight was used for the repeat. | `effects-day/effects-dupe-900/game/shot-01-physics_droplets_pools_stains.png` through `shot-04-ragdoll_blood.png`, `console.log`, `remix-dxvk.log` |
| 48, combat and settings | **Partial pass.** Real pistol/shotgun/AR2 hits on citizens, Combine, zombies, antlions and ragdolls; stock-off fallback, alternate colours, floor stains, one Blood panel, one Dynamic Toolgun Screen panel, zero old Utilities shortcuts. Dedicated wall-stain and live upscaled-screen acceptance remain open. | `effects-day/blood-900/game/` (27 captures), `console.log`, `effects-day/blood-900/session.json` |
| 48, dynamic screen under upscaling | **Not accepted.** Live 1/1 selector request never yielded a ready snapshot within 45 seconds, so the probe stopped before claiming sharpness or recording its intended screenshots. No Lua error/device loss; normal quit is only a shutdown result here. | `effects-day/toolgun-live/game/console.log` (`R20Q_TOOLGUN_FAIL`), `remix-dxvk.log`, `effects-day/toolgun-live/session.json` |
| 45, live startup advice | **Partial pass, blocked for sign-off.** Real native 0/0 and 1/0 readouts give the correct hint once, zero while obstructed, after the guide/gate closes. No native getter stub was used. Readiness race below prevents accepting the combined feature. Both-on and both suppression settings need a clean repeat after the runtime fix; earlier timing experiments do not establish those results. | `hints-acceptance/both-off/game/`, `hints-acceptance/fgoff/game/` (two captures each, `R20Q_EFFECTIVE`, `R20Q_HINT`, `R20Q_FINAL`); readiness diagnostic in the latter's `console.log` |
| 49, sky defaults | **Pass.** Fresh profile is 1/20; old 0/30 migrates to 1/20. Running clock advances 0.445220661 hours in 22.261033 real seconds: **1.2 game hours/minute**, a 20-minute day. Once-only migration/player-choice preservation also passes the production-Lua harness. | `hints-acceptance/both-off/game/console.log`, `hints-acceptance/fgoff/game/console.log`, their `nativeloader_companion/` marker copies; `qol-regression.log` |
| 46, menu/older-loader reminder | **Open in merged live QA.** Synthetic record and manifest validation prepared; no menu process launched. Existing executable menu/companion harnesses remain in the Release gate. | `synthetic-package-validation.json`, `package-dev/`, `menus-driver.log` (queued, then cancelled) |
| 50, main/pause multiplayer warning | **Open in merged live QA.** Same stop boundary; no live route/persistence result claimed. Existing route/button/persistence harnesses remain in the Release gate. | `menus-driver.log`, `menu-cases.json`; final Release log |
| 4K RTX, current versus old runtime | **Open.** No 3840x2160 map was launched by Q. R20-A's device losses are still unresolved; neither reproduction nor a fix is claimed. | `4k-cases.json`, `baseline-package.json`, `baseline-overlay.json`, `baseline-overlay-validation.json` |

The clean combat stress phase admits six synthetic impact events per rendered frame at the normal
simulation speed and a 60 FPS cap: **241 frames / 4.013328 seconds**, median **16.6474 ms**, p99
**23.2845 ms**, peak **512 live particles**, 341 recent particle admissions and 192 stains during
the cleared stress epoch. The combat/stress session records 2,208 landing callbacks with zero trace misses. The
statistics span two decal epochs; 576 cumulative stains do not mean the 384-per-epoch cap failed.

The uncapped Physics Blood phase reached **420 droplets / 16 pools**; its 863-frame sample has
median **9.1459 ms**, p99 **16.4200 ms**. These are RTX 5090 development measurements, not a
hardware-independent guarantee. Earlier night captures retain a strong additive glint; accepted
daylight framing shows the red flow clearly and avoids the advancing clock as a visual confound.

## Runtime finding: unrelated writers invalidate the upscaling snapshot

This is an R20-E integration issue, not a missing Lua function. The real getter and capability
flags are present. Runtime patch 0040 calls `invalidateUpscalingState()` from **every**
`RtxOptionImpl::markDirty()` (`runtime/patches/0040-Publish-live-upscaling-state-for-startup-advice.patch:291`).
Invalidation clears `m_upscalingOptionsResolved` and the published `ready` bit (lines 129-135).
The publisher restores readiness on the render thread at present (lines 45-47, 229-244).
The running sky regularly edits sun/moon/cloud options between those publications and ordinary
Lua timer reads. Those edits do not change the two upscaling enums or device capabilities.

The diagnostic in `hints-acceptance/fgoff/game/console.log` prints `R20Q_DIAG_BEGIN`,
`R20Q_DIAG_HOLD` and **`R20Q_NATIVE_DIAG`**. It never replaced the native getter or fabricated a
snapshot. A temporary Lua setter wrapper observed normal writes, deferred unrelated writes for
seven seconds, replayed their latest values, then restored the original setter. This was an
isolated diagnosis, not a proposed gameplay workaround. Both enums stayed **1/0**, all three
capabilities stayed true, and all measurements used the real native function:

| Phase | Ready reads | Pending reads |
|---|---:|---:|
| Normal writers, four seconds | 14 | 65 |
| Unrelated writers deferred, seven seconds | 140 | 0 |
| Writers restored, six seconds | 10 | 110 |

The wrapper caught **536** ready-to-pending transitions caused by `rtx.atmosphere.sunElevation`,
plus one cloud-wind-direction and two cloud-coverage transitions. The separate toolgun probe's
1/1 request remained unready for its full 45-second limit. Thus extending a Lua screenshot delay
does not solve the underlying readback contract. Correct off-state hints can pass when a poll lands
in a ready interval; those passes do not disprove the race.

`out/r20q/native-readiness.json` is the exported native diagnostic object. The corresponding
reproducer is `out/r20q/readback_diagnostic.lua`, retained in its executed 1/0 form.

The waiting menu runner was cancelled before it held the lock. The active hint batch stopped
before its third case by withdrawing its test-only fixture; the resulting driver
`FileNotFoundError` is that deliberate cancellation, followed by verified restoration, not a
missing packaged Lua file or game failure.

The runtime follow-up should invalidate for upscaling/preset/device dependencies, preserving
invalidation during genuine pending edits and cyclic callback failures, without letting unrelated
sky/effect changes starve the snapshot. Add a regression with continuous unrelated option writes
and normal Lua timer reads, then rebuild the **combined** runtime and import the final binary once.
Changing the consumer to trust `ready=false`, guessing from config files, stopping the player's sky
or forcing graphics options is not an acceptable fix.

## Changes, checks and next handover

No functional gameplay fix or new package binary was made. The source comment now names the
shipped R20-E provider; its sidecar and shared QA/research notes record the integration finding.
No new translated player text or design decision was introduced. Commits carry the requested
`Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>` trailer.

- Build and package validation pass; the directly executed QoL regression passes all **7** methods.
- Final mandatory **`tools/test.ps1 -Config Release` passes, exit 0**, ending `All checks passed.`
  Receipt: `out/r20q/release-final.log`. All **27 CTests** and **710 Python tests** (655 tools,
  29 gmapack, 26 Steam; two existing optional-environment skips) pass with the normal dispatch.
- Final depot verification and original-file/registry restoration are separate from unit tests;
  both must pass before handover. The native boundary is a live defect even when the unit gate passes.

**Open:** native readiness fix, then repeat item 45's full off/on/suppression matrix, the sharp live
screen and wall-stain views, the other effects' controlled visual comparison, all merged
main/pause-menu reminder/persistence checks, and the 4K
current/old-package diagnosis. Integration/release approval remains with the lead. The repository
release record is deliberately not advanced, and this branch has not published anything.

## After the readiness fix

Resumed from `f7bfe41` after R20-E's dependency-scoped invalidation fix and the combined runtime's
single rebuild/import. The earlier stop above is historical; this section records the follow-up.
The refreshed PoC remains on GMod build 26439081. Evidence is under **`out/r20q/afterfix/`**.

The loader Release build passes all 27 CTests. The final thirteen-part package, validated by this
branch's `nlctl`, is `final-dist/gmod-rtx-remix-0.0.0-dev.20261106154248_01052ec2.gma`:
**1,458 files**, **1,955,100,507 archive bytes**, SHA-256
`cb38e5073aea358b6c9e0a0f59d6a640b2bf504c8379042d8beda620a6f05382`.
`final-package.json` / `final-package-build.log` retain its receipt. The supplied combined runtime
is **417,509,888 bytes**, SHA-256
`00124bf6009ee6acb2b2ffbc64d8a724aeb0ed700fa88b0dc4dbb7a8720b05a1`; Q did not change/import it.
The repository's release record stays **0.14.0**. The validated local menu fixture records 0.16.0.

| Open check | Follow-up result | Evidence under out/r20q/afterfix |
|---|---|---|
| 45, full matrix with running sky | **Pass.** Real 0/0, 0/2 (upscaling off with FSR 3 FG), 1/0 and 1/1 states; correct single hint for the three off cases, none with both on, `cl_showhints 0` or the actual RTX checkbox clicked off. No hint while obstructed. Across steady samples: 3,140 ready / 0 pending / 0 wrong, with continuing sky writes and a running 20-minute day. | `hints/*/game/console.log`, two native-size captures per case, `hints/*/session.json`; `hints/optout/game/shot-01-checkbox_off.png` |
| 48, wall/floor stains | **Pass.** Ten effect dispatches produced 50 observed wall decals and 101 floor decals, 229 landing callbacks and zero trace misses. The camera/trace normals and pictures show real world surfaces, not direct test stamps. | `views/wall-floor/game/console.log`, `shot-01-wall_stains.png`, `shot-02-floor_stains.png` |
| 48, sharp live screen | **Pass for live updating and sharpness.** Ready DLSS/DLSS-G 1/1; actual 512x512 `dtscreen_screen512`, two live layouts, 902 capture / 451 HUD redraw callbacks in the short standalone run. The fixed-daylight inspection with the refreshed bootstrap also shows readable live text, backlight 1, dim 0 and ready 1/1 state. | `views/toolgun/game/` (two captures, log); `menus-en-fixed/later/toolgun-daylight*.png`, `toolgun-scene.json` |
| 44, controlled comparison | **Comparison complete; colour/intensity parity is not claimed.** Same fixed map sun, camera, FOV, seed, effect inputs and 0.05 timescale; samples near 0.05/0.15/0.30 simulation seconds. Draconic dust is faint in both; the stock `blood_impact_red_01` ragdoll cloud is darker under RTX. Shapes/fades render without opaque filter rectangles, and the RTX guard is clean. This remains a visual difference for renderer review, not a demonstrated Q-owned Lua failure. | `compare/off/game/` and `compare/on/game/`: three dust and three ragdoll captures each, `R20Q_COMPARE_VIEW`, `R20Q_COMPARE_SAMPLE`, `R20Q_COMPARE_FINAL` |
| 46, main-menu reminder | **Pass in English and zh-CN.** Synthetic 0.16.0 shows versions/instructions; Later permits a reminder after restart; per-version ignore survives a restart. Open download page opens only the recorded project `/releases/tag/v0.16.0` URL in Steam's browser (expected 404 for this synthetic version). With both preferences cleared, the real 0.14.0 record shows no update window. | `menus-en/open/` (URL prefix/suffix and opened-page captures), `menus-en-fixed/{later,ignore,remembered}/`, `menus-zh/{real-record,later,ignore,remembered}/`, targeted `*choices.json` receipts |
| 46, in-game fallback | **Pass in English and zh-CN.** DATA status alone is simulated to 0.14.0; the actual DLL remains 0.15.0. The shipped companion displays its verified-record reminder with complete text/buttons; Later closes it. | `menus-en-fixed/later/companion-update.png`, `menus-zh/later/companion-update-zh.png`, `companion-scene.json`, `old-status` command receipts |
| 50, main/pause warnings | **Pass in English and zh-CN.** Find Multiplayer opens the warning in both contexts. Back returns home; Continue reaches the real server browser. Checking the box then Back does not save dismissal; checking it then Continue does. Cookie `1` and direct browser entry survive new processes in both languages. No server was joined. | `menus-en-fixed/later/{multiplayer-warning,pause-warning,back-did-not-dismiss,pause-continue-browser}.png`, `menus-zh/later/{warning-zh,pause-warning-zh,pause-continue-zh}.png`, restart captures/`*choices.json` in both groups |
| 4K current/old runtime | **Pass for these bounded loads; historical loss not reproduced.** Both packages load gm_construct at actual 3840x2160 with borderless direct-map startup, and with bordered main-menu-to-map startup. Four normal quits, no device-loss/allocation-failure markers. Current native readback is ready 1/0. Old package is the untouched distributed v0.14-era archive, internal version `0.0.0-dev.20261106004558+ad5cf8e8`, runtime `b311f0d9` (full hash in the original `baseline-package.json`). | `fourk/{v014-4k,merged-4k}/game/`, their `session.json`; `fourk-menu/{v014,merged}/`: `map-4k*.png`, `record.json`, `modules.json`, `loader.log`, `status.json`, `remix-dxvk.log` |

The hint batch's `restoration.json` verifies 4,200 original files/timestamps and the video registry,
with zero differences; lock hold 6.89 minutes. Its own verified binary copies were removed after
restoration, retaining screenshots, logs, text and JSON receipts (`hints/binary-cleanup.json`).

### Fix found during live menus

The stored `gmsv_nlrtxclient_win64.dll` was the R4 artifact (456,192 bytes, `de92d026...`), linked
to an old config parser. It printed `unknown key "performance_tier" in remix` from
`loader/client/module.cpp:190`, so it never prepared the verified client catalog. This is distinct
from the loader's menu notices, which could still work.

The current-source Release build accepts that exact config and reports `verified; waiting for
the client realm`. It passed the real menu, map/fallback and restart checks before its **one final
import** through `inputs.py`: **460,800 bytes**, SHA-256
`f23c711c4e6b3678661cbed45cf34d034d064b0444cd45c77a3e8b66851c508b`.
The owning input/index and part README are updated. No C++ policy change or new native source
permission was introduced; normal SP loading remains the explicit early return in
`loader/client/bootstrap.lua:8`. Evidence: `bridge-overlay.json`, `bridge-validation.json`,
`bridge-import.log`, `bridge-import-receipt.json`, `bridge-inputs-verify.log`. This is Q's only
binary import; the final package was rebuilt after it.

### Diagnosis and limits

R20-A's old-package 4K records contain `VK_ERROR_DEVICE_LOST` and exit 1 on the older PoC. The
follow-up's four runs retain active loader/runtime reports and the expected native runtime module
paths, complete 3840x2160 captures and exit 0. Their Remix logs contain no device-loss or allocation
failure marker. This does not isolate the old failure: the game build and isolated content/cache
setup differ from A's run. No R20-specific cause was reproduced, no speculative rendering fix was
made, and stability with every field subscription is not established by these smoke tests.

The effect comparison's CPU lighting probes differ: vanilla `[0.5622,0.5959,0.5713]`, RTX
`[0.4202,0.3902,0.3339]`. Colour/intensity equality therefore cannot be inferred from identical
effect timing or geometry. The darker ragdoll cloud remains documented; the bounded observer did
not block it and no new native renderer fault was established. The auxiliary old-4K stock-PCF
photo was taken after that effect expired and is not used as colour-parity evidence.

The RTX comparison also displays the shipped Model Hotloader's compatibility notice: its native
release's tested engine hashes predate build 26439081. It runs anyway. Q has not claimed a new
imported-character/physics acceptance or changed that metadata to hide the notice; that broader
field/model validation remains outside these effect/menu checks.

### Restoration, cleanup and final gate

Every follow-up batch verifies **4,200** retained file hashes/timestamps and the original video
registry. The longest completed hold is the English menu group at **15.08 minutes**; all are below
20 minutes. The real field game was never launched or ended. No Steam setting or `user.conf` was
changed. The English menu runner initially kept its own SQLite connection open (a Python sqlite
context commits but does not close); explicit close fixed the runner. The game had quit normally;
recovery completed under its retained lock and verified all 4,200 files before the next run
(`menu-recovery.log`, `menus-en/restoration.json`).

Large binary snapshot/generated copies are deleted only after the corresponding successful
restoration receipt; `*/binary-cleanup.json` records paths and bytes. Screenshots, logs, JSON and
Lua/text are kept. `acceptance.json` and `acceptance-summary.json` index the follow-up's records
and native-size image hashes; `assertions.json` checks the functional results and restart cookies
while explicitly excluding colour/intensity equivalence. `package-binary-cleanup.json` records
removal of the superseded initial package and extracted fixture binaries. Re-extract the retained
final GMA before rerunning a cleaned synthetic fixture.

Final results under `afterfix/`:

- **`tools/test.ps1 -Config Release` passes, exit 0**, with the normal dispatch: **27 CTests and
  710 Python tests** (655 tools, 29 gmapack, 26 Steam; two existing optional-environment skips),
  ending `All checks passed.` Receipt: `release-final.log`.
- `final-restoration.json` / `final-audit.log`: **4,200** original file hashes/timestamps match;
  **zero added, missing or changed files**, identical video registry and original 3840x2160
  settings, no `user.conf`, no PoC process. The task lock is released.
- `poc-after.json` / `poc-after.log`: **2,877** stock files / **7,282,813,551 bytes** match current
  manifests, zero missing/size/hash/reparse/unverified failures. Only the same permitted
  `autoexec.cfg` user-config difference remains. GMod build **26439081** is kept.

**Open for review:** the darker stock ragdoll-cloud appearance, the unisolated historical 4K cause,
and the Hotloader/current-build notice and full field/model parity. No additional Q-owned defect
was confirmed in the exercised paths. Review/release/publication remain with the manager; Q has
not pushed, merged, tagged, published or started a workflow.
