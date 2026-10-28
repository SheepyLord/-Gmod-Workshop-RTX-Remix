# test_package_workshop.py

Unit tests for [`package_workshop.py`](../package_workshop.py.md). They build small packages under
`out\tmp` and combine them; nothing else is touched.

```powershell
cd tools; python -m unittest tests.test_package_workshop
```

| Test | Checks |
|---|---|
| two folders become one package and archive | the merged manifest: kinds, `requires_loader`, `requires_remix`, the runtime, root files, patch sets and session variables; every file's bytes; `addon.json`; the archive's entries and SHA-256 |
| an archive part is read in place | a `.gma` part gives the same digest as its folder |
| the digest ignores version and name but not content | same digest for two versions; a changed file changes it |
| a file in two parts is refused | including two paths that differ only in case |
| two runtimes are refused | at most one part may carry `remix` |
| a file that does not match its manifest is refused | and nothing is written |
| conflicting session values and unknown keys are refused | |
| nlctl validates a real combination | runs only when `nlctl.exe` is built: a mod package plus a binary-module package passes `nlctl manifest` |

Exit 0 when every test passes.
