# R11: automatic PBR (report)

[Plan](R11-plan.md); Codex's report [R11-A](R11-A-report.md); ADRs [0091](../decisions/0091-automatic-pbr-fallbacks.md)
and [0092](../decisions/0092-generated-fallback-mods-rank-last.md).

The user's items: **32**, imported Wuthering Waves, Arknights: Endfield and Silver Palace characters'
packed PBR maps detected and applied in RTX with the aggressive look, with a setting; **34**, the
fixes' ToPBR ("autopbr") validated, more robust for vanilla Source materials and closer to the RTX
look; and the note on 34: "actual PBR replacements, if exists, should always overwrite the autoPBR
result." Codex was restarted a few minutes in to carry the note.

## What Codex built (R11-A)

- **Imported game PBR:** for a Model Hotloader character whose source folder is known
  (`sources.local.json`), the maps beside its PMX are found by the games' suffixes and stems, checked,
  unpacked (RG normals with rebuilt Z in the right green convention; Silver Palace `_MRA`; Endfield `_P`
  metallic, smoothness to roughness, AO, and `_E` emission; Wuthering Waves normals only, its toon masks
  left alone) and published through ToPBR, keyed by the hotloader's texture. What a game does not ship
  follows `aggressive.json`; skin, face and eye texels stay protected, faces get no generated material
  (so R10's eye-white aliases keep working). `rtx_topbr_game_maps` (default 1), "Imported game PBR" in
  the RTX menu's character options, translated.
- **ToPBR:** client work bounded (one snapshot a frame; VMT reads, companion probes, decoding and writing
  on a worker), content-keyed DDS reuse with full validation, atomic USD snapshots that disabling
  retracts, Phong to perceptual GGX roughness, no metal from darkness, commented VMT properties off by
  default, the broken diagnostics fixed. Measured on the PoC: client inspection 23.553 ms to 0.830 ms;
  no steady frame cost on gm_construct, gm_flatgrass and d1_canals_01. World conversion stays opt-in.
- **Precedence in the fixes:** a guard skips every material hash found in other mods' USD and retracts
  late conflicts; an unreadable mod (binary USD, reparse points, scan limits) suppresses generated output.
  Codex measured a late authored pack winning 0.8 s after it was written, and left the absolute rule to
  the runtime, outside its scope.
- The fixes DLL rebuilt from `codex/r11-autopbr` (`7094baf` + three commits), 5,060,608 bytes,
  SHA-256 `c4833fc1...`, imported with the ToPBR Lua driver, file by file; the GPL sources with it in
  `packages/fixes/licenses/oversized-skinning/autopbr`.

## Review and the runtime rule (Claude)

- **Runtime patch 0020** (ADR 0092): mods listed in `rtx.gmod.fallbackMods` (default `~gmod_topbr`) get
  priority 1, so every authored mod wins over ToPBR's materials whatever its folder name, also when it
  loads or reloads later; their search paths come first. Unit test `test_fallback_mods`; with
  `test_eye_whites` and `test_mmd_alpha` 3/3 pass. Built in R10-E's tree and imported once: `d3d9.dll`
  SHA-256 `f76c316a...` (HEAD `f8b42e63`, base + 0001-0020).
- **The rule in game** (PoC, `out/r11-qa/precedence_driver.py`): two test mods, a listed fallback
  `~zz_r11_fallback` and an authored `ÿ_r11_authored` (sorting after `~`), both empty at start; during the
  session blue into the fallback, then red into the authored mod, then the authored mod emptied, each
  hot-reloaded, on `brick/brickwall003a_construct`. Mean colour of the 3,501 pixels the material covers:

  | Run | fallback only | authored added | authored emptied |
  |---|---|---|---|
  | `rtx.gmod.fallbackMods` lists the fallback | blue (8, 39, 126) | **red (80, 27, 34)** | blue (8, 38, 125) |
  | control: option empty (name order) | blue | blue | blue |

  The control is the old failure: by name, the fallback beat a pack named after `~`.
- **Characters on the final package** (Codex's probe, runtime 0020): Baizhi, Akekuri and Alf got 4, 6 and
  13 generated materials with the setting on and 0 off; on/off difference 4.2, 3.1 and 3.4 against a
  repeat noise of 0.9-1.3; Robin (a pack) 1.9, near noise; eye whites still `applied=2`; client snapshot
  0.000 ms, worker jobs up to 1.6 s off the frame; normal quit, no Lua error.
- Visual check of Codex's close-ups: no inverted normals, black metal or touched faces.

## Limits

- **The source folder must still exist.** All five Wuthering Waves and Silver Palace characters in the
  field library came from a `Desktop\test_models` folder that is gone (25 of the 45 recorded sources still
  exist), so they keep their old look; characters imported from `E:\G\Upload` are covered.
- World ToPBR stays opt-in: real ExoPBR/GPBR/BFT content was not found to render-test, and the user's
  maps and add-ons were not all checked.
- An unreadable mod (binary USD) still suppresses all generated output (a coverage limit; precedence is
  the runtime's now).

## Merge, publish and field

- `tools\test.ps1 -Config Release` on `r11-autopbr`: 26 of 26 CTests, the Python suites (500, 28 and 25
  tests), "All checks passed". `main` fast-forwarded to `78d06b3`; the merge published Workshop item
  3829070317 as `0.0.0-dev.20261102210333+f497f506`, content digest `066ea889...`, the package checked on
  the PoC. Pushed `60ff5f6..78d06b3` with the runtime's and the fixes DLL's Git LFS objects (60 MB).
- Field (the user idle, the user's add-ons): start 01 ran the R10 package while Steam fetched R11; start
  02 deployed it (250 changes) and ran runtime `0.0.0-dev.20261102210333+f497f506`. ToPBR initialised and
  published 0 automatic materials against the 1,640 authored hashes of the user's mods (world conversion
  off, no imported game character spawned); normal quit, no Lua error.
- The field player's archived `rtx_topbr_parse_commented_properties 1` (the old default) is kept: the new
  default 0 reaches new players. It matters only with world ToPBR on.

