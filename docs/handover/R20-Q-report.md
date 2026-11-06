# R20-Q: merged-package QA, stopped at the runtime boundary

Branch `r20-qa`, from `708051b`; [brief](R20-Q-integration-qa.md), [shared plan](R20-plan.md).
**The merged round is not signed off.** Integration exposed a native readback defect in runtime
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
