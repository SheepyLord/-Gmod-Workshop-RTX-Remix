# Pre-release review: verified findings (2026-11-05)

**How it was done**
- Codex (gpt-6-sol, max effort, priority tier) reviewed the release in eleven parts and reported 67 findings.
- An independent Claude verifier then checked each part against the code, read-only, and tried to refute every finding.
- I re-read the high findings myself.

**Result**
- 11 confirmed.
- 49 partly right: the code fact holds, but the trigger or impact is narrower than claimed.
- 7 false positives.
- 11 problems Codex missed: 10 found by the verifiers, 1 by me.
- Most of Codex's "high" ratings came down after checking. Four problems remain high. Two of them are new; one of those is mine.

Paths are relative to the repository unless they start with `runtime:`, which means
`out\worktrees\r17\out\runtime-src\src\`.

## High: fix before the release

### H1. A texture file in a Remix mod can corrupt the game's memory (new; verifier, confirmed by me)

**What happens**
- The runtime's DDS reader takes the mip count from the file without checking it (`runtime:dxvk/rtx_render/rtx_asset_data_manager.cpp:161`).
- It then writes one size per mip into a fixed array of 16 entries (`:176-186`, array at `:234`).
- The only guard is an `assert`, which is compiled out in the release build.

**With a file that claims 17 or more mips**
- It overwrites the total size and then the open file handle, which it later passes to `fclose` (`:192`, `:214-219`).
- At 19 or more it overwrites the object's virtual-table pointer, and beyond that, the heap.

**The fallback path is also unsafe**
- When the reader rejects a short file, the GLI fallback copies as many bytes as the header claims.
- It copies them from a buffer only as large as the file (`include/gli/core/load_dds.inl:319-321`; `GLI_ASSERT` is empty in release).

**Who it hits:** every DDS that a loaded mod references is read this way at mod load. That includes content-only packages from Workshop items (ADR 0027).

**The fix:** a runtime patch that caps the mip count at 16 and at what the dimensions allow, and checks sizes before the GLI copy. Small; it needs a d3d9 rebuild. This is upstream NVIDIA code; it matters here because the loader deploys mods from the Workshop automatically.

### H2. A multiplayer server can make the loader install content the player never subscribed to (new; mine)

**What the loader does**
- Content-only discovery takes every folder in `steamapps\workshop\content\4000` whose single `.gma` lists `native/manifest.json` (`loader/core/src/discovery.cpp:251-261`).
- It never reads Steam's `subscribedby` field; only test fixtures contain it.

**How an unsubscribed item gets there**
- GMod's client Lua `steamworks.DownloadUGC(id, cb)` installs an item into that folder without a subscription.
- This was measured in M6 (`docs/RESEARCH.md:2378-2384`, ADR 0015 step 3).
- Any server can run client Lua on its players, and many servers use `DownloadUGC` to stream content.
- This machine has 40 installed items with no `subscribedby`.

**The result, with the default config** (`subscribed_content` is true)
- At the player's next start, the loader deploys that item's Lua add-on into `garrysmod/addons`. It is permanent and runs in single-player and hosted games.
- It also deploys the item's Remix mod into `rtx-remix/mods`, which is loaded in every RTX session.
- Together with H1, this is a path from joining a server to memory corruption at every later start.
- ADR 0027 assumed "subscribed"; the code checks only "installed".

**The fix:** accept a content-only candidate only when `WorkshopItemDetails` has a non-zero `subscribedby`, and remove an already deployed one that lacks it, as for an unsubscribe. Small; it ships in `winmm.dll`, so a new loader version.

### H3. Any server can make the RTX fixes write files outside GMod, or connect to a network share (Codex RTX-fixes F-02, confirmed)

**What happens**
- `MaterialPipeline.ToPBR.SetOutputDirectory` stores any string (`packages/fixes/licenses/oversized-skinning/autopbr/source/material_pipeline/to_pbr/to_pbr.cpp:338-344`, binding `:5642-5651`).
- `EnsureOutputDirectory` creates every folder level and then writes `mod.usda`, `materials.usda`, DDS and cache files there (`:350-378`; republished every 3 s).
- The module registers into the real `_G`, so any server's client Lua can call it.

**The risk**
- File names are fixed, and no route to code execution was found.
- A network path (`\\host\share`) makes Windows connect to a host the server picks and offer the player's Windows login (NTLM), unless outbound SMB is blocked.

**Related (verifier's miss):** `SetEnabled(true)` overrides the player's `rtx_topbr_enabled 0`, and `ProcessSingleMaterial` queues conversions of up to 1 GiB per session (`to_pbr.cpp:5177-5191`, `4507-4513`).

**The fix:** accept only a folder under the game's own output root, refuse absolute, UNC and `..` paths, and respect the player's cvar. Small. It is in the fixes' native module (garrys-mod-rtx-remixed, GPL): a module rebuild, then a pins.json change.

### H4. The dance tool can freeze and hide another player (Codex motion-Lua L-01, confirmed)

**What happens**
- `SelectTargetForPlayer` accepts any player as the target (`packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua:1138-1166`, `is_usable_actor` at `:250-262`).
- An unmodified client reaches it through the tool's Shift+right-click.
- Play then pulls that player out of vehicles, hides them, and locks their movement every tick until they stop it or die (`:3255-3270`).
- The debug window can also write lasting poses onto them.

**Who it hits:** any game where the add-on runs on the server, for example a game an RTX player hosts.

**The fix:** allow only the player themself, or an admin. Small; Lua.

## Medium: should fix

| # | Problem | Evidence | Fix |
|---|---|---|---|
| M1 | After a release upload from GitHub (`publish_workshop.py --from-ci`), the next commit, merge or push on `main` uploads a local development build over the release: the CI record has no input fingerprint (Codex tooling F-02, confirmed) | `tools/publish_workshop.py:372-375` vs `:506-510` | record the fingerprint with the CI upload; small |
| M2 | Seven bodygroup-damage settings checkboxes cannot be turned off: `convar:GetBool() or fallback` returns true for 0 when the fallback is true (BBS-01, confirmed) | `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_40_damage.lua:129-132` | one line |
| M3 | Material editor: alternating the HELLO protocol version resets the 2 s limit, so a client can make the server re-encode every profile without limit (ADV-02, confirmed) | `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sv_31_rtx_store.lua:686-706`, `:1115` | keep the limit across HELLOs; small |
| M4 | Bodygroup tool: the client's region cache grows with every model, bodygroup and skin combination until the map changes (ABT-02, confirmed) | `packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/advanced_bodygroup_tool/cl_uv_hide.lua:414-449` | cap it; small |
| M5 | A take-over's original goes to `backup/originals/<path>` with no transaction number; after an uninstall that leaves one there ("put it back by hand"), every later deployment that takes over that path fails (verifier's miss, checked by me; rare trigger, lasting failure) | `loader/core/src/deploy.cpp:786-795`, `:1494-1497`; moves never replace, `fs.cpp:101` | small; loader |
| M6 | Material-editor bridge accepts DDS files on a header-only check, and cached copies on their first 128 bytes; this leads into H1 (BR-03) | `packages/advanced-material-editor/source/rtx_bridge/src/texture_ingest.cpp:66-99` | check sizes and mips; small |
| M7 | Model Hotloader: a downloaded PMX model's texture paths may use `..`, pulling an image from elsewhere on the drive into the cache; exposed only if the player shares the result (MH-01) | `packages/model-hotloader/source/mmdhl/native/dependency_scope.cpp:205`, `assets.cpp:334` | refuse paths outside the model folder; small |
| M8 | Motion builds: the build cache is limited to 16 entries by count, not size, and each can be tens of MB; no per-player cap (L-09; medium on public servers) | `sv_commands.lua:47-53`, `:4811-4829` | size budget; medium |
| M9 | Changing map during a dance leaves the RPE and skirt add-ons' cvars at 0; the next dance saves 0 as the "original", so those add-ons stay off for the session (verifier's miss; single-player too) | `sv_commands.lua:13-14`, `:410-411`, no `ShutDown` hook | restore on shutdown; small |

## Low: real, but narrow

**Loader**
- A stale `status.json` makes every later off-switch (vanilla) start install the RTX guard. Proxy F-02, confirmed: `_nativeloader_guard.lua:14-22`.
- The player README names `-nonativeloader` as the way to play without RTX, instead of `remix.enabled:false`. Proxy F-01: `dist/README-native-loader.txt:71-72`.
- Uninstall and rollback edge cases: NLCORE-01 to 05.
- A wrap-around in the space check needs a crafted size. NLCORE-05.
- `load_first` is tried only once, and the forbidden flag combination has no effect. F-04, F-05.
- `LoadLibraryW` runs inside `DllMain`, but no lock cycle can form. F-08.
- The observer's export table and the silent skips in `nlctl scan`: F-06, F-07.

**Motion and Hotloader Lua**
- "Stop all" stops every player's dances. L-03, confirmed.
- Dances keep looping after their owner disconnects. L-05, confirmed.
- The collision-mesh request is throttled only on the client. L-08, confirmed.
- Force Reset, and every death, unfreezes a player whom an admin tool had frozen. Verifier's miss: `sv_commands.lua:1385-1399`, `:236-238`.
- L-02, L-04, L-06 and L-07 are narrower than reported: prop protection still decides.

**RTX fixes**
- Flashlight receivers have no cooldown, and a quick double toggle orphans a light. F-03, F-04.
- The flashlight override returns true for every player, so dead players and spectators get a flashlight. Verifier's miss: `sv_remix_flashlight.lua:155-171`.
- The water polygon over-read stays inside the same heap block. F-01.

**Runtime**
- An option string is read after its lock is released, only while that option is edited in a developer menu. Igsn F-01; predates our patches.
- A shared cached texture skips the preload. F-03, upstream.
- The middle deck's patch probes lose nothing visible at the default 14 km. F-04.
- The middle deck's moon shadows use the wrong patch coverage: partly cloudy, at night, with a low moon. F-05, confirmed.
- Linked config files are rewritten in place. R-01.
- The scene-wide multiplier is by design. R-02.
- Float options accept NaN; fix it in the parser. R-03.

**Glass**
- A client can learn shot positions it cannot see through its debris interest. F-01.
- The late-join pane snapshot is unpaced. F-02.
- On a crafted map:
  - lumps are inflated before the size cap is checked (GL-01);
  - static props are capped only per game-lump entry (verifier's miss, `bsp.cpp:213`);
  - the leaf walk has no work budget, which freezes quit and map change (verifier's miss, `bsp.cpp:96-98`).

**Editors**
- ADV-01, ABT-01, ABT-03 and ABT-04: these match vanilla behaviour, or are capped.
- BBS-02: denied settings packets each print one console line.
- BR-02: hash copies run before the length check; the result is a catchable error.

**Tooling and CI**
- `ref_name` is passed into bash in the release job.
- `actions: write` is granted to every job.
- `--from-ci` treats "no run within 5 min" as success.
- `pillow` is unpinned in `build.yml`.
- The Hotloader bootstrap's tarballs have no digest check, though they are pinned by full SHA.
- The GMA LZMA spool has no size cap.
- `inputs.py` accepts trailing dots.

**Companion:** the eye-white cache eviction and the VRAM log rotation act only on the companion's own documented files (F-03, F-04): no change needed.

## False positives (7)

- **MH-03:** the map is guarded by a lock.
- **RTX fixes F-05:** a server-only message, bounded by the map.
- **RTX fixes F-06:** the retired glass add-on is not shipped.
- **Proxy F-03:** the marker works as ADR 0056 intends.
- **BR-01:** MSVC's mutex throws instead of deadlocking, and LuaJIT catches the error.
- **Runtime F-02:** a pinned preload reloads its full mip chain.
- **Tooling F-06:** the documented opt-in.

## Where the fixes land

| Where | Fixes | What it takes to ship |
|---|---|---|
| Runtime fork | H1, low runtime items | new patch, d3d9 rebuild, `inputs.py import` |
| Loader (`winmm.dll`) | H2, M5, stale status guard | new loader version; it reaches players only with the release zip |
| RTX fixes native module | H3 and its miss | garrys-mod-rtx-remixed commit, module rebuild, pins.json, `packages/fixes` import |
| Material-editor bridge native | M6 | bridge rebuild |
| Lua in `packages/` | H4, M2, M3, M4, M8, M9, motion and flashlight lows | edit, then re-index |
| Tooling | M1, CI lows | `tools/publish_workshop.py`, workflows |

Working notes, with every verdict: `out/review-final/verdicts.md`. The Codex reports are in `out/review-final/task-*.md`.
