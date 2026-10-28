# M5 report: the RTX fixes on a vanilla install

- Author: Claude, 2026-10-28, with two helper agents (an independent reviewer for M4, and one that
  wrote `package_fixes.py`, `compare_frames.py` and the companion from the plan); planned and built
  without further approvals at the user's request.
- Plan: [M5-plan.md](M5-plan.md). Decisions: [ADR 0010](../decisions/0010-rtx-session-extras.md),
  [ADR 0011](../decisions/0011-lua-addon-folders.md) (the user should confirm 0011: it widens the
  package path rules), [ADR 0013](../decisions/0013-rtx-only-addons-hidden-without-rtx.md). Facts:
  [RESEARCH.md](../RESEARCH.md) sections 12-13.
- Branch: `m5-rtx-fixes` in the main checkout, merged into `main` with M6 (they share files).

## Result

**A vanilla install with only `bin\win64\winmm.dll` and two local packages path-traces like the
classic RTX install, and stays vanilla with RTX off.**

- **gm_construct**, at the spawn camera pinned in both installs: the PoC and `GarrysMod_RTX_c`
  differ by block_diff **0.90** on the user's measure. With the final build and package it was
  **1.01**. Both are within the noise between two captures of one install (about 1). Mean RGB
  119.5/113.2/101.0 in both.
- **The user's gm_csgosafehouse save**, at their camera: **3.18-3.24** over four PoC captures. Two
  reference frames 4 s apart differ by 0.83. That is "close" on the user's scale (1.5-3.6), not
  "broken" (16-26).
  - Geometry, lighting, shadows and almost every material match. The difference sits on the woven
    chair backs, darker in the PoC (41-46 of 880 blocks above 8).
  - Byte-identical in both: the runtime (`d3d9.dll` a8e39d93), the fixes module (485667b7),
    `stdshader_dx6.dll`, `rtx.conf`, `dxvk.conf`, `user.conf`, `config.cfg` and three of the four
    fixes mods.
  - Copied into the PoC with no change to the result: the user's 21 add-ons, their native modules,
    the material editor's data, two linked Remix mods, and the reference's own ToPBR mod.
  - What cannot be equalised is the game: the reference runs GMod 2026.09.15 (10174), the PoC the
    current 2026.10.26 (10215), with a different `engine.dll` and VPKs. Steam's files are never
    written. [RESEARCH.md](../RESEARCH.md) section 13 has the table.
- **RTX off** with both packages deployed:
  - System32's `d3d9.dll`, the stock shader DLL, no patches, override or session variables.
  - The fixes' nine add-on folders are left out of GMod's add-on search: 21 add-ons mounted instead
    of 30, no line from the fixes' Lua. They stay on disk, and the next RTX start mounts all 30.

## What was built

