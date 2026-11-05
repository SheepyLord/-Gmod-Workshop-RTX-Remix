# R19-H report: the Model Hotloader and the motion importer

Part R19-H of [R19](R19-plan.md): the pre-release review's findings in the Model Hotloader (its Lua, its
native source copy and its bootstrap) and in the Character Motion Importer. Branch `r19-hotloader`, made from
`r19-int`. Inputs: [R19-review.md](R19-review.md) (H4, M7, M8, M9), the Codex reports `task-mw40hf6a`
(native, MH), `task-mw40hmqv` (Lua, L) and F-03 of `task-mw40i2w9`, and `verdicts.md` with its two
confident misses.

Who did what: Claude (this part), alone. No game was started.

## Findings

| ID | Verdict | Outcome |
|---|---|---|
| **H4 / L-01** | confirmed, high | **Fixed** |
| **M8 / L-09** | partly, medium | **Fixed** |
| **M9** (miss) | confident miss | **Fixed** |
| Force Reset (miss) | confident miss | **Fixed** |
| L-02 | partly, low | **Fixed** |
| L-03 | confirmed, low | **Fixed** |
| L-04 | partly, low | **Fixed** with M9 |
| L-05 | confirmed, low | **Fixed** |
| L-06 | partly, low | **Fixed** |
| L-07 | partly, low | **Fixed** |
| L-08 | confirmed, low | **Fixed** |
| **M7 / MH-01** | partly, medium | **Fixed** |
| MH-02 | partly, low | **Fixed**, with the limit a shared Lua state sets (below) |
| MH-03 | false positive | No change |
| MH-04 | partly, low | **Fixed** |
| MH-05 | partly, low | **Fixed** |
| MH-06 | partly, low | **Fixed** |
| F-03 | partly, low | **Fixed** (git, as the plan prefers) |

### The motion importer (`packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua`)

The file's main chunk is at 196 of Lua's 200 locals, so every new helper lives in one new table, `guard`
(exposed as `MMDVMDNPC.Guard`, so a server owner or a test can lower its limits). A test loads the file to
keep that true.

