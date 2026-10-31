# pbr_mod.py

Stages the **Remix mod folder** of a Workshop pack (`pbr_<name>`) from rpai's live mod (`ai_pbr`):
the named model layer(s), exactly the files they reference, and a `mod.usda` that lists only those
layers. The folder is the `--mod` input of `tools\package_content.py`, which deploys it to
`rtx-remix\mods\pbr_<name>`.

It is the fallback for `stage_pbr_mod.py` in the mmd-remix-pbr skill, which does the same job and is
the stager the current recipe names (Evernight and March 7th). This one is the earlier script
(Guinaifen, Robin), kept for when that skill is not at hand. Both copy only what the layers reference
and check every copy by SHA-256.

```powershell
$M = 'H:\SteamLibrary\steamapps\common\GarrysMod\rtx-remix\mods\ai_pbr'
$B = 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\packages\robin'
python -I scripts\pbr_mod.py $M robin_r18_f9c3e4b4 "$B\pbr_robin" "Robin" --dry-run   # what it would copy
python -I scripts\pbr_mod.py $M robin_r18_f9c3e4b4 "$B\pbr_robin" "Robin"
# two characters in one mod:
python -I scripts\pbr_mod.py $M evernight_cf3eec2f "$B\pbr_evernight_march7th" "Evernight and March 7th" --layer model_e2c25f9e
```

## Arguments

| Argument | Meaning |
|---|---|
| `src` | rpai's live mod, `<game root>\rtx-remix\mods\ai_pbr`. Read only |
| `key` | the rpai model key, the layer `models\<key>.usda` (`rpai status` lists them). The key may keep `r18`: it is a file name inside the mod, not a deployed folder |
| `out` | the mod folder to write; name it `pbr_<name>`, lowercase ASCII, no `r18` (a warning says so otherwise). Must not exist |
| `label` | the character's name for the `mod.usda` doc string (`"Robin RTX PBR (rpai layer ...), packaged for the Workshop."`) |
| `--layer KEY` | another layer in the same mod (repeatable) |
| `--dry-run` | list the layers, texture counts and sizes; write nothing |
| `--replace` | replace an earlier staged mod at `out` (a folder holding only `mod.usda`, `models`, `textures`) |
| `--allow-game-install` | allow `out` inside a game install. Only when the user asked for that |

## What it does

For each layer it collects every `@...@` asset path:

- a path starting with `../` is a file of the mod (the layer's DDS maps): it must stay inside the mod,
  be Remix data (`.usd .usda .usdc .usdz .dds .png .jpg .jpeg .tga .bmp .exr .hdr .mdl .json .txt`, what
  a content package may deploy) and an ASCII path (what the loader deploys);
- any other path must be a Remix shader (`.mdl`, such as `AperturePBR_Opacity.mdl`) and is skipped.

It copies the layer and those files with their times (`copy2`), compares each copy's SHA-256 with its
source, writes `mod.usda` (the header rpai and the earlier packs use: `lightspeed_layer_type =
"replacement"`, `metersPerUnit = 0.01`, `upAxis = "Z"`) and moves the folder into place
(built as `<out>.partial-<pid>`).

Output: `<n> textures (<MB> MB), <m> materials` (one line per layer, prefixed with its key when there
are several, and a total).

## Side effects

Writes only `out`. Refuses an `out` inside `src` (or the reverse), or inside a game install unless
`--allow-game-install`. Standard library only; runs with `python -I`.

## Exit codes

0 staged (or dry run done); 1 refused or failed (the reason on stderr, nothing left behind);
2 bad command line.

## Verified (2026-10-31)

Staging `robin_r18_f9c3e4b4` from the classic install's `ai_pbr` reproduced
`out\packages\robin\pbr_robin` byte for byte: 32 files, `mod.usda` included (30 textures, 386 MB,
17 materials).

## Provenance

Written for this user by Claude in the Guinaifen session (2026-10-29), given a label argument in the
Robin session (2026-10-30), tidied for this skill (2026-10-31: several layers, `--dry-run`, the
Remix-data and ASCII checks, atomic output, `--replace`, the game-install guard). Not third-party code.
