# R19-E report: the editors

[Plan](R19-plan.md) (section "R19-E: the editors"); [review](R19-review.md). Branch `r19-editors`, fix
commit `d3a3693` on `1e4cb10`. Not started in the game (rule 7).

Every change to `packages/` went through `tools/inputs.py import`: working copies under
`out\r19e\work\<part>` (unpacked from the parts), `tools/package_content.py` with each part's
`workshop.json` arguments, then `import --inventory` with the add-on folder and `bin` as roots, and a
plain `--root` import for the bridge's `source/`. `python -I tools\inputs.py verify`: **11 parts checked,
0 problems**. Against `HEAD` before the change only these indexed files differ:

| Part | Files |
|---|---|
| `advanced-material-editor` | `lua/advmat/sh_20_net.lua`, `sv_30_store.lua`, `sv_31_rtx_store.lua`, `cl_71_rtx_source.lua`; `bin/gmcl_advmat_rtx_bridge_win64.dll`; `source/Source.md`, `source/provenance.json`; `source/rtx_bridge/CMakeLists.txt`, `README.md`, `src/lua_bindings.cpp`, `src/standalone_module.cpp`, `src/texture_ingest.cpp`, `tests/writer_tests.cpp`, new `tests/lua_binding_tests.cpp` |
| `advanced-bodygroup-tool` | `lua/autorun/advanced_bodygroup_tool.lua`, `lua/advanced_bodygroup_tool/cl_uv_hide.lua`, `lua/weapons/gmod_tool/stools/advanced_bodygroup.lua` |
| `procedural-bodygroup-destruction` | `lua/bullet_break_simulator/cl_22_shape.lua`, `cl_25_profiler.lua`, `cl_32_mesh_persistence.lua`, `cl_40_damage.lua`, `sv_20_hits.lua` |

Outside `packages/`: `tools/ci/pins.json` (`advmat_bridge.changes`, a note that the copy differs from
its origin commit) and the new `tools/tests/test_editors.py`, `editors_harness.lua` and their `.md`.

## Findings

| ID | Verdict | Result |
|---|---|---|
| ADV-01 | partly, low | **Fixed** |
| ADV-02 | confirmed, medium (M3) | **Fixed** |
| ABT-01 | partly, low | **Fixed** |
| ABT-02 | confirmed, medium (M4) | **Fixed** |
| ABT-03 | partly, low | **Fixed** |
| ABT-04 | partly, low | **Fixed** (the self-or-admin rule) |
| BBS-01 | confirmed, medium (M2) | **Fixed**, plus the same idiom in the material editor |
| BBS-02 | partly, low | **Fixed** |
| BR-02 | partly, low | **Fixed** |
| BR-03 | partly, medium (M6) | **Fixed** |
| BR-01 | false positive | Left as it is |

**ADV-01, the material sync queue** (`sv_30_store.lua`, `sh_20_net.lua`)
- `EncodedSnapshot` (`sv_30_store.lua:672`) encodes the snapshot once per state of the store and keeps
  it. It is reused while `Store.Revision` and `Store.SnapshotSerial` are unchanged.
- A broadcast changes the store and the revision together. The changes that leave the revision alone
  call `InvalidateSnapshot`: a dupe paste's entity rules, an entity removed with its rules (the old
  `EntityRemoved` hook cleared them silently), `Store.Load`, `advmat_wipe`. The serial lives on `Store`,
  so a key is never reused across a Lua autorefresh.
- `AdvMat.Net.SendSnapshotData` (`sh_20_net.lua:216`) queues encoded data under a key, and requests
  coalesce:
  - a player already waiting for a queued snapshot, or receiving this very one, is not queued again
    and gets no second `AdvMat.SyncBegin`;
  - a newer snapshot takes over every job that has not sent a chunk, recipients included.
  So the queue holds the job going out and one waiting job at most, however often clients ask.
- **Why the client copes:** a player moved into a newer snapshot keeps its one announcement. The client
  retires announced revisions older than the snapshot it installs (`cl_40_store.lua:597-616`), and its
  delta log, kept since the first announcement, replays what is newer.
- `AdvMat.Net.SendChunked` stays for any other caller, unchanged in behaviour: it encodes and never
  coalesces. Nothing in the package calls it now.

**ADV-02, the RTX HELLO** (`sv_31_rtx_store.lua`)
- No HELLO resets `AdvMatRTXNextSync` any more, whatever its protocol (`:1150-1201`).
- A capable HELLO inside the 2 s window is answered once, by a per-player timer, when the window ends.
  Before, it was dropped, and only the reset made a quick RTX off-and-on work. A protocol-0 or
  mismatched HELLO cancels that timer, and so does a disconnect.
