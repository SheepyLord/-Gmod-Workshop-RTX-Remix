---
name: workshop-content-pack
description: Pack Garry's Mod RTX content that depends on other add-ons into a native-loader content package and upload it to the Steam Workshop - an MMD character imported with Model Hotloader plus its rpai RTX Remix PBR (mmdhl_<name> add-on, pbr_<name> mod, package id <name>-rtx), or a remastered map's Remix mod and Lua. Covers live texture hashes, the Model Hotloader package (hotloader_export.py, offline mmdhl_pack.py), staging only referenced DDS, package_content.py, nlctl manifest/verify, check_pack.py, the 512x512 icon, the description with Required items (RTX package 3829070317, the native loader), gmpublish create (hidden) and update -id, post-upload checks, and what the loader deploys from any subscription. Use it whenever the user asks to pack, upload, publish or update a character, model or map with its PBR on the Workshop, mentions gmpublish, a hidden or private item, Required items or dependencies, a Model Hotloader package, or items 3829348717, 3829892354 or 3830769477.
---

# Workshop content packs for Garry's Mod RTX

A **pack** is one Workshop item holding a native-loader package (`docs/PACKAGE_FORMAT.md` in the
repository `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix`) with content only: a Model Hotloader
package add-on and a Remix mod for a character, or a Lua add-on and a Remix mod for a remastered map.
GMod cannot mount such an item; the native loader deploys it at start-up from any subscription
(ADR 0027), and it relies on the RTX package (3829070317) for the Remix runtime and Model Hotloader.

Made this way so far (dates UTC; all hidden):

| Item | Package id | What | Notes |
|---|---|---|---|
| 3829348717 | `guinaifen-rtx` | Guinaifen: Model Hotloader package + 18 PBR materials, 695,563,031 bytes | published by the user from the agent's build (2026-10-29), then updated by the agent |
| 3829347093 | `guinaifen-rtx` | the agent's first upload of the same pack, first build | hidden duplicate; never delete, never subscribe |
| 3829892354 | `robin-rtx` | Robin: preset `Default`, name `Robin`, 17 materials, 452,591,324 bytes | created 2026-10-30 as `robin-r18-rtx`, updated twice; page title still the old one unless the user renamed it |
| 3830769477 | `evernight-march7th-rtx` | Evernight and March 7th: two models, two layers, 1,222,846,295 bytes | created 2026-10-31 with `hotloader_export.py`; download read back identical |

Related: 3829275998 Modern House RTX (a map remaster, ADR 0023), 3829070317 the RTX package.

## Rules from this user