- **H4 / L-01.** `guard.may_target(ply, ent)`: a player target only when it is the requester or the requester
  is an admin (single player and a listen host count as admins; NPCs stay with the tool's `CanTool`).
  `SelectTargetForPlayer` and `OpenDebugForPlayer` refuse another player ("only admins may select or dance
  another player; press R to select yourself"), and the check runs again where it matters, so a selection
  made while an admin, or a forged one, does not outlive that: `start_playback_on_entity`,
  `start_build_for_entity`, `mmdvmd_debug_apply`, `mmdvmd_debug_request`. The menu's `mmdvmd_select_target`
  message now accepts only the sender (its one sender, `cl_menu.lua` `RequestSelectSelf`, sends the local
  player); everything else is chosen in the world with the tool gun.
- **Force Reset (miss).** `freeze_player_target` records the freezes it makes (`MMDVMDNPC.FrozenByAddon`) and
  only undoes those; it never froze a player in the current code, so Force Reset and every death no longer
  unfreeze an admin-frozen player. `set_self_player_hidden(ply, false)` with no record of hiding them does
  nothing (it used to call `SetNoDraw(false)`).
- **L-03.** "Stop all" stops the requester's own NPC dances (`state.ply` or `state.initiator`); an admin's
  stops everyone's.
- **L-05.** `PlayerDisconnected` stops the leaver's NPC dances (their music and cvar suppression go with them).
- **L-06.** `mmdvmd_debug_request`: one frame per player every 0.1 s; a request inside the interval is
  answered when it ends, with the latest frame asked for (a scrubbed slider still lands on its frame).
- **M9 and L-04.** The originals of the RPE and skirt cvars are also kept in `data/mmd_vmd_npc/settings/
  cvar_restore.json` while a cvar is off. A `ShutDown` hook puts them back (a cvar made by Lua at once with
  `SetString`, an engine one with `RunConsoleCommand`); `InitPostEntity` at the next start restores what an
  earlier session left off (a crash, or a command that never ran) and removes the record. A "0" left behind
  is never taken for the original: a dance that begins while a record exists takes the recorded one. The
  release puts the original back only while the cvar still holds our "0" (or our "0" has not applied yet,
  the same-frame build-to-play hand-over), so a value an admin set during the dance stays. The record is
  read back only for the three known cvar names and numeric values: it can never name what to run.
- **M8 / L-09.** `BuiltCache` keeps, besides the 16-entry limit, a byte budget by the size of each entry's
  JSON (`guard.BuiltCacheMaxBytes`, 128 MiB; decoded tables take about twice that); playing entries are never
  dropped. Per player (by SteamID, admins exempt): at most 16 builds waiting behind a running one and 32 new
  built files while a map runs. Per build: past 128 MiB of built JSON it stops (a 6,305-frame, 58-bone dance,
  the packaged one, is about 22 MB). The finished build's JSON chunks are released before the cache keeps it.

### The Model Hotloader's Lua (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/`)

- **L-02** (`server.lua`, `sharing.lua`). `remove` and `replace` in `mmdhl_action` are checked as the
  `remover` property too, and need `mmdhl.OwnsEntity`: prop protection's owner (CPPI) or else the creator, or
  an admin, as the static props' `owns()` decides; a character nobody owns stays with `CanProperty`. Other
  edits are unchanged.
- **L-07** (`props/server.lua`). `mayUseTarget` refuses a target whose nearest point is farther than 4096
  units from the player's eyes (the tool's aim range for placing; `P.AttachReach`), with the existing
  `props.attach.aim_target` phrase.
- **L-08** (`carrier.lua`). The `mmdhl_collision_mesh` receiver keeps the client's pace: one mesh per entity
  every 1.5 s (the client asks every 2 s) and four a second per player.
- **MH-05, the Lua side** (`scene_sharing.lua`). `PublishRemoteScene` now also returns the shapes the module no
  longer holds; the client forgets them and asks again when a frame names them. A shape the module refuses
  waits ten seconds before it is asked for again.

### The Hotloader's natives (`packages/model-hotloader/source/mmdhl/`)

The changes are listed in `source/r19-changes.patch` and `source/Source.md` ("Changes made here (R19)").

- **M7 / MH-01** (`native/dependency_scope.*`, `assets.cpp`, `props/import.cpp`, `props/material_overrides.cpp`,
  `props/texture_resolver.hpp`). Every model reads its textures, buffers and sidecar textures only inside its
  import root: its own folder, the `tex` and `textures` folders one and two levels up (which the static prop
  resolver already searched), and, for a model in a Steam Workshop item folder
  (`...\workshop\content\<app>\<item>`), that whole item. The file the player chose in the picker is in the
  model's folder, so that folder is "the folder the player chose". `..` inside the root still works, as in
  2.2. `Reach::Local` (PMX and PMD, static props) still follows a link the player made inside the root (a
  downloaded model brings no junction); `Reach::Confined` (FBX, glTF, DAE) still also checks where the file
  really is. A refused texture is left out with a new warning, "Texture outside the model's folder was not
  read: <path>" (static props: "Material override texture outside the model's folder was not used: <name>",
  "Model dependency outside the model's folder"); a static prop's texture outside its folder is still looked
  up by its file name in its folders first.
- **MH-02** (`file_access.*`, `module.cpp`). A remembered folder answers only the label and the script it was
  given to. The script is what the Lua VM recorded: `luaCaller` walks the stack through lua_shared's own
  `lua_getstack`/`lua_getinfo` (which Lua cannot replace) to the first Lua function outside
  `mmdhl/file_access.lua`; what the caller passes as `script` is ignored for this, and the dialog now shows
  the script the module found. An addon that only reuses another addon's label is asked again. The limit,
  written where the grant is declared: Lua in the same state can still name a chunk after another addon's
  file (`CompileString`), so this keeps addons apart rather than being a boundary. Grants saved before R19
  carry no script; they answer only a caller the module could not identify either, so the player is asked
  once more (an "always" then replaces them).
