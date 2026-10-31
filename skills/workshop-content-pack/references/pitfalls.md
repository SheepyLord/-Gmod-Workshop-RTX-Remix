# Pitfalls: what went wrong, why, and the fix

Every failure and near-miss of the Guinaifen (2026-10-29), Robin (2026-10-30) and Evernight and
March 7th (2026-10-31) sessions, plus traps found while writing this skill. Dates are UTC. Items
marked **inferred** follow from the code but were not observed.

## The pack does not show up in game

### 1. Model not under External Models, and no PBR (Guinaifen, item 3829348717)

- **Symptom.** The user subscribed; the model was missing from Model Hotloader's External Models, and
  a manual re-import had no PBR.
- **Cause.** The native loader never deployed the item. The loader then (0.3.1) deployed only
  allowlisted Workshop items, and the field `native-loader\config.json` listed 3829070317 and
  3829275998 only. `native-loader\logs\loader.log` showed `deployment.change_count=0`, and neither
  `garrysmod\addons\mmdhl_guinaifen` nor `rtx-remix\mods\pbr_guinaifen` existed.
- **Fix then.** The session added 3829348717 to the field allowlist (backup in
  `out\field-backups\20261029-guinaifen\config.json`), `nlctl plan` showed it ACTIVE, the user
  restarted.
- **Now.** Since loader 0.4.0 (ADR 0027) a content-only package deploys from any subscription with no
  allowlist entry; players cannot edit the allowlist anyway. On 2026-10-31 the field allowlist holds
  only 3829070317 and `nlctl plan` lists all three packs as `ACTIVE ... (subscribed, content only)`.
  Keep packs content only (pitfall 14) and check with `nlctl plan`.
- **Not the cause.** GMod does not mount the archive itself (the session's report said it did; the
  console shows `Couldn't mount addon file ... (3829348717)`). Model Hotloader finds the model only
  once the loader has deployed the add-on folder.

### 2. The loader deploys only at start-up

- **Symptom.** After an update, the game still shows the old build (Robin: the old name).
- **Cause.** Deployment runs when GMod starts. Steam downloaded the new Robin build at 22:09 local
  while the game that had deployed the previous one at 21:01 kept running. A session also keeps the
  build it started with if Steam fetches an update during it (two-phase update, ADR 0015).
- **Fix.** Tell the user a restart is needed. Never restart their game yourself. `nlctl plan` shows the
  version the next start will deploy; it shows the old one until Steam has fetched the update.

## The PBR is missing on some sheets

### 3. Live texture hashes changed (Guinaifen: 灰.jpg and sita.png)

- **Symptom.** Most of the model had PBR; the face sheet and the mouth did not.
- **Cause.** The packed layer had the hashes rpai recorded in the classic install. In the user's
  session two sheets uploaded with other hashes (`37B3BC9B48184AA9` for 灰.jpg, `84168AFC8CF54915`
  for sita.png), while 9 of 12 matched. The cause was not established: the two imports' VTF textures
  were byte-identical (`gma_diff.py`: 14 of 14), and the import id does not matter (the PBR targets
  texture hashes).
- **Fix.** Before packing, refresh the hashes in the running game with the model spawned
  (`rpai hashes`, then `rpai publish` if any changed; rpai keeps every hash it has seen). On an
  already staged layer: `add_hashes.py <layer> OLD=NEW`, where OLD is the sheet's hash already in the
  layer (the Guinaifen fix: `A35D6E8412838268=37B3BC9B48184AA9 6CD8A24E251A7BE3=84168AFC8CF54915`),
  then rebuild and `gmpublish update`. Check coverage with `add_hashes.py --check-json`.

### 4. Hidden parts have only predicted hashes

- **Symptom.** `rpai hashes` marks textures `predicted` (Robin: bunny suit, mask, blush, eye shadow,
  tongue, inmon2; Evernight: seven parts).
- **Cause.** Remix reports a texture's hash only once it is drawn; predictions can be wrong (on
  Guinevere 8 of 13 agreed).
