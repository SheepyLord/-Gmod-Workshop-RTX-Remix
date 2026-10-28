# M4: setting up Codex, and the prompt to give it

For the user. The task itself is specified in [M4-handover.md](M4-handover.md).

## 1. Before starting Codex

1. **Baseline.** The handover is committed on `m4-activation`, on top of M4 parts 1 and 2
   (`3679fdf`), and the main checkout `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix` has
   `m4-activation` checked out (in GitHub Desktop: Current branch, `m4-activation`). Leave it there
   while Codex works; switching branches under it would mix its changes into another branch.
2. **Run Codex locally on this PC** (CLI, IDE extension or desktop app), with the main checkout as
   its working folder. Codex Cloud cannot do M4: it needs the MSVC Build Tools, the PoC install, the
   fork's build output, the GPU and your running Steam client.
3. **Sandbox configuration**, as for M1, in `%USERPROFILE%\.codex\config.toml`:

   ```toml
   sandbox_mode = "workspace-write"
   approval_policy = "on-request"

   [sandbox_workspace_write]
   writable_roots = ['H:\SteamLibrary\steamapps\common\GarrysMod_PoC']

   [windows]
   sandbox = "elevated"   # "unelevated" if you cannot approve the admin set-up
   ```

   Codex only reads the fork (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`) and `GarrysMod_RTX_c`'s
   root `rtx.conf` and `dxvk.conf`; do not make those writable. Leave network access off.
4. **Expect approval prompts**, and approve them one at a time:
   - `git commit`: Codex's Windows sandbox protects `.git`;
   - every game launch: Codex asks before each one, and run 1 needs you to look at the screen
     (is gm_construct path-traced?);
   - possibly `tools\test.ps1`, if the sandbox account cannot run Python from your user profile.
5. **Keep Steam running and logged in, and close every GMod** (`GarrysMod_RTX_c` included) before
   Codex's in-game runs.
6. **Disk:** about 4 GB free on `H:` for two runtime packages and their deployed copies.
7. Already on this machine, nothing to install: VS 2022 Build Tools, Python 3.12, git, `pefile`.

## 2. The prompt (paste as Codex's first message)

```text
You are picking up milestone M4 (activation: start-up deployment, preload, config layers,
environment, launch arguments) of this repository.
Working folder: H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix (the main checkout), branch
m4-activation. It already holds M4 parts 1 and 2, written by Claude, and the handover commit.

1. Read AGENTS.md, then docs/handover/M4-handover.md. The handover is your task specification:
   scope, boundaries, definition of done and report format. AGENTS.md rules always apply.
2. Before changing anything, run tools\test.ps1 and confirm it passes on the current commit.
3. Do section 4.1 of the handover (corrections to parts 1 and 2) first, then 4.2 to 4.7, strictly
   within section 6.
4. Run tools\test.ps1 before every commit. Commit in logical steps on m4-activation.
   Never push, merge into main, or rewrite history.
5. In-game tests use only the PoC install H:\SteamLibrary\steamapps\common\GarrysMod_PoC, and you
   ask me before every game launch. Never write to the field install
   H:\SteamLibrary\steamapps\common\GarrysMod, to GarrysMod_RTX_c, or to the dxvk-remix-gmod fork.
6. If anything listed in section 9 of the handover comes up, stop and ask me instead of guessing.
7. When done or blocked, write docs/handover/M4-report.md as section 8 describes, commit it, and
   give me a short summary. Claude reviews the branch before it is merged.
```

## 3. After Codex finishes

- Codex leaves `docs/handover/M4-report.md` and its commits on `m4-activation`; nothing is pushed
  or merged.
- Tell Claude the report is ready. Claude reviews the branch against the definition of done (as in
  [M1-review.md](M1-review.md)), then merges it into `main` with your OK and updates the status line
  in AGENTS.md.
- If Codex asked you a question it could not settle, paste it to Claude together with the report.
