# R21-B report: Hotloader game-build findings are diagnostics

Branch `r21-hotloader`, from `r21-int` (`9e596255`). Implementation commit `c8ed277`.
Task: [R21-B-hotloader-notice.md](R21-B-hotloader-notice.md), under [R21-plan.md](R21-plan.md).
Decision: [ADR 0125](../decisions/0125-hotloader-game-build-findings-are-diagnostics.md).

## Built

- Imported the local `overrides/installation.lua` through `python -I tools/inputs.py import`.
  `tools/workshop.json` already ships it as `mmd_hotloader/lua/mmdhl/installation.lua` through
  `--addon-file`; its wiring is unchanged.
- Neither realm turns `game_unverified`, native `game_incompatible` findings, `game_check_failed`
  or `game_unchecked` into installation issues. Current and future builds need no maintained list.
  The unchanged UI therefore gives them no banner, notice, Dismiss key or problem count.
- Chose to omit these findings from the installation window too: the raw native report remains
  in `status.compatibility` and Copy diagnostics, without presenting informational findings as
  problems. A plain console line names every unverified library and native finding, or the failed
  or unavailable check. Control characters become spaces so it stays one line.
- The line prints once per realm's Lua session, after pending libraries settle or reach their
  existing retry limit; refresh and Recheck do not repeat it. A new map creates new realms, each
  of which reports its own check. This follows the existing realm-local installation logging.
- Feature gating, pending/retry behavior and the existing `game_not_ready` timeout warning are
  unchanged. Outdated releases, policy/fallback, identity and missing-file warnings are unchanged.
  No native source, binary, guard, compatibility profile, translation or UI code changed.
- Imported the local-change record in `packages/model-hotloader/source/Source.md` and updated the
  `packages/README.md` part row. ADR 0125 records the user's assumption and drops R20's separate
  new-build validation/evidence-refresh task. Actual breakage appears as failures and the console
  diagnostic; there is no game-build warning prompting a dismissal.

The required top-level `packages/README.md` row is unindexed repository documentation, not an
importable part input, so it was edited directly. Both indexed files changed only through import.

## Tests and package evidence

All evidence is under this worktree's `out/r21b/`.

- `lua-tests.log`: seven focused unittest methods execute 24 client/server LuaJIT scenarios against
  the complete shipped installation override and its unchanged UI. They cover arbitrary future
  library names and native codes, tested builds, nil/throwing checks, old modules, pending/retries,
  timeout, refresh/Recheck, retained raw reports, UI counts/notices and no dismissal writes. Other
  warnings remain visible, including the old module's separate `outdated` warning.
- `native-build.log`: `tools/build.ps1 -Config Release` passed all 27 CTest checks.
- `test-release.log`: `tools/test.ps1 -Config Release` passed: repository conventions, 27 CTest
  checks, and Python groups of 29, 26 and 662 tests (two existing skips across the first two groups).
- `package-build.log`: normal repository-input package built; compare exit 3 means changed content,
  as expected. The published release's CI-built natives differ from stored development inputs.
- `release-overlay.json`, `release-package-build.log`: for a controlled game comparison, extracted
  55 native/policy files from the current published package into an untracked overlay and built
  the candidate with `--built`, `--require-nlctl`, keeping the unchanged ReShade installer input.
  No binary was imported or changed in Git.
- `package-comparison.json`: SHA-256 checked all 1,459 entries of both archives. Only the shipped
  installation Lua and generated manifest differ; all native binaries and policies are identical.
  Baseline archive SHA-256: `bf4aa6a784c7901938d2d3449c9a30a763b5ae10b606282b8265307ba6d5ebbf`.
  Candidate archive SHA-256: `5e6b032ecf6b9236c854e92017a2455c4dec8d157c8d1da5184fcf8ae1658ac6`.
  Installation Lua SHA-256: `d019a35befe1a83ee6e0b133ec3a6c59472074d87d346531e2bdd7d56bc15c23`.

## PoC QA

`qa-summary.json` passes the automated comparison on GMod build 26439081, `gm_construct`, with
RTX active in both sessions. `poc/session.json` records the owning launches with `-multirun`,
normal exits, zero Lua/status errors and the field's settings executed before each quit.

| Check | Current published package | Candidate, identical natives |
|---|---|---|
| Client game-build issue | `game_unverified`; four unverified libraries | No installation issues |
| Problem count | 1 | 0 |
| Hotloader notice | Shown | Absent |
| Installation window | Game-build warning | Native installation verified |
| Imported Guinaifen | Instance 1, draw age 0, 53 live draws | Instance 1, draw age 0, 53 live draws |
| Raw client/server compatibility reports | Retained | Identical to baseline |
| New diagnostic console line | Not present | Exactly one per realm, despite Recheck |

The client identifies `engine.dll`, `client.dll`, `materialsystem.dll` and `shaderapidx9.dll` as
unverified; its native report has no interface findings. The server's `vphysics.dll` still matches
its profile, so its console diagnostic correctly says no unverified libraries or findings. The
LuaJIT scenarios separately cover unverified server libraries and server findings.

Screenshots, visually inspected:

- `poc/baseline/shot-01-baseline-installation.png`: the current package's warning and top-right
  notice. The probe reopens the real computed notice after startup, without changing issues or
  writing a dismissal; its initial status already recorded the notice as shown.
- `poc/candidate/shot-01-candidate-installation.png`: no notice, verified installation, no game
  findings in its window. Both realms' raw reports remain in the captured status/console data.
- `poc/{baseline,candidate}/shot-02-*-model.png`: the imported model drew in RTX. These first model
  shots also show the unchanged, separate loader-update reminder (the PoC bootstrap is 0.14.0).
  A supplemental candidate capture closes transient frames without changing reminder preferences.
- `model-check/poc/candidate/shot-02-candidate-model.png`: the imported character's face and torso
  render without the reminder window, with native draw age zero and live draws recorded. The
  camera also includes the PoC player. `model-check/qa-summary.json` evaluates this extra run.

`restoration.json` verifies every original file and directory in the copied loader, add-on, data,
settings and RTX trees. `snapshot/rollback.json` is clean, including shared registry settings and
all 2,877 depot files. The lock was created exclusively and released after verified restoration;
the comparison held it for 214.98 seconds. Original trees were moved back, leaving no large tree
snapshot copies. The supplemental capture has its own clean lock/snapshot/restoration records and
held the lock for 133.39 seconds. Verified
large file-snapshot copies were discarded after rollback; the hash inventories and rollback reports
remain. `user.conf` bytes and shared settings are preserved.

The first capture attempt used the default Python environment, which lacks Pillow. It failed in
the screenshot helper, with zero Lua errors; the owning harness stopped its game. Its complete
rollback verified 2,877 depot files, restored the snapshots and released the lock. Evidence is in
`attempt-1/`; verified large snapshot copies were discarded. The rerun uses the already installed
Python 3.12 and Pillow 12.3.0, with a preflight import before acquiring the lock.

## Open and integration

No native validation/profile-refresh task remains for this warning: the user expressly dropped it.
Future game-update failures are addressed when they occur, behind unchanged native guards.

The coordinator still owns review, merging onto `r21-int`, the shared CHANGELOG/ROADMAP/RESEARCH/
TESTING updates and eventual publication. This task made only its permitted ADR-index addition to
shared docs. No push, merge, tag, publication, GitHub workflow or change to the field install,
Hotloader repository, Workshop files, Steam settings or launch options was made.
