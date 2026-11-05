# R19-T report: tooling and CI

Part R19-T of [R19](R19-plan.md): the tooling and CI findings of the pre-release review
([R19-review.md](R19-review.md); Codex report `task-mw40i2w9-6ipiaq.md`, verdicts "Tooling and CI").
Branch `r19-tooling`, worktree `out\worktrees\r19-tooling`, from `r19-int` (`1e4cb10`). Code commit:
`f9a33a3`. Touched: `tools/` and `.github/workflows/` only; no C++, no `packages/`, no shared doc.

## Findings

| ID | Verdict | Result |
|---|---|---|
| M1 (F-02) | confirmed, medium | **fixed** |
| F-01 | partly, low | **fixed** |
| F-04 | partly, low | **fixed** |
| F-05 | partly, none | **fixed** (the plan asks for it; the smallest change) |
| F-07 | partly, low | **fixed** |
| F-08 | partly, low | **fixed** |
| F-09 | partly, low | **fixed** |
| Miss: no run is not success | low | **fixed**; a cancelled run fails too |
| Miss: unpinned pillow | low | **fixed** |
| F-03 | partly, low | not here: part R19-H (`bootstrap.py`) |
| F-06 | false positive | no change: `install-loader.ps1 -Uninstall -RemoveState` removing the loader's state, the config with it, is the documented opt-in |

### M1 (F-02): a release replaced by the next commit's development build

**The problem.** `publish_workshop.py --from-ci` wrote a `published.json` without a fingerprint. The
next hook run on `main` (any commit, merge or push, even docs only) could not stop at "inputs
unchanged". It built the package here from the stored binaries, whose digest differs from the
release's (those were built on GitHub), and uploaded that development build over the release.

**The fix** (`tools/publish_workshop.py`)
- `--from-ci` records the release commit in full, `commit_sha` (the local record gets it too).
- New step 3a of the local path, `holds_this_release()`: while `published.json` holds a GitHub release
  (`source: github`) whose `commit_sha` has the packaging inputs `HEAD` has
  (`git diff --quiet --no-ext-diff --no-textconv <commit_sha> HEAD -- <REPO_INPUTS>`, `same_inputs()`),
  with the configuration this run uses (`tools/workshop.json` of that commit equals the loaded one, so
  a `--config` elsewhere does not count), and with no uncommitted change to a packaging input, the run
  reports `unchanged-inputs`, records the fingerprint and uploads nothing. The next runs then stop at the
  fingerprint check until an input changes; from then on the development build uploads as before.
- Not taken for a release: a record without `commit_sha` (one written before R19), a release commit
  this clone does not have (logged; built as usual), `--force`, `--dry-run`/`--allow-dirty` with dirty
  inputs.
- `publish()` and `publish_from_ci()` take the checkout as `repo` (default this one), so the tests run
  them against a throwaway git repository.

**Tests, both directions** (`tools/tests/test_publish_workshop.py`, `ReleaseThenHookTests`): a release
is uploaded with the real `publish_from_ci` (fake `gh`, recorded upload) from a throwaway repository,
then the hook path (`publish`) runs, with the real build of two small packages:
- at the release's own commit, and after a commit that touches only docs: `unchanged-inputs`, the log
  says why, still one upload, the record keeps `source: github`, its run and `commit_sha`, and gains
  the fingerprint; the next run stops at "inputs unchanged"; `--force` still uploads;
- after a commit that changes a packaging input: the development build is uploaded as before and
  recorded with its `commit_sha`; the next run is `unchanged-inputs`;
- a record without `commit_sha`, or another configuration than the release commit's, would build and
  upload (dry run); `same_inputs` is `None` for a commit the clone lacks.

### F-01: the tag name pasted into the release script

`build.yml`'s release job now passes `github.ref_name` and `github.repository` through `env:`
(`RELEASE_TAG`, `REPOSITORY`) and the script reads `"$RELEASE_TAG"` and `"$REPOSITORY"`. "Similar
values": `package.yml`'s two steps that pasted `${{ env.RUN_URL }}` into a script now read
`"$env:RUN_URL"` (with `shell: pwsh`, the default there anyway). No `${{ }}` is left in any `run:`
script of either workflow. No tag-format check was added: the environment variable removes the
injection, and a check that was wrong would stop the release.

### F-04: `actions: write` for every job