| Piece | Where |
|---|---|
| Patch sets: byte patches written when an engine DLL is mapped, only where the pattern occurs exactly once; `-insecure` sessions by default | `nl::patch`, `loader/proxy/modules.cpp`; manifest `patch_sets` |
| Module override: `filesystem_stdio`'s load of `bin\win64\stdshader_dx6.dll` loads the package's copy, through `LoadLibrary*` import hooks installed as game DLLs are mapped | `loader/proxy/modules.cpp`; manifest `module_overrides` |
| Session console variables: `+exec nativeloader_session.cfg`; the user's archived values recorded and put back once at the next start without RTX | `nl::session`, `loader/proxy/runtime.cpp`, `startup.cpp`; manifest `session_cvars` |
| RTX-only add-ons hidden without RTX: `filesystem_stdio`'s `FindFirstFile*`/`FindNextFile*` imports skip their folders when no runtime is active | `nl::session::hidden_addons`, `loader/proxy/modules.cpp`, `startup.cpp`; manifest `requires_remix`; ADR 0013 |
| Lua add-on folders and create-only seed data as package areas | `nl::paths`, `nl::manifest`, journal |
| Runtime folder on `PATH` instead of `SetDllDirectoryW` (an M4 bug found here: it broke the fixes' module lookups) | `loader/proxy/runtime.cpp`; ADR 0010 point 4 |
| `session.json`, and `status.json`'s `session` block | `loader/proxy/modules.cpp`, `nl::status` |
| The fixes package from the fixes repo: 9 add-ons, 4 mods, 2 modules, the shader DLL, 7 patch sets, 33 session variables; marked `requires_remix`; the ToPBR converter's mod create-only | `tools/package_fixes.py` |
| The Lua companion: console summary, M6's restart notice | `companion/nativeloader` |
| PoC tooling: console text through `WM_COPYDATA` (single-player quit, camera, saves, a Workshop map mounted from Lua), parity content in layers, the user's block measure | `tools/poc_session.py`, `tools/poc_parity.py`, `tools/compare_frames.py` |
| Loader version 0.2.0; `package_runtime.py --insecure` | `CMakeLists.txt`, `tools/package_runtime.py` |

## Evidence

- Tests: `tools\test.ps1` (Debug) and the Release build: conventions, the Python tests, CTest 16/16.
  - `test_m5.cpp`: 135 core cases in all.
  - `nl_session_integration`: a fake engine DLL patched before its own DllMain, the override, the
    session cfg and its restore, and a fake `filesystem_stdio.dll` whose add-on listing loses the
    RTX-only folder only without RTX. Five scenarios.
  - M4's 17 synthetic scenarios still pass.
- Real sessions on the PoC, in `out/m5/acceptance` (its `session.json` lists every run):
  - First start: both packages deployed (445 changes, 1.43 GB) in 7.3 s.
  - All 7 patches applied, the shader load redirected, 15 game modules hooked, 33 session variables
    run.
  - The fixes' module created all its variables ("Got ILuaConVars interface") and every session
    quit normally.
- Comparisons: `ref-construct-pinned-2` against `poc-construct-pinned` (0.90) and `poc-on-final-2`
  (1.01).
- Safehouse: `ref-safehouse-mounted` against `poc-safehouse-mounted`, `-advmat`, `-allmods` and
  `-reftopbr`, in `safehouse-compare*.json`.
- RTX off: `poc-off-hidden-2`. Its `status.json` has `session.hidden_addons` with 9 folders, and its
  `session.json` has `hidden_addons.left_out` (9) and `filesystem_stdio.dll (5 imports)`.
- Clean-up: the PoC uninstalled (2,877 depot files OK) and every parity layer restored. The data
  folders the add-ons' Lua wrote and the ToPBR leftover were removed. Remix's logs and two crash dumps
  stay in the PoC; the one from 05:17 is the `SetDllDirectoryW` bug below (`crash-0517`).

## Deviations from the plan

- The plan named only `garrysmod/addons/<addon>` as a new area. The fixes also seed
  `garrysmod/data/remix_map_configs/default.txt`, so `garrysmod/data/<folder>` became a create-only
  area too.
- `mat_disable_d3d9ex` stays out of the session variables (it is read before any cfg runs), and
  session variable names are limited to rendering prefixes so a package cannot run commands.
- M4's `SetDllDirectoryW` was replaced (see above). The PoC crashed in the fixes' `require` until then.
- ADR 0013 is new. The first RTX-off check showed the fixes' Lua still running, so the add-ons are now
  hidden in memory. Undeploying them was rejected because the fixes rewrite their own deployed files,
  which then blocked the package. That same trap showed up on a reinstall, so `package_fixes.py`
  makes the ToPBR mod create-only.
- The safehouse save needed more than the plan foresaw.
  - Its map is a Workshop item, and the reference install takes over 15 minutes to mount the user's
    Workshop add-ons. The session driver now mounts just that item from Lua.
  - Parity needed the user's add-ons (five of them links to working copies) and native files.
- The parity copy first followed two linked mods into a loop and wrote about 390 GB into the PoC
  before it was stopped. The copy was deleted, `poc_parity.py` now never follows links, and nothing in
  the reference install was written ([RESEARCH.md](../RESEARCH.md) section 13).

## Open

- The fixes' five Steam-file overwrites (menu, camera SWEP, images) are left out; anything that
  depended on them would differ.
- The companion ships inside the fixes package, so it is hidden with RTX off too, and M6's restart
  notice then shows only in RTX sessions. A package of its own without `requires_remix` would fix
  that.
- The fixes' module has its own runtime patcher for the same culling patches the loader's patch sets
  write. Both agree today; if they ever disagree, the module's restore at map exit puts back what it
  found, which is the loader's patched bytes.
