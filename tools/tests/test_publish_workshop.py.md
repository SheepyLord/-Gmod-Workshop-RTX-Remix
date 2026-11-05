# test_publish_workshop.py

Unit tests for [`publish_workshop.py`](../publish_workshop.py.md).

- They build two small, valid packages under `out\tmp`, and point the state folder there too.
- The upload step is replaced by a recorder, so `gmpublish` never runs and nothing reaches the
  Workshop.
- The hook tests use a throwaway `git init` repository under `out\tmp`.
- Publisher preflight tests use synthetic bytes with the reviewed instruction window, mocked real
  API initialization and mocked child processes. They never initialize Steam or run an upload.

```powershell
cd tools; python -m unittest tests.test_publish_workshop
```

| Test | Checks |
|---|---|
| the background run shares one hidden console | `--background` relaunches without that flag, with `CREATE_NO_WINDOW` and never `DETACHED_PROCESS` |
| first run uploads, then unchanged inputs stop early | one upload; `published.json`; the change notes name the version; the second run uploads nothing |
| changed content uploads again | a changed file in a part uploads a new version |
| same content with new input times uploads nothing | a rebuild with the same digest is `unchanged-content` and keeps the new fingerprint |
| dry run and force | a dry run uploads and records nothing; `--force` uploads although nothing changed |
| only the newest archive is kept | |
| config errors | a bad item id, a part with neither or both sources, an unknown builder |
| the fingerprint ignores unpacked inputs and the working folder | a part read from `out/inputs` does not change the fingerprint when its file appears there, nor when the script runs from another folder; an absolute path elsewhere still does |
| one publish at a time and no lock left behind | R3-005: a second handle cannot take the lock; once released it can; a process that ends holding it leaves it free; the file stays |
| a push publishes from the checkout of the pushed commit | R3-004: in a repository with a worktree on another branch, `checkout_at` finds each commit in the checkout that has it, and nothing for a commit checked out nowhere |
| install, refuse foreign and uninstall | all four hooks (`post-commit`, `post-merge`, `post-checkout`, `pre-push`) carry the marker and LF line endings and run Git LFS's step of the same name; post-commit, post-merge and pre-push run the publisher with `--commit`, never `--from-ci` (ADR 0108); a foreign hook is refused unless forced; uninstall removes only ours |
| `FromCiTests` (R16, ADR 0106, 0108; `gh` and the upload replaced by recorders, `GitHubFakes`) | the run's package is downloaded, checked against its report and uploaded once, the change note names the run and the SHA-256, `published.json` records the run and the full commit SHA (`commit_sha`), the same run again is `unchanged`; a `.gma` that does not match its report uploads nothing; a failed and a cancelled run upload nothing and fail (review R19); a commit without a package run waits five minutes, uploads nothing and fails, and `main` exits 1 with the reason on stderr (review R19: it was `no-run`, exit 0); a queued, then running build is waited for; a dry run downloads and checks but uploads nothing |
| `ReleaseThenHookTests` (review R19, M1; a throwaway git repository, `GitHubFakes`, the real build) | after a release uploaded with `--from-ci`, the hook's run (`publish`) at the release's own commit, and after a commit that touches only docs, uploads nothing, says why, keeps the release's record and records the fingerprint, so the next run stops at "inputs unchanged"; `--force` still uploads; after a commit that changes a packaging input the development build is uploaded as before and recorded with its `commit_sha`; a release record without `commit_sha` (before R19) or a configuration other than the release commit's is not taken for the release; `same_inputs` says `None` for a commit the clone lacks |
| the hooks are valid sh | `sh -n` accepts every hook, with the `sh` git runs hooks with: on the path, or Git for Windows' own beside `git.exe` (`bin\sh.exe`, `usr\bin\sh.exe`); skipped only without either |
| a source repository's hook environment does not redirect git | the script run as a hook would run it, with `GIT_DIR`, `GIT_INDEX_FILE` and `GIT_WORK_TREE` naming another repository: its shared state and `git rev-parse --show-toplevel` are still this repository's, and no repository-local git variable is left |
| old source hooks are removed and only ours | `--uninstall-source-hooks` removes a marked `post-commit` that ADR 0024 put in an add-on's repository and leaves a foreign `post-merge`; `install_source_hooks` is gone (ADR 0033) |
| the parts a config unpacks | `input_parts()`: the `packages/` parts that `out/inputs/<part>/...` paths name, with either slash, and nothing for paths elsewhere |
| every repository file a packager reads is a publish input | review R4: the modules the packagers (and `companion_i18n.py`) import from `tools/` and the repository files they name (`os.path.join(REPO, ...)`, `REPO / ...`) are all under `REPO_INPUTS`, including `tools/companion_i18n.py`, `LICENSE` and `third_party/gmod/LICENSE`; `.gitattributes` is an input |
| the package workflow starts only by hand | ADR 0108: `.github/workflows/package.yml`'s only trigger is `workflow_dispatch` |
| a copy still held after a good upload is not an error | review R4: the fallback copy is still open when the retry succeeds, so its folder cannot be removed; `upload()` returns the success and logs the folder left in `out/tmp` |
| normal publisher success | runs the original executable once, without a compatibility probe or copy |
| exact stale-process error | retries from a temporary copy; only the reviewed conditional-branch opcode changes; same item, archive, notes and game working directory; dependency bytes stay exact; originals remain unchanged and temporary copies are removed |
| later initialization/login/owner failures | never trigger the early-process fallback |
| unreviewed executable/API or mismatched code window | fail closed before the probe or copied executable can run |
| unsuccessful real initialization or fallback upload | remains a failure; never claims publication |
| initialization probe | app ID is process-local, timeout is bounded, raw diagnostic output is captured, and errors/timeouts refuse fallback |

Exit 0 when every test passes.
