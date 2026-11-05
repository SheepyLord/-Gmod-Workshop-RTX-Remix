# cache_key.py

Prints the cache key of one of the package workflow's binary builds (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)): a SHA-256 of exactly the sources
that build reads, so a run reuses a cached build only for the same sources.

```powershell
python tools\ci\cache_key.py runtime
python tools\ci\cache_key.py modules
```

| Build | What the key covers |
|---|---|
| `runtime` | every file under `runtime/` except its Markdown (patches, `base.json`, `submodules/`, `build_runtime.ps1`), `collect_runtime.py`, `tools/lib/VsDevEnv.psm1`, and the list of files the runtime part ships under `files/` (names, not hashes) |
| `modules` | `build_modules.ps1`, `tools/lib/VsDevEnv.psm1`, the four fixes patches, the debug module's and the bridge's source copies, and `pins.json`'s `garrysmod_common`, `premake`, `fixes`, `rtxdebug` and `advmat_bridge` |

Each file counts with its path and its bytes with CRLF read as LF, so a checkout's line-ending conversion
does not change a key. The workflow prefixes the key with the build's name and `BUILD_SALT`. **Exit:** 0
printed; 2 for an unknown build. Tested by [test_ci_tools.py](../tests/test_ci_tools.py.md).
