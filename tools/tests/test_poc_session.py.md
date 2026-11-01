# test_poc_session.py

R7-B verifies that launches force `NATIVE_LOADER_EXIT_REPORT=quiet`, overriding an inherited
`off`, so post-exit evidence stays enabled without an unattended dialog.

Unit tests for [`poc_session.py`](../poc_session.py.md), without a game. `subprocess.Popen`,
`console()`, the window and module lookups and the clock are mocked, so no game is ever started and
the session clock is simulated. Watchdog/capture tests use short real thread waits with bounded
event synchronization. Scratch goes in a temporary folder under `out\tmp`.

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
- **A Lua file that paces its own screenshots.**
  - `--lua` sends the file through the console, behind a first line that prints `NL_SESSION_LUA 1`.
  - With `--lua-shots`, each `NL_SHOT <label>` line it prints gives one screenshot, named
    `shot-<nn>-<label>.png`, and is answered with `nl_shot_taken <nn>`.
  - `NL_SHOT_DONE` ends it. The record has the labels in order and `lua_shots_done`.
- **With `--workshop`, no map before the Workshop is mounted.** The command line carries no `+map`
  and no `-noworkshop`, and carries `-multirun`. `map gm_construct` goes through the console only after the second
  `Mounted ... workshop addons!` line and 5 s of quiet. Without `--workshop` the map stays on the
  command line.
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

- `test_a_partial_first_mount_waits_for_a_remount_for_a_while` (R3-013): `Mounted 3 of 755` first, then a
  remount: the map waits for the second mount (`workshop_ready_by` "the remount"); without a remount it is
  sent once `PARTIAL_MOUNT_GRACE` has passed.
- `test_crash_report_prompts_are_declined_never_accepted` (R4): the question gets `IDNO`, the notice
  `IDOK`, never `IDYES`; a run answers them while it waits for the map and records how many.
- `test_crash_minidumps_are_kept_before_the_declined_prompt_deletes_them` (R4): a dump waiting from an
  earlier crash is copied into `crash-reports-before\` before the launch, and a crashed run's own into
  `crash-reports\`, both named in the record.
- `test_the_menu_shot_is_taken_at_the_menu_before_the_map` (R4): `--menu-shot` captures `menu.png` once
  the Workshop is mounted and before `map` is sent.
- **R6 unattended failure handling.** Fake process/windows/logs exercise both device-loss markers,
  an old log (unchanged, appended and rewritten), a persistent hung window, the 20 s continuous-hang
  grace and recovery during a normal 12 s load stall. Console retries check health after a 10 s
  send; known hung windows receive neither console text nor capture calls. A frozen capture worker
  times out and cannot save a late image; capture success and errors are checked too.
- **Watchdog lifetime and evidence.** A real background thread polls fake prompts, survives a
  temporary lookup error, counts successful No/OK answers only and stops on process exit or explicit
  close. Prompt sends have a bounded timeout. A crash after map startup shows its prompt during the
  exit grace: the watchdog copies its dump before the fake runtime deletes it, declines the prompt
  and allows the Remix GPU-crash exit without a kill. The consent-granting environment flag is removed.
  Device loss or a persistent hang skips subsequent operations, bounds the exit wait at 60 s and
  keeps console/Remix logs, modules and dumps. Known exit codes (signed and unsigned) get names and
  hex values without losing the numeric exit; the CLI persists failed records and returns 1.
- A temporarily locked Remix log still allows hang detection. A failed dump-copy retry preserves
  the previous complete evidence file. A capture timeout follows bounded session cleanup and still
  collects the logs.