- **MH-04** (`runtime.hpp` `LoadBudget`, `assets.cpp`). Before `loadAsset` reads `model.bin`, its size times
  eight (the bytes, nanoem's objects, the model's own copies) is checked against half the physical memory free
  now, less what loads already running hold; each texture it verifies or decodes is checked the same way. A
  load that does not fit fails before it allocates, with "This model needs about N MB of memory to load, more
  than this computer has free for loading now (M MB); close other programs or remove other models first".
  Where the free memory cannot be read, nothing is refused.
- **MH-05** (`scene_share.*`, `module.cpp`). A remote collision shape goes when no frame has named it for 60 s
  (its entity went away or out of reach); past 256 MiB or 4,096 shapes the one unused the longest goes first,
  and a shape larger than the budget is refused. `PublishRemoteScene` returns the dropped shapes and those a
  frame named but that were gone (two values; the old Lua ignored the second).
- **MH-06** (`module.cpp`, `assets.cpp`). The module's close sets a flag the loads (`RequestAsset`) and asset
  checks (`StartAssetCheck`) carry; `loadAsset` stops at its next step (before and after reading the model,
  after parsing, before each texture, before the materials and the fit). A map change waits only for the step
  each is in. (`std::async` starts every task at once, so there was no queue to cancel; the steps are the
  queued work.)
- **MH-03.** A false positive (the `verified` map is guarded by a lock): no change.
- **F-03** (`scripts/bootstrap.py`). Each locked commit is fetched with git (`git fetch --depth 1 <repo>
  <sha>` into a scratch bare repository, checked to be exactly the locked commit, then `git archive`), so git
  checks every object against its hash; the lock must name full 40-digit commits and plain `owner/name`
  repositories. `git archive` runs with `core.autocrlf=false` and `core.eol=lf`, or Git for Windows would
  write CRLF. All eleven locked repositories fetched this way in 21 s on this machine, file for file and byte
  for byte the trees of R16's archive-fetched vendor folder (only the files bootstrap and
  `patch-bullet-threading.py` patch afterwards differ). CoACD's wheel keeps its SHA-256 check.

## Build and import

