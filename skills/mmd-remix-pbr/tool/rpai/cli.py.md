# cli.py

Command line for Remix PBR AI.

python -m rpai run "E:\path\model.pmx"      hashes -> generate -> publish
python -m rpai hashes|generate|publish|remove "model.pmx"
python -m rpai status | doctor

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

`publish`/`run` accept `--emissive-adaptive-intensity R` (or the same top-level JSON field).
It is a ratio to the fixed USD intensity per scene luminance, default `25` (tuned in game,
[ADR 0069](../../../../docs/decisions/0069-tuned-adaptive-eye-emission.md)); `0` opts out.
Publish multiplies the existing normalisation scale and `--emissive-intensity` by `R`, and writes
that input only for emissive maps whose cached class coverage contains `sclera`, `eye` or
`highlight`. Every hash for that sheet receives it. Other emitters and entries with no class
coverage stay fixed. The final adaptive USD value must fit 0..65504. This reuses existing maps;
there is no AI or texture regeneration. See [standards](../../references/standards.md) for the
exposure-1 derivation and the in-game tuning. PMX/hash dependencies load when constructing the model context;
option parsing and offline publish tests need only the standard library.
Class-key presence is authoritative: cached coverage is rounded to four decimals, so a tiny eye
region whose recorded fraction is zero still receives the input.

## Side effects

The `rpai` command. Work files go to `RPAI_HOME\work\<model key>`; `publish` writes the game's `rtx-remix\mods\ai_pbr` (layers, DDS, an atomically rewritten `mod.usda`) and prunes DDS files no layer references unless `--no-prune`; `hashes`, `compare` and `generate` talk to the running game through `gamebridge.py`. It never writes `rtx.conf`, `user.conf` or `!advanced_material_editor`.

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