`package.yml`: the workflow's token is `contents: read`; only the `package` job, which deletes the
older artifacts, has `permissions: {contents: read, actions: write}`. The `runtime`, `modules` and
`hotloader` jobs (other people's build scripts and downloads) can only read. Their caches and the
artifacts use the runner's own token, not these permissions, so nothing they do changes.

### F-05: `make_vanilla_copy.py` copied files it could not verify

A non-empty depot file without a SHA-1 in the manifest (Steam's 20 zero bytes) is no longer copied
when its size matches; it is listed under `unverified` (exit 1), as `verify_install.py` already did.
Empty files and user-config files without a hash are still copied. The review found a SHA-1 for all
2,878 files of GMod's manifests, so nothing changes for GMod today. Test:
`test_clone_leaves_out_a_depot_file_without_a_hash` (`tools/steam/tests`).

### F-07: the older packages deleted before the new upload

`package.yml`'s package job now uploads `rtx-package` first and deletes the older `rtx-package`
artifacts after it (the step runs only when everything before it succeeded). A failed upload leaves
the last good package; a successful run still keeps one. This replaces the order in ADR 0106 decision 4
("before uploading its own"); see "Proposed decision note" below. For the minutes between the upload
and the deletion, Actions storage holds two packages: see "Before the release run".

**Integrator's change (Claude, R19 integration): reverted to deletion first, by design.** Actions
storage is 2 GB and about 1.2 GB was in use, one package about 0.84 GB: holding two would make the
release run's upload fail. The workflow and `tools/ci/README.md` say why the order is deliberate; the
last good package stays on the Workshop item and in `out\workshop\ci`, and ADR 0106 decision 4 stands.

### F-08: the LZMA spool had no cap

`tools/gmapack/gmapack.py` (the user's vendored GMA File Packer; the change is noted in
`gmapack.py.md`): `MAX_LZMA_OUTPUT_SIZE` = 8 GiB. A wrapper that declares a larger size stops before
anything is decoded; one that declares no size stops once its output passes 8 GiB. The largest real
archive these tools read is the RTX package, 1,814,543,303 bytes (the current item). The spool still
spills to `TEMP`, which `tools\test.ps1` and `tools\build.ps1` point into `out\tmp`. Test:
`test_lzma_output_is_capped` (the cap lowered by the test; both forms).

### F-09: Windows aliases in the package indexes

`tools/inputs.py`
- `check_rel` also refuses a path part that ends in a dot or a space, a Windows device name with any
  extension (`NUL`, `com1.txt`, `CONOUT$`, superscript `COM¹` included), a character Windows does not
  allow (`<>:"|?*`, control characters) and the 8.3 form of a short name with a digit after the tilde
  (`LONGNA~1.DLL`). `~gmod_topbr` (the fixes part's 87 paths) has no digit after the tilde and passes.
- `alias_problems`: across a whole index, two paths that differ only in case (`casefold`), or a path
  and the same path plus `.xz` (stored under one name), are refused.
- `read_index` checks every path and the aliases, so `verify` reports such an index and `unpack`,
  `extract` and `import` stop before they read or write by it. `import` also refuses a new path that
  names an indexed path's file, before anything is stored (on Windows it would overwrite it).
- `import` no longer replaces an existing index it cannot read with a new one that holds only the
  imported files (that would now have happened to an index refused by these checks); only a part
  without an index starts a new one.
- The real `packages/`: all 1,221 indexed paths pass (`test_the_repository_packages_verify`; none ends
  in `.xz`, none is a device name, an 8.3 name or a case twin).
- Tests: `test_names_windows_reads_as_other_files_are_refused`,
  `test_an_index_that_cannot_be_read_stops_an_import`.

### The misses

- **No run is not success.** `--from-ci` now fails (exit 1) when no run of the commit appears within
  five minutes: "no run of the package workflow for <sha> appeared within 5 minutes: nothing
  uploaded. Start it for this commit (Actions > Build the RTX package > Run workflow), then run this
  again". **Also a cancelled run** now fails like a failed one: the `cancelled` result (exit 0) was
  for a newer push's run replacing an older one, which cannot happen since ADR 0108 (no push trigger,
  `cancel-in-progress: false`); a person who runs `--from-ci` for a release should not see exit 0
  when nothing was uploaded. Tests: `test_a_commit_without_a_package_run_is_an_error` (also through
  `main`: exit 1, the reason on stderr), `test_a_failed_or_cancelled_run_uploads_nothing_and_fails`.
- **Pillow** is pinned in `build.yml` to `pillow==12.3.0`: what `package.yml` installs (its runs of
  `a141826` and `f83d7ad` succeeded with it on `windows-2022`, Python 3.12) and what the tests run
  with on this machine.

## Checks and tests

**Workflows** (actionlint is not installed here, and downloading it needs the user's permission):
- Both files parse with PyYAML 6.0.3. A structural check (a scratch script, not committed): every step
  has exactly one of `uses` and `run`, known keys, shells and permission scopes; the jobs' effective
  permissions are `build: contents read`, `release: contents write` (`build.yml`), and
  `runtime`/`modules`/`hotloader: contents read`, `package: contents read, actions write`
  (`package.yml`); no `${{ }}` expression is left in any of the 27 `run:` scripts.
- Every PowerShell `run:` script parses without error (Windows PowerShell 5.1's parser; `pwsh` 7 is not
  installed here); the release script passes `bash -n`.
- The release step, run with a stub `gh` that prints its arguments: for `v0.14.0` it passes exactly the
  arguments the old step passed (tag, `dist/*.zip`, `--repo`, `--title "Native loader v0.14.0"`, the
  notes); with the tag `v$(touch pwned)` nothing runs and the tag arrives as text.
- Not proven: a run on GitHub. The package job's new order, its job-level permissions, `$env:RUN_URL`
  and the build jobs' caches without `actions: write` can only be seen in the release run. The caches
  and artifacts authenticate with the runner's own token, not the job's `permissions`; `build.yml`'s
  build job already uploads its artifacts with `contents: read` alone.

**Tests** (run from the worktree, `TEMP` in `out\tmp`)
- `tools/tests/test_publish_workshop.py`: 35 tests, OK (31 before: 4 new, 2 renamed and changed).
- `tools/tests/test_inputs.py`: 17, OK (2 new). `tools/tests/test_ci_tools.py`: OK.
- `tools/gmapack/tests`: 29, OK (1 new; 1 skipped, as before). `tools/steam/tests`: 26, OK (1 new; 1
  skipped: symbolic links need Developer Mode, as before).
- `python -I tools\check_repo.py`: repo conventions OK.
- `tools\test.ps1 -SkipNative` (no C++ changed): **all checks passed**: conventions; `tools` 584 tests
  (7 skipped), `tools\gmapack` 29 (1 skipped), `tools\steam` 26 (1 skipped). Log:
  `out\worktrees\r19-tooling\out\r19t\test-skipnative.log`.

## Proposed CHANGELOG lines (under `## [Unreleased]`)

- **Fixed:** after a release uploaded from GitHub (`publish_workshop.py --from-ci`), the next commit,
  merge or push of `main` no longer uploads a development build over it while the packaging inputs are
  the release commit's. The release record names its commit in full (`commit_sha`), and the hook run
  records its fingerprint (review R19, M1).
- **Changed:** `publish_workshop.py --from-ci` fails (exit 1) when no run of the package workflow for the
  commit appears within five minutes, or when the run was cancelled; it reported `no-run` and
  `cancelled` with exit 0 (ADR 0108: only a person starts the workflow).
- **Security:** `build.yml`'s release job passes the tag and the repository to the shell as environment
  variables, never pasted into the script, and pins Pillow to 12.3.0; `package.yml` reads the run's URL
  the same way and grants `actions: write` only to the package job (review R19, F-01, F-04).
- **Fixed:** `package.yml` deletes the older `rtx-package` artifacts only after the new one is uploaded,
  so a failed upload leaves the last good package (review R19, F-07; replaces the order of ADR 0106).
- **Fixed:** `gmapack.py` stops an LZMA-wrapped archive whose decoded size passes 8 GiB, declared or
  not (review R19, F-08).
- **Fixed:** `inputs.py` refuses paths Windows reads as other files (a trailing dot or space, device
  names, refused characters, 8.3 short names) and, across an index, paths that differ only in case or
  would be stored under one name; an import stops at an index it cannot read instead of replacing it
  (review R19, F-09).
- **Fixed:** `make_vanilla_copy.py` leaves out, and reports as unverified, a non-empty depot file the
  manifest gives no SHA-1 (review R19, F-05).

## Proposed RESEARCH facts

- **Actions artifact storage, 2026-11-05** (`gh api repos/{owner}/{repo}/actions/artifacts`, unexpired):
  1,200 MiB in all. One `rtx-package`, 841,294,833 bytes (802 MiB, run 41977506299). 88
  `gmod-native-loader` bundles from `build.yml`, 392 MiB, 3.6 to 5.3 MB each (growing) and about
  eleven a day since 2026-10-28, kept 90 days (the default). 13 `test-evidence` (5.9 MiB), and 46 reports and
  summaries (0.3 MiB). A release run now holds two packages for a few minutes: about 2.0 GiB with
  today's bundles.
- **The package indexes, 2026-11-05:** 1,221 paths in `packages/*/files.json`; 87 contain `~` (all
  under the fixes part's `~gmod_topbr`); none ends in `.xz`, ends in a dot or a space, is a device name,
  has the 8.3 form, or differs from another only in case.
- **`git diff --quiet <a> <b> -- <paths>`** exits 0 when a path is in neither commit (no error), 1 on a
  difference, 128 for an unknown commit: what `same_inputs()` relies on.

## Proposed decision note

R19-T has no decision number. ADR 0106 decision 4 says each run "deletes the older `rtx-package`
artifacts before uploading its own"; since R19 (F-07) it deletes them after its upload has succeeded,
and still keeps one. The integrator may record this in R19's decision record or the index; ADR 0106
itself stays as it is.

## What the integrator must do

**At the merge**
- `tools/inputs.py` and `tools/gmapack/gmapack.py` are packaging inputs (`REPO_INPUTS`): the merge's
  hook run builds the package (their changes do not change its content).
- After all parts are merged, run `python -I tools\inputs.py verify`: the other parts imported with the
  old `inputs.py`, and the merged indexes must pass the new name checks (they all pass on `r19-int`).
- The hooks need no reinstall (their text did not change).

**Before the release run**
- **Storage.** Check the unexpired artifacts (the `gh api` above): about 1.2 GB now, plus three or so
  bundles of 5 MB from the merge, push and tag. The new order adds the new package (about 0.8 GB)
  before the old one goes: about 2.0 GiB for a few minutes. GitHub's quota error says that usage is
  recalculated every 6-12 hours, so a short overlap should pass; this was not tried. If the upload
  fails with "Artifact storage quota has been hit", the old package is still there (that is the fix):
  with the user's agreement delete the old `rtx-package` artifact (run 41977506299, R16's) by hand and
  start a new run.
- **A new run, not a re-run.** If the package job fails after its uploads (the deletion step, say),
  re-running the job collides with the artifacts the run already has (upload-artifact refuses a name
  twice in one run, as before R19): start the workflow again.
- **Order.** Start the workflow first, then `publish_workshop.py --from-ci --commit <sha>` (first with
  `--dry-run`, as R16 did): without a run within five minutes it now fails.

**After the release upload**
- `published.json` has `commit_sha`. The R19 report's commit and the push that follows should log
  "the item holds the release built on GitHub from <sha>, whose packaging inputs HEAD has: nothing to
  upload" (`out\workshop\logs`), then "inputs unchanged". Check that no development upload follows the
  release.
- The tag's release job: check that the GitHub release is named "Native loader v0.14.0" with the
  bundle.

**In game:** nothing; this part changes no shipped file. **Strings to translate:** none.

## Open issues

- **Artifact storage will fill.** At the current pace the bundles add about 50 MiB a day for 90 days.
  With one package, the 2 GB is reached in about two weeks; then every upload fails, `build.yml`'s
  bundle too, and a release run sooner (it needs room for two packages). Proposal for the user: give
  `build.yml`'s `gmod-native-loader` and `test-evidence` artifacts `retention-days: 7` (a release keeps
  its bundle on the GitHub release itself). Not done here: it changes how long every push's bundle can
  be downloaded, which is the user's call.
- **F-04, further:** the build jobs still keep checkout's credentials (`persist-credentials`); the
  `hotloader` job needs them for `git lfs pull` of the private repository. Left as it is.
- **F-01, further:** no check of the tag's form.
- **F-09:** a case-only rename of an indexed path is now refused at import (on Windows the old and new
  names are one file, and `--prune` would delete the new content); remove the old entry first.
- **F-08:** when `gmapack.py` is run by hand outside `tools\test.ps1`, its spill file still goes to the
  system `TEMP`.
