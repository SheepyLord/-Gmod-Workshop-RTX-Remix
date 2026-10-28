# Decision records

One file per decision, numbered in order: `NNNN-short-title.md`. An accepted record is never
rewritten; a later record supersedes it and both say so. Add one whenever a choice would surprise
someone reading the code later, or when [AGENTS.md](../../AGENTS.md) rules change.

| # | Decision | Status |
|---|---|---|
| [0001](0001-bootstrap-winmm-proxy.md) | The bootstrap is a `winmm.dll` proxy that works at the EXE entry point | Accepted 2026-10-27 |
| [0002](0002-source-agnostic-payloads.md) | Payloads are source-agnostic; Workshop route decided after a private upload test | Accepted 2026-10-27 |
| [0003](0003-native-trust-allowlist.md) | Only allowlisted packages may deploy native code until signatures exist | Accepted 2026-10-27 |
| [0004](0004-runtime-in-versioned-folder.md) | The Remix runtime is preloaded from a versioned folder, not copied into `bin\win64` | Accepted 2026-10-27 |
| [0005](0005-repo-conventions.md) | Agent-facing repo conventions and MIT licence | Accepted 2026-10-27 |

## Template

```markdown
# NNNN: Title

- Status: Proposed | Accepted YYYY-MM-DD | Superseded by NNNN
- Decided by: who agreed

## Context
What forces the decision; facts with sources (link docs/RESEARCH.md).

## Decision
What we do.

## Consequences
What gets easier, what gets harder, what to watch.

## Alternatives considered
Each with the reason it lost.
```
