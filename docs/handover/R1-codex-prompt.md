# R1: setting up Codex, and the prompt to give it

For the user. The review itself is specified in [R1-handover.md](R1-handover.md).

## 1. Before starting Codex

1. **Baseline.** The brief is committed on `main`, on top of `8f8a540`, and Codex gets its own
   worktree, so the main checkout stays on `main`. Both are local steps; Claude can do them for you.
   The worktree command is:

   ```powershell
   git -C "H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix" worktree add out\worktrees\r1-review -b r1-review main
   ```

2. **Run Codex locally on this PC** (CLI, IDE extension or desktop app), with its working folder set
   to `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r1-review`. Codex Cloud cannot do
   this review: it needs the MSVC Build Tools and this machine's folders.

3. **Sandbox configuration**, in `%USERPROFILE%\.codex\config.toml`:

   ```toml
   sandbox_mode = "workspace-write"
   approval_policy = "on-request"

   [windows]
   sandbox = "elevated"   # "unelevated" if you cannot approve the admin set-up
   ```

   - If `[sandbox_workspace_write]` still lists the PoC from M4, remove that entry: R1 writes nothing
     outside its worktree.
   - Leave network access off.

4. **Expect approval prompts:**
   - `git commit` of the report. A worktree keeps its git data in the main checkout's `.git`, outside
     Codex's working folder.
   - Possibly `tools\test.ps1`, if the sandbox account cannot run Python from your user profile.

5. **Close every GMod before Codex runs the tests.** The deployer counts a `gmod.exe` whose folder it
   cannot read as a running game. A sandbox account may not be able to read your game's process, and
   the synthetic deployment tests would then fail. Codex never launches GMod itself.

6. **Disk:** about 1 GB on `H:` for the Debug and Release builds in the worktree.

7. **Already on this machine, nothing to install:** VS 2022 Build Tools, Python 3.12, git and `pefile`.
   LuaJIT is not needed; the one test that uses it is skipped without it.

## 2. The prompt (paste as Codex's first message)

```text
You are doing review R1: a thorough, independent code review of this whole repository, before the
native loader goes into the user's real game for good.
Working folder: H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r1-review, branch
r1-review: main (M0-M7, pushed) plus the commit that adds your brief.

1. Read AGENTS.md, then docs/handover/R1-handover.md. The brief is your task specification: scope,
   order, boundaries, severity scale and report format. AGENTS.md rules always apply.
2. First run tools\test.ps1, then tools\build.ps1 -Config Release, and record the results. If they
   fail on this clean worktree, stop and tell me.
3. Review; do not fix. Change no production code, tests, tools or docs. If you change something
   temporarily to reproduce a finding, revert it; keep its code and output under
   out\r1-review\repro\.
4. Never launch GMod. Never write to any game install (the PoC included), GarrysMod_RTX_c, the fixes
   checkout or the Remix fork. Never read a console.log from my installs, or anything in the main
   checkout's out\m7\snapshot\. No network.
5. Write docs/handover/R1-report.md as section 8 of the brief describes, and keep its coverage table
   current as you go. Commit only that file, on r1-review. Never push, merge or rewrite history.
6. If you run short of context or time, finish the area you are in, commit the report with its
   coverage table, and tell me what is left. I will start a new session to continue.
7. When done, give me a short summary: the number of findings at each severity, and the three that
   matter most.
```

## 3. After Codex finishes

- The report and its commit are on `r1-review`, in the worktree. Nothing is pushed or merged.
- Tell Claude the report is ready, and paste Codex's summary and any questions it asked you.
- Claude then:
  1. verifies every finding;
  2. writes the triage: each finding accepted or rejected, with the reason;
  3. fixes the accepted findings on a new branch;
  4. runs the tests, and real PoC sessions where they matter;
  5. merges with your OK.
- If you want Codex to check the fixes, Claude writes a short brief for that second round.

**To continue an interrupted review,** start a new Codex session in the same worktree. Give it the
same prompt, plus: "Continue from the coverage table in docs/handover/R1-report.md."
