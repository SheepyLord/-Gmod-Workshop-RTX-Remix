# R20-Q: integration QA of the merged round in the PoC

Worktree `out/worktrees/r20-qa`, branch `r20-qa`, from `r20-int` after the merge of R20-A to R20-E and
the combined runtime (`d3d9.dll` 53e38714, patches 0034, 0035, 0040). Implementer: Codex (gpt-6.1-sol).
Read first: [R20-plan.md](R20-plan.md) (the user's words and the rules for every task) and the five
reports: [R20-A](R20-A-report.md), [R20-B](R20-B-report.md), [R20-C](R20-C-report.md),
[R20-D](R20-D-report.md), [R20-E](R20-E-report.md). Each built its own PoC drivers and fixtures under
its worktree's `out\` (`out/worktrees/r20-menu/out/r20a`, `r20-qol/out/r20b`, `r20-blood/out/r20c`,
`r20-render/out/r20d`, `r20-native/out/r20e`): reuse them rather than starting over.

## Goal

Prove that the merged round works as one package with loader 0.15.0, in the PoC, item by item, and
fix what breaks. Every task tested on its own branch; nothing has run together yet.

## Steps

1. **Refresh the PoC to the field's GMod build** (under the lock, first). The field verifies clean
   against Steam's current manifests (buildid 26439081); the PoC is one update behind (46 files,
   among them `bin/win64/client.dll`). Run `python -I tools\steam\verify_install.py
   H:\SteamLibrary\steamapps\common\GarrysMod_PoC --manifests-from
   H:\SteamLibrary\steamapps\common\GarrysMod --report out\r20q\poc-before.json`, copy exactly the
   reported mismatched depot files from the field (read only) into the PoC, verify again (all OK
   except the user-config `autoexec.cfg`). Record the list. This is the vanilla refresh the PoC copy
   tool describes; touch no other file.
2. **Build** the loader (`tools\build.ps1 -Config Release`) and the RTX package from `packages/`
   (`python tools\build_package.py`), and install them into the PoC the way the task reports did
   (loader via `tools\workflow.ps1 -SkipTests -Install`, the package as an allowlisted local or dev
   package validated by this branch's `nlctl`). Snapshot first; restore exactly at the end.
3. **Check every item** with the merged build, RTX on unless stated, at 1600x900, then the 4K check:
   - **51** stock dupe save of two props: no `cam.End underflow`, a readable icon.
   - **44** Physics Blood (3818841829), and the two other add-ons R20-D used: droplets, pools, flows,
     stains look right under RTX; guard log clean; frame time with the heaviest effects.
   - **48** RTX tab shows the Blood panel and the toolgun screen settings once each (and not in the
     old places); blood impacts on citizens, Combine, zombies, antlions and ragdolls with pistol,
     shotgun, AR2; stains on floors and walls; the effect off gives the stock effect; the dynamic
     toolgun screen works and stays sharp after upscaling.
   - **45** live: start with upscaling or frame generation off in the runtime's effective state (set
     it in memory through `RemixConfig.SetConfigVariable` before the decision, or with a PoC
     `rtx.conf` layer you restore; never write `user.conf`): the right hint appears once, after the
     map is unobstructed; with both on, none; `cl_showhints 0` and the RTX tab checkbox suppress it.
   - **49** fresh profile: time passes, 20-minute day; a profile with the old 0/30 migrates once.
   - **46** main menu reminder with a test record newer than 0.15.0 in a local package (the
     repository record stays 0.14.0): window, buttons, "don't remind me" across a restart; no window
     with the real record. The companion's in-game reminder for a simulated 0.14.0 status.
   - **50** Find Multiplayer Game from the main menu and the pause menu: the warning, Back, Continue,
     dismissed for good across a restart.
   - **4K RTX**: R20-A's two 4K RTX map loads lost the GPU device in the PoC. Repeat at 3840x2160
     windowed (or the largest size that works) on gm_construct with the merged build: does it happen,
     does it happen with the v0.14.0 package too (the runtime from `r20-int~` before 32ce8ca), and
     what the Remix log and loader report say. Diagnose; fix only if the cause is in this round's
     changes, otherwise report it with evidence.
4. **Fix** what breaks, in the owning files, with tests; keep each fix small and say which task's code
   it touches. A runtime change is not expected; if one is needed, stop and report instead.
5. **Report** `docs/handover/R20-Q-report.md`: a table item by item (result, evidence path under
   `out\r20q\`), fixes made, what is open. `tools\test.ps1 -Config Release` passes before your last
   commit.

## Your paths

Fixes in the companion, the loader's menu script, the parts' Lua, tests and docs as needed; no new
binaries in `packages/` unless a fix requires one (one import each). The PoC under the lock. Never
the field install's files (read only), never `user.conf`, never Steam settings.