- **Workshop only means no repository edits.** Build under the main checkout's git-ignored
  `out\packages\<name>\`; `git status --short` stays empty. Record an item in the repo (handover,
  CHANGELOG) only when the user asks.
- **Upload only the pack the user asked for, hidden.** `gmpublish create` makes the item hidden; keep
  it so. The page's title (after creation), description, Required items and visibility are the
  user's to set on the item page. Making an item public needs the user's go-ahead after a licence and
  content review.
- **Never remove or delete a Workshop item**, duplicates included (AGENTS.md rule 5). So never
  `create` twice for one pack: look for its item first; every later build goes to `update -id`.
- **Public limits.** R18 models (nude base bodies, explicit morphs) stay hidden. The icon is free of
  adult content even for a hidden item. Models with restrictive terms (Evernight's record: 禁止二配，
  禁止非法使用, in its own English "Secondary matching and unauthorized use are prohibited"), game
  rips and another author's map are the user's call; never re-upload someone else's map, make it a
  Required item.
- **Never restart the user's game, never stop a `gmod.exe` you did not start.** The loader deploys only
  at start-up: tell the user a restart is needed.
- **The field install** (`H:\SteamLibrary\steamapps\common\GarrysMod`) is the user's game: read it
  freely (`nlctl plan`, library entries), change nothing there unless the user asks in this
  conversation, after backing up what you touch. Never write `GarrysMod_RTX_c`.
- Never edit `rtx-remix\mods\!advanced_material_editor`, `rtx.conf` or `user.conf`. `ai_pbr` is rpai's
  (it overwrites edits at the next publish): stage copies.
- Do not grep the user's GMod console logs; read only your own session's part. The loader's own logs
  are fine.

## What a pack holds

| In the archive | Deployed to | Made by |
|---|---|---|
| `native/manifest.json` (kinds `lua-addon`, `root-files`) | read by the loader | `package_content.py` |
| `native/root/garrysmod/addons/mmdhl_<n>/` with `addon.json`, `data_static/mmdhl/packages/<32 hex>.json`, `data_static/mmdhl/files/<sha256>.dat` | `garrysmod\addons\mmdhl_<n>\` | `hotloader_export.py` or `mmdhl_pack.py` |
| `native/root/rtx-remix/mods/pbr_<n>/` with `mod.usda`, `models/<rpai key>.usda`, `textures/<rpai key>/*.dds` | `rtx-remix\mods\pbr_<n>\` | `stage_pbr_mod.py` or `pbr_mod.py` |

**Names.** `<n>` is the character(s) in lowercase ASCII with underscores (`robin`,
`evernight_march7th`), never `r18`. Package id `<n with hyphens>-rtx`, archive `<id>.gma`, package
name `<Display> RTX`, title `<Display> (Model Hotloader + RTX PBR)` for both the Hotloader package and
the archive (the archive's title becomes the Workshop title at `create` and never changes with
`update`). The model's display name in Model Hotloader: the character's plain ASCII name (`Robin`).

**The path into the game.** Steam puts the subscribed item in
`H:\SteamLibrary\steamapps\workshop\content\4000\<item id>\<n>-rtx.gma` (the uploaded file's name).
At the next start the loader (0.4.0 or later) finds `native/manifest.json` in it, checks it is
content only and deploys both folders. GMod mounts the add-on folder; Model Hotloader (the RTX
package's copy) finds
`data_static/mmdhl/packages/*.json` in the first map, installs the model into its cache and library;
Remix loads `pbr_<n>` at that start. GMod refuses the archive itself (`Couldn't mount addon file`,
red in the add-on list): expected. Format and install rules: `references/model-hotloader-package.md`.

## Dependencies

- **From any subscription, no allowlist** (ADR 0027): kinds `lua-addon` and `root-files` only; root
  files under `rtx-remix/mods/<mod>/` that are Remix data (`.usd .usda .usdc .usdz .dds .png .jpg .jpeg
  .tga .bmp .exr .hdr .mdl .json .txt`) and under `garrysmod/addons/<add-on>/` that gmad's whitelist
  takes (plus `addon.json`). A player turns this off with `"allow": {"subscribed_content": false}` in
  `native-loader\config.json`.
- **Needs the allowlist**, which players cannot edit (in practice only 3829070317 has native code):
  payload files, binary modules, patch sets, module overrides, session variables, module
  dependencies, root files anywhere else. Such a pack is skipped, so packs use only `--addon` and `--mod`.
- **Precedence.** An allowlisted source of the same package id wins; of two subscriptions with one id
  the first found (item order) deploys and the other is "shadowed"; a pack whose folders overlap an
  active package's is skipped. Hence unique `mmdhl_<n>`, `pbr_<n>`, `<n>-rtx`.
- **What a player needs:** the loader (`bin\win64\winmm.dll` from its release bundle, not a Workshop
  item), the RTX package 3829070317 (runtime, fixes, Model Hotloader with its natives), the pack; for a
  map remaster also the map's own item. In starts without RTX the RTX package's Model Hotloader is
  hidden; a subscription to the standalone Model Hotloader (3810025467) runs then.
- **Required items** are set by the owner on the item page (Steam's owner controls, "Add/Remove
  Required Items"); `gmpublish` cannot set them. Not exercised in these sessions. The loader ignores
  them: each subscribed package deploys on its own. Put them in the description too.
- **`--requires-remix`:** for a map whose Lua only makes sense with Remix, yes (Modern House). For a
  character pack, no (the current recipe, Evernight): Guinaifen and Robin had it, which hides the model
  add-on without RTX and, by `workshop.lua` (inferred), lets a standalone Model Hotloader delete and
  later reinstall the model (`references/pitfalls.md` 22).

## Procedure for a character pack

Set the paths once (PowerShell):

```powershell
$repo  = 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix'
$nlctl = "$repo\out\build\win64-release\loader\cli\nlctl.exe"
$game  = 'H:\SteamLibrary\steamapps\common\GarrysMod'          # the install with the import and ai_pbr
$K     = '<base directory of this skill>'                      # scripts in $K\scripts
$P     = "$env:USERPROFILE\.claude\skills\mmd-remix-pbr\scripts"  # or $K\..\mmd-remix-pbr\scripts
$py    = "$env:USERPROFILE\.rpai\venv\Scripts\python.exe"       # rpai's Python, for the mmd-remix-pbr scripts
$B     = "$repo\out\packages\<n>"                              # the build folder
```

1. **Scope.** Get the character(s) (PMX path or Model Hotloader asset id), the rpai model keys
   (`rpai status`; `<slug>_<asset8>`), the display names, the default preset. Look for an existing
   item for this pack (the table above, `$B\gmpublish-create.log`, the user); if there is one, follow
   "Updating an item". Check `git -C $repo status --short` is empty and `$B` is new. Load the
   mmd-remix-pbr skill for rpai. Find where the sources are: on 2026-10-31 the field's `ai_pbr`
   holds only Evernight's and March 7th's layers; Guinaifen's and Robin's layers (and their original
   imports) are in `H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c` (read only). `rpai status`
   names rpai's mod folder.
2. **Refresh the live hashes.** In the user's running game, in a map, the model spawned with every
   part shown that should get PBR: `rpai hashes "<pmx>"`, then `rpai publish "<pmx>"` if a hash
   changed. Spawn with `mmdhl.RequestSpawn(id, {}, cb)` and remove with `lua_run
   Entity(idx):Remove()` only what you spawned. Then list what the pack will lack:
   `python -I $K\scripts\add_hashes.py $game\rtx-remix\mods --check-json $env:USERPROFILE\.rpai\work\<key>\hashes.json`
   reads every mod of the install (`ai_pbr` and the deployed packs): `only in <mod>:<layer>` marks a
   sheet another character covers on this machine only; predicted-only parts are listed too. No game
   running: pack the recorded hashes and say so in the report.
3. **Name and preset.** Read `$game\garrysmod\data\mmd_hotloader\library\<asset>.json`
   (`name`, `bodygroups.default`, `presets`). Ship the user's default preset under a real name
   (`Default`) and an ASCII display name. Model Hotloader never changes either for a player who
   installed an earlier build (`writeIfMissing`), so get them right in the first upload.
4. **The Model Hotloader package**, into `$B\mmdhl_<n>`. Write `$B\description.txt` first (below).
   - Preferred, game running and the models in its library, private items only (it skips the terms
     dialog):
     `& $py "$P\hotloader_export.py" --game-root $game --asset <id8> [--asset <id8>] --title "<Display> (Model Hotloader + RTX PBR)" --description-file "$B\description.txt" --file-name <n> --tag cartoon --out "$B\mmdhl_<n>"`.
     It takes the library's names and presets as they are: rename them in Model Hotloader first
     (ask the user) or use the fallback. The archive stays in `$game\garrysmod\data\mmd_hotloader\exports\`.
   - Fallback, offline (any install's cache):
     `python -I $K\scripts\mmdhl_pack.py $game\garrysmod\data\mmd_hotloader <id8> "$B\mmdhl_<n>" "<Display> (Model Hotloader + RTX PBR)" "<Name>" "SheepyLord" "$B\description.txt" [--item <id8>=<Name2>] [--default-preset-name Default]`.
     It reproduces Model Hotloader's exporter byte for byte (`scripts/mmdhl_pack.py.md`).
5. **The PBR mod**, into `$B\pbr_<n>`, only the DDS the layers reference, every copy SHA-checked:
   - preferred: `& $py "$P\stage_pbr_mod.py" --src $game\rtx-remix\mods\ai_pbr --dest "$B\pbr_<n>" --layer <key> [--layer <key2>] --doc "<Display> RTX PBR (rpai layer <key>), packaged for the Workshop."`;
   - fallback: `python -I $K\scripts\pbr_mod.py $game\rtx-remix\mods\ai_pbr <key> "$B\pbr_<n>" "<Display>" [--layer <key2>]`.
   - A hash that changed after staging, with no rpai at hand: `python -I $K\scripts\add_hashes.py "$B\pbr_<n>\models\<key>.usda" OLD=NEW`.
6. **Icon** `$B\icon.jpg`: a 512x512 baseline JPEG of the face(s) from a tuned in-game shot (rpai's
   `work\<key>\aabb_*\...\results.json` lists the shots), no adult content. Cropping is fine here;
   the never-crop rule is for test evidence.
   `& $py -I -c "from PIL import Image; im = Image.open(r'<shot>').convert('RGB'); im.crop((<l>, <t>, <r>, <b>)).resize((512, 512), Image.LANCZOS).save(r'$B\icon.jpg', 'JPEG', quality=92, progressive=False)"`
7. **Build** (no `-I`: the script imports its neighbours; its absolute path makes it check with the
   main checkout's `nlctl`):
   ```powershell
   $d = (Get-Content -Raw -Encoding utf8 "$B\description.txt").Trim()
   python "$repo\tools\package_content.py" --id <n>-rtx --name "<Display> RTX" --addon "$B\mmdhl_<n>" --mod "$B\pbr_<n>" `
     --title "<Display> (Model Hotloader + RTX PBR)" --type model --tag cartoon --description $d --gma "$B\<n>-rtx.gma" --link
   git -C $repo status --short    # nothing
   ```
   Add `--force` to rebuild an existing archive. It writes `<n>-rtx.gma` and `<n>-rtx.gma.inventory.txt`.
8. **Validate.** `& $nlctl manifest "$B\<n>-rtx.gma"` (`OK: valid native package`), `& $nlctl verify
   "$B\<n>-rtx.gma"` (`OK: gmad, <files> files`), then
   `python -I $K\scripts\check_pack.py $B --hashes-json $env:USERPROFILE\.rpai\work\<key>\hashes.json --deep`:
   no errors; carry its warnings into the report.
9. **Upload** (Steam running, signed in to the user's account; from a game root holding
   `steam_appid.txt`, the PoC as `tools\workshop.json` names it):
   ```powershell
   $root = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC'
   Push-Location $root
   & "$root\bin\win64\gmpublish.exe" create -addon "$B\<n>-rtx.gma" -icon "$B\icon.jpg" *> "$B\gmpublish-create.log"
   "exit $LASTEXITCODE"
   Pop-Location
   Get-Content "$B\gmpublish-create.log" | Select-String 'Success|item ID|hidden|rror|fail'
   ```
   Expect `Success! Your new item ID is <id>!` and `currently marked as hidden`. The log is the
   record of the id: keep it in `$B`. Its first lines carry the account's Steam ID; do not quote them.
   Robin's 452 MB took 23 s and Guinaifen's 696 MB 28 s; give the call a 10-minute timeout, or run it
   in the background for a much larger pack.
10. **After the upload.**
    - Optional: Steam's public lookup cannot see a hidden item (`result 9`):
      `(Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body @{itemcount=1; 'publishedfileids[0]'='<id>'}).response.publishedfiledetails | Select-Object result, title`.
    - Once subscribed (by the user; subscribing for them changes their Steam account, so only when they
      asked for a test, e.g. with the throwaway probe `$repo\out\round5\steam_ugc_probe.py <game root>
      <library steamapps> subscribe <id>`, unverified beyond its header): the download's SHA-256 equals
      the build's (`Get-FileHash`), and `& $nlctl plan $game` prints
      `ACTIVE  workshop <id> (subscribed, content only) -> <n>-rtx <version>`.
    - After the user restarts: `$game\native-loader\logs\loader.log` deployed it, both folders exist,
      the model is in Model Hotloader's library, and with it spawned `rpai hashes` plus
      `add_hashes.py $game\rtx-remix\mods\pbr_<n> --check-json ...` shows the hashes covered.
11. **Tell the user** (plain words, numbers): the item link (`https://steamcommunity.com/sharedfiles/filedetails/?id=<id>`)
    and that it is hidden; package id, version, size; models with their display names and default
    preset; layers, materials, DDS count and size; the checks run and their results; what is not
    verified (the in-game install and PBR until a restart; predicted-only parts; sheets only another
    character's layer covers); what only they can do on the item page (paste the description, add
    3829070317 as a Required item, rename the title after an update, decide on public); the restart;
    why it must stay hidden (R18, terms); that the repository is unchanged and where the build is.

## The description

Plain text, no straight double quotes (PowerShell 5.1 drops them on the way to `package_content.py`),
at most 8000 bytes. `package_content.py --description` puts it in the archive; the Workshop page's
description is pasted by the user (gmpublish's logs show no description step, and its closing line
asks to add one). Template:

```
<Display> (<game>), the MMD model <file>.pmx imported with Model Hotloader, plus <her/his/their> RTX
Remix PBR materials (rpai: upscaled albedo, normal, roughness and metallic maps; <style notes>).
Spawns with <her/his> 'Default' bodygroup preset.

Required items:
- RTX Remix for GMod, Workshop item 3829070317: the Remix runtime, the RTX fixes and Model Hotloader.
- The GMod native loader: bin\win64\winmm.dll from the loader's release bundle (not a Workshop item).

The loader deploys this item at the next start: the Model Hotloader package add-on
garrysmod\addons\mmdhl_<n> and the Remix mod rtx-remix\mods\pbr_<n>; Model Hotloader then installs the
model into its library. GMod cannot mount the item itself: its console line Couldn't mount addon file
and the red entry in the add-on list are expected. Private test item.
```

## Updating an item

1. Find the id (the table above, `$B\gmpublish-create.log`, the user) and the last build in `$B`
   (`out\packages\guinaifen`, `out\packages\robin`; Evernight's is in its worktree,
   `.claude\worktrees\pbr-textures-evernight-marth-8c028c\out\packages\evernight-march7th`).
2. Rebuild what changed (steps 2-7; `mmdhl_pack.py --replace`, a fresh stage folder,
   `package_content.py --force`), then step 8. Keep the item's package id and folder names unless
   the user asks for new ones (Robin's rename to `robin-rtx` was the user's request).
3. `& "$root\bin\win64\gmpublish.exe" update -id <id> -addon "$B\<n>-rtx.gma" [-icon "$B\icon.jpg"] -changes "<version>: <what changed>" *> "$B\gmpublish-update.log"`
   from `$root` as in step 9; expect `Success!`.
4. Tell the user: `update` does not change the title (rename it on the page), the description or the
   visibility; players get the new build at the start after Steam fetched it; a model already
   installed keeps its library name, presets, fit and terms (they rename in Model Hotloader, or you
   edit the library entry at their request with GMod closed and a backup).

## A remastered map

The same route with a Lua add-on (`--addon <folder>`, its own folder name), the Remix mod
(`--mod <folder>`), `--requires-remix` when the Lua only makes sense with Remix, and the map's own
type and tags. Modern House RTX (ADR 0023, item 3829275998, 3.3 GB):

```powershell
python "$repo\tools\package_content.py" --id modern-house-rtx --name "Modern House RTX" --requires-remix `
  --addon <modern_house_rtx add-on> --mod <modern_house_rtx mod> --title "Modern House RTX (native loader package)" `
  --type effects --tag scenic --tag realism --gma "$repo\out\packages\modern-house-rtx.gma" --link
```

Never ship the map or its files (the Workshop bans re-uploads): it is a Required item (Modern House:
3495468649). Textures derived from another author's map keep the item hidden until the user decides.
Keep packs under about 4 GB (the Workshop's guideline). `check_pack.py --addon <folder>` checks a
plain Lua add-on without the Hotloader rules.

## Scripts

| Script | Route | Does |
|---|---|---|
| `scripts/mmdhl_pack.py` | fallback for `hotloader_export.py` | the Model Hotloader package add-on folder, offline, from a cache |
| `scripts/pbr_mod.py` | fallback for `stage_pbr_mod.py` | the Remix mod folder with only the referenced files |
| `scripts/add_hashes.py` | both | add hashes to a staged layer; `--check-json` coverage of rpai's live hashes |
| `scripts/gma_diff.py` | diagnosis | compare two archives member by member (two imports' textures, a build and a download) |
| `scripts/check_pack.py` | both | read-only preflight of a build folder: names, Hotloader package, mod, archive, nlctl, icon, description |
| mmd-remix-pbr `scripts/hotloader_export.py` | preferred | Model Hotloader's own export through the running game |
| mmd-remix-pbr `scripts/stage_pbr_mod.py` | preferred | the Remix mod folder from `ai_pbr` |

Each script has a `.md` beside it. This skill's scripts need only the standard library and run with
`python -I`; `mmdhl_pack.py` and `check_pack.py --deep` need Windows. The mmd-remix-pbr scripts run
with rpai's Python. `tools\package_content.py` runs without `-I`.

## References

- [references/model-hotloader-package.md](references/model-hotloader-package.md): the package's
  files, fields, limits and packet format; what Model Hotloader does on install; display names.
- [references/pitfalls.md](references/pitfalls.md): every failure so far with its cause and fix, and
  where to look when a pack does not show up.
- The repository's `docs/PACKAGE_FORMAT.md`, ADRs 0015, 0016, 0023, 0024, 0027, and
  `tools/package_content.py.md`, `tools/publish_workshop.py.md`, `tools/gmapack/gmapack.py.md`.
