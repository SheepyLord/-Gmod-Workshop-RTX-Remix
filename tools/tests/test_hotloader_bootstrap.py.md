# test_hotloader_bootstrap.py

Checks the Model Hotloader's `scripts/bootstrap.py` (`packages/model-hotloader/source/mmdhl/scripts/`), which
fetches the add-on's locked dependencies for its native build ([build_hotloader.ps1](../ci/build_hotloader.ps1.md)).
Since R19 (review F-03) it fetches each locked commit with git, which checks every object it receives against
its hash, instead of downloading GitHub's archives with no digest.

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_bootstrap.py    # from the repository root
```

Each test copies the script into a scratch add-on folder under `out\tmp` and points it (`GIT_BASE`) at a local
bare repository standing in for GitHub, whose locked commit is no longer the branch's tip.

| Test | Checks |
|---|---|
| `test_a_locked_commit_is_fetched_with_git` | The locked commit's tree is written to `vendor/<name>` with its stored bytes (no CRLF, even with `core.autocrlf=true` as Git for Windows sets it), `export-ignore` honoured as in the archives, `.mmdhl-revision` written, no scratch repository left; a second run says `ready` |
| `test_a_commit_the_repository_does_not_have_is_refused` | A hash the repository does not have fails and leaves nothing |
| `test_only_full_commit_hashes_and_plain_repository_names` | A short hash and a repository name that is not `owner/name` are refused |
| `test_the_archive_download_is_gone` | The script no longer names `codeload.github.com` |

**Needs:** git (skipped without it). **Writes:** a scratch folder under `out\tmp`, removed after each test.
Exit code 0 on success.
