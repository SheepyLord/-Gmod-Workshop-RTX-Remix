# R21-B: no Model Hotloader warning about the game's build

Worktree `out/worktrees/r21-hotloader`, branch `r21-hotloader`, from `r21-int`. Implementer: Codex
(gpt-6.1-sol). ADR number: **0125**. Read first: [R21-plan.md](R21-plan.md) (the user's words and the
rules for every task), [AGENTS.md](../../AGENTS.md), [packages/README.md](../../packages/README.md) (the
`model-hotloader` row), the `model-hotloader` entry of `tools/workshop.json`,
`packages/model-hotloader/overrides/installation.lua` (the package ships it as
`mmd_hotloader/lua/mmdhl/installation.lua`, see `--addon-file`), `mmd_hotloader/lua/mmdhl/installation_ui.lua`,
`mmd_hotloader/lua/mmdhl/compatibility_policy.lua`, the `install.warning.*` lines of
`mmd_hotloader/resource/localization/en/mmdhl.properties`, `packages/model-hotloader/source/Source.md`,
and the open item about the Hotloader in [R20-report.md](R20-report.md).

## The user's item

> Dismiss the hotloader warning for this and future game updates. User decide to assume Hotloader
> should works even with the game update since it is a separate dll. In case of issues, user will fix
> them in an update to update basis.

## Facts

- Steam's GMod update of 2026-11-05 (build 26439081, the PoC's and the field's) changed game libraries
  that the packaged native release's compatibility profiles do not describe. `RefreshGameCompatibility`
  then adds `game_unverified` ("This Garry's Mod build has not been tested with this native release
  (... changed). Model Hotloader runs anyway; ..."), and the UI raises its banner and notice until the
  player presses Dismiss; the dismissal is keyed on the set of problems, so the next build brings it back.
- The same function turns the binary's own interface, slot and class findings into `game_incompatible`
  warnings, a failed check into `game_check_failed`, and a module too old to check into
  `game_unchecked`. None of them turns a feature off; only `pending` (a library not loaded yet) does.
- The natives are not to change in this task: the binary's guards still refuse an engine call they
  cannot make.

## What to build

1. In the shipped install check, the game-build findings (`game_unverified`, `game_incompatible`,
   `game_check_failed`, `game_unchecked`) no longer become warnings, in both realms: no banner, no
   notice, nothing that needs Dismiss, nothing in the problem counts. This holds for build 26439081 and
   any later build, with no list of builds to keep current. The installation window may list them as
   neutral information or not at all: your call, recorded.
2. Nothing else changes: features stay as they are (`pending` still waits for its library), the report
   stays in `status.compatibility`, and every other warning (an outdated release, the policy fallback,
   an identity mismatch, missing files) is unchanged.
3. One plain console line per realm and session names what the check found (the libraries this release
   has not seen, and any findings), so the user can diagnose a game update themselves.
4. Change only this repository's copy, through `tools\inputs.py import`; the Hotloader's own repository
   is not touched. Record the change where this part records its local changes (and say in
   `packages/README.md`'s row that the override carries it), with **ADR 0125**: the user's decision, what
   players no longer see, how a broken game update now shows itself (failures and the console line, no
   warning), and that the validation task R20 proposed is dropped.

## Tests and QA

A test that the shipped install check never turns those codes into warnings or problem counts (use the
repository's existing Lua or package tests if there are any; otherwise a focused one). In the PoC with
RTX on: with the current package the notice appears (screenshot); with yours it does not, the console
line does, and an imported Hotloader model still loads and renders. Evidence under your worktree's
`out\r21b\`. `tools\test.ps1 -Config Release` passes.
