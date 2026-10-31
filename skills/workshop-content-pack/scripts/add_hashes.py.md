# add_hashes.py

Adds Remix texture hashes to an rpai layer, and checks which live hashes a layer or a whole mod
covers.

Remix keys a replacement material by the hash of the texture the game uploads (`over "mat_<HASH>"`).
The same sheet can upload with another hash in another session or install: on 2026-10-29 the user's
fresh import of Guinaifen uploaded the face sheet (`灰.jpg`) and the mouth (`sita.png`) with new hashes,
and those sheets lost their PBR until the packaged layer had both. Adding copies the sheet's block
under the new hash, right after the old one, and keeps the old block.

Prefer the upstream fix when the game is running: spawn the model, `rpai hashes`, `rpai publish`, stage
the mod again (rpai keeps every hash it has seen). Use this script on a layer that is already staged.

```powershell
$L = 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\packages\guinaifen\pbr_guinaifen\models\new_mmd_model_1c2ed2fc.usda'
python -I scripts\add_hashes.py $L A35D6E8412838268=37B3BC9B48184AA9 6CD8A24E251A7BE3=84168AFC8CF54915 --dry-run
python -I scripts\add_hashes.py $L A35D6E8412838268=37B3BC9B48184AA9 6CD8A24E251A7BE3=84168AFC8CF54915

# which live hashes rpai recorded does the package cover?
python -I scripts\add_hashes.py H:\...\out\packages\robin\pbr_robin --check-json "$env:USERPROFILE\.rpai\work\robin_r18_f9c3e4b4\hashes.json"
# and which of them only another character's layer covers, on this machine (every mod of the install):
python -I scripts\add_hashes.py H:\SteamLibrary\steamapps\common\GarrysMod\rtx-remix\mods --check-json "$env:USERPROFILE\.rpai\work\robin_r18_f9c3e4b4\hashes.json"
```

## Modes

| Mode | What it does |
|---|---|
| `<layer> OLD=NEW ...` | for each pair: when the layer has no `mat_NEW`, copy the `over "mat_OLD"` block (from its line to the closing brace at the same indentation) as `mat_NEW` right after it. `--dry-run` reports only; `--backup FILE` copies the layer to FILE first (FILE must not exist). Writes through a temporary file, LF line ends |
| `<layer or mod> --list` | every material hash with the first texture it references |
| `<layer or mod> --check HASH ...` | for each hash, the layers that have it, or `MISSING`; exit 1 if one is missing |
| `<layer or mod> --check-json hashes.json [--key KEY] [--strict]` | reads rpai's `work\<key>\hashes.json` (live and predicted hashes per texture) and `generated.json` (which sheets got PBR maps: beside it, or in `work\<KEY>\` for a re-import's hashes). For each live hash: `ok` (in the model's own layer), `only in <other layers>`, `MISSING: the sheet has maps but no material for this hash` (a defect: add it), or `left to Remix (no maps)` (body skin, or a sheet rpai left to another character). Textures with predicted hashes only are listed with the layers that have those. Exit 1 on a MISSING (with `--strict`, also on `only in`) |

Hashes may be written `0x37B3BC9B48184AA9`, `37b3bc9b48184aa9` or `mat_37B3BC9B48184AA9`. A mod
folder means every `models\*.usda` in it; a mods folder (`<game root>\rtx-remix\mods`) every
`<mod>\models\*.usda` below it, reported as `<mod>:<key>` (rpai's `ai_pbr` and the deployed packs
alike). `--key` names the model's own layer (default: the folder name of `hashes.json`, which is the
rpai model key); in a mods folder any `<mod>:<key>` counts as its own.

## Side effects

Adding rewrites the given layer only (and writes `--backup` if given). It refuses a layer inside a game
install (rpai owns `ai_pbr` and overwrites edits at the next publish) unless `--allow-game-install`.
The other modes only read. Standard library only; runs with `python -I`.

## Exit codes

0 done (checks passed); 1 refused, failed, or a check failed as described above; 2 bad command line.

## Verified (2026-10-31)

- Adding the two Guinaifen pairs to the layer as it was before the fix
  (`out\packages\guinaifen-layer-v1.usda`, 16 materials) gave a file byte-identical to the published
  fixed layer (18 materials). A second run reports `already there`.
- `--check-json` on Robin's recorded hashes against the classic install's live `ai_pbr` reproduced the
  Robin session's finding: four live hashes (bq, the ropes, 口球, Blindfold Text) are only in other
  characters' layers, and three more sheets (黑, 颜赤, sita) have only predicted hashes, also found in
  other layers. Against the field install's whole mods folder the same four are covered by the
  deployed Guinaifen and Evernight packs (`pbr_guinaifen:new_mmd_model_1c2ed2fc`,
  `pbr_evernight_march7th:evernight_cf3eec2f`), and Evernight's `bq.png` by Guinaifen's.
- On the user's re-import of Guinaifen (`work\new_mmd_model_bf8aee59\hashes.json`, `--key
  new_mmd_model_1c2ed2fc`): the published layer covers all 11 live hashes with maps, Body.png is left
  to Remix; the layer before the fix misses the two sheets.

## Provenance

Written for this user by Claude in the second Guinaifen session (2026-10-29); tidied for this skill
(2026-10-31: indentation-aware block matching, hash spellings, `--dry-run`, `--backup`, atomic write,
the game-install guard, and the `--list`, `--check` and `--check-json` modes). Not third-party code.
