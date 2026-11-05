# session_integration.py

M5 synthetic acceptance (CTest `nl_session_integration`): the RTX-session extras of
[ADR 0010](../../../docs/decisions/0010-rtx-session-extras.md), and the hiding of RTX-only add-ons
without RTX of [ADR 0013](../../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md), in a
generated game root with the M4 fake runtime. Never starts a real game.

```text
python -I -B session_integration.py --repo <repo> --host <nl_proxy_host.exe> --proxy <winmm.dll>
  --runtime <folder of the fake d3d9.dll> --fixtures <folder of the M5 engine.dll, stdshader_dx6.dll, filesystem_stdio.dll,
                                                     lua_shared.dll, gmcl_nl_dep_win64.dll, nl_dep_runtime_win64.dll>
  --scratch <repo>\out\tmp\m5-session-<config> --config Debug|Release
```

It builds a runtime package with [`package_runtime.py`](../../../tools/package_runtime.py.md) and a
fixes package as a development folder, marked `requires_remix` (a patch set for `engine.dll` that
rewrites the fixture's marker, an override of `stdshader_dx6.dll`, two session variables, an add-on
folder `garrysmod/addons/nl_rtx_addon`, and, for loader 0.3.0's `module_dependencies`
([ADR 0024](../../../docs/decisions/0024-bundled-addons-and-module-dependencies.md)), a binary module
`gmcl_nl_dep_win64.dll` whose static import `nl_dep_runtime_win64.dll` is deployed only beside it in
`garrysmod/lua/bin`). The probe loads that module through a fake `lua_shared.dll`, as GMod's
`require` does: it must load, its runtime loaded first (both reports say so), in the RTX runs, the
runs without RTX and after the failed activation; with the loader switched off
(`NATIVE_LOADER_DISABLE`) it must fail with `ERROR_MOD_NOT_FOUND` (126), which shows the fixture needs
the hook. It places the host as `bin\win64\gmod.exe` beside the
built `winmm.dll` and the three fixtures, creates the user's own add-on folder `user_addon`, writes a
`config.cfg` with the user's values, then runs the host's `--m5-probe` thirteen times. Each probe also
lists `garrysmod\addons` through the fake `filesystem_stdio.dll`, relative with the A functions and
absolute with the W ones, and `garrysmod\cfg`, and loads the shader a second time with
`LOAD_LIBRARY_SEARCH_DEFAULT_DIRS`, a flag Windows refuses next to `LOAD_WITH_ALTERED_SEARCH_PATH`:

| Run | Expected |
|---|---|
| RTX on, `-insecure` | the marker is patched before the fixture's DllMain; `stdshader_dx6.dll` comes from the package, by both loads (R19, proxy F-05); `+exec nativeloader_session.cfg`; the user's values recorded; both add-on folders listed, none reported hidden |
| RTX on, no `-insecure` | no patches (and a note why), the override still applies, record and cfg not rewritten |
| RTX on, `NL_M5_DEP_RETRY` (R19, proxy F-04) | the probe moves the module's runtime aside for a first `require` (`ERROR_MOD_NOT_FOUND`, 126) and back for a second, which loads; `session.json` reports the dependency `failed`, then `loaded`; the runtime is back in place |
| RTX off, invalid journal (R1-004) | `config.cfg` first rewritten as the game would archive it (the session's `r_nl_test`, and `r_3dsky` changed by the user); no restore and no command-line change; the record untouched |
| RTX off | the vanilla marker and shader, by both loads; `+exec nativeloader_restore.cfg` with only `r_nl_test` (the user's own `r_3dsky` stays); the record marked done; `nl_rtx_addon` left out of both listings while `user_addon` and `garrysmod\cfg` are listed in full; `status.json` and `session.json` (with its `utc`) name it; its file unchanged on disk |
| RTX off again | the record forgotten, nothing added to the command line; the add-on still hidden |
| RTX off, `filesystem_stdio.dll` without an import name table (R1-006) | a copy whose KERNEL32 descriptor has `OriginalFirstThunk` 0: the add-on still hidden (hooked by bound address) |
| `native-loader\logs` a junction (R1-001) | the junction's target `loader.log` unchanged |
| `garrysmod\data\native-loader` a junction (R1-005) | the target's `session.json` unchanged and no `status.json` written there |
| RTX on again | the user's values recorded afresh, patched again; the add-on listed again |
| RTX on, runtime DllMain fails (`NL_M4_FAIL_ATTACH`) | activation `failed` after the module hooks went in: no patch, the vanilla shader, and the RTX-only add-on hidden by a second hook installation |
| A `gmod-rtx-remix` dev package with the seven shipped rendering recipes (from `tools/package_fixes.py`), `patch_sets.allow_rtx_render_patches: false`, no `-insecure` | [ADR 0056](../../../docs/decisions/0056-guard-and-startup-fallbacks.md): activation `failed` with a reason naming the key and `-insecure`, listed in `errors`; no patch, the vanilla shader, the RTX-only add-on hidden |
| The same with `-insecure` | active; the marker patched; `session.patches` counts the eight patches the session applies |

Inputs and outputs: scratch below `out\tmp` (deleted afterwards); probes, status and session
reports under `out\m5-synthetic\<config>-<pid>`. Exit 0 when every check passes; an `AssertionError`
(exit 1) names the first that failed.
