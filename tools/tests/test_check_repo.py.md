# test_check_repo.py

Unit tests for [`check_repo.py`](../check_repo.py.md). Each test builds a minimal repo in a temporary
folder under the repo's `out\tmp` that passes every rule, breaks one rule, and checks that exactly
that problem is reported: script without a `.md`, module README missing a source file, nested module
without a README, broken relative link (links in code are ignored), CHANGELOG without `Unreleased`,
folder missing from `docs/COMPONENTS.md`, and `CLAUDE.md` not importing `AGENTS.md`.

The temporary folder is always under `out\tmp`, whatever `TEMP` says (AGENTS.md rule 9; R1-028). A
test points `tempfile` at a folder that does not exist and checks the fixture still starts there.

Run from `tools\`: `python -m unittest discover -s tests` (or `tools\test.ps1`). Scratch goes to
`out\tmp` either way.

- `test_the_stored_runtime_must_be_what_runtime_builds` (R3-014): a matching `runtime/base.json` record passes,
  also with a reworded `why`; a changed patch, a changed submodule setting or another stored `d3d9.dll` fails.
- `test_other_checkouts_inside_are_not_this_repos_files`: a folder with its own `.git` (a worktree in
  `.claude/worktrees`) is skipped.
