# test_check_repo.py

Unit tests for [`check_repo.py`](../check_repo.py.md). Each test builds a minimal repo in a temporary
folder that passes every rule, breaks one rule, and checks that exactly that problem is reported:
script without a `.md`, module README missing a source file, nested module without a README, broken
relative link (links in code are ignored), CHANGELOG without `Unreleased`, folder missing from
`docs/COMPONENTS.md`, and `CLAUDE.md` not importing `AGENTS.md`.

Run from `tools\`: `python -m unittest discover -s tests` (or `tools\test.ps1`).
