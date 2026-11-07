# R22 report: a loading window for the first start, and the frame generation hint at the top right

Claude did this round alone, as the user asked ("For this task, don't use CodeX, do everything
yourself"), on branch `r22` in `out/worktrees/r22`. Loader **0.16.0**.

## The user's words (2026-11-07, item 52, verbatim)

> 1. (High) The game, in the first time installation, will take a long time to load (for unpacking
> stuff) for the gmod.exe to actually show up and user think their game is not working so they
> terminate it after 15 seconds. Something should be shown to let user know the game is loading and
> unpacking files.
> 2. (Low) The hints to enable framegen are not obvious, while keeping the current game hint approach,
> also add hints that show on top right on user's like the Hotloader's warning. This warning expires
> after 15 seconds.

## What was built

| Item | Built | Decision |
|---|---|---|
| 52.1 the first start looks dead | The bootstrap shows a loading window of its own from the start of its work until the game's own window appears: "Preparing RTX Remix", what is happening and that the game opens by itself, a progress bar and a status line (checking installed files; unpacking files: done of total, percent; putting files in place; starting Garry's Mod), in the game's language (seven catalogs). It opens only for an unpack of at least 64 MiB or a start-up longer than 3 s, never for an ordinary start; it never takes focus; `NATIVE_LOADER_LOADING_WINDOW=0` turns it off. The deployer reports its phase and the bytes it unpacks. The loader's windows now also follow Steam's language for the game. The player README's first-start note is corrected (about 7 GB, a minute or more) | [0128](../decisions/0128-a-loading-window-while-start-up-unpacks.md) |
| 52.2 the hint is not obvious | The sandbox hint stays; the same advice also shows in a notice at the top right like the Model Hotloader's ("RTX Remix", the advice, a close button), for 15 seconds, scaled for 4K, below another notice in that corner. It shows even with `cl_showhints 0`; the RTX tab's checkbox turns both off | [0129](../decisions/0129-the-upscaling-hint-also-at-the-top-right.md) |

**Why the hint was not seen.** The PoC check found `"cl_showhints" "0"` in the user's own game
(`garrysmod/cfg/client.vdf`, which Steam Cloud does not carry). Under ADR 0117 that setting suppressed the
whole hint, so that game had shown no advice at all; the notice now shows regardless.

## How it was checked

- **Native tests:** `nl_proxy_tests` gains ten loading-window cases (`test_loading.cpp`): the switch, when it
  shows, percent and sizes per catalog, the status line per phase, the language order, and the real
  window on its own thread (opens without activation, little CPU while open, closes when a window of the
  process appears or after its wait, never opens for a quick start). The import table stays KERNEL32-only.
- **Lua tests:** `test_companion_qol.py` adds the notice at 1080p, 4K and 720p, with sandbox hints off and
  with the RTX checkbox off.
- **PoC, a real first start** (`out/r22/poc_qa.py`; evidence `out/r22/qa2`, `out/r22/qa3` in the worktree):
  the PoC's loader folders were moved aside, the branch's loader 0.16.0 and package installed from nothing
  deployed, then an ordinary start. The loading window opened 0.58 s into the first start, showed the
  unpack (7.3 GB, 46.7 s of deployment) and closed 0.1 s after the game's own window appeared (48.3 s);
  the ordinary start (0.33 s of deployment) showed none. With the user's `cl_showhints 0`, the notice showed
  at the top right (1280x720: 333 x 64 at x 934, y 27) and went after its 15 seconds. Both runs quit
  normally with the field's settings; every moved folder and file came back unchanged and the depot
  rollback was clean.

- **The whole suite:** `tools\test.ps1 -Config Release` passes: 27 of 27 native tests and 741 Python tests
  (29, 26 and 686; two optional skips).
- **ADR 0126's module record:** the version bump and the deployer's change are among the recorded sources
  of the two modules this repository builds, so `tools/ci/repo_builds.py refresh` rebuilt and imported
  `gmsv_nlrtxclient_win64.dll` and `gmcl_nlglass_win64.dll`. Their own code did not change: the new images
  have the old sizes and no version text, and differ only in link stamps and the debug path, which names
  another build folder (`r22` instead of `r20-qa` and `r19-glass`), so the stored copies could not be kept.

## Found and fixed while building

- The first window redrew on every pass of its loop, so a paint was always pending: the wait returned at
  once, the thread spun and never saw the end of start-up. Redraws now come from a timer and the event is
  checked on every pass; a test bounds the window's CPU use.
- Closing an active window handed activation to the game's window, whose thread can be busy: the window is
  never active now (no focus taken, nothing handed over).
- `poc_session.game_window` takes any window titled with "Garry's Mod": the loading window is titled
  "RTX Remix".

## Open

- **The loader change reaches players with a loader release.** Loader 0.16.0 is built and tested here;
  releasing it (a `v0.16.0` tag, then the package record) needs the user's go-ahead.
- The package change (the notice) is published with this round's push of `main`, as a local build.

## Published (2026-11-07 UTC)

`main` was pushed at `156138d` (two Git LFS objects, the refreshed modules). The merge's hook built the
package here and uploaded it to item 3829070317 as **0.0.0-dev.20261107074707+ea3267dc** (2,181,716,693
bytes, SHA-256 `23a3b3a80b321514b356b0f62d111277523f609a5185318cc7e1c53ec9c3a29a`); Steam's public record
shows that size, updated 07:47:43 UTC. The notice reaches players with it; the loading window needs loader
0.16.0, which is not released yet.
