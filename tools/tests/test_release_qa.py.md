# test_release_qa.py

Unit tests for [`qa/release_qa.py`](../qa/release_qa.py.md), without a game: nothing is launched, and
scratch goes in a temporary folder under `out\tmp`.

```powershell
cd tools; python -m unittest tests.test_release_qa -v    # or tools\test.ps1
```

Covers:

- **Command lines.** A field session mounts the Workshop, keeps the game's own window settings
  (`--no-window`), takes the menu screenshot only in the first session, passes the launch options
  given with `--extra` and leaves `mat_queue_mode` to the user's settings. A PoC session mounts only
  the modern_house map item (`--mount-workshop 3495468649 --change-map modern_house`) and switches on
  queued rendering; `sv_cheats 1` goes only to the glass sessions.
- **Pass rules on a record.** A good record passes; a crash (no normal quit, its exit code), an
  unfinished probe, an inactive runtime and a step that failed before the launch do not.
- **Pass rules on probe output.** The session probe needs the guard without errors before and after
  the toolgun and a toolgun redraw with draws and no error; the spawn-menu probe needs its tab list and
  no missing tab; the map glass needs shards after the first shot; the spawned pane must break into
  more shards than it had.
- **`--evaluate-only`.** The latest run of each session is checked (an earlier failed run of the same
  session does not count), `qa-summary.json` is written, and the exit code is 0; a crash with kept
  minidumps or a session with no recorded run fails the summary with exit code 1.

Side effects: the temporary folders, removed afterwards. Exit code: unittest's (0 when all pass).
