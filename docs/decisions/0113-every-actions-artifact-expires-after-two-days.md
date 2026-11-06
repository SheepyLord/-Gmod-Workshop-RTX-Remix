# 0113: Every Actions artifact expires after two days

- Status: Accepted 2026-11-05 (amends [ADR 0017](0017-release-bundle-and-ci.md) decision 1, which keeps
  the bundle "as a run artifact", and [ADR 0106](0106-the-rtx-package-built-on-github.md) decisions 3 and
  4, which keep the report "for 90 days" and the package until the next run)
- Decided by: the user, on R19's open issue about Actions storage ([R19-report.md](../handover/R19-report.md)).
  R19-T proposed `retention-days: 7` for the per-push bundles. The user answered: "Yes, but make all
  artifact builds expire after 2 days, include the loader build." (2026-11-05)
- Builds on: [0108](0108-releases-built-on-github-by-hand-development-built-here.md) (only a person starts
  the package workflow, for a release)

## Context

- **Storage is 2 GB.** Every unexpired artifact counts against the account's 2 GB of Actions storage
  (the request behind ADR 0106).
- **What was kept, and for how long.** After the v0.14.0 release, 152 artifacts took 1,222 MiB:
  - the release's `rtx-package`, 809 MiB;
  - 91 loader bundles (`gmod-native-loader`, one per push of `main`, about 4.5 MiB each), 407 MiB;
  - `test-evidence`, the reports and older summaries, about 6 MiB.

  `build.yml` kept its artifacts for GitHub's default of 90 days; `package.yml` kept its two for 90 days.
- **It would have filled.** At about eleven pushes a day the bundles add about 50 MiB a day, so storage
  would be full in about two weeks (R19-T). Then the next release's package upload fails.
- **Nothing reads an artifact later.** The release job in `build.yml` downloads the bundle in the same
  run, minutes after the build. A GitHub release keeps its zips as release assets, which do not expire.
  `tools/publish_workshop.py --from-ci` downloads the package run's two artifacts right after the run.
  The package workflow's jobs pass binaries to each other through caches, which are not artifacts.

## Decision

1. **Every artifact expires two days after its run.** Each `actions/upload-artifact` step in
   `.github/workflows/build.yml` and `package.yml` sets `retention-days: 2`:
   - `gmod-native-loader`, the loader's bundle;
   - `test-evidence`, kept when a check fails;
   - `rtx-package-report`;
   - `rtx-package`.

   `test_every_artifact_expires_after_two_days` in `tools/tests/test_publish_workshop.py` holds every
   upload step to `ARTIFACT_DAYS` in `tools/publish_workshop.py`.
2. **`--from-ci` says when a run's package is gone.** Before it downloads anything, it asks GitHub for
   the run's artifacts. If the package or the report has expired, or a newer run deleted it, it fails
   (exit 1), names the artifact and says to start the workflow again. It leaves `out\workshop\ci`, the
   last download, as it is.
3. **What stays the same.** Releases keep their zips. The package workflow still deletes the older
   `rtx-package` artifacts before it uploads its own (ADR 0106 decision 4, review R19 F-07). The run's
   summary still shows the hash report.

## Consequences

- **Storage stays small.** Two days of bundles are about 0.1 GB; with one package the total stays under
  1 GB, so a release run's upload has room.
- **`--from-ci` has two days.** The release flow runs it right after the package run. Later, the
  workflow has to run again for the commit; its caches key on sources, so an unchanged runtime is not
  rebuilt.
- **A push's bundle and a failed check's evidence** must be downloaded within two days. A release keeps
  its zips; a development build can also be made locally with `tools\workflow.ps1`.
- **Artifacts uploaded before this change keep the expiry they were uploaded with.** GitHub cannot
  change an artifact's retention afterwards. Deleting them is a separate step that needs the user's
  go-ahead ([AGENTS.md](../../AGENTS.md) rule 5).

## Alternatives considered

- **Seven days for the bundles only** (R19-T's proposal). The user chose two days for every artifact.
- **The repository's default retention** (Settings > Actions > General). It also shortens the logs, and
  it lives outside the repository; the workflows' own setting is reviewed and tested with the code.
- **A scheduled job that deletes old bundles.** More to maintain, and a token that may delete artifacts
  in every run.
