# R6 T2: the last session's evidence, memory telemetry, RAM warning (loader)

Read [R6-plan.md](R6-plan.md) first: its rules, decisions and interfaces bind this task. Background in
[R5-stability-proposal.md](R5-stability-proposal.md) proposals 3, 5 (part 1) and 11 (the menu panel
warning), and sections 1.7, 3 and 4. Branch `r6-t2-evidence`, worktree `out\worktrees\r6-t2-evidence`.
ADR number 0063.

## 1. Keep the last session's evidence at the next start (proposal 3)

Before the bootstrap loads the runtime (which truncates `rtx-remix\logs\remix-dxvk.log` when it opens
it, `src/util/log/log.cpp:72-79` in the fork):

1. Read the last part of `rtx-remix\logs\remix-dxvk.log` (bounded, e.g. the last 256 KiB) and classify
   the previous session: `device_lost` (`VK_ERROR_DEVICE_LOST`, "Exiting after GPU device loss"),
   `cs_exception` ("Exception on CS thread"), `allocation_failed` ("Memory allocation failed"),
   `clean` (a normal shutdown marker, if the log has one; find it), else `unknown`. Read
   `rtx-remix\logs\last_gpu_crash.json` when present (interface I7, written by T4's runtime patch; every
   field optional).
2. Find crash files newer than the previous start (the loader knows its previous start time from its
   own records; add one if needed): `rtx-remix\logs\.sentry-native\last_crash` and `reports\*.dmp`,
   `garrysmod\..\crashes\*.dmp` and `*.txt` in the game root's `crashes` folder (a `.txt` or dump holding
   "OUT OF MEMORY!" marks `out_of_memory`), `native-loader\logs\gpu\*` (Aftermath dumps, interface I4),
   and the tail of `native-loader\logs\memory.csv` (section 2).
3. If anything was found (or the class is not `clean`), copy the log and those files into
   `native-loader\logs\sessions\<UTC time>-<reason>\`. Keep the newest five folders and at most 200 MB in
   total; never delete, move or change an original. Copy with the share modes that do not block another
   reader, and skip files that are locked.
4. Write interface I5 (`status.json` `previous_session`). `nlctl` prints it. The main menu panel (ADR 0050)
   shows one line when the reason is not `clean`/`unknown`: what happened and the folder. Its strings
   follow the panel's localisation, all seven languages.

Time budget: this runs on the start-up path before the runtime loads; keep it to a few milliseconds when
there is nothing to copy (measure it, report the numbers) and do the copying off the critical path if it
can take longer (a worker that finishes before the bootstrap exits its start-up phase, or after).

## 2. Memory telemetry (proposal 5, part 1)

- A low-priority thread in the bootstrap appends one CSV line every 10 s to
  `native-loader\logs\memory.csv`: UTC time, the process's private bytes and working set
  (`K32GetProcessMemoryInfo`), system commit, commit limit and available RAM (`K32GetPerformanceInfo`),
  and this process's GPU local and non-local usage and budget (`IDXGIAdapter3::QueryVideoMemoryInfo`
  on the adapter the runtime uses or the largest NVIDIA one; DXGI loaded at run time as `activate.cpp`
  does, so the proxy's import table stays as it is). Flush each line. Keep about the last two hours
  (rotate to `memory.1.csv`). On by default; `config.json` `diagnostics.memory_telemetry`
  (`on` default, `off`).
- The proxy's import table must not grow (check what the existing tests assert about it).

## 3. RAM warning (proposal 11)

The main menu panel warns, once per start, when the system commit limit is under 32 GiB, or when more
than 70 % of it is in use when the panel is shown before a map loads. Text: what it means and the two
fixes (a system-managed page file on a drive with room; close other programs), all seven languages.

## Tests, docs, limits

- Unit tests with fixture logs and files in a temporary game root (each class, the bounds, locked files,
  nothing to copy), the telemetry line format and rotation, the warning's thresholds.
- ADR 0063; CHANGELOG; `docs/ON_DISK_LAYOUT.md` (the new folders and files); `docs/TESTING.md`; RESEARCH.
- Do not touch `companion/`, `packages/`, `runtime/`, or the layer list in `activate.cpp` (T1 changes
  it). Additive edits only in `status.cpp`, `nlctl.cpp`, `diagnostics.cpp`, `config.cpp`. No version bump.
- You may not launch the game.
