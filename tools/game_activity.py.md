# game_activity.py

Read-only Windows gate for R12 game measurements. Enumerates `gmod.exe` executable paths,
foreground ownership and `GetLastInputInfo`; never activates a window, sends game input or
changes any process. Unknown executable paths fail closed. A field game blocks launches while
it owns the foreground window or the user's input is less than ten minutes old.

`python tools/game_activity.py --evidence out/r12-vram/activity.json` checks once. Add `--wait`
to check every five minutes until clear. The JSON evidence contains only this invocation's checks;
use a distinct path for each launch. A clear sample is not a reservation: check again immediately
before launching. Long waits use thirty-second sleeps so the caller can continue other work.

Inputs: the Windows process/window/input APIs and the field root from `poc_session.py`.
Output: JSON to stdout and, optionally, the evidence file (atomically replaced).
Exit: 0 clear, 3 busy for a single check, other nonzero on an API error. No game files are read.
