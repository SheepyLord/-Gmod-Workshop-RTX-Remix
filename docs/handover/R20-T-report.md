# R20-T: the toolgun remains a lit display at night

Branch `r20-toolgun`, from `67ca0ec` (main's R20 plus the brief). [Brief](R20-T-toolgun-night.md),
[shared plan](R20-plan.md). Implementation commit: `eff0c90`.

## Built and cause

The companion's private screen material now has **`$ignorez=1`**, alongside its existing unlit
shader and no-cull flag (`companion/nativeloader/lua/autorun/client/nativeloader_toolgun.lua:9-15`).
The owning add-on still renders the same pixels: colours, layouts, animation, backlight and tool
overrides remain its choices. No Dynamic Toolgun Screen input, guard policy, runtime patch or
native binary was changed. RTX-off rendering retains the add-on's original UnlitGeneric display.
This repairs the existing 2D HUD design, rather than introducing a new rendering policy or ADR.

The missing depth flag made the first screen HUD draw eligible for the **lit scene**. In the actual
R20 runtime source (`src/d3d9/d3d9_rtx.cpp:574-583`, build `3cb32fb8`), orthographic draws trigger
UI injection only with **Z writes off**. Later draws rasterize after injection (lines 620-632).
The old opaque material reported `$flags=8192` (no-cull only); the fixed one reports **40960**
(no-cull plus ignore-Z). "UnlitGeneric" alone does not make scene geometry emissive in Remix.

This explains why capture/draw counts looked healthy in R20-F and why daylight QA missed it:
the draw can execute while entering the wrong rendering path, and ordinary earlier HUD elements
can accidentally trigger injection first. **The diagnostic itself matters:** drawing the healthy
RT in a HUD corner immediately made the toolgun bright and sharp, then removing that preview
returned the dim, smeared display. The raw texture was not dark; its sky/exposure was not leaking
into the offscreen painter. A magenta replacement also confirmed correct projected geometry.

The fix supplies the intended HUD material state, so a runtime change is unnecessary. It adds
no brightness gain, exposure compensation, emissive replacement or persistent texture category.

## Evidence and validation

All paths below are relative to **this worktree's `out/r20t/`**. All live work used the PoC,
`gm_construct`, no Workshop mount, isolated native allowlisting, ReShade off and `-multirun`.

| Check | Evidence / result |
|---|---|
| Main package / loader 0.15.0, noon and night, 4K | `depth/loader015-4k/game/shot-02-before_noon_inspect.png`, `shot-03-before_night_inspect.png`: the night capture reproduces R20-F's nearly black display at actual **3840x2160**, fixed **21:00**, ready **DLSS/DLSS-G 1/1**. |
| Exact release loader 0.14.0, same package | `depth/loader014-4k/`: repeats the same before/after material isolation. Loader SHA-256 `256f245fbb6dde4b2b41cba070c1a4fcc4a88110865941ce781ea065cad40e5b`, from the retained release ZIP. This is not a 0.15-only defect. |
| Healthy RT / dependency on other HUD draws | `nomirror/no-mirror/game/shot-03-before_night_inspect.png` through `shot-05-night_disable_mirror.png`, and the equivalent 4K shots 03-05 in both `depth/` cases. Adding/removing the corner preview toggles the failure. |
| Only the private material changed in a live session | `depth/*/game/shot-07-night_hud_ignorez.png`, `shot-08-night_hud_ignorez_no_inspect_overlay.png`: bright and sharp without the preview, including with DTS's 3D inspect overlay off. |
| Packaged fix, release loader 0.14.0, deterministic HUD order | `acceptance/fixed014-4k/`: eleven captures, production screen called before every other HUD hook, then after a known UI draw. Noon/night, repeated live updates, half backlight, return to noon, Terminal, Minimal, stock screen at noon/night. The screen remains readable. RT PNGs are copied under this case's `r20t/`. |
| Packaged fix, loader 0.15.0, corrected probe | `final/fixed015-4k-clean/`: the same eleven-case matrix passes at 3840x2160 and real ready DLSS/DLSS-G 1/1; final screen status reaches **8,244 captures / 4,122 draws**. Both accepted fixed-loader runs have zero guard errors, cleanup errors or blocked entries. |
| Colours and backlight | `pixel-measurements.json`: sampled static RT regions have identical noon/night RGB. The white navigation region is **255/255/255** in both RT and screen at noon/night and in both HUD orders; half backlight gives **128/128/128** in both. Blue/green patches differ from the sampled RT by at most 3.8 channel units after filtering, with the same values by day/night. |
| Before runtime patch 0034 | `followups/v014-complete/`: six noon/night/preview captures with the actual distributed **v0.14.0 runtime**, SHA-256 `b311f0d918c2614fe9983acc7db3e08fb39ee17ba4c42f49496dea2f3c0f5564`, old companion Lua and standalone DTS. The dim, smeared display and preview-dependent recovery are already present. Thus patch 0034 did not introduce this mistake. The old runtime has no effective-state readback; DLSS/FG were requested, not claimed as a ready native 1/1 snapshot. |
| Standalone DTS alone, RTX off | `followups/standalone-off-clean/`: three captures; native UnlitGeneric, no RemixConfig or render guard, original display readable in normal and darkened native lighting; half backlight still works. Without RTX there is no physical-sky clock, so a single-player QA command sets native lightstyle 0 to `a`, then returns it to `m`. The stock sky bitmap remains. |
| Combined package configured with RTX off, standalone present | `followups/combined-off/`: repeats those three native cases with the full package allowlisted. The aggregate package requires Remix and is skipped while RTX is off; the existing standalone continues to own the screen. This is coexistence/preservation evidence, not a claim that the aggregate deploys in an RTX-off session. |
| Bundled screen part alone, RTX off | `offpart/bundled-only-off/`: the independently packaged screen part, no standalone copy or other product add-on, passes all three native-lighting/backlight views. Its source is built with the unchanged toolgun part arguments from `tools/workshop.json` (`toolgun-only-build.log`). |
| GPU-free regression | `toolgun-unit.log`: ten production-Lua scenarios. First-HUD and prior-UI cases model the runtime's injection boundary; geometry, live texture, resize, unsupported views and failure recovery still pass. `regression-before.log` proves the old material fails the new first-HUD case. |

The actual fixed archive is
`fixed-package/gmod-rtx-remix-0.0.0-dev.20261106172321_0c7a0680.gma`, **1,955,100,824 bytes**,
SHA-256 **`352a4ed5fad388f882be2564b28702936a745a083d4c749ebb8c64c025070547`**.
`package-fixed.log` records its successful Release `nlctl` validation. This archive contains only
the companion material correction relative to main's shipping inputs, not the diagnostic helpers.
`package-diff.json` independently compares the archive manifests: the only changed shipping file
is `native/root/garrysmod/addons/nativeloader/lua/autorun/client/nativeloader_toolgun.lua`.

## Probe corrections and scope limits

`before/` deliberately showed a corner preview and therefore concealed the original failure until
the preview-free `nomirror/` repeat. Its magenta/overlay-isolation pictures remain useful, but its
bright night view is not accepted as a preview-free baseline.

`acceptance/fixed015-4k` is excluded: the first deterministic-order probe removed the production
hook and tried replacing `hook.Call`; GMod retained a cached dispatcher, so the production draw
count stayed zero. The corrected probe uses one real HUD hook and invokes the saved hooks in order.
The subsequent 0.14.0 case uses that corrected probe. Raw RT readback occurs after the frame, so
it does not introduce another HUD draw before the screen.

The first `comparison/v014-runtime` fixture was incomplete after Q's large-file cleanup: `nlctl`
had not yet validated that scratch fixture, and the loader refused it. That run was vanilla and
its probe errored; it provides no RTX comparison. The fixture was completed and validated before
retrying. The first `comparison/standalone-off` run confirms the standalone daytime display but
its attempted `lua_run` from client Lua was correctly blocked by GMod; that dark-lightstyle claim
is excluded and repeated through a bounded, single-player-only QA server command.

The validated old-package fixture retains the distributed runtime and old Lua but is not a
byte-identical copy of the old archive: two deleted CI-built modules (`gmcl_RTXFixesBinary_win64.dll`
and `mmdhl_runtime_win64.dll`) were recovered from **that release's exact v0.14.0 tag inputs**,
then indexed and validated. `v014-completion.json` records the distributed and substituted hashes,
and `v014-validation.json` records `nlctl` acceptance. The distributed runtime came from the
held, hash-checked original PoC cache. No character was imported/spawned. This bounded comparison
tests the relevant pre-0034 renderer and screen Lua without claiming complete old archive identity.
Git blame also dates the missing flag to **`6c45603`, 2026-10-30**, before the R20 round.

## Completion checks and restoration

`acceptance.json` validates **eight selected cases / 53 native-size screenshots**, retaining the
explicit exclusions above. All selected sessions quit normally with exit 0, finish their probe,
restore the field's settings before quit, and have no Lua error, device loss, persistent hang or
loader status error. Both fixed 4K runs retain actual ready 1/1 for all eleven readouts, advance the
live frame counter, and report no guard errors, cleanup errors or blocked entries. Their RT PNGs
provide readback without an earlier diagnostic HUD draw.

Eight live-test PoC holds stayed between **1.43 and 4.47 minutes**. Every hold's `restoration.json`
verifies the same **4,200 original file hashes/timestamps** and video registry values, zero
differences. The independent final check is `final-restoration.json`: the first snapshot still
matches, no PoC process or `user.conf` remains, and the registry is equal. `depot-final.json` /
`depot-final.log` verify **2,877 Steam depot files / 7,282,813,551 bytes**, zero missing, size/hash,
reparse or unverified failures; only the pre-existing permitted `autoexec.cfg` user-config difference.

Original non-depot trees were moved aside and restored by rename, rather than copied whole.
Only this task's own locks were released, after restoration. `cleanup.json` in each batch and
`large-cleanup.json` record deletion of the verified generated trees, duplicate loader snapshots,
old fixture and baseline archive. Screenshots, own-session logs, hashes, receipts, small settings
backups and the fixed archive remain. Temporary/build files stayed inside this worktree's `out/`.

No field game was launched or ended. The field's config/client ConVars were read only to restore
Steam Cloud settings before each normal quit (`settings_back=restored`). The PoC's pre-existing
console was moved aside unread; only this task's own console output was inspected. No Steam depot
file, Steam setting, launch option, `user.conf`, runtime source or shipping binary was written by
this task. No push, merge, tag, publication, Workshop operation or workflow start occurred.

The complete **`tools/test.ps1 -Config Release` gate passes, exit 0**, ending `All checks passed.`:
**27 CTests and 710 Python tests** (655 tools, 29 gmapack, 26 Steam; two existing environment skips).
Evidence: `release-final.log`, `release-final-summary.json`. The final documentation links and
diff whitespace are also checked before the last commit. Every commit uses SheepyLord's noreply
identity and the plan's Codex co-author trailer.

## Open

Merge/publication and a repeat in the user's field profile belong to the manager's follow-up.
This task does not launch or modify the field game. R20-F's unrelated unrun combat/dupe/effect and
heavy-scene checks remain its separate QA work; this screen fix does not claim those results.
