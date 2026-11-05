# fetch_prebuilt.py

Downloads the RTX package's binaries that the workflow does not compile and checks each against its pins
(R16, [ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)), from `pins.json`'s
`fetched` list:

| Name | Part/path | From | Why it is fetched |
|---|---|---|---|
| `reshade-setup` | `reshade/ReShade_Setup_6.8.0.exe` | reshade.me | ReShade's signed setup; `tools/package_reshade.py` takes `ReShade64.dll` out of it and checks that hash too (`contains`) |
| `stdshader_dx6` | `fixes/garrysmod/bin/win64/stdshader_dx6.dll` | the public fixes repository at `d958da61` | the fixes' Obsoletium shader DLL; its author never published the source of this build |
| `coacd` | `model-hotloader/bin/lib_coacd.dll` | CoACD 1.0.14's PyPI wheel | CoACD's own CI build (MIT); the archive's SHA-256 is checked, then the member's |

```powershell
python tools\ci\fetch_prebuilt.py [--out out\ci\built] [--run-url URL] [--only NAME ...]
python tools\ci\fetch_prebuilt.py --from out\inputs        # a test without network
```

Each download is retried three times (User-Agent `gmod-native-loader-ci/1`). A file whose size or
SHA-256 differs from its pin (or whose archive's SHA-256 differs) is not written. `--from DIR` takes
`<DIR>\<part>\<path>` instead of downloading (for local tests, such as the unpacked `out\inputs`); the
hashes are checked the same way and the provenance says it was a local test.

Writes each file to `<out>\<part>\<path>` and `<out>\provenance-fetched.json`: for each file's SHA-256
(and each `contains` hash) its part, path, repository, commit or tag, URL, `how` (`fetched: ...`) and the
run; `problems` lists what failed. **Exit:** 0 when every file was fetched and verified; 1 otherwise.
Tested by [test_ci_tools.py](../tests/test_ci_tools.py.md).
