# session_integration.py

M5 synthetic acceptance (CTest `nl_session_integration`): the RTX-session extras of
[ADR 0010](../../../docs/decisions/0010-rtx-session-extras.md), and the hiding of RTX-only add-ons
without RTX of [ADR 0013](../../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md), in a
generated game root with the M4 fake runtime. Never starts a real game.

```text
python -I -B session_integration.py --repo <repo> --host <nl_proxy_host.exe> --proxy <winmm.dll>
  --runtime <folder of the fake d3d9.dll> --fixtures <folder of the M5 engine.dll, stdshader_dx6.dll, filesystem_stdio.dll>
  --scratch <repo>\out\tmp\m5-session-<config> --config Debug|Release
```

It builds a runtime package with [`package_runtime.py`](../../../tools/package_runtime.py.md) and a
fixes package as a development folder, marked `requires_remix` (a patch set for `engine.dll` that
rewrites the fixture's marker, an override of `stdshader_dx6.dll`, two session variables, and an
add-on folder `garrysmod/addons/nl_rtx_addon`). It places the host as `bin\win64\gmod.exe` beside the
built `winmm.dll` and the three fixtures, creates the user's own add-on folder `user_addon`, writes a
`config.cfg` with the user's values, then runs the host's `--m5-probe` five times. Each probe also
lists `garrysmod\addons` through the fake `filesystem_stdio.dll`, relative with the A functions and
absolute with the W ones, and `garrysmod\cfg`:

| Run | Expected |
|---|---|
| RTX on, `-insecure` | the marker is patched before the fixture's DllMain; `stdshader_dx6.dll` comes from the package; `+exec nativeloader_session.cfg`; the user's values recorded; both add-on folders listed, none reported hidden |
| RTX on, no `-insecure` | no patches (and a note why), the override still applies, record and cfg not rewritten |
| RTX off | the vanilla marker and shader; `+exec nativeloader_restore.cfg` with the recorded values; the record marked done; `nl_rtx_addon` left out of both listings while `user_addon` and `garrysmod\cfg` are listed in full; `status.json` and `session.json` name it; its file unchanged on disk |
| RTX off again | the record forgotten, nothing added to the command line; the add-on still hidden |
| RTX on again | the user's values recorded afresh, patched again; the add-on listed again |

Inputs and outputs: scratch below `out\tmp` (deleted afterwards); probes, status and session
reports under `out\m5-synthetic\<config>-<pid>`. Exit 0 when every check passes; an `AssertionError`
(exit 1) names the first that failed.