- **Fix.** Show those parts (morphs, bodygroups) in game and run `rpai hashes` again, or pack them as
  predicted and say so in the report. `check_pack.py --hashes-json` lists them.

### 5. Sheets another character's layer covers (Robin: 7 sheets; Evernight: bq.png, inmon.png)

- **Symptom.** On the author's machine everything looks right; a player with only this pack gets plain
  Remix on some sheets.
- **Cause.** Characters of one game share byte-identical sheets (`bq.png` has hash `B596852E9205F706`
  in Guinaifen, Robin and Evernight). rpai gives such a sheet to one model's layer, so the other
  models' layers have no material for it. Robin's package lacked bq, 黑, 颜赤, the ropes, 口球,
  Blindfold Text and sita.
- **Fix.** Find them: `add_hashes.py <game root>\rtx-remix\mods --check-json <work\key\hashes.json>`
  reads every mod of the install and prints `only in <mod>:<layer>` (on 2026-10-31 the field shows
  Robin's four live ones covered by the deployed Guinaifen and Evernight packs). Then either stage the
  other character's layer into the same mod as well (it ships that character's textures too), or tell
  the user which sheets players get as plain Remix (Robin's choice).

### 6. On the author's machine, `ai_pbr` hides the packaged layer (inferred)

- **Cause.** Remix checks mods in path order and the first one with a hash wins
  (`!advanced_material_editor` < `ai_pbr` < `~gmod_topbr`, mmd-remix-pbr `references/runtime-notes.md`).
  `ai_pbr` sorts before `pbr_<name>`, so where both have a hash, rpai's live layer is used.
- **Consequence.** Seeing the PBR on the author's machine proves the live layer, not the packaged one.
  Check the packaged layer by hashes (`add_hashes.py <staged pbr_<name>> --check-json ...`), or in an
  install without the character in `ai_pbr`. Later tuning in `ai_pbr` keeps showing there even before
  the item is updated.

## Names and settings

### 7. "Robin R18" stuck in the library (Robin, 2026-10-30)

- **Symptom.** After the item was rebuilt with the name `Robin`, the game still showed "Robin R18".
- **Cause, three layers.** (1) The game ran the previous build (pitfall 2). (2) Model Hotloader had
  installed the model from that build and wrote the library entry `library\<asset>.json` with
  `"name": "Robin (知更鸟)"`; it writes that file only if it does not exist (`writeIfMissing`), so no
  later build changes it. (3) For an English reader, a non-ASCII name is replaced by the PMX's ASCII
  English name from the terms record (`names.lua`), and 知更鸟.pmx calls itself `Robin R18`.
- **Fix.** Give the item a plain ASCII name from the first upload. For an install that already has the
  entry: the user renames the model in Model Hotloader, or, at the user's request, with GMod closed and
  the file backed up, set `name` in the library entry (Model Hotloader keeps entries in memory and can
  write its copy back while the game runs). By 2026-10-31 the field entry reads `Robin`.
- **Same mechanism.** Presets, the default preset, spawn size, arm parts, fit and terms of an installed
  model never change with a new build either.

### 8. Guinaifen shows as "New MMD Model" to English readers (inferred)

The item name `Guinaifen (桂乃芬)` is non-ASCII and her PMX's English name is `New MMD Model`; the
field install's library and terms records hold exactly those (read 2026-10-31). By `names.lua` an
English reader sees `New MMD Model`. Not looked at in game. The cure is the one of pitfall 7: an ASCII
name in a rebuild only reaches new installs; the existing entry needs a rename in game.

### 9. The default bodygroup preset was named "1" (Robin's first build)

- **Cause.** `util.TableToJSON` writes presets named `1`, `2` as a JSON array; the first packer copied
  it as it was, so the preset installed as `1`. The user asked for "the default bodygroup preset".
- **Fix.** `mmdhl_pack.py` turns the array into named presets and `--default-preset-name Default`
  renames the default one. Robin's 83 visibility flags stayed identical to the classic install's preset.
  With `hotloader_export.py` the library's names travel as they are: rename the preset in Model
  Hotloader's bodygroup editor first (ask the user), or use the offline packer.

### 10. "r18" in names (Robin's first build)

The first build used `mmdhl_robin_r18`, `pbr_robin_r18`, package id `robin-r18-rtx`, title "Robin R18
RTX (native loader package)" and display name `Robin R18 (知更鸟)`. The user asked for `pbr_robin`
only and the name `Robin`. Use plain names everywhere a player sees them or a folder is deployed; the
rpai layer key (`robin_r18_f9c3e4b4.usda`) is only a file inside the mod and may keep its name.
Changing the package id between builds is fine: the loader replaces the old deployment.

## gmpublish and the Workshop

### 11. `gmpublish update` keeps the old title (Robin)

- **Symptom.** The Workshop page still said "Robin R18 RTX (native loader package)" after two updates.
- **Cause.** `create` sets the title from the archive header ("Updating title..."); `update` updates
  only the icon, the tags and the file (its log has no title step). It cannot change the description
  or the visibility either (ADR 0016).
- **Fix.** Get the title right before `create`. Afterwards the owner renames it on the item page; you
  are not signed in to Steam's website. Tell the user.

### 12. A hidden duplicate that cannot be deleted (Guinaifen 3829347093)

- **Cause.** The first session created 3829347093; the user then published the same build as
  3829348717. Rule 5 of AGENTS.md: nothing on the Workshop is removed until the user says the project
  is done.
- **Consequence.** 3829347093 stays, hidden, holding the first build. It has the same package id
  (`guinaifen-rtx`): if both were subscribed, the loader would deploy the first one found and skip the
  other as "shadowed by ..., which provides the same id".
- **Fix.** Before any `create`, look for an existing item (the build folder's `gmpublish-create.log`,
  the table in SKILL.md, `steamapps\workshop\appworkshop_4000.acf`, the user). After it, every new build
  goes to `update -id`. Never subscribe to the duplicate.

### 13. "Couldn't initialize Steam! Make sure it is running!" while Steam runs

- **Cause.** On 2026-10-30 Steam's `HKCU\Software\Valve\Steam\ActiveProcess` named an old PID, and
  gmpublish's process check failed early (`tools/publish_workshop.py.md`).
- **Fix.** `publish_workshop.py` has a reviewed, hash-guarded fallback for the RTX item only. For a
  pack: stop and tell the user (restarting Steam is theirs to do). Never patch or copy gmpublish
  yourself. If Steam is simply not running, gmpublish fails the same way: ask the user to start it.

### 14. A pack that needs the allowlist

- **Symptom.** `nlctl plan` prints `skipped workshop <id> (subscribed, content only) ... not in the
  allowlist, so it may hold only Remix mods and Lua add-ons, but ...; to deploy it, add Workshop item
  <id> to allow.workshop`.
- **Cause.** The package holds more than content: payload files, binary modules (`--lua-bin`),
  `--load-first`, root files outside `rtx-remix/mods` and `garrysmod/addons`, or a file that is not
  Remix data in the mod.
- **Fix.** Packs use only `--addon` and `--mod`. `check_pack.py` checks the manifest is content only.

### 15. Overlapping folders or a reused package id

The planner skips a package whose root files overlap an active package's (`root file ... overlaps
...`) and one whose id an earlier source provides. Give every pack its own `mmdhl_<name>`,
`pbr_<name>` and `<name>-rtx`; never reuse `ai_pbr` or another pack's folder name.

### 16. GMod's add-on list shows the item red; the console says "Couldn't mount addon file"

Expected for every native-loader package (the repository's `docs\RESEARCH.md` section 24: GMod cannot
mount an archive whose files sit under `native/`). Say so in the description (ADR 0015) so players
do not report it.

## Building

### 17. `package_content.py` reports "not checked (no nlctl built)"

All three sessions ran from a worktree without a loader build. The script checks with the `nlctl` of
the checkout it lives in. Run the main checkout's `nlctl.exe manifest` and `verify` yourself (or call
the main checkout's `tools\package_content.py` by its absolute path, which then finds that build).

### 18. `package_content.py` fails under `python -I`

It imports its sibling modules (`package_fixes`, `package_runtime`, `package_workshop`), which `-I`
takes off the path. Run it without `-I`. The scripts of this skill run with `-I`.

### 19. Double quotes vanish from the description (Robin)

`Spawns with her "Default" bodygroup preset.` reached the archive as `Spawns with her Default
bodygroup preset.`: PowerShell 5.1 does not escape embedded double quotes when it passes a string to
a native program. Write the description without straight double quotes (use 'single' or typographic
quotes). The Model Hotloader package reads the file directly and kept them.

### 20. A reused add-on folder keeps an old manifest

Each build of the Hotloader package gets a new random id. Building into an existing folder would leave
the old `<id>.json` (and stale `.dat` files) beside the new one; the Robin session deleted the folder
first. `mmdhl_pack.py` refuses an existing folder unless `--replace`, which replaces it whole;
`check_pack.py` warns about a second manifest and unlisted `.dat` files.

### 21. `hotloader_export.py` refuses

It needs the game in a map (client Lua) with Model Hotloader loaded and the models in its library. It
refuses models shared by a server (`entry.shared`), models not in the cache, and a Model Hotloader
without `StartPackageExport`. It times out after 600 s by default (the export may still finish in the
game). It skips the terms-of-use dialog: private items only.

### 22. `--requires-remix` differs between the packs (inferred effect)

Guinaifen and Robin were built with `--requires-remix`, Evernight and March 7th without it. With it,
the `mmdhl_<name>` folder is hidden in starts without RTX (ADR 0013). The user's standalone Model
Hotloader (Workshop item 3810025467) runs in such starts; by `workshop.lua` it then sees the package
gone and deletes the Workshop-installed model from its cache (unless in use), and the next RTX start
installs it again. Not observed. The current recipe (Evernight) leaves it off for character packs; a
map remaster whose Lua only makes sense with Remix uses it (Modern House RTX).

## Diagnosing

| Question | Where to look |
|---|---|
| Will the next start deploy the pack? | `nlctl plan <game root>` (main checkout's `out\build\win64-release\loader\cli\nlctl.exe`): `ACTIVE workshop <id> (subscribed, content only) -> <package id> <version>`, or `skipped ...: <reason>`. Read only |
| Is the archive valid? | `nlctl manifest <gma>` (`OK: valid native package`), `nlctl verify <gma>` (`OK: gmad, <n> files`), `python -I tools\gmapack\gmapack.py verify -f <gma>` (`0 CRC failure(s)`), `check_pack.py` |
| What did the last start do? | `<game root>\native-loader\logs\loader.log` (`deployment.outcome`, `deployment.change_count`, `deployment.blocked_by`, `deployment.error`, `deployment.note`); `<game root>\garrysmod\data\native-loader\status.json` (`deployment.packages`, `deployment.skipped` with each package and reason); `nlctl status <game root> [--verify]` (the journal) |
| Did Steam download it? | `H:\SteamLibrary\steamapps\workshop\content\4000\<id>\<uploaded file name>.gma` (SHA-256 against the build), `steamapps\workshop\appworkshop_4000.acf` (`WorkshopItemsInstalled`, `WorkshopItemDetails`). A first download shows in the details before the folder exists |
| Is the item hidden? | gmpublish's log ("currently marked as hidden"); Steam's public `ISteamRemoteStorage/GetPublishedFileDetails` answers `result 9` for it (seen for all three) |
| Did Model Hotloader install the model? | `garrysmod\addons\mmdhl_<name>\` exists; `garrysmod\data\mmd_hotloader\library\<asset>.json`, `terms\<asset>.json`; `assets\<asset>\` (with a locally rebuilt `materials-v5.gma`); the library under Workshop. Model Hotloader prints `[Model Hotloader workshop] ...` errors to the console; read only your own session's part of the user's console log |
| Does the PBR apply? | `rtx-remix\mods\pbr_<name>\` exists; with the model spawned, `rpai hashes`, then `add_hashes.py <that folder> --check-json <hashes.json>` |
