# test_publish_workshop.py

Unit tests for [`publish_workshop.py`](../publish_workshop.py.md).

- They build two small, valid packages under `out\tmp`, and point the state folder there too.
- The upload step is replaced by a recorder, so `gmpublish` never runs and nothing reaches the
  Workshop.
- The hook tests use a throwaway `git init` repository under `out\tmp`.

```powershell
cd tools; python -m unittest tests.test_publish_workshop
```

| Test | Checks |
|---|---|
| first run uploads, then unchanged inputs stop early | one upload; `published.json`; the change notes name the version; the second run uploads nothing |
| changed content uploads again | a changed file in a part uploads a new version |
| same content with new input times uploads nothing | a rebuild with the same digest is `unchanged-content` and keeps the new fingerprint |
| dry run and force | a dry run uploads and records nothing; `--force` uploads although nothing changed |
| only the newest archive is kept | |
| config errors | a bad item id, a part with neither or both sources, an unknown builder |
| the lock takes over a dead owner and waits for a live one | |
| install, refuse foreign and uninstall | all four hooks (`post-commit`, `post-merge`, `post-checkout`, `pre-push`) carry the marker and LF line endings and run Git LFS's step of the same name; a foreign hook is refused unless forced; uninstall removes only ours |
| the hooks are valid sh | `sh -n` accepts every hook, with the `sh` git runs hooks with: on the path, or Git for Windows' own beside `git.exe` (`bin\sh.exe`, `usr\bin\sh.exe`); skipped only without either |
| a source repository's hook environment does not redirect git | the script run as a hook would run it, with `GIT_DIR`, `GIT_INDEX_FILE` and `GIT_WORK_TREE` naming another repository: its shared state and `git rev-parse --show-toplevel` are still this repository's, and no repository-local git variable is left |
| old source hooks are removed and only ours | `--uninstall-source-hooks` removes a marked `post-commit` that ADR 0024 put in an add-on's repository and leaves a foreign `post-merge`; `install_source_hooks` is gone (ADR 0033) |
| the parts a config unpacks | `input_parts()`: the `packages/` parts that `out/inputs/<part>/...` paths name, with either slash, and nothing for paths elsewhere |

Exit 0 when every test passes.
