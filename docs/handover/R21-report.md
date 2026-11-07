# R21 report: Blood Overhaul's resources, and no Hotloader warning after game updates

Claude was the project manager and reviewer; Codex (gpt-6.1-sol, reasoning effort max, priority tier,
as the user asked for this session) wrote the code in two tasks. [Plan](R21-plan.md) (with the user's
words) and the task reports: [R21-A](R21-A-report.md), [R21-B](R21-B-report.md). Integrated on
`r21-int` in `out/worktrees/r21`. No loader change: the round ships as a package update.

## What the user asked for, and what was built

| The user's words (2026-11-06) | Built | Decision |
|---|---|---|
| "Permission is obtained from the author of the resources of Blood Overhaul, please package them and publish and I will update the credit section." | The `blood-overhaul-rtx` part now carries everything R20-C left out for want of that permission: Crunchy's textures, the stock-name decal files as the user's own add-on ships them (blood1..8, yblood1..6 and their subrects, stains, flesh, alien flesh, antlion impacts) and every PBR map and material override made from them (179 DDS, 186 entries, both hash kinds). The mixer draws 26 shapes (Blood Overhaul's eight first, then the eighteen generated ones) in all four blood families; colour schemes also reach the engine's own blood materials, as the original add-on did, and the master switch restores what it changed. The package's credits and a shipped notice name Crunchy (Workshop 2683396098) and record the reported permission; those resources stay the author's and outside the MIT licence. The Workshop page's credit section is the user's to update | [0124](../decisions/0124-blood-overhaul-resources-by-permission.md), superseding [0118](../decisions/0118-bundled-toolgun-screen-and-owned-blood-patterns.md) in part |
| "Dismiss the hotloader warning for this and future game updates ... assume Hotloader should works even with the game update since it is a separate dll." | The package's Model Hotloader install check no longer turns game-build findings (an unverified build, the binary's interface checks, a failed or missing check) into warnings, so no banner, notice or Dismiss for build 26439081 or any later build; one plain console line per realm names what the check found. The natives, their guards and every other warning are unchanged. The validation task R20 proposed is dropped | [0125](../decisions/0125-hotloader-game-build-findings-are-diagnostics.md) |

## Review and QA

- **R21-B** compared the published v0.15.0 package with the candidate in the PoC (build 26439081, RTX):
  the published one raises the "not tested with this native release" notice (engine.dll, client.dll,
  materialsystem.dll and shaderapidx9.dll changed); the candidate shows none, logs one line per realm,
  and an imported character still loads and renders. 24 LuaJIT scenarios run the shipped Lua in both
  realms.
- **R21-A** tested the blood part in the PoC with RTX, alone and beside Crunchy's own add-on and a
  field-style legacy copy in both mount orders: no Lua error, one mixer and one panel, engine blood
  visible with its PBR in red and yellow, Physics Blood unaffected, R20-C's impact budgets held. Its own
  QA found and fixed two defects of the new restore path: a material reached through two Lua objects
  was restored from the wrong baseline, and restoring a texture by its object (not its name) left the
  engine's own decals missing under RTX.
- **The reviewer's gate.** A post-clear item in R21-A's first report was sent back for a comparison with
  the published package using a player's steps (shoot, the panel's Clear button, the sandbox clean-up,
  `r_cleardecals`, scheme changes, a wait and a map change). New blood appears after every clear in both
  packages; enabled scheme changes went back to R20's paint-only path (restoring only when the master
  switch goes off), with a regression test. The pronouns and the permission's wording were corrected:
  the notice states only what the user reported.
- `tools\test.ps1 -Config Release` passes on the merged branch (with main's ADR 0126 module check):
  27 of 27 native tests and 733 Python tests (29, 26 and 678; one optional skip).

## Size

The blood part grows from 261 indexed inputs (112 binaries, 55.5 MB compressed) to 550 (272 binaries,
109.4 MB compressed): **160 new Git LFS objects, 51.36 MiB**, each imported once. The package grows by
about 226.6 MB (1,746 files, about 2.18 GB). Remix replacement textures still load when first used.

## Open items

- **Small impact stains on a white floor plate** (found by R21-A's comparison, older than R21): the
  droplets' `util.DecalEx` stains do not show on a stock white floor plate in PoC captures, with the
  published v0.15.0 package as with R21, although their traces and calls are counted. Wall, cube and NPC
  blood, and the engine's own decals, render. Cause not established; the runtime was not changed.
- **Engine blood colour beside Crunchy's own add-on**: where Crunchy's original modulate VMTs win the
  mount order, engine blood keeps its natural colours (visible, with PBR) and only the mixer's
  materials follow the schemes. The package's own VMTs do the full job; the subscription is no longer
  needed. The field still has Crunchy's item subscribed and the legacy `Blood Overhaul` folder; both
  are the user's to remove or keep.
- **The 4K GPU timeout during a map load** ([R21-C](R21-C-report.md)): the user's fresh-install field
  start timed out in the map's first ray-traced frames; one of five PoC starts timed out before them.
  Closed by the user as not reproducible; the cause is not established.
- Carried from R20: the darker stock ragdoll blood cloud under RTX, and R20-A's two unreproduced 4K
  device losses.

## Published (2026-11-07 UTC)

`main` was pushed at `87cd8b2` (160 new Git LFS objects, 54 MB). The merge's hook built the package
here from `packages/` and uploaded it to item 3829070317 as **0.0.0-dev.20261107011558+809ceec2**
(2,181,712,520 bytes, SHA-256 `b4056946da48225d89769fbd1f430d2caedc44cfb0e9ebf0202d7400873b49c5`);
the push's hook found the same inputs. Steam's public record of the item shows that size, updated at
01:16:45 UTC. The item had held the v0.15.0 release built on GitHub; this development build carries the
binaries stored in `packages/` (ADR 0108). Steam had not yet downloaded it into the user's library ten
minutes later: the game's next start fetches it.
