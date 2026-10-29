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
| install, refuse foreign and uninstall | all three hooks carry the marker and LF line endings; a foreign hook is refused unless forced; uninstall removes only ours |
| source hooks call this checkout's script by absolute path | `post-commit` and `post-merge` in a part's source repository: the marker, the main checkout's script, the add-on's name in the change notes, `main` only (every branch with `--any-branch`), LF; nothing written when one target hook is foreign; uninstall leaves foreign hooks alone |

Exit 0 when every test passes.
