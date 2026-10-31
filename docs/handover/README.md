# Handovers

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
| R6 performance and stability | [R6-plan.md](R6-plan.md) | six briefs: [T1](R6-T1-loader-layers.md), [T2](R6-T2-evidence-telemetry.md), [T3](R6-T3-companion-docs.md), [T4](R6-T4-runtime-logs.md), [T5](R6-T5-fixes-memlimits.md), [T6](R6-T6-performance-tiers.md) | (to come) | Codex (gpt-6.1-sol) through the Claude Code plugin; Claude as project manager | `r6-t1-layers` ... `r6-t6-tiers` in `out/worktrees/` |
| R1 whole-repo review | [R1-handover.md](R1-handover.md) | [R1-codex-prompt.md](R1-codex-prompt.md) | [R1-report.md](R1-report.md) (Codex), [triage](R1-triage.md) (Claude) | Codex; triage and fixes by Claude | report on `r1-review`; fixes on `r1-fixes`, both in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r1-review`, from `main` after `8f8a540`; merged into `main` 2026-10-28 |

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
