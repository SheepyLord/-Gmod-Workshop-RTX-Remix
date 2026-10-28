# test_poc_session.py

Unit tests for [`poc_session.py`](../poc_session.py.md), without a game. `subprocess.Popen`,
`console()`, the window and module lookups and the clock are mocked, so no game is ever started and
no test waits. Scratch goes in a temporary folder under `out\tmp`.

```powershell
cd tools; python -m unittest tests.test_poc_session -v    # or tools\test.ps1
```

Covers:

- **Client Lua through the console (R1-015).** The lines carry Lua full of `;`, line breaks, `//`,
  quotes and non-ASCII text, hex-encoded. No line holds a character the console treats specially,
  every line stays under Source's 512-byte command limit, and the chunks decode back to the code.
  Each line goes through `console()`, and a failed line stops the rest.
- **`step_run` writes nothing into the game folder for client Lua.** A reference run leaves an
  existing `garrysmod\data\nl_session\` (R1-015's repro) and the rest of the folder exactly as it was.
  A run with `--camera` sends exactly the expected console lines and creates no `garrysmod\data`.
- **Ending only what a run started (R1-019).** `classify` takes the launched game and its
  descendants, a helper reached through a non-game process included. It leaves out a game with
  another parent, one older than the launch, one whose parent PID was recycled by a newer process,
  a parent cycle and an unknown creation time. A same-root game that appears after the preflight is
  not terminated and is recorded as `not_ours` (R1-019's repro). At a quit timeout, the game is
  killed through its handle and only its two helpers are terminated, with their creation times.
- **Real processes.** One test starts a Python child that starts a grandchild. Toolhelp32 parents and
  creation times must classify both as the launch's. `terminate` must refuse a mismatched creation
  time and end the grandchild with the right one. Both are ended afterwards.
- **The install step's config guard (R1-026).** A different existing `config.json` is refused before
  the installer runs and stays as it was. `--replace-config` saves it in the evidence folder first,
  and the record names the copy and its SHA-256. The same config needs no flag and gets no backup. A
  config changed while the installer runs is kept, and the step fails. The command line wires
  `--replace-config` through to the session record.
- **PowerShell's module path (R1-029).** `install` and `uninstall` start both installer scripts
  without `PSModulePath` and with the rest of the environment. A real Windows PowerShell child
  must find `Get-FileHash` while this process's `PSModulePath` starts with a stand-in for
  PowerShell 7's `Microsoft.PowerShell.Utility`, a Core-only module 5.1 cannot load. That case is
  skipped when `powershell` is not installed.

Side effects: the temporary folders, removed afterwards, and two short-lived Python processes.
Exit code: unittest's (0 when all pass).
