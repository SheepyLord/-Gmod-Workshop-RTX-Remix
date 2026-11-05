# R16 plan: the sky at a map's start, and the RTX package built on GitHub

The user's items (2026-11-04), verbatim:

> Address a bug:
>
> 44. The weather and daytime setting is not applied when user enters the map, user has to open the
> menu and go to the setting panel to activate.
>
> Address 1 QoL,
>
> 45. Make the action more transparent for monitoring, the RTX package's action should report the
> SHA256 HASH of all files in the .gma files and the .gma file itself used to upload to the workshop.
> All binaries have to be freshly built (not uploaded from our local) and the .gma has to packed on
> GitHub. Note there is only 2 GB of artifact storage, thus only one most recent workshop package .gma
> should be kept in action.

Claude works in the main session on `r16` (worktree `out/worktrees/r16`, from `main` `2f6a03d`). Codex
translates only.

## Item 44: what was found

Traced option by option (a PoC-only add-on logging every `RemixConfig.SetConfigVariable` of the sky,
weather and game lights, with the caller), with the field player's sky settings:

| Case | The companion's sky at the start |
|---|---|
| PoC, new game, gm_construct | Sent at InitPostEntity; the RTX fixes' light updater sets `rtx.ignoreGameDirectionalLights False` 1.2 s later; the companion's 5 s re-send puts it back |
| PoC, the field's `rtx.conf` | The same |
| PoC, a map change (gm_construct to gm_flatgrass) | The same, in the new map's Lua |
| PoC, a two-player listen server | The same |
| Field, gm_construct, the user's own settings and add-ons | Applied (clouds and the sun follow the settings from the first picture) |
| PoC, `modern_house` with Modern House RTX | Sent at InitPostEntity, then Modern House RTX sets its afternoon 5.8 s later and the companion stands aside (ADR 0031 rule 5) until a setting changes: the report |

Fix: [ADR 0105](../decisions/0105-the-players-sky-applies-from-a-maps-start.md).

## Item 45: what was found and done

The survey of every native binary's source (`out/r16/binary-sources.md` in the main checkout; the facts
are in RESEARCH.md, "R16: where the package's binaries come from") found 54 native binaries in
`packages/`: 41 in the runtime, 5 in the fixes, 5 of the Model Hotloader, one each for ReShade, the glass
and the material editor. Decision: [ADR 0106](../decisions/0106-the-rtx-package-built-on-github.md).

| Binaries | In the workflow |
|---|---|
| Runtime `d3d9.dll`, two USD plugins | compiled: the fork at `runtime/base.json` with `runtime/patches` (`runtime/build_runtime.ps1 -Install`) |
| Runtime's 38 vendor DLLs (DLSS, NRC, XeSS, OpenUSD, ...) | fetched by that same Meson build (packman, submodules, clones) |
| `gmcl_RTXFixesBinary_win64.dll` | compiled: public `f28bd5a9` with the four GPL patches of `packages/fixes/licenses` (= the native tree of `913bb6b`), `ReleaseWithSymbols` |
| `gmcl_rtxwater_win64.dll` | compiled: `source/rtx_water` of `b5c194ec` (native Version 4) |
| `gmcl_rtxdebug_win64.dll` | compiled: `packages/fixes/licenses/rtxdebug/checkout` |
| `gmcl_advmat_rtx_bridge_win64.dll` | compiled: the private repository's `native/rtx_bridge` at `8ece1415`, vendored in `packages/advanced-material-editor/source` |
| `gmsv_nlrtxclient_win64.dll`, `gmcl_nlglass_win64.dll` | compiled: this repository at the packaged commit |
| ReShade setup (and `ReShade64.dll` in it), `stdshader_dx6.dll`, `lib_coacd.dll` | fetched from reshade.me, the public fixes repository and CoACD's PyPI wheel, checked against pinned SHA-256 hashes |
| Model Hotloader: `gmcl_mmdhl`, `gmsv_mmdhl`, `mmdhl_runtime`, `mmdhl_worker` | from `packages/`: built from staged, uncommitted changes in its author's worktree; reported as such |

Local proof (2026-11-04, this worktree): `tools/ci/build_modules.ps1` with the local fixes clone,
garrysmod_common and premake built all four modules at the shipped sizes; `collect_runtime.py` found all
189 runtime files in the fork's `_output`; `build_package.py --built` made a 1,736,040,838-byte package
whose report counts 9 compiled, 41 fetched and 4 `packages/` binaries.
