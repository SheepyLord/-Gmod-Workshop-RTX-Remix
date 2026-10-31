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

## Checked in the game

| Where | What | Result |
|---|---|---|
| Field, modern_house | Night sky tours (`night_sky_probe.lua`) before the fix, and with the new sky module swapped in for a session (`out\tmp\night_sky_fixcheck.lua`) | Before: daylight in two views, hazy wedges along the previous view's edge. After: two Modern House re-applies during the tour, every view a clean night sky (`out\qa-field\r5-sky\10-night-sky-fix-check`) |
| PoC, the R5 package (`out\worktrees\r5\out\dist-r5`) | `release_qa.py` (session, spawn menu, map glass, spawned glass) | All four pass; the summary first failed on `nativeloader_sky_hour` `0.00` -> `0.000000` (the RTX tab's slider writing it back in `%f` form), now compared as numbers (`out\qa-poc\r5-release`) |
| PoC, modern_house | [`glass_debris_probe.lua`](../../tools/qa/glass_debris_probe.lua.md) | 36 pieces, all `COLLISION_GROUP_WEAPON`; four shots into the pile moved 7 and broke 3; none left after a 6 s lifetime (`out\qa-poc\r5-glass\01-glass-debris`) |
| PoC, the Evernight and March 7th pack mounted over the field's own settings files with the install records removed | Model Hotloader's scan (`out\tmp\takeover_probe.lua`) | Both models installed, `ownBefore`, labelled with the pack's title, the player's settings kept under `workshop/own` (`out\qa-poc\r5-takeover\01-takeover`; the PoC's state put back afterwards) |
| PoC, External Models at 1280x720 | The RTX normals checkbox | Under "Import Character Models". At this size, with the native release banner shown, the window's columns already overlap without the new row; it adds 34 px (`out\qa-poc\r5-takeover\02-layout`). Model Hotloader's layout, not changed |

One field run of eleven crashed at start: NVIDIA's `nvoglv64.dll` faulted on a worker thread of the
runtime compiling pipelines, 4 s after the device was created; the rerun was clean (RESEARCH.md, the
night sky section).

## Stability proposal

[R5-stability-proposal.md](R5-stability-proposal.md), research only (`dc2218b` on `r5-stability`,
merged): nothing is implemented. In short:

- **The attached dump is not the device loss.** It is the 2026-10-30 "Venti NPC" crash: system commit
  exhausted (46.74 of 46.74 GiB, GMod holding 11.44 GiB) while the engine read an NPC texture, with
  DLSS frame generation on.
- **The device loss (RTX 4060 Laptop, 8 GB) has no recorded cause**: Aftermath was off. The last
  warning was the opacity micromap cache at its budget, about 1 GiB of the 7188 MiB the driver gave
  the process. Leads: opacity micromaps, VRAM paging ending in a GPU timeout, frame generation.
- **Every GPU runs the RTX 5090 settings**: the package pins the Custom preset, which skips the
  runtime's own 8 GB rule (`rtx.lowMemoryGpu`), doubles the sky probe and quadruples the fog grid;
  the companion keeps 213 MiB of night sky images resident.
- **Found:** the loader's own Remix layer loses to the package's for `rtx.*` keys (the first entry of
  `DXVK_CONFIG_FILE` is the strongest), so ADR 0030's non-NVIDIA preset has most likely never applied;
  the rejected `rtx.resourceLimits.*` keys are sent by the RTX fixes module itself at every map load
  and never existed in the runtime; Remix truncates its log at the next start, and answering No at
  its crash prompt deletes its dumps.
- **Proposed first:** list the loader's layers first; an automatic low-VRAM layer for NVIDIA GPUs of
  8 GiB or less (`rtx.lowMemoryGpu`, a 512 MiB micromap cap, sky probe 1024, fog grid scale 8,
  terrain 2048); keep the last session's evidence at the next start; a one-start Aftermath switch;
  memory telemetry for testers. Six more and ten questions for the user are in the proposal.

## Open

- The stability proposal's decisions (its section 6), above all the layer order and the low-VRAM
  layer; nothing is implemented until the user chooses.
- Carry the Model Hotloader changes (`workshop.lua`, `ui.lua`, the catalogs) and the updated test into
  Model Hotloader's own repository.
- External Models overlaps at small window heights (1280x720 with the native release banner), with or
  without the new row: Model Hotloader's layout.
- Modern House RTX (hidden test item 3829275998) could run `NativeLoaderSkySet` itself, or skip its
  sun once the native loader's companion holds the sky; the companion's wrapper covers today's item.
- The Evernight and March 7th pack (3830769477): plain names and March 7th's terms, then upload again.
- The night sky image's galaxy band shows the Milky Way's core three times (the runtime wraps it).
