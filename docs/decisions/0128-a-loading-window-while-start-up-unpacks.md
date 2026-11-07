# 0128: A loading window while start-up unpacks the package

- Status: Accepted 2026-11-07 (R22, the user's item 52.1; loader 0.16.0)
- Context: the user reported that "in the first time installation, will take a long time to load (for
  unpacking stuff) for the gmod.exe to actually show up and user think their game is not working so
  they terminate it after 15 seconds. Something should be shown to let user know the game is loading
  and unpacking files."

## Context

The bootstrap does its start-up work at the game's entry point, before Garry's Mod runs any code of its
own ([ADR 0008](0008-activation-at-startup.md), [ADR 0009](0009-startup-deployment-last-good.md)): it
plans, unpacks the packages' files and activates the runtime, and only then calls the original entry
point, which creates the game's window. A first start after installing the RTX package, or after an
update, unpacks it: in the PoC, 2,324 changes in 61.8 s (`deployment.elapsed_ms`, R21-A's fresh
deployments 42-62 s) with nothing on screen, longer on a slower disk. An ordinary start, with nothing to
unpack, takes 34-590 ms. Killing the game in the middle is safe (the next start undoes the interrupted
transaction), but it only starts the wait again.

## Decision

1. **A window of the bootstrap's own**, on a thread of its own, opened before deployment and told when
   start-up work is over. It names what is happening ("Preparing RTX Remix": the first start after
   installing or updating unpacks the package's files, it can take a few minutes, keep the game running,
   it opens by itself), shows a progress bar and a status line: checking installed files; unpacking
   files: done of total (percent); putting files in place; starting Garry's Mod. The bar fills while
   files unpack and moves while the amount is not known.
2. **Progress from the deployer.** `deploy::Options::progress` (a `deploy::Progress` of relaxed atomics)
   receives the bytes the run will unpack (the packages' files to stage, known before extraction), the
   bytes unpacked (counted in the staging sink as they are written and hashed) and the phase. `nlctl`
   passes none; nothing else changes in the deployer.
3. **Only for a real wait.** The window opens when the run unpacks at least 64 MiB (after a 0.4 s grace)
   or when start-up work has gone on for 3 s; an ordinary start never shows it. `NATIVE_LOADER_LOADING_WINDOW`
   `0`/`off` turns it off, `always` opens it at once (screenshots, tests).
4. **Until the game's window appears.** Once start-up work is over, an open window stays until this
   process shows a visible window of its own (the game's) or two minutes pass, so there is no blank gap
   between the two. A window that never opened never opens late.
5. **It never costs the game anything.** `start()` and `finish()` only create a thread and set an event;
   the start-up report notes whether and when the window opened. The window never takes activation
   (`WS_EX_NOACTIVATE`, shown with `SW_SHOWNOACTIVATE`): it takes no keyboard focus and, when it closes,
   hands no activation to the game's window, whose thread may be busy loading. Its title bar has no
   buttons and it ignores Alt+F4: closing it would not stop the work. A taskbar button shows the game is
   starting. Faults in the window's thread end that thread only (C++ and SEH guards).
6. **The import table stays KERNEL32-only** (the M1 rule, checked by `check_imports.py`): user32 and gdi32
   are bound at run time, as the observer does.
7. **Crisp at any scaling.** The window's thread is per-monitor DPI aware (V2); the game's thread is not
   touched. It follows `WM_DPICHANGED`.
8. **The game's language.** Its text is in the seven catalogs of `ui/labels.json` (`loading_*`, with
   localized size units and decimal marks). The language is `+gmod_language`, then `config.cfg`'s
   `gmod_language`, then Steam's language for the game (`appmanifest_4000.acf`, `UserConfig/language`,
   which the game itself uses while `gmod_language` is unset), then Windows'. The exit report gets the
   Steam step too.

## Consequences

- A player sees what is happening from the first second of a long start, in their language, and the
  window gives way to the game's own.
- Only loader 0.16.0 and later has the window: the update reminder ([ADR 0115](0115-released-loader-record-and-reminders.md))
  brings players to it once 0.16.0 is released.
- Rejected: a separate helper process (the observer's rundll32 host) for the window. It would isolate
  the window further but needs a second process launch, an IPC channel for the progress and its own
  lifetime rules, for a window that only draws.
- Rejected: speeding the unpack up instead. Worth doing, but no speed-up makes a minute on a slow disk
  invisible.
