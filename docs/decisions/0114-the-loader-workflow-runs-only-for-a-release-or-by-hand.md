# 0114: The loader's workflow runs only for a release or when a person starts it

- Status: Accepted 2026-11-05 (amends [ADR 0017](0017-release-bundle-and-ci.md) decision 1, where
  `build.yml` runs "on every push of `main`, every pull request, and on demand")
- Decided by: the user, after R19's release: "Make push does not start a new Build winmm.dll CI, it
  should be started only when a release need to be drafted or user request." (2026-11-05)
- Builds on: [0113](0113-every-actions-artifact-expires-after-two-days.md) (every artifact expires after
  two days), [0108](0108-releases-built-on-github-by-hand-development-built-here.md) (the package
  workflow, too, runs only when a person starts it)

## Context

- **Every push ran it.** `build.yml` ran `tools\test.ps1 -Config Release` and built the loader's bundle
  on every push of `main`, about eleven a day (R19-T), each for about 12 minutes on a `windows-2022`
  runner (R19's last two pushes: 13 min 48 s and 11 min 41 s).
- **The same checks already gate a push.** AGENTS.md rule 5 lets agents push `main` only once
  `tools\test.ps1` passes on the developer's machine: the same conventions, Release build, CTest and
  Python tests, on this machine rather than a clean runner.
- **Pull requests** are not how work reaches `main` here: rounds merge locally and `main` is pushed.

## Decision

1. **`build.yml` runs for a pushed `v*` tag, and when a person starts it** (Actions > Build winmm.dll >
   Run workflow, or `gh workflow run build.yml --ref main`). No push of a branch and no pull request
   starts it. `test_the_loader_workflow_starts_only_for_a_release_or_by_hand` in
   `tools/tests/test_publish_workshop.py` holds the triggers.
2. **A release still gets every check on a clean runner.** A tag's run builds and tests as before, and its
   `release` job, which needs the build, makes the GitHub release only when they pass.
3. **Agents start it by hand only for a release being prepared, or when the user asks.** Before a `v*`
   tag, a run on `main` finds a failure that only a clean machine shows while there is still no tag.
   The tag itself still needs the user's go-ahead (AGENTS.md rule 5).

## Consequences

- **A push uploads no bundle,** so Actions storage holds the artifacts of releases and manual runs only.
- **A failure only a clean runner shows is found later.** In R8, `build.yml` failed on four of the five
  pushes after the R7 merge, in tests that passed here ([RESEARCH.md](../RESEARCH.md), "R8 CI"). Such a
  failure now shows at the next manual run or tag. A tag whose checks fail gets no release; the fix goes
  into a new tag.
- **The README's build badge** shows the latest run on `main`, which now comes only from manual runs.

## Alternatives considered

- **Keeping pull-request runs.** The user asked for releases and requests only, and no pull requests are
  used.
- **Skipping only docs-only pushes** (`paths-ignore`). Pushes that change code would still start it.
- **A scheduled run.** It would run without a request.
