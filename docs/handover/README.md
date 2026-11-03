# Handovers

The latest round is R14, noclip and glass and the redesigned guide: [R14-report.md](R14-report.md); before it R13, less RAM and VRAM: [R13-report.md](R13-report.md).

The latest QoL batch fixes [player bodies, arms and shadows](../decisions/0043-player-body-viewmodel-and-shadows.md).
The previous batch adds legacy Remix migration in loader 0.8.0. GarrysMod_RTX_c now runs our implementation and is no longer the classic baseline.

When a milestone moves to another agent (or person), the giver writes a **brief** here and the
receiver writes a **report** here when done or blocked. Both are committed on the milestone branch,
so the next agent has the full story without the chat transcripts.

| Milestone | Brief | Prompt | Report | Assignee | Branch / worktree |
|---|---|---|---|---|---|
| M1 inert bootstrap | [M1-handover.md](M1-handover.md) | [M1-codex-prompt.md](M1-codex-prompt.md) | [M1-report.md](M1-report.md), [review](M1-review.md) | Codex | `m1-bootstrap` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\m1-bootstrap` (user-selected output root); merged into `main` 2026-10-27 |
| M2 core + CLI | (none: Claude, who wrote the plan) | | (none: evidence in the [roadmap](../ROADMAP.md) M2 row) | Claude | `m2-core` in the main checkout; merged into `main` 2026-10-27 |
| M3 deployer | (none: Claude; design in [ADR 0007](../decisions/0007-transactional-deployment.md)) | | (none: evidence in the [roadmap](../ROADMAP.md) M3 row) | Claude | `m3-deployer` in the main checkout; merged into `main` 2026-10-27 |
| M4 activation | [M4-handover.md](M4-handover.md) | [M4-codex-prompt.md](M4-codex-prompt.md) | [M4-report.md](M4-report.md), [review](M4-review.md) | Codex; parts 1-2 and review fixes by Claude | `m4-activation` in the main checkout; merged into `main` 2026-10-28 |
| M5 RTX fixes | [M5-plan.md](M5-plan.md) (no handover: Claude planned and built it) | | [M5-report.md](M5-report.md) | Claude | `m5-rtx-fixes` in the main checkout; merged into `main` 2026-10-28 with M6 |
| M6 Workshop route | (in the roadmap row; Claude) | | [M6-report.md](M6-report.md) | Claude | committed with M5 on `m5-rtx-fixes` (shared files); merged into `main` 2026-10-28 |
| M7 field install | [M7-plan.md](M7-plan.md) | | [M7-report.md](M7-report.md) | Claude | `m7-field` in the main checkout; merged into `main` 2026-10-28 |
| R3 whole-repo review: robustness, stability, bugs | [R3-handover.md](R3-handover.md) | [R3-codex-prompt.md](R3-codex-prompt.md) | [R3-report.md](R3-report.md) (Codex), [triage](R3-triage.md) (Claude) | Codex; triage and fixes by Claude | report on `r3-review` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r3-review`; fixes on `r3-fixes` in `out\worktrees\r3-fixes`, from the report; merged into `main` 2026-10-29 |
| QoL updates (from 2026-10-29) | [QoL-handover.md](QoL-handover.md): state, features, limitations, standard, test protocol, pitfalls | (the user's requests) | [QoL-report.md](QoL-report.md) | Codex Astra | one branch and worktree per change under `out\worktrees`, from `main` at the brief's commit |
| R4 review and field QA of the QoL batch | (the user's request, 2026-10-31) | | [R4-review.md](R4-review.md): findings, the user's four reports, field QA, the release run | Claude (lead), seven read-only reviewers and six fix branches | `r4-review-qa` in `out\worktrees\r4`, merged from `r4-legacy`, `r4-startup`, `r4-rtxdebug`, `r4-runtime`, `r4-companion`, `r4-motion`; merged into `main` 2026-10-31 (loader 0.10.1) |
| R5 QoL round | (the user's report, 2026-10-31) | | [R5-qol.md](R5-qol.md): the night sky line, loose broken glass, Workshop packs over own imports, the RTX normals checkbox, the content pack checks, the stability proposal | Claude (lead), a glass agent and stability researchers | `r5-qol` in `out\worktrees\r5`, with `r5-glass` merged |
| R6 performance and stability | [R6-plan.md](R6-plan.md) | six briefs: [T1](R6-T1-loader-layers.md), [T2](R6-T2-evidence-telemetry.md), [T3](R6-T3-companion-docs.md), [T4](R6-T4-runtime-logs.md), [T5](R6-T5-fixes-memlimits.md), [T6](R6-T6-performance-tiers.md) | [R6-report.md](R6-report.md): what was built, the reviews, PoC QA and tier measurements, open issues | Codex (gpt-6.1-sol) through the Claude Code plugin; Claude as project manager | `r6-t1-layers` ... `r6-t6-tiers` in `out/worktrees/` |
| C-16 steady eye-white brightness | [C16-plan.md](C16-plan.md) | two briefs: [C16-A runtime](C16-A-runtime.md), [C16-B content](C16-B-content.md) | [C16-report.md](C16-report.md): what was built, the review, the PoC measurements and tuning, the packs, open issues | Codex (gpt-6.1-sol); Claude as project manager | `c16-runtime`, `c16-content` in `out/worktrees`, integrated on `c16-int` |
| G1 glass overhaul | [G1-plan.md](G1-plan.md) | two briefs: [G1-A Lua](G1-A-lua.md), [G1-B native](G1-B-native.md); fix passes [1](G1-fix-pass.md), [2](G1-fix-pass-2.md) | [G1-report.md](G1-report.md): what was built, the integration findings and fixes, the PoC measurements (old and new system), open issues | Codex (gpt-6.1-sol); Claude as project manager | `g1-lua`, `g1-native` and their fix branches in `out/worktrees`, integrated on `g1-int` |
| R7 the user's report of 2026-11-01 | [R7-plan.md](R7-plan.md) | three briefs: [R7-A MMD alpha under Remix](R7-A-mmd-alpha.md) (after Claude's investigation), [R7-B crash report and diagnostics](R7-B-crash-diagnostics.md), [R7-C glass interaction](R7-C-glass-interaction.md) | [R7-report.md](R7-report.md) (with [R7-A](R7-A-report.md), [R7-B](R7-B-report.md), [R7-C](R7-C-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r7-crash-diag`, `r7-glass-interact` in `out/worktrees`, integrated on `r7-int` |
| R11 automatic PBR (2026-11-02) | [R11-plan.md](R11-plan.md) | one brief: [R11-A automatic PBR for vanilla Source materials and imported game characters](R11-A-autopbr.md) | [R11-report.md](R11-report.md) (with [R11-A](R11-A-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r11-autopbr` in `out/worktrees`, with the fixes branch `codex/r11-autopbr` in `out/worktrees/r11-fixes` |
| R12 the user's report after R11-B (2026-11-02) | [R12-plan.md](R12-plan.md) | four briefs: [R12-A NPCs after a re-import](R12-A-hotloader-npc.md), [R12-B game PBR by texture features and manual overrides](R12-B-game-pbr-matching.md), [R12-C VRAM](R12-C-vram.md), [R12-D manual eye whites](R12-D-eye-white-assignment.md); a follow-up after review: [R12-B2 straight-alpha decoding and mask evidence](R12-B2-decode-and-masks.md) | [R12-report.md](R12-report.md) (with [R12-A](R12-A-report.md), [R12-B and B2](R12-B-report.md), [R12-C](R12-C-report.md), [R12-D](R12-D-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r12-hotloader`, `r12-pbr` (fixes `codex/r12-pbr` in `out/worktrees/r12-fixes`), `r12-vram`, `r12-eyes` in `out/worktrees`, integrated on `r12-int` |
| R14 noclip and glass, the guide (2026-11-03) | [R14-plan.md](R14-plan.md) | (none) | [R14-report.md](R14-report.md) | Claude (scheduled task r14-after-r13) | `r14` in `out/worktrees/r14` |
| R13 less RAM and VRAM (2026-11-03) | [R13-plan.md](R13-plan.md) | three subagent tasks: R13-M compact game maps and reuse across versions, R13-A characters on first use and the lag trigger, R13-B the runtime's texture memory; R13-C memory profiles by Claude | [R13-report.md](R13-report.md) (with [R13-M](R13-M-report.md), [R13-A](R13-A-report.md), [R13-B](R13-B-report.md)) | Claude subagents; Claude as project manager (no Codex, as the user asked) | `r13-maps` (fixes `claude/r13-maps` in `out/worktrees/r12-fixes`), `r13-hotloader`, `r13-runtime` (runtime `claude/r13-runtime` in `out/worktrees/r12-vram/out/runtime-src`) in `out/worktrees`, integrated on `r13-int` |
| R11-B cached imported game maps (2026-11-02) | [R11-B brief](R11-B-cached-game-maps.md) | (the user's request) | [R11-B-report.md](R11-B-report.md) | Codex (gpt-6.1-sol); Claude as project manager | `r11-cache` in `out/worktrees/r11-cache`, fixes `codex/r11-autopbr` in `out/worktrees/r11-fixes` |
| R10 the user's character report (2026-11-02) | [R10-plan.md](R10-plan.md) | two briefs: [R10-E steady eye whites for imported characters](R10-E-eye-whites.md), [R10-H imported NPCs after a map change and VMD expressions](R10-H-hotloader-expressions.md) | [R10-report.md](R10-report.md) (with [R10-E](R10-E-report.md), [R10-H](R10-H-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r10-eyes`, `r10-hotloader` in `out/worktrees` |
| R9 the user's glass report (2026-11-02) | [R9-plan.md](R9-plan.md) | one brief: [R9-G realistic fracture, instant breaks, sounds, water, blasts, stable pushes, a clear button](R9-G-glass.md); the CI fixes and the melee error are Claude's | [R9-report.md](R9-report.md) (with [R9-G](R9-G-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r9-glass` in `out/worktrees` |
| R8 the user's report after R7 (2026-11-01) | [R8-plan.md](R8-plan.md) | two briefs: [R8-C vanilla graphics add-ons](R8-C-addon-compat.md), [R8-G glass under load, collision levels, follow-up hits](R8-G-glass.md); the character noise is Claude's (runtime patch 0018); [R8-B Backrooms native fixes](R8-B-backrooms-fixes.md) | [R8-report.md](R8-report.md) (with [R8-B](R8-B-report.md), [R8-C](R8-C-report.md), [R8-G](R8-G-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r8-compat`, `r8-glass` in `out/worktrees`, integrated on `r8-int` |
| R1 whole-repo review | [R1-handover.md](R1-handover.md) | [R1-codex-prompt.md](R1-codex-prompt.md) | [R1-report.md](R1-report.md) (Codex), [triage](R1-triage.md) (Claude) | Codex; triage and fixes by Claude | report on `r1-review`; fixes on `r1-fixes`, both in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r1-review`, from `main` after `8f8a540`; merged into `main` 2026-10-28 |

G1-B implementation/offline validation is complete: [G1-B report](G1-B-report.md). G1-A and Claude's
integration/game acceptance remain separate from that native/debris report.

G1-B's post-game fix pass is complete for implementation/offline checks:
[G1-B fix report](G1-B-fix-report.md), branch `g1-native-fix`. Integration/game acceptance remains
with Claude; the report includes real-map import counts and before/after timing limits.

## Rules for briefs

- Self-contained for someone who has read [AGENTS.md](../../AGENTS.md) and nothing else.
- State scope, files the assignee may and may not touch, acceptance criteria, how to test, what to
  report, and when to stop and ask.
- Never rewrite an accepted decision record in a brief; point to it, or ask for a new one.

## Rules for reports

- What was built (files), decisions taken (with any new decision record), test evidence (commands
  and the lines that show success), deviations from the brief, open issues, questions for the user.
- Facts worth keeping also go into [docs/RESEARCH.md](../RESEARCH.md); the report links to them.

## Native package addon menu

The 2026-10-30 continuation of QoL adds loader 0.7.0's native-package warning suppression, blue cards
and Workshop descriptions. See [QoL-report.md](QoL-report.md#native-package-addon-cards-2026-10-30)
and [ADR 0039](../decisions/0039-native-package-addon-presentation.md). Source branch:
`codex/native-addon-menu`, worktree `out/worktrees/native-addon-menu`.

## Native map glass

The next QoL batch fixes Modern House glass disappearing without shards. Source branch:
`codex/map-glass`, worktree `out/worktrees/map-glass`. See
[QoL-report.md](QoL-report.md#modern-house-map-glass-2026-10-30) and
[ADR 0040](../decisions/0040-native-map-glass-debris.md).

## Hotloader DepthWrite errors

The QoL shader batch is on codex/hotloader-depth in out/worktrees/hotloader-depth. See
[QoL-report.md](QoL-report.md#hotloader-depthwrite-shader-errors-2026-10-30) and
[ADR 0041](../decisions/0041-hotloader-remix-depth-materials.md).