- `EncodedProfileMessage` (`:237`) encodes each profile message once per revision. The cache is weak,
  keyed by the profile table: every change installs new tables, so a table and the revision identify
  a message. The snapshot no longer encodes each profile twice, and the next player's snapshot encodes
  nothing.
- `SendSnapshot` captures the tombstones with a shallow copy instead of `table.Copy`. Installed
  tombstones are only ever replaced, never changed in place, so their profiles keep the identity the
  cache uses.

**ABT-01, crafted dupes** (`advanced_bodygroup_tool.lua`)
- `SanitizeStoredState` (`:712`) builds a state from stored data:
  - a field that is not a table reads as empty;
  - keys must be integers in range;
  - region groups must be tables;
  - one budget of 4,096 entries spans every field, and at most 256 regions and 64 cut groups are kept.
- The duplicator callback (`:791`) and `GetState(entity, true)` both use it. `GetState` used to
  `table.Copy` whatever a stored modifier held, so a string there raised the error, also on the next
  tool action.
- The old per-region `CountHiddenRegions` scan was quadratic on a crafted table. A running count
  replaces it.

**ABT-02, the region analysis cache** (`cl_uv_hide.lua:48`, `:428`)
- `RegionAnalysisCache` is now least-recently-used, within `ABT.MaxRegionAnalyses` (8) and
  `ABT.MaxRegionAnalysisTriangles` (300,000).
- The analysis just built or used is never evicted, even when it alone is over the budget.
- The hover state and the cut editor keep their own references, so an eviction never breaks them.

**ABT-03, rate** (`advanced_bodygroup_tool.lua:808`)
- A token bucket on each player covers both receivers: a burst of 24, refilled at 8 a second.
- A vertex-cut request refused for rate still gets its `false` reply, so the editor stops waiting.

**ABT-04, other players**
- `ABT.CanEditPlayer` (`:65`): a player entity may be edited only by that player or an admin, the rule
  L-01 sets for the motion tool. `PlayerCanEditSelection` applies it before `CanTool`.
- The stool (`advanced_bodygroup.lua:37`, `:53`) no longer selects another player for a non-admin, and
  `Think` drops such a selection.
- Props, NPCs and ragdolls stay with `CanTool` and prop protection.

**BBS-01, settings that could not be turned off**
- `GetBool` now returns `convar:GetBool()` whenever the convar exists; the fallback is only for a
  missing convar. Changed in `cl_22_shape.lua:11`, `cl_25_profiler.lua:26`,
  `cl_32_mesh_persistence.lua:68` and `cl_40_damage.lua:132`.
- `cl_40_damage.lua` has mixed line endings. It was changed with an exact-replace script, which kept
  the mix: 2,742 CRLF and 4,777 LF after the change, against 2,738 and 4,777 before. An editor would
  have rewritten every line.
- The material editor's `ConVarBool` (`cl_71_rtx_source.lua:98`) had the same idiom. It showed
  `advmateditor_livepreview` and `advmateditor_showall` as on when they were 0. Fixed the same way, as
  `cl_70_ui.lua` already does it.
- `cl_30_overlay.lua`'s helper ends in `or false`, which is correct. Left as it is.

**BBS-02, the console log** (`sv_20_hits.lua:105`)
- A refused settings packet logs one line per player every 10 s.
- The next line says how many were refused in between.
- Admins and single player are unchanged.

**BR-02, the Lua boundary** (`lua_bindings.cpp`, `standalone_module.cpp`)
- `CopyBoundedString` (`:49`) reads a string's length from `GetString` and copies nothing over the
  limit or with a NUL inside:
  - a hash, 18 bytes (`0x` and 16 digits): `ParseHashes`, `:329`;
  - a texture path, 2,048;
  - an operation, op, channel or enum name, 64;
  - any other request string, 4,096.
- One 16 MiB string in all 128 hash entries is refused at the first entry. It used to cost 2 GiB of
  copies.
- `Guarded` (`:986`) wraps every exported function: a C++ exception becomes
  `false, "native_exception: <what>"`, and the bridge lock is released on the way out. It catches only
  `std::exception`, so a Lua error raised during a call still propagates as before.
- `RegisterLua` registers an unavailable provider when constructing the bridge throws. The module's
  entry point catches discovery failures.

**BR-03, DDS validation** (`texture_ingest.cpp:193-344`)
- `ValidateDdsLayout` checks the header against the file:
  - a known storage: the DXGI formats with a fixed size, the legacy FourCC codes (DXT1-5, ATI1/2,
    BC4/5, the packed 4:2:2 codes, the D3DFORMAT float codes) and whole-byte RGB, luminance, alpha,
    bump and YUV pixels; planar, video and unknown formats are refused;
  - a mip count, `max(1, mipMapCount)`, of at most 16 and at most `floor(log2(max(w, h, d))) + 1`;
  - a DX10 header present, with an array size from 1 to 2,048 and a valid resource dimension;
  - a legacy cube map with at least one face and no volume flag;
  - a volume depth within the dimension limit;
  - every byte that all levels, faces and layers need, summed in 64 bits with overflow checks, present
    after the headers.
