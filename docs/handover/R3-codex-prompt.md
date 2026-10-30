# R3: setting up Codex, and the prompt to give it

For the user. The review itself is specified in [R3-handover.md](R3-handover.md).

## 1. Before starting Codex

1. **The worktree.** The brief is committed on `main`; Codex gets its own worktree on a new branch, so
   the main checkout stays on `main`. Claude can do this for you; the command is:

   ```powershell
   git -C "H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix" worktree add out\worktrees\r3-review -b r3-review main
   ```

   It checks out `packages\` with its real content from the shared `.git\lfs` (about 1.8 GB on disk
   once unpacked by a build), without the network.

2. **Run Codex locally on this PC** (CLI, IDE extension or desktop app), with its working folder set
   to `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r3-review`. Codex Cloud is not
   suited: the review needs the MSVC Build Tools, the Git LFS content (a cloud clone would spend about
   0.6 GB of the account's 10 GiB monthly LFS bandwidth) and, for context, the runtime fork's clone on
   this machine.

3. **Sandbox configuration**, in `%USERPROFILE%\.codex\config.toml`:

   ```toml
   sandbox_mode = "workspace-write"
   approval_policy = "on-request"

   [windows]
   sandbox = "elevated"   # "unelevated" if you cannot approve the admin set-up
   ```

   - Leave network access off.
   - Writable: only the worktree. Everything else it reads (the fork's clone, the add-ons'
     repositories, the main checkout's `out\workshop\published.json`) stays read-only.

4. **Expect approval prompts:** `git commit` of the report (a worktree keeps its git data in the main
   checkout's `.git`, outside the working folder), and possibly `tools\test.ps1` if the sandbox account
   cannot run Python from your profile.

5. **Close every GMod before Codex runs the tests.** The deployer counts a `gmod.exe` whose folder it
   cannot read as a running game, and the synthetic deployment tests would then fail. Codex never
   launches GMod itself.

6. **Disk:** about 4 GB on `H:`: the Debug and Release builds, the unpacked inputs and one package build.

7. **Already on this machine, nothing to install:** VS 2022 Build Tools, Python 3.12 with Pillow and
   numpy, git with Git LFS, LuaJIT (the companion's tests run under it).

## 2. The prompt (paste as Codex's first message)

```text
You are doing review R3: a thorough, independent review of this whole repository for robustness,
stability and bugs. Working folder: H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r3-review,
branch r3-review: main as pushed, with your brief.

1. Read AGENTS.md, then docs/handover/R3-handover.md. The brief is your task specification: scope,
   order, boundaries, severity scale and report format. AGENTS.md rules always apply.
2. Run the baseline first (brief, section 5): tools\test.ps1, tools\build.ps1 -Config Release, then
   python tools\build_package.py --require-nlctl --out out\r3-review\dist --compare
   H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\workshop\published.json
   and record the summary lines. If the tests or builds fail on this clean worktree, stop and tell me.
3. Review in depth everything since R1 (git diff afe1fb9 HEAD), in the brief's order: the code inside
   gmod.exe first, then the runtime's sky patch (runtime/patches/0004-*.patch), then the build and
   publish toolchain (tools/inputs.py, build_package.py, publish_workshop.py and its hooks, the
   packagers, the CI workflows, runtime/build_runtime.ps1), then the companion, packages/ and
   licences, the tools that touch installs, the tests and the docs. Read the rest as context.
4. Review; do not fix. Change no production code, tests, tools, docs or packages\. If you change
   something to reproduce a finding, revert it and keep the repro under out\r3-review\repro\.
5. Never commit to main, merge or push: main's hooks publish the Workshop item, and a push uploads Git
   LFS content. Never run tools\publish_workshop.py, gmpublish, git lfs push, git lfs pull or
   inputs.py import. No network. Never launch GMod or write to a game install. Never touch the runtime
   fork's checkouts or branches, or the add-ons' repositories. Never read a console.log from my installs
   or anything under out\m7\snapshot\. Never set RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES.
6. Write docs/handover/R3-report.md as section 8 of the brief describes and keep its coverage table
   current as you go. Commit only that file, on r3-review.
7. If you run short of context or time, finish the area you are in, commit the report with its
   coverage table, and tell me what is left. I will start a new session to continue.
8. When done, give me a short summary: the number of findings at each severity, and the three that
   matter most.
```

## 3. After Codex finishes

- The report and its commit are on `r3-review`, in the worktree. Nothing is pushed or merged.
- Tell Claude the report is ready, with Codex's summary and any questions it asked you. Claude then
  verifies every finding, writes `R3-triage.md` (each finding accepted or rejected, with the reason),
  fixes the accepted ones on a new branch, runs the tests and PoC sessions where they matter, and
  merges with your OK.

**To continue an interrupted review,** start a new Codex session in the same worktree with the same
prompt, plus: "Continue from the coverage table in docs/handover/R3-report.md."
