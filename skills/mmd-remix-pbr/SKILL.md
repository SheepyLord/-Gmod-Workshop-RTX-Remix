---
name: mmd-remix-pbr
description: Generate, tune, A/B-test and package RTX Remix PBR materials for MMD/PMX characters in Garry's Mod RTX (models imported with Model Hotloader), using the bundled rpai tool. rpai does AI upscaling plus normal and roughness maps (PBRify), material classes rasterised into UV space, anime-safe face and eye rules, live Remix texture hashes, a hot-reloaded ai_pbr mod, scripted in-game AABB tests and packaging. Use this whenever the user wants an MMD character or PMX model to look PBR in GMod RTX or RTX Remix, asks for normal, roughness, metallic or emissive maps or upscaled textures for a character, mentions rpai, ai_pbr, PBRify, Remix texture hashes or a Model Hotloader model, wants to tune how a character's cloth, metal, hair, skin, face or eyes look under path tracing, wants a before/after or A/B in game, or wants a character's PBR packaged, even if they never say "skill" or "rpai".
---

# MMD character PBR for RTX Remix (Garry's Mod RTX)

rpai turns an MMD character's diffuse-only textures into Remix PBR materials and hot-loads them into
the running game. It upscales each albedo with PBRify (DAT) up to 4096, generates normal and
roughness maps, and decides per texel what each surface is. It does that by classifying every PMX
material (cloth, metal, skin, face, iris…) and rasterising the classes into texture space, because
MMD sheets are shared atlases. Then it writes `over "mat_<HASH>"` layers into
`rtx-remix/mods/ai_pbr`, keyed by the texture hashes the game itself reports.

The tool lives in this skill: `tool/` (code, presets, README). Its runtime (venv, model weights, work
files) is `%USERPROFILE%\.rpai`. Read `tool/README.md` when you need the full method or option list.

## Ground rules from this user

- **Measure; don't eyeball.** The user builds Model Hotloader and the Advanced Material Editor, and
  wants numbers: before/after differences with a noise floor, patch values, and detail retention.
- **Standards change only with full-body evidence and the user's decision.** A skin change once
  looked good on limbs and was rejected because it faded body and neck detail. Run a full-body AABB
  (`references/testing-protocol.md`) and present the options. If nothing is accepted, revert to the
  original RTX Remix look.
- **Body skin changes are made and applied only when the user asks for them.** That covers anything
  that changes how body skin renders: `original: 0` or other skin-class overrides (globally or per
  texture), relief from the model's own normal maps on skin sheets, subsurface scattering,
  de-lighting, and the roughness of skin texels on shared sheets. Do not propose them as part of
  other work, and do not leave them applied after a test the user did not accept. When the user
  asks, build them as variants, run the full-body AABB and let the user choose. A tested look that
  is not (or no longer) wanted is kept, unapplied, in `tool/presets/on_request/` (never auto-loaded)
  and the per-model preset goes back to the standard. Guinaifen's body skin was tested on request
  and reverted at the user's request on 2026-10-25.
- **Do not get stuck debugging side issues.** When something unrelated blocks you (an addon quirk,
  a hung game), note it, take the evidence you have and move on. The user said so explicitly.
- **Leave their setup alone:**
  - never write into `rtx-remix/mods/!advanced_material_editor`;
  - ask before editing `rtx.conf` or `user.conf`, or downloading anything;
  - never restart the game.
  - Restore every scene change you make (camera hooks, hidden parts), and only those: the user may
    be changing the scene at the same time.
- **R18 models:** aim test views at the surface under test (neck and collarbones, abdomen, arms,
  legs). In these local debug and AABB sessions keep screenshots whole: never crop them, and never
  change morphs or part visibility to hide the model's base body (it is there for layered
  rendering). See the testing protocol.
- Explain plainly what changed and what it looks like, with the numbers.

## Setup check

```bash
"%USERPROFILE%/.claude/skills/mmd-remix-pbr/tool/rpai.cmd" doctor
```

`rpai.cmd` puts `tool/` on `PYTHONPATH` and runs the venv Python. From Git Bash, the equivalent is:

```bash
PYTHONPATH="$HOME/.claude/skills/mmd-remix-pbr/tool" "$HOME/.rpai/venv/Scripts/python.exe" -m rpai doctor
```

The doctor checks torch with CUDA, the PBRify weights, the NVTT exporter from the Remix Toolkit, and
whether the running game answers.

