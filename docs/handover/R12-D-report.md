# R12-D: manual eye-white materials

Implementation, offline validation and PoC acceptance are complete on `r12-eyes` from `2dd3033`.
Design: [ADR 0097](../decisions/0097-manual-eye-white-materials.md).
All scratch and evidence are under this worktree's `out/r12-d/`.

## Behavior and files

- `companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua` owns selection, persistence
  and the window. The existing menu registers one **Choose eye-white materials** button beside the
  brightness slider (RTX Remix → Rendering → Model outlines). The console command is
  `nativeloader_eye_white_materials`.
- The window selects the looked-at character, the only spawned character, or a character from its
  dropdown. Rows show native names, original texture thumbnails, automatic/manual status, a checkbox
  and **Use automatic detection**. It populates 24 rows per page, four per frame, and preserves normal
  Derma dragging/resizing. Thumbnails reuse existing original textures, without cloning atlases.
- Explicit true and false choices outrank the name matcher. Unmarking restores owned public/soft
  bindings immediately; marking uses the existing validated proxy/alias path before rebinding.
  Brightness, global enablement and authored PBR precedence retain their R10 behavior. Choices apply
  to every instance of this asset without respawning or changing entity/submaterial overrides.
- DATA `nativeloader/eye_white_choices.json` stores schema 1: complete content asset ID → material
  slot/native name → boolean. Keys survive source moves, maps, restarts and same-asset re-imports;
  another asset does not inherit them. Missing means automatic detection. The loader rejects files
  over 1 MiB before reading, limits explicit choices to 4,096, preserves invalid/unknown-version or
  externally changed files, and verifies writes before changing the live selection.
- Discovery uses the hotloader's public entity/asset APIs and existing metadata. Unspawned library
  assets and previews cause no Material calls, proxy preparation or writes. Saving requires a
  spawned owner, a public path under that asset's 16-digit prefix and a real generated texture VTF.
  Existing per-atlas/session/cache budgets and eight-material work slices still apply. Removing the
  last spawned instance restores owned bindings and drops active aliases on the next sweep.
- The template and all six companion catalogs gain 15 additive translated keys. Source/script docs,
  the changelog, roadmap, testing/research notes and decision/handover indexes are updated. No new
  trusted render path is needed: all code stays in the already registered controller.

## Decisions and scope

The full asset identity plus slot/name avoids source-path and display-name collisions, while not
depending on a generated VMT's recipe version. The slot distinguishes duplicate native names.
Manual marks stay per surface: a shared atlas never makes every part an emitter. A checkbox can
mark an entire combined material if the player chooses it; this feature does not split its geometry.
Unreadable or externally edited choices block saving instead of being replaced. There is no
network message, new runtime option, shader/native change or hotloader patch.

Only the assigned controller, the menu's one registration, additive companion catalogs, the existing
eye-white harness/Python driver and their docs, ADR 0097 and additive shared documentation change.
`runtime/**`, `packages/**` and `loader/**` are unchanged. No binary import, push, merge, tag, Workshop
update, field write, Steam setting/launch-option edit or Remix user.conf write is part of this task.
Claude owns review and integration, including the combined R12-C memory measurements.

The R10 proxy format/allocation limits remain: unsupported or oversized textures fail closed, and
prepared atlas/helper textures remain in the engine's session cache. Restoring a binding and removing
an alias is not a claim of immediate GPU deallocation. This task prevents unused library assets from
starting that work; R12-C owns broader memory attribution/reclamation. Authored PBR still takes
precedence over automatic/manual fallback emission.

## Offline evidence

The focused LuaJIT suite has **45 passing cases**, including live mark/unmark, true/false precedence,
manual selection over an excluded name, reset, full asset isolation, controller restart/map reload,
same-session remove/re-import, corrupt/external/oversized settings, missing-file size variants, failed writes, and actual Derma
thumbnail/toggle/reset/pagination callbacks. Existing alias retries, old-runtime refusal, brightness,
alpha/mip preservation, shared-atlas isolation, soft copies and work/cache bounds remain covered.
Fixture JSON round-trips deep copies; it does not pretend to test GMod's native JSON implementation.

Commands:

```powershell
python -m unittest discover -s tools/tests -p test_eye_whites.py -v
python tools/companion_i18n.py check
tools/test.ps1 -Config Release
python tools/build_package.py --out out/r12-d/package-qa --require-nlctl --json
out/build/win64-release/loader/cli/nlctl.exe verify <local-qa.gma> --json
```

The final Release run passes **26/26 CTests and 572 Python tests** (28 + 25 + 519, with two
existing skips): `release-tests-final-ui.log` ends with **All checks passed.**, process exit 0.
Earlier full runs also passed (569 and 571 Python tests); the delivery run includes the additional
missing-file size regression exposed during PoC validation.
Catalog validation passes: 235 companion strings and 474 bundled-addon strings per translated
language (`i18n-check.log`). The final private package builds with exit 0 and passes nlctl manifest
validation: **1,091 files**, digest
`c8535b901d4419a052f85f34564eee6696b0cb532f3d82ead9d8467ac71834e7`.
GMA SHA-256: `d77bf80d29dcb974d772258f7c075709b69a6dddac535198dd3bc91bb8dc1c21`.
Receipts: `package-qa3-build.log`, `package-qa3-exit.json`, `package-qa3-verify.json` (CRC exit 0).

