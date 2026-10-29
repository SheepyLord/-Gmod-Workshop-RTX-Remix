# 0024: The RTX package bundles the user's add-ons and Model Hotloader's natives; the loader loads a module's runtime first

- Status: Accepted 2026-10-29
- Decided by: the user ("Ship them together, and bundle the model hot loader's binaries. Future updates
  on them will also update the remix workshop item"; and, for the fixes module another session rebuilt,
  "Please keep this updated"), Claude choosing how
- Builds on: [0003](0003-native-trust-allowlist.md) (allowlist), [0010](0010-rtx-session-extras.md)
  (RTX-session extras), [0013](0013-rtx-only-addons-hidden-without-rtx.md) (RTX-only add-ons hidden
  without RTX), [0016](0016-one-workshop-item-kept-current.md) (one item kept current),
  [0023](0023-content-packages-and-modern-house-item.md) (content packages)
- Extends 0010: one kind of extra applies in every session, not only RTX sessions (below).

## Context

- **The add-ons.** The user asked in round 2 to bundle Model Hotloader (its add-on and binary modules),
  Advanced Material Editor, Advanced Bodygroup Tool, Procedural Bodygroup Destruction and the Character
  Motion Importer. All five are the user's own Workshop items. The user subscribes to them, and the
  field install also had hand-placed copies of three of them, two being development links.
- **Model Hotloader's natives.** `gmcl_mmdhl_win64.dll` and `gmsv_mmdhl_win64.dll` statically import
  `mmdhl_runtime_win64.dll`. GMod loads binary modules with `LoadLibraryExA` from `lua_shared.dll`, without
  `LOAD_WITH_ALTERED_SEARCH_PATH`, so Windows looks for the runtime next to `gmod.exe`. Its installer
  therefore copies the runtime into `bin\win64`, which the package format cannot write (0003, 0014).
  - Searching the module's own folder for every module would break others: `gmcl_vrmod` finds
    `openvr_api.dll` in `bin\win64`.
- **Where the current builds are.** The classic install runs Model Hotloader 2.3.1: its add-on (a copy
  of the repository's working tree) and natives from a local build. The fixes package already takes
  its modules from the classic install, and so does the fixes module that another session rebuilt today
  with a tuned visibility rule.
- **Workshop copies in sessions without RTX.** The RTX package is `requires_remix`, so its add-ons are
  hidden without RTX (0013). The user's subscribed Workshop copies of the same add-ons still run then,
  and Model Hotloader's copy loads the bundled natives from `garrysmod\lua\bin`.

## Decision

1. **Module dependencies (loader 0.3.0).** A manifest may declare `module_dependencies`: for a `.dll`
   it deploys to `garrysmod/lua/bin/`, other files there to load first ([PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md)).
   - The bootstrap's `LoadLibrary*` import hooks on game modules load them by absolute path just
     before the module loads, once per process. The module's import then binds to the loaded file.
   - This applies in every session where the package is deployed, RTX or not: a start without a
     runtime installs the hooks for it too.
   - It loads only files of an allowlisted package (0003), and only when the game loads the module
     that needs them.
2. **The five add-ons ship in the RTX package**, one part each in `workshop.json`, built afresh at
   every publish by `package_content.py`:
   - **Model Hotloader:** its add-on and its six natives come from the classic install, where the
     user installs builds. `mmdhl_runtime_win64.dll` loads before both modules.
   - **Advanced Material Editor:** from the working copy, plus its RTX bridge module from the classic
     install. Its committed test textures (`materials/models/*`) are left out, as the published add-on
     leaves them out.
   - **The bodygroup tool, bodygroup destruction and the motion importer:** from the user's working
     copies.

   Add-on folders are filtered as gmad publishes them: GMod's whitelist and the folder's `addon.json`
   ignore list, so development files (`.codex*`, crash dumps, tests) stay out. The deployed folder names
   are the classic install's (`!advanced_material_editor`, `advanced_bodygroup_tool`,
   `!gmod_bullet_break_simulator`, `mmd_hotloader`, `mmd_vmd_npc`).
3. **Updates.** Each part's sources are in the publish fingerprint, so any publish ships what they
   hold. Hooks start a publish:
   - commits and merges on `main` here, as before (0016);
   - commits and merges on `main` of the material editor's, the bodygroup destruction's and the motion
     importer's repositories;
   - commits on **any** branch of the fixes fork and of Model Hotloader's repository. Those deliver
     their builds to the classic install from feature-branch worktrees, as the visibility-tuned fixes
     module came.

   A publish uploads only when the item's content changed. The bodygroup tool has no repository, and an
   install into the classic install starts nothing by itself. Both ship with the next publish.

## Consequences

- **Players need loader 0.3.0.** The RTX package now declares `requires_loader` `>=0.3.0`. An older
  loader keeps its last good deployment and reports the refusal. The release bundle from CI has 0.3.0;
  a public release (a `v*` tag) is the user's call.
- **Overlap in RTX sessions.** A subscriber to the standalone items gets the bundled versions: GMod
  prefers an add-on folder's file over a Workshop copy's of the same path. A file that only the
  Workshop copy has still loads.
- **Hand-placed copies block the package.** The loader never replaces files it did not place, so in
  the field the hand-placed copies were moved first: the add-on folders to `addons_d`, the natives to a
  backup in this repository's `out`.
- **Model Hotloader without the loader.** With the loader off (`-nonativeloader`), its modules on disk
  find no runtime: `bin\win64` holds none any more.
- **Journal compatibility.** A journal that records module dependencies cannot be read by an older
  loader.
- **Edits reach players.** The parts follow the user's working copies and installs, so an edit there
  reaches subscribers with the next publish.

## Alternatives considered

- **Preload the runtime at every start:** it would load a 10 MB DLL into sessions that never use it.
- **Put `garrysmod\lua\bin` on `PATH`:** a stale copy in `bin\win64` or the game folder would still win,
  and every module's bare-name loads would change.
- **Keep the Lua add-ons as Workshop requirements and ship only natives:** the user chose to ship them
  together.
- **Bundle the published Workshop GMAs:** they lag the versions the classic install runs (Model
  Hotloader 2.3.0 on the Workshop, 2.3.1 here).