- **No venv?** `tool/setup.ps1` creates it and downloads the PBRify_Remix v1.7.2 weights (CC0,
  72 MB). Ask before running it, because it downloads.
- **Keep `RPAI_HOME` on a short path.** PyTorch DLLs fail with WinError 206 from long paths.

## Workflow for a character

1. **Scope.** Get the PMX path. Confirm with the user:
   - which textures are in scope;
   - the style: defaults, or `presets/aggressive.json` for a strong, clearly-PBR look on materials.
2. **The game.** The character must be spawned in Model Hotloader in the running game, so Remix has
   drawn its textures. Parts that are hidden (alpha-0 materials, morph-toggled overlays) get only
   predicted hashes until they are shown.
   - **Compiled addons.** A character can also be a QC compile of the PMX installed as a folder
     addon (sheepylord's ports: `models/sheepylord/<game>/<name>.mdl`), spawned as a ragdoll or
     prop. Find it in game (entity class and `GetModel()`), then pass `--mdl <model path>` once;
     rpai remembers it for that PMX. Its VMTs must be named like the PMX materials (README,
     "Compiled models"). `abtest.py --asset <model path>` frames it.
3. **Hashes.** Run `rpai hashes "<pmx>"`. Live hashes are authoritative. Predicted ones are a
   fallback and can be wrong (on Guinevere, 8 of 13 agreed). Note which textures are predicted.
4. **Texture review.** For a new character, follow `references/texture-review.md`. Check the class
   of every material and what every sheet contains, then create the per-model preset
   `tool/presets/models/<model key>.json`. It holds the style include, class pins (`_materials`),
   colour region rules (`regions`, for example painted gold → metal) and per-texture overrides:
   size, class presets for one sheet only, and a `normal_map` the model ships under any name
   (a flattened one with red = green is rebuilt). Note a shipped body normal map (such as
   `Body normal.png`) in the review, but use it on skin only when the user asks for skin work.
   Example:

   ```json
   {
     "doc": "What this model needs and why (keep the review notes here).",
     "include": ["../aggressive.json"],
     "presets": {"_materials": {"38": "metal", "45": "gem"}},
     "regions": [{"texture": "衣.png", "within": ["cloth"], "class": "metal",
                  "hue": [28, 58], "sat": [0.30, 1.0], "val": [0.50, 1.0], "doc": "gold trim"}],
     "textures": {"丝袜.png": {"max_size": "source"},
                  "衣.png": {"normal_map": "衣 normal.png", "presets": {"cloth": {"rough": 0.6}}}}
   }
   ```

   Body skin settings never go into this file on your own initiative (see the ground rules);
   `tool/presets/on_request/` holds tested skin looks, applied with `--settings` only on request.

   When one material holds several surfaces (Robin's single `Body` material: dress, skin, gold,
   crystals, shoes), classify whole UV islands: `"islands": 0.6` takes islands whose texels match
   the colours for that fraction, `"box"` limits them by where they sit on the body, and rules
   apply in order, each on the classes the earlier ones left. Shipped game normal maps (`_N`,
   `Normal`) go in `normal_map` with the sheet's classes at `normal` 1.0; rpai rebuilds z when blue
   holds something else and measures the green convention.

5. **Generate.** Run `rpai generate "<pmx>"`. The first run per texture costs minutes of GPU time
   (DAT upscale). The AI outputs are cached in `work/<key>/raw`, so re-tuning class values
   recomposes in seconds, and only textures whose classes changed are redone. Inspect
   `work/<key>/preview.jpg`, the class masks and `classes.json`.
6. **Publish.** Run `rpai publish "<pmx>"`. It encodes DDS with the Toolkit's NVTT settings
   (BC7/BC5/BC4), writes the layer and rewrites `mod.usda`, and the runtime hot-reloads.
   - Confirm "Async reloaded USD data swapped in successfully" in `rtx-remix/logs/remix-dxvk.log`
     (runtime `384581b1`). Runtime `c6b48ed1`, in use since 2026-10-25, logs no reload line; check
     in game instead (`references/runtime-notes.md`).
   - A brand-new mod folder needs the user to click Alt+X → Enhancements → Loaded USD Files →
     "Rescan Mods & Reload USD Stage" once.
   - `rpai run "<pmx>"` does hashes, then generate, then publish.
7. **Show the result.**
   - `rpai compare "<pmx>"` toggles the model's layer from the user's current camera and saves a
     before/after.
   - For tuning or standards, use the AABB rig (`scripts/abtest.py`, below). Quote changes against
     the floor-corner or repeat noise.
8. **Iterate** on the per-model preset. `--settings extra.json` merges before the per-model preset,
   so the model preset wins.
9. **After a game restart, or before packaging,** re-run `rpai hashes` with the model spawned. The
   same texture can upload with a new hash in a new session, and rpai keeps every hash it has seen.

## Standards (defaults in `tool/rpai/classify.py`)

Details and evidence: `references/standards.md`. In short:

- **Materials:**
  - cloth 0.78 / normal 1.44, leather 0.42 / 1.12, stockings 0.55, rubber 0.22, hair 0.40;
  - metal 0.28 with metallic 1, gem 0.05;
  - `aggressive.json` pushes these (cloth 0.55 / 2.6, leather 0.20 / 2.0, metal 0.12…) and never
    touches skin or the face.
- **Gold type per character** (user request, 2026-10-26; table in `references/standards.md`):
  painted gold has low reflectance (F0 0.17-0.55), and polished at 0.12 it mirrors a dim room as
  dark bronze (Robin ZZZ's halo −37% in game). Painted golds get a satin metal in the per-model
  preset (0.30-0.36); bright silver and tiny jewelry stay polished. Measured on Robin R18: satin
  halves the darkening (gold −19% to −25% against −37% to −45% polished) with the same highlight
  peaks, and adding `"f0": 0.74` (real gold's reflectance) brings the gold to −10%..+4% of the
  original brightness, with a paler halo; Robin R18 uses it (measured) and Robin ZZZ too (same
  art, unmeasured), the others are not lifted. For a new
  character, measure its metal F0 on the mesh and pick the type the same way.
- **Face and eyes (anime-safe):**
  - face and mouth (teeth, tongue) 0.60, flat; lashes, brows and eyeliner 0.85;
  - eye white 0.25 with emission 0.025; iris 0.06 with emission 0.04;
  - catchlight mesh emission 0.6;
  - `--emissive-intensity` re-levels all eye emission at publish time, with no regeneration.
- **Body skin: left as Remix renders it** (`original: 1`). A skin-only sheet gets no override; skin
  on a shared sheet gets roughness 0.7, flat, original colours. De-lighting (`delight`) is opt-in
  only, and subsurface scattering (`sss` class field) is not standard: on runtime `c6b48ed1` it
  streaked thin limbs and left a seam where skin is split across materials. Relief from a model's
  own body normal map is available **on request only** (Guinaifen's tested recipe and evidence:
  `tool/presets/on_request/new_mmd_model_1c2ed2fc_body_skin.json`).
- AI relief and AI roughness variation are off on skin and the face classes: the AI finds nothing
  there except painted lines.

## Commands

| Command | What it does |
| --- | --- |
| `rpai run "<pmx>"` | hashes → generate → publish |
| `rpai hashes` / `generate` / `publish` / `compare` / `remove` | single steps (each takes the PMX path) |
| `rpai status`, `rpai doctor` | published models / installation check |
| `--mdl models/.../x.mdl` | the character is a compiled addon, not a Model Hotloader import (remembered) |
| `--asset 1c2ed2fc` | use this Model Hotloader import for the PMX (a re-import whose source folder is gone, rebuilt from a byte-identical copy) |
| `--only "衣.png,髪.png"` | limit to some textures |
| `--force` | redo the AI stage too |
| `--settings f.json` | extra settings, repeatable |
| `--no-prune` | keep old DDS files (variants, A/B) |
| `--emissive-intensity 0.7` | eye emission level |
| `--no-live` | skip the in-game query (earlier verified hashes are kept) |
| `--max-size`, `--upscaler span` | size cap; faster, softer upscale |
| `--height --displacement 0.03` | height maps for POM (off by default) |
| `python scripts/abtest.py bones --asset <id8>` | spawned entity and bone positions |
| `python scripts/abtest.py capture ...` | AABB capture of variant layers (restores everything after) |
| `python scripts/abtest.py metrics <run> --baseline A` | noise, change, detail-kept tables and comparison sheets |
| `python scripts/package_characters.py --dest <dir> --character name=key[=pmx] ...` | package characters |
| `python scripts/recolour_skin.py --src <sheet> --ref <images> --out <png> --pmx <pmx> --materials 0,1` | skin tone matched to a reference (on request only), used through a per-texture `albedo_source` |

Run the scripts with the rpai venv Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`). They put
`tool/` on the path themselves. The model key is `<english name slug>_<asset id[:8]>`; `rpai` prints
it, and the asset id prefix is its last 8 characters.

## Testing in game

Use `references/testing-protocol.md` for anything beyond a quick compare. Essentials:

- **Variants are complete model layers.** Build them with `generate --settings variant.json` and
  `publish --no-prune`, copying the layer after each. Swap them with `abtest.py capture`, which waits
  for the Remix swap and shoots each view twice back to back ("AABB"), so every effect comes with
  its own noise floor.
- **Views come from bone names.** Write a `views.json` with a target bone, target offset, camera
  offset, fov and an optional crop for the sheets. Camera control is a client `CalcView` hook.
- **Hide parts only via `mmdhl.SetMaterialVisible`** (`--hide 7,8,44`). If a part stays invisible
  while its flags say visible, check material morphs (for example `[Fullbody]`) instead of
  debugging further.
- **Present** the sheets and metrics, then ask with options that each carry their measured trade-off.

## Publishing for 8 GB GPUs

Characters meant for players with **8 GB GPUs are published with `--max-size 2048` into a separate
`--mod`**, such as `ai_pbr_2048`. Apply the cap while generating, then publish that output:

```bash
rpai run "<pmx>" --max-size 2048 --mod ai_pbr_2048
# Or, with hashes already checked:
rpai generate "<pmx>" --max-size 2048 --mod ai_pbr_2048
rpai publish "<pmx>" --max-size 2048 --mod ai_pbr_2048
```

`publish` encodes the existing generated maps; adding the flag only at publish time does **not**
resize an earlier 4096 px generation. Check per-texture `max_size` overrides (including `"source"`)
before generating the 8 GB variant: they can lift the global cap. Publishing replaces the model's
layer and prunes unused DDS files in that mod, so publishing the 2048 variant into the larger
variant's mod would remove its textures. Keep the larger variant in its own mod and stage/package
from `rtx-remix/mods/ai_pbr_2048` (pass `--mod ai_pbr_2048` to `package_characters.py`). Verify the
DDS dimensions referenced by the packaged layer are at most 2048 px. Install one variant at a time
when they override the same hashes.

At the same format and mip count, a 4096 x 4096 map has four times the pixels and approximately
four times the fully resident memory of a 2048 x 2048 map. With a full mip chain, BC7 albedo or BC5
normals cost about **21.3 MiB at 4096** versus **5.3 MiB at 2048**; BC4 roughness costs about
**10.7 MiB versus 2.7 MiB**. These are size calculations, not measured savings: residency depends
on streaming and the runtime's budget. Each sheet can carry several maps, and the original game
textures still have their own cost. Do not rely on the loader's low tier to make a large published
pack inexpensive for every player.

## Packaging

When asked to package characters, ask where (they chose
`H:\BACKUP_20260815\Modding\ipg\!GMRTX_PBR_Test` before), then run
`scripts/package_characters.py`. It writes:

- a drop-in mod with only the referenced DDS files and a `mod.usda` listing just those layers;
- per character: maps, AI cache, masks, settings, hashes and previews;
- a copy of the tool;
- a README, and a verification that every referenced DDS matches the live mod.

Add character-specific notes (decisions, left-to-Remix sheets) to its README.

### A Workshop item (model + enhancements, private test)

First done for Evernight + March 7th, 2026-10-30, as Guinaifen and Robin were before. The native
loader repo (`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix`) loads such items: a content package, no
allowlist needed (its ADR 0027). Only on the user's request; keep the item private/hidden.

1. **Game up**, in a map, Model Hotloader loaded, the models in its library. Re-check the hashes with
   the models spawned (`rpai hashes`; they were identical across sessions) and `rpai publish` if any
   changed. For an 8 GB audience, generate and publish the 2048 px variant into `--mod ai_pbr_2048`
   as above before staging it; keep that flag on subsequent publishes of this variant.
   Spawn and remove them yourself with `mmdhl.RequestSpawn(id, {}, cb)` and
   `lua_run Entity(idx):Remove()` if the user has not; remove only what you spawned.
2. `scripts/hotloader_export.py --game-root <GarrysMod> --asset <id8> ... --title ... --description-file ...
   --file-name <n> --tag cartoon --out <dir>\mmdhl_<n>`: the library's Export without its terms dialog
   (private items only), unpacked to an add-on folder (`addon.json` + `data_static\mmdhl`).
3. `scripts/stage_pbr_mod.py --src <GarrysMod>\rtx-remix\mods\ai_pbr_2048 --dest <dir>\pbr_<n> --layer <key> ...`:
   the 8 GB variant's referenced DDS, SHA-checked, plus `mod.usda`. For a different audience, use
   the separate mod holding its chosen variant.
4. In the repo, no `-I`: `python tools\package_content.py --id <n>-rtx --name ... --addon <dir>\mmdhl_<n>
   --mod <dir>\pbr_<n> --title ... --type model --tag cartoon --description ... --gma <dir>\<n>-rtx.gma --link`;
   then `nlctl manifest` and `nlctl verify` (the main checkout's `out\build\win64-release\loader\cli`).
5. A 512x512 `icon.jpg` (the two faces from tuned shots; keep it free of adult content), then from a game
   root with `steam_appid.txt` (the repo's `workshop.json` names the PoC's): `gmpublish.exe create -addon
   <gma> -icon <jpg>`. The item starts hidden. Log it, subscribe through steam_api (as the Modern House
   test did), and read the download back.
6. Record the item in the repo (`docs/handover`, CHANGELOG) when the user asks; never make it public.

The full packing procedure, the dependency model, the description template with Required items, the
offline fallback packers and the pitfalls of the earlier packs are in the sibling skill
`workshop-content-pack` (in the native loader repository: `skills/workshop-content-pack/SKILL.md`).

## Runtime caveats (details: `references/runtime-notes.md`)

- **The runtime is a fork** (sambow23/dxvk-remix-gmod, remix-main+384581b1) that rejects every
  colour-valued USD input (`color3f`/`float3`…). Colours must come from textures. rpai writes only
  bools, floats and textures for that reason.
- **Subsurface scattering works only under two conditions:** the material forced opaque
  (`use_legacy_alpha_state = 0`, `blend_enabled = 0`), and the skin colour given as
  `subsurface_transmittance_texture`. Otherwise skin turns near-black. `radius_scale` must stay at
  0.5 or above.
- **Remix hot-reloads only on a `mod.usda` timestamp change.** Mod priority by path:
  `!advanced_material_editor` < `ai_pbr` < `~gmod_topbr`.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| A texture shows no change in game | Its hash is predicted or stale. Spawn and show the part, run `rpai hashes`, then `rpai publish`. Check whether another model's layer wins a byte-identical sheet (publish prints a note) |
| "the game window did not accept the console message" | The game is loading or hung. Wait once; `hashes` falls back to earlier verified hashes. Don't loop or restart it |
| WinError 206 loading torch | The venv is on a long path. Keep `RPAI_HOME` short (`%USERPROFILE%\.rpai`) |
| New mod folder not loaded | The user must do Rescan Mods once (Alt+X menu), or restart the game |
| Skin or eyes look grey or dirty in sockets | Expected from path tracing. Eye white and iris emission handle the eyes; skin stays original by decision |
| Part invisible though its visibility flags say visible | A material morph (for example `[Fullbody]`) is hiding it. Leave it; it is the user's setting |
| "doesn't fit into STAGING memory" in the Remix log | Harmless for sheets over 96 MB (Firefly's 11059×8847 stockings) |
| Colour constant ignored ("has unexpected type") | Fork limitation; use a texture input |
| Thin crease or "normal slit" along UV seams (sides of stockings, sleeves) | The AI read island borders as relief. Fixed by gutter padding (`compose.gutter_fill`); maps generated before 2026-10-25 still have it, so run `generate` again (the upscale cache is kept) |
| Same slit down the sides of the body with a model's own `normal_map` | The map's bake padding does not match the UV borders, and front and back halves are rebuilt separately. `relief_normals` continues the island edge's slope outward and fades the relief to flat over the last 12 texels of each island (RELIEF_VERSION 3) |
| A compiled model turns (almost) invisible after publish | Its VMTs alpha-test at 0.5 and the PMX images carry a mask in alpha (Wuthering Waves `_D` toon masks, mean 0.2-0.4); the published albedo keeps that alpha. Point the PMX at RGB copies and republish (README, "Compiled models"; Hiyuki Alt skin 1, 2026-10-27) |

## Done criteria for a character

- `rpai status` lists the model.
- The Remix log shows the swap.
- A compare or AABB result with numbers has been shown to the user.
- Predicted-only textures are named.
- Any new decision is recorded in the per-model preset `doc` field, and, for standards, in
  `references/standards.md` and the `classify.py` comments.
