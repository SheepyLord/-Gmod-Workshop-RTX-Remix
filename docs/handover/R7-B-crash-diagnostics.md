# R7-B: an exit report after a crash, and the diagnostics (brief)

Read [AGENTS.md](../../AGENTS.md), [R7-plan.md](R7-plan.md), and for the existing evidence and diagnostics
[R6-report.md](R6-report.md) and [R6-T2-evidence-telemetry.md](R6-T2-evidence-telemetry.md). Work on branch
`r7-crash-diag` in `out/worktrees/r7-crash-diag`. Owns: `loader/**` (core, proxy, tests), `tools/poc_session.py`
and its tests/doc if automation needs it, `dist/README-native-loader.txt` if it mentions the change, a new
ADR, and additive edits to CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS. Does not touch `glass/**`,
`packages/**`, `runtime/**`, `skills/**`.

## 1. The exit report (the user's point 2, moderate)

The user: "when a crash (such as not enough memory) and game exit, display the error message and reason to
exit to the user (if known)". Today the reason is only worked out at the **next** start
(`loader/core/src/evidence.cpp` `collect`/`classify`: `out_of_memory`, `device_lost`, `allocation_failed`,
`cs_exception`, `crash`) and shown in the main menu's diagnostics as "Previous session". Add a report the
user sees right after the game closes abnormally:

- One message (a native dialog is fine) naming the reason in plain words and what to do, in the user's
  language (the seven of `loader/proxy/ui/labels.json`), and where the evidence folder is. For example:
  out of memory: Windows ran out of committed memory; use a system-managed page file on a drive with free
  space, close other programs, or pick a lower performance tier. Device lost: the GPU driver reset; update
  the driver, lower settings. Unknown crash: the exception code if known.
- It must work when the game dies of the very thing it reports (no memory, a fail-fast, a stack overflow,
  a Remix fatal exit such as "Exiting after GPU device loss"), so the observer is outside the game
  process. The end-user install is one file (`bin\win64\winmm.dll`, AGENTS.md): the observer must come from
  that file (for example a `rundll32` entry point of the proxy with a guard so nothing of the loader runs
  in that host, or another way you justify), started at startup, waiting on the game process handle, and
  gone when the game is gone.
- Reason sources, best first: the exit code (`0xC0000017`, `0xC0000005`, `0xC0000409`, `0xC00000FD`,
  `0xE06D7363`, ...), the Remix log tail (`rtx-remix/logs/remix-dxvk.log`: device loss, "Memory allocation
  failed", "Exception on CS thread"), a fresh Remix crash dump, the memory sampler's last commit sample
  (near the limit means likely out of memory). Reuse `classify` so the dialog and the next start agree.
- Nothing on a normal quit (exit code 0, or the engine's own `quit`), when the loader is disabled, or for a
  game the observer did not start for. Remix shows its own crash prompt first (it asks about sending a
  dump); the report comes after the process is gone and must not stack under it.
- Automated sessions must not be blocked: `tools/poc_session.py` and the test hosts start games
  unattended. Give them a documented way to keep the dialog off or to read the report without a window
  (for example an environment variable they set, plus the report written as JSON next to the evidence).
  Never use `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES`: it grants Remix crash-dump consent.
- Claude must be able to check it on the PoC without a real out-of-memory crash: a documented way to show
  each reason (for example a test switch of the observer, or ending a game with a chosen exit code).

## 2. The memory warning (the user's point 4a, low)

`loader/core/src/memory.cpp` `commit_warning(used, limit)` warns when the commit limit is under 32 GiB or
the system commit is above 70 % of it. The user's machine (61.6 GiB RAM, commit limit 90.6 GiB, 64.0 GiB
committed at the menu, 26.6 GiB free) was warned; that makes no sense. Warn only when a map load with RTX
would plausibly not fit: base the rule on free commit (limit minus used) against the headroom a map load
needs, from the R6 measurements in [RESEARCH.md](../RESEARCH.md) (runtime memory snapshots) and the tiers;
keep a sensible floor for small limits. 64.0 / 90.6 must not warn; state the rule and its source in the
code and the docs; boundary tests in `loader/tests/test_memory.cpp`. Adjust the message text in all seven
languages if the rule's meaning changes.

## 3. The add-on list (the user's point 4b, low)

`loader/proxy/ui/mainmenu.js` lists every deployed package with its version and hash. Show the package
`gmod-rtx-remix` (the RTX package) in full as now, and for the others only how many are enabled (one line,
for example "Content add-ons: 4 enabled"), in the panel and in the copied text. New labels in all seven
languages.

## Tests and report

Unit tests for each part (classification at exit for each source, no report on a normal exit, the
automation switch, the memory rule's boundaries, the add-on line). `tools\test.ps1 -Config Release` must
pass; commit on `r7-crash-diag` (no push, no merge, no game install changed, no Workshop item). Report in
`docs/handover/R7-B-report.md`: commits, design (the observer, why), how Claude shows each reason on the
PoC, test counts, limits.
