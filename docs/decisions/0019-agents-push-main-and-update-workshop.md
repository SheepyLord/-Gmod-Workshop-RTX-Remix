# 0019: Agents push `main` and update the Workshop items without asking

- Status: Accepted 2026-10-28
- Decided by: the user ("From now on, you have permission to push to Steam workshop and GitHub main.")
- Changes: AGENTS.md rule 5. It widens the standing exception for test items and the item updates of
  [0016](0016-one-workshop-item-kept-current.md).

## Context

AGENTS.md rule 5 asked before every push to `origin` and before any Workshop update. There were two
exceptions, both 2026-10-28: test items, and the updates of item 3829070317 that the git hooks make.
During field testing every round then waited for an approval to push, before CI could build the
bundle the user tests.

## Decision

Agents may do these without asking:

- push `main` to `origin`. That runs CI, and the pre-push hook updates the Workshop item when its
  inputs changed;
- update the project's Workshop items, item 3829070317 and test items, with
  [`tools/publish_workshop.py`](../../tools/publish_workshop.py.md) or `gmpublish`.

These still need the user's go-ahead:

- pushing another branch, or a tag (a `v*` tag makes a public GitHub release);
- force pushes;
- making an item public or changing its visibility, and publishing another real package;
- changing Steam settings or launch options, and deleting user data.

Removing or deleting anything on the Workshop stays forbidden until the user says the project is done.

## Consequences

- A fix reaches CI and the Workshop item in one step, and the user sees the result instead of a
  question.
- What reaches `main` must already be tested: `tools\test.ps1` passes before a push, and packaging
  changes are tried on a branch first (rule 5).
