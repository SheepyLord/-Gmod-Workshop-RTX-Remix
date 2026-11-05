# guard_session_marker.lua

CTest `nl_guard_session_marker` (R19, proxy F-02): the companion's render guard,
[`_nativeloader_guard.lua`](../../../companion/nativeloader/lua/autorun/_nativeloader_guard.lua.md),
installs only in this start's RTX session. This script runs the production file under LuaJIT once per
case, with only what the guard's installation decision reads: `CLIENT`, `SERVER`, `MENU_DLL`, the early
view's flag, and a fake `file` library that answers `file.Read("native-loader/status.json", "DATA")`,
`file.Exists` and `file.Find` for the session marker `native-loader/rtx-session.txt`. The guard's
first call after that decision is `CreateClientConVar`, which ends the run, so a case passes when the
guard reached it exactly when expected.

The 18 cases:

- loader 0.14.0 or later, RTX active, the marker held (seen by `file.Exists`, or only by the
  `file.Find` listing, or with `file.Exists` raising): installs, by the early view too;
- the finding: the same report with no marker (a start through an off switch after an RTX start, also
  with an early view a listen host served): does not install;
- loader 0.13.x and 0.10.1 reports: decide alone, as before (they hold no marker);
- a report of RTX off, or of a failed activation, next to another game's marker: does not install;
- no report, or one that is not the loader's: the marker alone decides.

Usage (CTest passes these): `luajit guard_session_marker.lua <path to _nativeloader_guard.lua>`.
Reads only that file; writes nothing. Prints `ok`/`FAIL` per case and `PASS guard session marker: 18
cases`; exit code 0 when every case passes, 1 otherwise. CMake registers the test only when it finds
`luajit` on `PATH` or in `%LOCALAPPDATA%\Programs\LuaJIT\bin`, as `tools/tests/test_render_guard.py`
skips without it. It checks the decision only: the guard's policies are the harness in `tools/tests`,
and the game itself is the integrator's check.