- `ValidateDdsFile`, the check on a copy this writer made earlier, runs the same layout check. It reads
  the first 148 bytes and takes the data size from the file's size, so a cached copy cut down to its
  header is no longer reused.
- It still does not read a 130 MB copy again on every preview; that was the point of the digest cache.
- The test fixture `WriteMinimalDds` now writes a real 32-bit BGRA pixel format. The old one had none,
  which the new check refuses.

## Tests

| Test | Result |
|---|---|
| `tools\ci\build_modules.ps1 -Only advmat` (local premake 5.0.0-beta2 and the fixes clone's `garrysmod_common` at `a854f237`, default `-Out`/`-Work`, `RUNNER_TEMP` = the main checkout's `out\t`) | Built `gmcl_advmat_rtx_bridge_win64.dll`, **324,096 bytes, SHA-256 `4e6361d1db911e420982823c9f30a6506837f3cbf948582f3c6aa80261c32f7f`** (was 316,416, `aeb5de42...`). CTest 2/2: `advmat_rtx_writer_tests` (with the new DDS layout block) and the new `advmat_rtx_lua_tests` passed. `/W4 /WX` |
| `python -m unittest discover -s tests -p test_editors.py` (in `tools`) | 8 passed. The seven LuaJIT scenarios also ran against the parts before this change (`out\inputs`): each fails at the property its fix gives (2 encodes for one state, 6 profile encodes for 3, `table.Copy` error from the dupe callback, 100 actions through, an unbounded cache, 100 log lines, `GetBool` true for 0) |
| `test_ci_tools`, `test_inputs`, `test_addon_workflow`, `test_addon_i18n` | Passed |
| `tools\test.ps1 -SkipNative` | **All checks passed**: conventions OK, 586 tools tests (7 skipped), 28 gmapack, 25 Steam |
| `python -I tools\inputs.py verify` | 11 parts checked, 0 problems |

`tools\test.ps1` ran with `-SkipNative`. No C++ that this repository's own build compiles changed. The
bridge's C++ is a part's source copy, built and tested by `build_modules.ps1` above.

## For the integrator

- **Merge:** `r19-editors` touches only its three parts, `tools/tests` (new files) and the
  `advmat_bridge` block of `tools/ci/pins.json`. No conflict is expected with R19-X, which edits
  `fixes`.
- **Imports and pins:** nothing more to import. The parts hold the new Lua, the source copy and the
  locally built bridge.
  - The package workflow builds its own bridge from `packages/advanced-material-editor/source/rtx_bridge`.
    Its hash will be the run's own, as with every native binary since R16.
  - The modules cache key changes with the source, so the workflow rebuilds the modules job.
- **Rebuilding the bridge from a worktree:**
  - The writer test needs `%TEMP%` of at most about 75 characters (RESEARCH.md, R16). This worktree's
    `out\t` is 76 characters, and the test fails there at `writer_tests.cpp:1152`.
  - Set `RUNNER_TEMP` to a short folder, as I did. `out\worktrees\r19\out\t` is 68 characters, so it
    is fine.
- **Strings:** no new catalog key, so there is nothing for Codex to translate. New English text that is
  not in any catalog:
  - the server console line "`<player>` tried to change `<setting>` without admin access (N other
    refused requests since the last line)";
  - the bridge's failure reasons, which the editor shows verbatim like its existing ones:
    - "every request.hashes entry must be a hexadecimal string of at most 18 characters";
    - "`<field>` must be a string of at most N bytes without NUL";
    - "native_exception: ...";
    - "DDS file is shorter than its DX10 header", "DDS array size is invalid", "DDS volume texture
      layout is invalid", "DDS resource dimension is invalid", "DDS cube map layout is invalid", "DDS
      pixel format is not supported", "DDS mip count N is invalid for a W x H texture", "DDS file is
      shorter than the data its header describes".