## Copied visual fixture

Baizhi/白芷 (`鳴潮_白蓮`), from the read-only source recorded in `model-copy.json`, was copied with its
textures to `out/r12-d/model/baizhi` (30,699,734 bytes). Its PMX SHA-256 is
`3b31d7f554d8dbdbb229185ea39db53d213b941e9e6836853a946701287d4ad8`; the original is unchanged
(`source-unchanged.json`). The shipped worker imports the copy into `model-cache` as
`489c095ce90ee2dcfdefa669febcd7ec875ebcec0c865b7164d184e73d921cd8` with 31 material slots.

The name matcher misses both `bai` (10) and `bai3` (16). UV masks show slot 10 samples pink backing
from the eye atlas; slot 16 samples white eye regions from the shared face atlas. Select **only 16**.
Evidence: `model-surfaces.json`, `uv-slot-10.png`, `uv-slot-16.png`, worker `request.json` / `status.json`.
The probe uses one frozen actor and the same front camera for before/marked/reloaded/0%-brightness/chooser/
unmarked/reset screenshots, and logs every material binding for comparison. Its script and transaction
runner remain under `out/r12-d/` for reproduction.

## PoC acceptance and restoration

The activity checks and their UTC timestamps are in `activity.jsonl`. The field game and recent user
input initially blocked launches; after it closed, R12-C/B/A held the shared PoC in turn. No field game
has been focused, ended or given input.

The final package ran **2026-11-03 02:37:01–02:38:51 UTC**, `-multirun`, gm_construct, 1280×720,
one frozen actor, front camera at distance 18/FOV 38, noon, eight seconds settling per cut. It
finished all seven captures and quit normally with **exit 0**, without device loss or session errors.
The final chooser was visually inspected: names, thumbnails, status and toggles are readable, the
looked-at actor is preselected and `bai3` is checked as **Chosen: eye white**.

| Cut | Choice / brightness | Result |
|---|---|---|
| Before | Automatic / 100% | No automatic match; all 31 original bindings |
| Marked | True / 100% | White eye surface brightens; only `bai3_16` receives the proxy |
| Reloaded | Persisted true / 100% | Disable/restore, reload the real controller, re-enable: native DATA JSON restores the choice and alias without a respawn |
| Zero | True / 0% | Proxy stays bound; adaptive emission disappears |
| Chooser | True / 100% | Readable paged UI with native names, thumbnails, checked state and reset button |
| Unmarked | False / 100% | Immediate original binding, empty active aliases |
| Automatic | Absent / 100% | Name detection resumes; this missed surface stays original |

`scope.json` asserts all seven successful choices, all 31 bindings per cut, the actual native JSON
reload and normal exit. Exactly **one of 31** materials changes in marked/reloaded/zero/chooser;
the other **30**, including the face sharing the atlas, stay original. Unmark/reset restore **31/31**.
The original `mmd/t/3d2df3e4d2fd3ce8` is never an emitter key; the alias is
`0x71f624d5c68def10=0x872f42a9c3b2ca2f`. Each controller prepares one **22,369,700-byte** VTF;
the final run records **118.572 ms** preparation, **96.822 ms** after reload. The earlier successful
run reached **1,960.334 ms** on its first preparation: cold file/texture work can stall, and these
are single observations, not GPU-memory or steady-frame benchmarks.

Canonical evidence is `poc/manual-eyes-accepted/`: `console.log` and
`shot-01-noon-before.png`, `shot-02-noon-marked.png`, `shot-03-noon-reloaded.png`,
`shot-04-noon-zero.png`, `shot-05-noon-chooser.png`, `shot-06-noon-unmarked.png`,
`shot-07-noon-automatic.png`. `poc/session.json`, `poc-accepted-run.log` and `scope.json` record the
driver results. Raw before/after images visibly demonstrate the missed white surface's correction.

The first session ran at 02:12–02:14 UTC on 2026-11-03 and ended normally, but is **excluded from
acceptance**: manual choices were refused, and the capture runner's recurring `nl_session_close`
timer removed the chooser before its shot. The absent-file path was hardened with a separate existence
check and a failing-then-passing regression. The real API then confirmed **exists=false / size=0**
with valid generated VMT/VTF inputs. The second successful matrix exposed low-contrast labels on
GMod's light panels; the final package uses explicit light rows and dark text. Only the test runner's
continuous frame-closing timer is removed for UI captures. These investigations caused no changes
outside the assigned source paths.

Every hold ended with the saved config restored, `nlctl apply` reconciling its original package, then
byte-for-byte restoration/checks of the bootstrap, configuration/video files, original console,
companion, all hotloader and companion DATA, and generated ToPBR directory. The shared Source video
registry also matches its snapshot. `poc-restored.json` has **all 11 checks true**, including unchanged
Remix user.conf presence/bytes; the owned lock was released. Earlier snapshots/receipts are retained
under `prior-state-*`; after other tasks changed the PoC baseline a fresh snapshot was taken instead
of restoring an obsolete one. No other task's lock was removed.

No acceptance item remains for R12-D. The established proxy-format/budget limits and cold preparation
cost remain documented above; Claude retains combined-round review/integration and R12-C's VRAM work.
