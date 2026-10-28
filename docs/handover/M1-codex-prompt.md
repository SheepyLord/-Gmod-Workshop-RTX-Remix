# M1: setting up Codex, and the prompt to give it

For the user. The task itself is specified in [M1-handover.md](M1-handover.md).

## 1. Before starting Codex

1. **Baseline.** The M0 scaffold and these handover docs are committed on `main` and tagged `m0`.
   The worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix-M1` exists on branch `m1-bootstrap`.
2. **Run Codex locally on this PC** (CLI, IDE extension or desktop app), with the M1 worktree as its
   working folder. Codex Cloud cannot do M1: it needs the MSVC Build Tools, the PoC install, the GPU
   and your running Steam client.
3. **Sandbox configuration**, in `%USERPROFILE%\.codex\config.toml` (or a `.codex\config.toml` in the
   worktree, which Codex reads only for trusted projects):

   ```toml
   sandbox_mode = "workspace-write"
   approval_policy = "on-request"

   [sandbox_workspace_write]
   writable_roots = ['H:\SteamLibrary\steamapps\common\GarrysMod_PoC']

   [windows]
   sandbox = "elevated"   # "unelevated" if you cannot approve the admin set-up
   ```

   Single-quoted TOML strings keep the backslashes literal. Leave network access off; M1 needs none.
4. **Expect approval prompts**, and approve them once at a time:
   - `git commit`: Codex's Windows sandbox protects `.git`;
   - starting GMod for the smoke test: it must run in your desktop session to reach Steam;
   - possibly `tools\test.ps1`, if the sandbox account cannot run Python from your user profile.
5. **Keep Steam running and logged in.** Do not play GMod while Codex runs the smoke test.
6. Already on this machine, nothing to install: VS 2022 Build Tools, Python 3.12, git.

## 2. The prompt (paste as Codex's first message)

```text
You are picking up milestone M1 (the inert winmm.dll bootstrap) of this repository.
Working folder: H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix-M1 (git worktree, branch m1-bootstrap, based on tag m0).

1. Read AGENTS.md, then docs/handover/M1-handover.md. The handover is your task specification:
   scope, boundaries, definition of done and report format. AGENTS.md rules always apply.
2. Before changing anything, run tools\test.ps1 and confirm the baseline passes.
3. Implement M1 strictly within section 6 of the handover. Another agent is implementing M2 in
   parallel in loader/core, loader/cli and third_party; do not touch those paths.
4. Run tools\test.ps1 before every commit. Commit in logical steps on m1-bootstrap.
   Never push, merge into main, or rewrite history.
5. In-game tests use only the PoC install H:\SteamLibrary\steamapps\common\GarrysMod_PoC.
   Never write to the field install H:\SteamLibrary\steamapps\common\GarrysMod or to GarrysMod_RTX_c.
6. If anything listed in section 9 of the handover comes up, stop and ask me instead of guessing.
7. When done or blocked, write docs/handover/M1-report.md as section 8 describes, commit it,
   and give me a short summary.
```

## 3. After Codex finishes

- Codex leaves `docs/handover/M1-report.md` and its commits on `m1-bootstrap`; nothing is pushed.
- Tell Claude the report is ready. Claude reviews the branch against the definition of done, then
  merges it with M2 (with your OK) and updates the status line in AGENTS.md.
- If Codex asked you a question it could not settle, paste it to Claude together with the report.
