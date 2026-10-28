# M1 review (Claude)

- Reviewer: Claude, 2026-10-27
- Branch reviewed: `m1-bootstrap` at `9aed9b3`, against the [brief](M1-handover.md) and the report
  (`docs/handover/M1-report.md` on the `m1-bootstrap` branch; it arrives here when M1 merges)
- Verdict: **accept.** Meets the definition of done. Not yet merged into `main` (waiting on the user).

## How I checked

Read the code that runs inside `gmod.exe` (`loader/proxy/bootstrap.cpp`, `activation.cpp`,
`startup.cpp`) and the installer. Then, in a throwaway detached worktree at `9aed9b3` under `out\`,
ran `tools\test.ps1` and `tools\build.ps1 -Config Release` independently of Codex, plus the export
check and a PE-import check on both DLLs. I did not re-run the in-game smoke test (it needs the live
desktop session); I relied on Codex's evidence and the restored PoC state for that.

## Findings

Independent results matched the report:

- `tools\test.ps1` (Debug) and `tools\build.ps1 -Config Release`: 4/4 CTest, 16 proxy cases, 23
  installer checks, 56 Python tests, conventions OK.
- `generate_exports.py --check`: 181 system ordinals covered, generated files consistent.
- Both `winmm.dll` builds import only `KERNEL32.dll` (no VC++ runtime).
- PoC on disk: no `winmm.dll`, `winmm.pdb` or `native-loader\`; `verify_install.py --manifests-from`
  reports 2,877 depot files OK. The field and RTX installs are untouched.

Code I was satisfied with:

- `DllMain` does only loader-lock-safe work: resolves the system `winmm.dll` by full path (never by
  bare name, which would recurse), gates on host and off switches, installs the entry hook. No
  threads, no waits, no file writes.
- The entry hook restores the original bytes before doing anything and terminates rather than
  re-entering a half-patched entry if restoration ever fails. Logging is wrapped in both a C++ and
  an SEH guard and always continues into the game.
- The host gate correctly excludes the GMod command-line tools (they load `winmm` via `tier0`) and,
  after a real-world find, Chromium helper processes that reuse `gmod.exe` with a `--type` argument.

## One deviation, accepted

The brief placed the worktree at a sibling path (`!NVIDIA-RTX-Remix-M1`) and expected the `m0` tag.
Windows Defender blocked builds and test fixtures outside this repo folder, so at the user's
instruction Codex built inside the repo under `out\worktrees\m1-bootstrap` and kept all scratch
there. I promoted this to a repo rule (AGENTS.md rule 9) on `m2-core` and pointed `build.ps1` /
`test.ps1` at `out\tmp`. The `m0` tag now exists (I added it at the M0 commit).

## Chromium `--type` gate: worth a second look later

Keeping helper processes inert keys on a decoded `--type=<value>` / `--type <value>` token. That is
the right signal today. When M2's discovery and M4's activation run in the start-up step, re-confirm
that the main game process is the only one that passes the gate (Codex's smoke test already asserts
the log PID matches the launched game, which is a good guard to keep).

## Merge note

`m2-core` and `m1-bootstrap` merge cleanly (`git merge-tree` reports no conflicts) once
`loader/CMakeLists.txt` lists the subdirectories in a non-colliding order, which `m2-core` now does.
Shared-doc edits on both branches are additive.
