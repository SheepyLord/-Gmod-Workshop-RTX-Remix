# Decision records

One file per decision, numbered in order: `NNNN-short-title.md`. An accepted record is never
rewritten; a later record supersedes it and both say so. Add one whenever a choice would surprise
someone reading the code later, or when [AGENTS.md](../../AGENTS.md) rules change.

| # | Decision | Status |
|---|---|---|
| [0001](0001-bootstrap-winmm-proxy.md) | The bootstrap is a `winmm.dll` proxy that works at the EXE entry point | Accepted 2026-10-27 |
| [0002](0002-source-agnostic-payloads.md) | Payloads are source-agnostic; Workshop route decided after a private upload test | Accepted 2026-10-27 |
| [0003](0003-native-trust-allowlist.md) | Only allowlisted packages may deploy native code until signatures exist | Accepted 2026-10-27 |
| [0004](0004-runtime-in-versioned-folder.md) | The Remix runtime is preloaded from a versioned folder, not copied into `bin\win64` | Accepted 2026-10-27; folder name refined by 0007 |
| [0005](0005-repo-conventions.md) | Agent-facing repo conventions and MIT licence | Accepted 2026-10-27 |
| [0006](0006-package-precedence-and-planning.md) | Package precedence (dev folder > local > Workshop) and planning rules | Accepted 2026-10-27 |
| [0007](0007-transactional-deployment.md) | Deployment is one journaled transaction per run, rolled back on failure | Accepted 2026-10-27 |
| [0008](0008-activation-at-startup.md) | Activation at start-up: preload the runtime, config layers, environment, launch arguments | Accepted 2026-10-27; revised before merge for transactional activation and user layers |
| [0009](0009-startup-deployment-last-good.md) | Startup deployment keeps the last good generation when an allowlisted source fails | Accepted 2026-10-27 |
| [0010](0010-rtx-session-extras.md) | RTX-session extras: in-memory patch sets, module overrides and session console variables | Accepted 2026-10-28 |
| [0011](0011-lua-addon-folders.md) | Packages may deploy GMod add-on folders (`garrysmod/addons/<addon>/`) | Accepted 2026-10-28, user to confirm |
| [0012](0012-distribution-route.md) | Native packages are released outside the Workshop; the Workshop stays a supported source | Accepted 2026-10-28; private upload test left to the user |
| [0013](0013-rtx-only-addons-hidden-without-rtx.md) | Add-ons of RTX-only packages are hidden from sessions without RTX, in memory | Accepted 2026-10-28 |
| [0014](0014-r1-hardening.md) | R1 hardening: no `garrysmod/cfg` area, files only inside named folders, deployed files checked by size and time at activation, a restore that keeps the user's own changes | Accepted 2026-10-28; supersedes the `garrysmod/cfg` area of the M2 path rules |

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
