# 0108: Releases are built on GitHub when a person starts it; development builds the package here

- Status: Accepted 2026-11-05 (supersedes the publishing parts of
  [ADR 0106](0106-the-rtx-package-built-on-github.md): its decision 5 and its push trigger; the build
  itself, the report and the one-artifact rule stand, as does [ADR 0107](0107-the-model-hotloaders-natives-built-from-a-source-copy.md))
- Decided by: the user, after R16: "we only build the workshop package when actual release. During
  development, we still build gma on local and update to the workshop. All workflows to build the large
  gma package should only be initiated by human."

## Decision

1. **The package workflow starts only by hand.** `.github/workflows/package.yml` has no trigger but
   `workflow_dispatch`: a person starts it (Actions > Build the RTX package > Run workflow) when releasing.
   No push, pull request, tag or schedule starts it, so no run spends hours of runner time or 0.84 GB of
   artifact storage unasked.
2. **During development the Workshop item gets packages built here.** The git hooks are back to their
   behaviour before R16: after every commit or merge on `main` and before every push of `main`,
   `tools/publish_workshop.py` builds the package in the background from `packages/` (the stored
   binaries) and uploads it when its content changed. `--local-upload` is gone; a local build uploads as
   it did before ADR 0106.
3. **A release goes to the Workshop from its run.** After the person's run of the workflow finishes,
   `tools/publish_workshop.py --from-ci --commit <sha>` downloads its `.gma`, checks it against the run's
   hash report and uploads exactly that file, as ADR 0106 decided.

## Consequences

- The item holds a development build (the stored binaries) most of the time and a GitHub-built package
  after a release. Both are recorded in `out/workshop/published.json` (`source: github` for a release).
- The workflow's build caches still serve releases; nothing runs between them.
- A development change to the runtime or a module reaches the item through an import into `packages/`
  (as before R16), and a release builds it again from source on GitHub.
