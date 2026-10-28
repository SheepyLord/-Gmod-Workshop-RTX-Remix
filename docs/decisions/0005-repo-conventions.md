# 0005: Agent-facing repo conventions and MIT licence

- Status: Accepted 2026-10-27
- Decided by: the user (SheepyLord): conventions requested at project start; MIT assumed in the
  M0 plan and approved with it

## Context

The repo is worked on mostly by agents, across many sessions. Anything that lives only in a chat
transcript is lost. The user asked for a `.md` beside every script, a document describing each
component, and a changelog of important changes.

## Decision

- [AGENTS.md](../../AGENTS.md) is the single entry point (rules, commands, duties); `CLAUDE.md`
  only imports it.
- Every script has `<script file name>.md` beside it (`build.ps1` → `build.ps1.md`, so `x.py` and
  `x.ps1` never collide). Every C++ module folder has a `README.md` naming each source file.
- [docs/COMPONENTS.md](../COMPONENTS.md) lists every component; [CHANGELOG.md](../../CHANGELOG.md)
  follows Keep a Changelog; design choices get a decision record here.
- [`tools/check_repo.py`](../../tools/check_repo.py.md) enforces the mechanical parts and runs first
  in [`tools/test.ps1`](../../tools/test.ps1.md).
- Licence: MIT for this repo. Code from `garrys-mod-rtx-remixed` (GPL-2.0) is not copied in.

## Consequences

- Small changes carry some documentation overhead; the checker keeps it from being skipped.
- Vendored code keeps its layout; only `.md` files are added beside its scripts.
