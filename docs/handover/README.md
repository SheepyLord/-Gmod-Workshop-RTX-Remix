# Handovers

When a milestone moves to another agent (or person), the giver writes a **brief** here and the
receiver writes a **report** here when done or blocked. Both are committed on the milestone branch,
so the next agent has the full story without the chat transcripts.

| Milestone | Brief | Prompt | Report | Assignee | Branch / worktree |
|---|---|---|---|---|---|
| M1 inert bootstrap | [M1-handover.md](M1-handover.md) | [M1-codex-prompt.md](M1-codex-prompt.md) | `M1-report.md` (written by the assignee) | Codex | `m1-bootstrap` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix-M1` |
| M2 core + CLI | (none: Claude, who wrote the plan) | | | Claude | `m2-core` in the main checkout |

## Rules for briefs

- Self-contained for someone who has read [AGENTS.md](../../AGENTS.md) and nothing else.
- State scope, files the assignee may and may not touch, acceptance criteria, how to test, what to
  report, and when to stop and ask.
- Never rewrite an accepted decision record in a brief; point to it, or ask for a new one.

## Rules for reports

- What was built (files), decisions taken (with any new decision record), test evidence (commands
  and the lines that show success), deviations from the brief, open issues, questions for the user.
- Facts worth keeping also go into [docs/RESEARCH.md](../RESEARCH.md); the report links to them.
