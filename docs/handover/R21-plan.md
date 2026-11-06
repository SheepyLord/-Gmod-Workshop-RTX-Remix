# R21 plan: Blood Overhaul's resources, and no Hotloader warning after game updates

Claude is the project manager and reviewer; Codex (`gpt-6.1-sol`, reasoning effort max, priority
tier, as the user asked for this session) writes the code in two tasks, each in its own worktree.
Standing rules: [AGENTS.md](../../AGENTS.md). The round before this one: [R20-report.md](R20-report.md).

## The user's words (2026-11-06, after R20's release, verbatim)

> 1. Permission is obtained from the author of the resources of Blood Overhaul, please package them and
> publish and I will update the credit section.
>
> 2. Dismiss the hotloader warning for this and future game updates. User decide to assume Hotloader
> should works even with the game update since it is a separate dll. In case of issues, user will fix
> them in an update to update basis.

"The credit section" is the Workshop page's: the user updates it. This round makes the package's own
credits ([CREDITS.txt](../../packages/blood-overhaul-rtx/licenses/CREDITS.txt), the part's README) true.

## Tasks

| Task | Worktree / branch | Brief | ADR | What |
|---|---|---|---|---|
| R21-A | `out/worktrees/r21-blood` / `r21-blood` | [R21-A-blood-resources.md](R21-A-blood-resources.md) | 0124 | Blood Overhaul's resources and the PBR made from them join the `blood-overhaul-rtx` part |
| R21-B | `out/worktrees/r21-hotloader` / `r21-hotloader` | [R21-B-hotloader-notice.md](R21-B-hotloader-notice.md) | 0125 | The Model Hotloader shows no warning about the game's build, now or after later updates |

Both branch from `r21-int`. Claude reviews each commit as it lands, merges both on `r21-int`, runs
`tools\test.ps1 -Config Release`, writes the round's report and the shared docs, and pushes `main`
(the hooks publish the package to item 3829070317, a local build). No loader release, no GitHub
workflow.

## Rules for every task

- **Your paths.** Touch only what your brief gives you. Shared docs (CHANGELOG, ROADMAP, RESEARCH,
  TESTING, COMPONENTS, `docs/decisions/README.md`, `docs/handover/README.md`) are Claude's this round:
  leave them alone, except a line in `docs/decisions/README.md` for your ADR. Use only your ADR number.
  End with `docs/handover/R21-<X>-report.md`: what you built, the tests, the evidence (paths under your
  worktree's `out\`), what is open.
- **Commit identity.** Commit as `SheepyLord <37598021+SheepyLord@users.noreply.github.com>`, which is
  the repository's git config: do not set or pass another author or committer. End each message with
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`.
- **The PoC is shared.** `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` (GMod build 26439081, the
  field's). Lock: `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock` (in the main
  checkout), created exclusively; if it exists, another task or session holds the PoC: wait (retry every
  two minutes) and never remove a lock you did not create. Snapshot what you change in the PoC, restore
  it exactly, then release the lock. Prepare everything first; keep each hold under about 20 minutes.
  Launch with `-multirun` (`tools/poc_session.py` and the drivers under `tools/qa/`; read their `.md`).
  End sessions with the field's settings (PoC quits write GMod's cloud config). Never set
  `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES` (the drivers decline Remix's crash prompt instead).
  Delete large snapshot copies once a restoration is verified (an earlier round filled the disk).
- **The field install** (`H:\SteamLibrary\steamapps\common\GarrysMod`) is the user's game: read it,
  never write it, do not launch it.
- Never read the user's own GMod console logs: only the part of `console.log` your session wrote.
- No questions to the user: decide, record why, carry on. Never push, merge, tag, publish, start a
  GitHub workflow or touch the Workshop or another repository.
- A file in `packages/` changes only through `tools\inputs.py import` (read `packages/README.md`),
  each binary once, at the end, after its final preparation (Git LFS storage is never freed; the
  quota is 10 GiB). No other binaries in git.
- Run repository Python with `-I` from the worktree root. Temporary files stay under your worktree's
  `out\`.
- `tools\test.ps1 -Config Release` passes before your last commit.