- **In-game checks** (PoC, Lua errors 0 throughout):
  1. *Material editor, Source rules:*
     - Save a model rule and a material rule.
     - Run `advmat_resync` five times quickly. The rules stay applied and the console shows "Synced N
       persistent rule(s)".
     - Remove an entity that has an entity-scope rule, then `advmat_resync`.
  2. *Material editor, RTX:*
     - Save an RTX profile with an enhancement's BC7 DDS map (any mod under `rtx-remix/mods`) and one
       with a PNG map. Both apply, and `rtx-remix/mods/!advanced_material_editor/textures/...` holds
       the copies.
     - `lua_run_cl PrintTable(AdvMatRTXBridge.Capabilities())` shows `ddsImport` and
       `legacyMaterialOverrides` true.
     - Set `advmat_backend vanilla` then `rtx` within 2 s. The profiles come back within about 2 s.
  3. *Bodygroup tool:*
     - Select a prop. Force-hide a bodygroup, hide a region, set a cut, and cycle 10+ bodygroup and
       skin combinations.
     - Press R and edit your own player model.
     - Copy the prop with the duplicator and paste it. The hidden state comes back.
  4. *Destruction:*
     - In its settings, untick "damage enabled" and "apply materials". They stay unticked when the
       panel reopens, and a shot ragdoll shows no damage.
     - Tick them again and damage returns.
     - With `bbs_mesh_disk_cache 0`, no new files appear under `data/bbs_mesh_cache`.

## Proposed lines

**CHANGELOG** (`## [Unreleased]`)
- Fixed: Advanced Material Editor: the full-database sync snapshot is encoded once per state of the
  store, and repeated requests coalesce, so the server's sync queue holds two snapshots at most
  (R19, ADV-01).
- Fixed: Advanced Material Editor RTX profiles: no HELLO resets the 2 s snapshot limit any more, and a
  HELLO inside it is answered once when it ends. Profile messages are encoded once per revision for
  all players (R19, ADV-02).
- Fixed: the material editor's RTX bridge checks every request string's length before copying it, and
  returns `false` and a reason instead of letting a C++ exception reach Lua (BR-02). It accepts a DDS,
  or reuses its own cached copy, only when the header's format, mip count (16 at most), faces, layers
  and data fit the file (BR-03). New `gmcl_advmat_rtx_bridge_win64.dll`.
- Fixed: Advanced Bodygroup Tool:
  - crafted dupes paste without Lua errors (ABT-01);
  - the client's region analyses are a bounded, least-recently-used cache (ABT-02);
  - tool actions have a per-player budget (ABT-03);
  - another player's model is editable only by that player or an admin (ABT-04).
- Fixed: Procedural Bodygroup Destruction: settings whose default is on (damage enabled, apply
  materials, no-cull, UV seams, local bounds, RTX direct override, hole damage scaling, the disk cache)
  can be turned off again (BBS-01). Refused settings packets log one line per player every 10 s
  (BBS-02).
- Fixed: Advanced Material Editor: the RTX source tab shows the live-preview and show-all settings as
  they are.

**RESEARCH**
- The material-editor bridge's writer test fails at `writer_tests.cpp:1152` (`aperture152Apply`) when
  `%TEMP%` is 76 characters long (`out\worktrees\r19-editors\out\t`). It passes with 50 (`RUNNER_TEMP`
  = the main checkout's `out\t`), which confirms R16's limit of about 75. `build_modules.ps1` uses
  `RUNNER_TEMP` when it is set.
- The material editor's client keeps a list of announced snapshot revisions (`cl_40_store.lua:597-616`).
  When a snapshot installs, it retires every older one and one equal. So the server may give a waiting
  player a newer snapshot than the one announced, without a second `AdvMat.SyncBegin`. That is what
  ADV-01's coalescing relies on.
- GMod's duplicator calls entity modifiers without `pcall`: an error in one stops the rest of the
  paste. The bodygroup tool's old `GetState` raised one by `table.Copy`-ing a stored field that was a
  string.

**TESTING** (beside test_addon_workflow and test_motion_tab)
- [test_editors.py](../../tools/tests/test_editors.py.md): under LuaJIT it loads the shipped material
  editor, bodygroup tool and destruction Lua with game stand-ins. It checks:
  - the snapshot encoding and coalescing;
  - the HELLO limit;
  - crafted dupes;
  - the action budget and player targets;
  - the region cache;
  - the refusal log;
  - the GetBool helpers.

  It also checks statically that no `:GetBool() or <fallback>` remains.

## Open issues

- **ABT-04 changes behaviour on multiplayer servers:** non-admins can no longer edit other players'
  bodygroups, as they could in vanilla Sandbox. This is the rule the brief asks for.
- **`AdvMat.Net.SendChunked`** remains public and does not coalesce, for third-party callers. Nothing
  in the package uses it.
- **The DDS check is stricter.** A map in a format the bridge cannot size (planar or video DXGI
  formats, unknown FourCC codes, pixel formats without RGB, luminance, alpha, bump or YUV flags) is now
  refused with `invalid_dds`. So is a cached copy of one. RTX Remix's own loader has no use for those.
- **The `files.json` origins** of the changed folders and files now name this worktree's `out\r19e`
  working copies, which are machine-local, as earlier imports did.
- **No in-game test.** The checks above are for the integrator's PoC sessions.