- Natives: `tools\ci\build_hotloader.ps1 -Source <worktree>\out\r19-h\stage\mmdhl -Vendor
  <main checkout>\out\worktrees\r16\out\ci\work-hl\src\vendor -Work <worktree>\out\r19-h\hl -Out
  <worktree>\out\r19-h\built` (absolute paths, default `-Jobs`), with R16's already bootstrapped vendor folder
  from the main checkout's `out\` (nothing fetched for the build). The worker reports release 2.3.1, build
  `1e4cb10d1a76-20261105T224511Z` (this branch's base commit and the configure time); `native_manifest.py`
  rewrote only the 2.3.1 entry of `native_policy.lua` (its build and the four sizes and hashes), and
  `mmdhl-native-release.json` likewise. The script needs absolute `-Work`, `-Out` and `-Source` paths: with
  relative ones it builds, then cannot find the worker it built (it runs it after `Push-Location`); noted for
  R19-T below.
- Imported with `tools\inputs.py import --file`, as packages/README.md "Updating a part" shows (script:
  `out\r19-h\import.ps1` in this worktree, git-ignored):
  - `character-motion-importer`: `sv_commands.lua`;
  - `model-hotloader`: `server.lua`, `sharing.lua`, `props/server.lua`, `carrier.lua`, `scene_sharing.lua`; the
    eighteen changed source files, `source/Source.md` and the new `source/r19-changes.patch`; the four natives,
    `bin/mmdhl-native-release.json` and `native_policy.lua` from the build.
- `python -I tools\inputs.py verify`: 11 parts checked, 0 problems (also with `--deep`). Against `r19-int`,
  exactly the intended files changed: 31 entries of `model-hotloader` (the five Lua files, the policy, the four
  natives and the release record, `Source.md`, the eighteen source files, the new patch) and `sv_commands.lua`
  in `character-motion-importer`; `lib_coacd.dll` and everything else untouched.
- `tools/ci/pins.json` is unchanged (the release stays 2.3.1; ADR 0107 rewrites its policy entry with every
  build). `cache_key.py hotloader` changes with the source and the policy, so the package workflow rebuilds
  the natives.

**The natives' new SHA-256:**

| File | Bytes | SHA-256 (was) |
|---|---|---|
| `bin/gmcl_mmdhl_win64.dll` | 2,847,232 | `0b94dba5379682a84f708ca8472b96facb789b88ba2503c0acefb67c8357113b` (`c1a68138...`) |
| `bin/gmsv_mmdhl_win64.dll` | 1,863,680 | `4f965440306495d9a89fc0be94e8fb1196ca4ad839f30cabb085a928d581faf6` (`2b1f92cf...`) |
| `bin/mmdhl_runtime_win64.dll` | 10,754,560 | `1b8978d1af3a9f7d31dc15a26eee1aecca715cea62782ab96f9c511fe4ff1aa2` (`351a7068...`) |
| `bin/mmdhl_worker.exe` | 4,149,760 | `c94ed2eccb772182da2c765cba8cb5e446c0cebf93ca95d2034468220f971631` (`808a5c10...`) |
| `bin/mmdhl-native-release.json` | 1,085 | `82f7661d82ca0edf7149b6b71e1ddb208b489f2c6b4f1c552a8713e05e5fefcb` |
| `mmd_hotloader/lua/mmdhl/native_policy.lua` | 26,584 | `292dd558781725ec879f10ac0b7cc3e5851e2a6d437cbf37b9c3adf5ded85733` |

The release's natives will differ (built on GitHub, build `source-<time>`); the policy and the release record
are regenerated with them in the same run.

## Tests

- **`tools\test.ps1 -SkipNative`** (no C++ of this repository changed; the add-on's C++ is not part of it):
  all checks passed, 599 Python tests (7 skipped), the conventions check OK. Run before and after the natives'
  import.
- **New Python tests** (each also run against the files as they were, where every fix's scenario fails):
  - [test_motion_server.py](../../tools/tests/test_motion_server.py.md), 13 tests: H4/L-01, the forged or stale
    selection, Force Reset and death, L-03, L-05, L-06, M9 after a map change, after a crash, with a Lua cvar,
    L-04, M8's byte budget, the per-player and per-build limits, and the 200-local limit.
  - [test_hotloader_server.py](../../tools/tests/test_hotloader_server.py.md), 4 tests: L-02, L-07, L-08 and the
    client side of MH-05.
  - [test_hotloader_bootstrap.py](../../tools/tests/test_hotloader_bootstrap.py.md), 4 tests: F-03 against a local
    repository (a non-tip commit fetched by hash, stored bytes with `core.autocrlf=true` in force, export-ignore,
    refusals). A copy of the script without the line-ending override fails it.
  - The existing tests around these files pass: `test_mmd_lazy_load`, `test_mmd_reimport(_qa)`,
    `test_motion_tab`, `test_addon_i18n`, `test_hotloader_depth`, `test_addon_workflow`, `test_ci_tools`.
- **The add-on's C++ tests** (built from the final source in a separate tree, `out\r19-h\dev`, with the same
  vendor folder; TEMP in the worktree's `out\`):
  - `import_errors`: passed, 121 checks, among them MH-01's PMX cases (a texture inside the root read, `..`
    inside it, the player's junction followed; outside it refused with the new warning; a Workshop item's own
    files read, one beside the item refused) and MH-04/MH-06 (a model past the load budget refused before
    reading, two loads counted together, the budget released after a load, a load stopped by the closing flag).
  - `file_access`: passed, with the MH-02 checks (a grant keyed on the script the module found; the same label
    from another script and from an unidentified one asked again; the dialog names the found script). Its check
    that the grants list shows the user's folder as `~` now expects that only when the test's folder lies in
    the profile, as the same file's earlier check already did: with TEMP in `out\` it otherwise failed before
    R19's changes.
  - `static_props` (the texture resolver's MH-01 cases: a reference outside the folder refused and looked up by
    name, a glTF buffer outside refused, one behind the player's junction read, a sidecar texture outside left
    out with the new warning), `native_runtime`, `workshop_packages`, `character_import`,
    `vrm_import_and_springs`: passed.
  - `animated_carriers_and_sharing`: the new remote-shape test (MH-05: shapes kept while named, dropped after 60 s
    idle and reported, the client told about missing ones, the 4,096-shape limit, clear) runs first and passes;
    the executable then fails at its long-path deletion check, as it does before R19's changes in this
    environment (cache paths past MAX_PATH under a deep TEMP).
  - `character_import_worker` needs `scripts/test-character-import.py`, which the copy leaves out (Source.md).

## For the integrator

1. Merge `r19-hotloader`. It touches only `packages/model-hotloader`, `packages/character-motion-importer`,
   `tools/tests` (new files) and `tools/ci/build_hotloader.ps1.md`.
2. The natives in `packages/` are this machine's build; the release's come from the package workflow (ADR
   0108), which rebuilds them from the imported source and regenerates the policy. Nothing to pin.
3. Translations (see below), then the shared docs lines below.
4. **In-game checks** (PoC, a listen server with a second client, `-multirun`):
   - H4: as a non-admin client, select the host with the motion tool (Shift+right-click on them): refused with
     the new message; the host can still select and dance themself (R, E+R) and an NPC. As the host (admin),
     selecting the client still works.
   - Force Reset: freeze a player with an admin tool (or `ent:Freeze(true)` from the server console), press
     Force Reset as that player and let them die: they stay frozen.
   - M9: with the RPE add-on installed, start a looping dance, `changelevel` mid-dance; after the new map
     `sv_rpe_living_body_enable` is back to 1 and `garrysmod/data/mmd_vmd_npc/settings/cvar_restore.json` is
     gone. Also quit mid-dance and start again: restored at the next map.
   - L-03/L-05: two players each start an NPC dance; the client's Alt+R stops only its own; the client
     disconnects: its dance stops.
   - MH-01: import a PMX whose texture is `..\tex\x.png` (a tex folder one level up): imported with the
     texture. One referencing `..\..\other\x.png`: imported, that texture left out with "Texture outside the
     model's folder was not read".
   - MH-02: the file-access settings list still shows remembered folders; an addon that asked "always" before
     R19 is asked once more, then answered silently.
   - MH-04/MH-06: load a large character and change map while it loads: the map change does not hang.
   - MH-05 and L-08: on a server, a character with secondary collision against server shapes still collides
     after a minute with the colliding objects out of reach and back.
   - The add-on's installation check accepts the new natives (no `native_mismatch`), and an RTX session shows
     no Lua errors from these files.

## Strings for translation

- Character Motion Importer (server messages; the server renders them in English, like its other status
  messages, so they are not in the catalog and the catalog check is unaffected):
  `mmd_vmd_npc.status.other_player_admin_only` "only admins may select or dance another player; press R to
  select yourself", `mmd_vmd_npc.status.build_file_limit_fmt` "build limit reached: you have built %d
  animations on this map; ask an admin to build more", `mmd_vmd_npc.status.build_queue_limit_fmt` "%d builds
  are already waiting; let them finish first", `mmd_vmd_npc.status.build_too_large_fmt` "build stopped: the
  built animation would exceed %d MB". Add them to the catalog only together with a client-side lookup.
- Model Hotloader: no new catalog phrase (L-07 reuses `props.attach.aim_target`). The new native sentences are
  English like every other native warning and error (shown as they are): "Texture outside the model's folder
  was not read: <path>", "Material override texture outside the model's folder was not used: <name>", "Model
  dependency outside the model's folder", "... needs about N MB of memory to load ...", "Model loading
  stopped: the map is changing", "The check stopped: the map is changing", "Remote collision shape exceeds the
  memory budget".

## Proposed lines for the shared docs

**CHANGELOG (Unreleased):**

- Character Motion Importer: a player can no longer select, pose, build on or dance another player (only an
  admin can); Force Reset and death no longer unfreeze or show a player the add-on did not freeze or hide;
  "stop all" stops your own NPC dances; a leaver's dances stop; debug frames are paced (R19, review H4).
- Character Motion Importer: the RPE and skirt add-ons' cvars it turns off come back after a map change, a
  quit or a crash, and an admin's change during a dance is kept (R19, M9).
- Character Motion Importer: built animations kept in memory have a byte budget, and each player's queued
  builds, new built files per map and each build's size are capped (R19, M8).
- Model Hotloader: only a character's owner or an admin removes or replaces it; prop attachments need the
  target within reach; collision meshes are paced on the server (R19, L-02, L-07, L-08).
- Model Hotloader natives: a model reads textures and other files only inside its folder (and the tex and
  textures folders near it, or its Workshop item); remembered file-access folders are keyed on the requesting
  script; loads check free memory first and stop when the map changes; remote collision shapes are evicted
  (R19, M7, MH-02, MH-04 to MH-06).
- Model Hotloader build: its bootstrap fetches the locked dependencies with git instead of unverified archives
  (R19, F-03).

**TESTING:**

- [test_motion_server.py](../../tools/tests/test_motion_server.py.md) runs the Character Motion Importer's
  `sv_commands.lua` under LuaJIT with the game stubbed: who may select, pose, build on and dance whom, Force
  Reset and death, stop all, a leaver's dances, the debug frame pace, the RPE and skirt cvars across map
  changes and crashes, and the build budgets (R19).
- [test_hotloader_server.py](../../tools/tests/test_hotloader_server.py.md) runs Model Hotloader's `server.lua`,
  `props/server.lua`, `scene_sharing.lua` and production slices of `sharing.lua` and `carrier.lua` under LuaJIT:
  remove and replace by the owner only, the attach reach, the collision mesh pace, dropped remote shapes asked
  for again (R19).
- [test_hotloader_bootstrap.py](../../tools/tests/test_hotloader_bootstrap.py.md) checks the Hotloader
  bootstrap's git fetch against a local repository (R19).

**RESEARCH:**

- The Model Hotloader's eleven locked dependencies fetched with `git fetch --depth 1 <repo> <sha>` and `git
  archive` (with `core.autocrlf=false`, `core.eol=lf`) are byte-identical to GitHub's codeload archives of the
  same commits (R16's vendor folder), 21 s for all eleven on this machine; with Git for Windows' default
  `core.autocrlf=true`, `git archive` writes CRLF.
- `sv_commands.lua`'s main chunk holds 196 locals (Lua's limit is 200; LuaJIT refuses to load past it).
- In this environment, with TEMP inside the worktree's `out\`, the Hotloader test `animated_carriers_and_sharing`
  fails at its long-path deletion check (paths past MAX_PATH under a deep TEMP); it fails the same way before
  R19's changes.

## Open issues

- **MH-02's limit** (above): within one Lua state no caller identity can be proven; keying on the VM's chunk
  name stops label reuse, not deliberate impersonation. The comment in `file_access.hpp` says so.
- **MH-01 changes 2.2's reach for static props too**: a static prop's buffers, OBJ libraries and sidecar
  textures outside its folder (and outside the tex and textures folders near it) are no longer read. A
  texture is still looked up by its file name in the model's folders. A model that kept textures in a
  sibling folder with another name loses them, with a warning per texture.
- The per-player build caps count per SteamID while a map runs; a long map on a busy server can still add
  32 built files per player. No total disk budget for `data/mmd_vmd_npc/built` was added.
- The test `animated_carriers_and_sharing` (the add-on's own) fails here before and after the changes (long
  paths under a deep TEMP); the new remote-shape test runs first in that executable and passes.
- For R19-T (not this part's path): `tools/ci/build_hotloader.ps1` takes `-Work`, `-Out` and `-Source` as given,
  and a relative `-Work` makes it look for the worker it built relative to the source folder after
  `Push-Location`; resolving the three to full paths at the start would fix it. The workflow passes absolute
  paths, so the release is not affected.
- The Workshop item root is tested with a PMX only. Workshop items hold `.gma` archives, so a model file lies
  in an item folder only when a player put it there by hand; the rule is the same for every format.
