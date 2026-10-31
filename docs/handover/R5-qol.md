# R5: the user's QoL report of 2026-10-31

Claude's round on the user's report of 2026-10-31, on `r5-qol` in `out\worktrees\r5` (from `main` at
`df80147`), with the glass work done by a separate agent on `r5-glass` (`out\worktrees\r5-glass`) and
merged. Field evidence is in `out\qa-field\r5-sky\`, PoC evidence in `out\qa-poc\r5-*\`.

## The report

| # | Report | Cause | Done |
|---|---|---|---|
| 1 | "a clear line visible in the sky, where one side has a lot of stars, and another has none" (night sky, modern_house) | Modern House RTX re-applies its settings, its afternoon sun among them, 23, 43 and 63 s after the map starts; a sky the player had taken over came back only on the companion's 10 s timer. Up to 10 s of afternoon, three times, and the daylight lingered in the image's temporal history where the camera had looked: a haze with a straight edge along the previous view | The companion takes the sky back in the same tick: it wraps `MHRTX.ApplySettings` to run the new hook `NativeLoaderSkySet` (`51e3b6d`); checked in the field with the module swapped in, two re-applies during a tour, every view clean (`out\qa-field\r5-sky\10-night-sky-fix-check`) |
| 2 | Broken glass on the ground is not physically interactive, cannot be broken further, never goes away | Debris in `COLLISION_GROUP_WORLD` (the No Collide tool's group); shards never called `TakePhysicsDamage`; map debris could not break; nothing removed pieces | Loose physics that players pass through and everything else hits, breaks again down to dust, one 256-piece budget, `rtx_glass_debris_lifetime` (120 s) with a slider ([ADR 0061](../decisions/0061-loose-glass-breaks-again-and-expires.md), `7e7a6e4`, `e6ba578`) |
| 3 | Workshop model packs must always load, "even if user had imported it. Overwriting is okay" | Model Hotloader counted a model already in the cache with no install record as the player's own import: never installed or labelled as the package's (the Evernight and March 7th pack over the user's own imports). The PBR session also packed the models with their PMX names, March 7th without terms, and published unchecked | Model Hotloader takes such a model over: installs it from the package (differing files only), labels it the package's, keeps the player's settings files under `workshop/own/<asset>/` and puts them back if the package goes; installs record their start so an interrupted one resumes (`8fa405f`). The content pack skill refuses non-plain names and missing terms and checks in the game before an upload (`4d852a8`) |
| 4 | Move "Recalculate normals for RTX" below the import button; its note: only if the model looks off | — | Moved to a row under the import button, one switch for characters and props; the note in seven languages (six agent-written, unreviewed) (`8fa405f`) |
| 5 | Stability on machines with limited resources (a device lost on an RTX 4060 Laptop, 8 GB): research and propose, do not implement | — | [Proposal](#stability-proposal) below; nothing implemented |

## Night sky: how it was found

Eleven field runs on `modern_house` (the user's install, `-insecure`, closed with `quit`) with
[`night_sky_probe.lua`](../../tools/qa/night_sky_probe.lua.md) and variants; details and numbers in
[RESEARCH.md](../RESEARCH.md) "The night sky line on modern_house". The order of elimination: the night
sky image (a CPU render of its layers is seamless), the fixes' Custom 2D Skybox, `r_skybox`, Modern
House's mirrors, the map's skybox faces (with Remix's debug views: no geometry in the sky, only the
house and the trees), the clouds (off: clean, but also clean with clouds once the re-applies had
stopped), the clouds' hex de-tiling. The haze followed the previous view's frustum edge and came in
the minute after the map started; the daytime views fell on Modern House RTX's timer.

The probe takes the sky over for the session it runs in, as a player changing a setting does. A
change to the fixes' Custom 2D Skybox made while hunting it was reverted (it was not the cause).

## Glass

The glass agent's report, in short (its full notes are in ADR 0061 and the changed files' `.md`):
pieces use `COLLISION_GROUP_WEAPON` (`COLLISION_GROUP_DEBRIS` with `rtx_glass_expensive_shards 0`);
clients have no physics copy of a shard, so players pass through instead of being stopped where the
client predicts open space. Broken-off pieces split into 3-8 planes, fragments under radius 20 turn
into GlassImpact dust (at most 3 effects per split, 24 per tick), impacts above 500 units/s break
loose pieces, two loose pieces never break each other. Found and not changed: crack overlays are never
drawn on clients; the add-on's own shard-against-shard test reads a physics object and never matches;
Reset to Defaults sets the minimum break speed to 100 against the setting's 80; two stale source line
references in the companion's catalogs.

## Workshop packs over the player's own imports

- **Own import**: a model in the cache (`mmd_hotloader/assets/<id>/manifest.json` and `model.bin`, or a
  prop's `.gmdl`) with no record in `mmd_hotloader/workshop/state.json`. Taken over by a `workshop`
  package (not a demo `user` pack): marked `ownBefore`, installed through the usual verified transfer
  (only files whose hash differs are written), then its settings, arms and fit files are written over,
  the player's kept once under `workshop/own/<asset>/`. The label shows the package.
- **Unsubscribed**: a taken-over model stays, with the player's settings put back, and the record goes.
- **Repairs and interrupted installs**: a record means this addon's install. Installs now record their
  start (`installing`), so one stopped part way is resumed and still removed when its package goes. An
  install interrupted before this version (no record) is taken for an own import: it completes, and
  stays if the package goes.
- **Tests**: Model Hotloader's own `tests/test_workshop_packages.py` passes against the new
  `workshop.lua` with its old expectation ("a player's own import was taken over") replaced by the
  takeover's checks (`out\tmp\mmdhl-tests\test_workshop_packages_r5.py`). The change is in this repo's
  `packages/model-hotloader` only; Model Hotloader's repository does not have it yet.

## Stability proposal

To come: the research agents' proposal for limited-resource machines (the device lost on an 8 GB RTX
4060 Laptop, the opacity micromap budget warning, the rejected `rtx.resourceLimits` keys, Aftermath).

## Open

- Carry the Model Hotloader changes (`workshop.lua`, `ui.lua`, the catalogs) and the updated test into
  Model Hotloader's own repository.
- Modern House RTX (hidden test item 3829275998) could run `NativeLoaderSkySet` itself, or skip its
  sun once the native loader's companion holds the sky; the companion's wrapper covers today's item.
- The Evernight and March 7th pack (3830769477): plain names and March 7th's terms, then upload again.
- The night sky image's galaxy band shows the Milky Way's core three times (the runtime wraps it).
