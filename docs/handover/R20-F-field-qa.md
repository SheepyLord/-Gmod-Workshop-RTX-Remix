# R20-F: field QA of the published R20 package

Worktree `out/worktrees/r20-field`, branch `r20-field`, from `main` at the R20 merge. Implementer:
Codex (gpt-6.1-sol). Read first: [R20-report.md](R20-report.md), [R20-Q-report.md](R20-Q-report.md)
(the PoC QA you repeat here in the field), [R20-plan.md](R20-plan.md) (the rules for every task) and
[docs/TESTING.md](../TESTING.md) (the field release QA protocol, `tools/qa/release_qa.py`); R19's field
release check is the model: `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r19release\field_release.py`
and its results beside it.

## Situation

`main` was pushed with R20; the git hooks uploaded the locally built RTX package to Workshop item
3829070317 (`out/workshop/published.json` in the main checkout names the version). The field install
(`H:\SteamLibrary\steamapps\common\GarrysMod`, the user's real game, 3840x2160, GUI Scaler) runs the
v0.14.0 release loader (`bin\win64\winmm.dll`, loader 0.14.0) and gets the package from the Workshop;
Steam may need one start to download the new version before a second start deploys it. The field
also has the user's own standalone copies `garrysmod\addons\dynamic_toolgun_screen` and
`garrysmod\addons\Blood Overhaul`, and Physics Blood (3818841829) among its subscriptions: the real
coexistence case.

## Permission and rules for this task

The user allows agents to close and launch the field game for tests (2026-11-01) and to end a running
field game when a test needs it (2026-11-02). Before a start, look for other sessions' PoC labs and
running games (`out\r10\poc.lock`, running `gmod.exe`); never end another agent's field test. Change
nothing in the field install yourself: no file copies into it, no settings saved, never `user.conf`,
never Steam's files. Save `garrysmod\cfg\client.vdf` before and put it back byte for byte; end every
session with the field's own settings (the drivers do). Any file the game itself creates during your
tests that is clearly yours (a test dupe and its icon, screenshots) is recorded and removed afterwards;
nothing else is deleted. Read only the part of `console.log` your session wrote. `-multirun`.

## Check, with the published package and loader 0.14.0

1. The deployed package is the published version; `status.json` shows RTX active and no errors; the
   field verifies against Steam's manifests before and after (`tools\steam\verify_install.py`).
2. **45** the startup hint with the field's real Remix settings (observe only; do not change them):
   it appears once if a supported feature is off, not otherwise; record what the readback reported.
3. **49** the sky: time passes, the day length the field profile ends up with (the user's own
   changed values are kept; old defaults migrate once).
4. **48** the RTX tab shows the Blood panel and the toolgun screen settings once each, with the
   standalone copies present; blood impacts on a spawned citizen and on a ragdoll (pistol, shotgun);
   floor and wall stains; the dynamic toolgun screen live and sharp after upscaling.
5. **44** Physics Blood together with the package's blood impacts: no Lua error, no conflict, its
   pools and flows visible under RTX.
6. **51** one stock dupe save of two props: no `cam.End underflow`, a readable icon (remove your dupe
   afterwards).
7. Frame time in the heaviest scene, and that no device loss happens at 3840x2160.

Write `docs/handover/R20-F-report.md` (a table: item, result, evidence under `out\r20f\`), with
anything that differs from the PoC. No code change is expected; if something is broken, record the
evidence and stop: report it rather than fixing it in this task. Commit only the report (as the
repository's git identity, with the trailer `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`).
Never push, merge, tag or publish.
