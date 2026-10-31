# cli.py

Command line for Remix PBR AI.

python -m rpai run "E:\path\model.pmx"      hashes -> generate -> publish
python -m rpai hashes|generate|publish|remove "model.pmx"
python -m rpai status | doctor

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

The `rpai` command. Work files go to `RPAI_HOME\work\<model key>`; `publish` writes the game's `rtx-remix\mods\ai_pbr` (layers, DDS, an atomically rewritten `mod.usda`) and prunes DDS files no layer references unless `--no-prune`; `hashes`, `compare` and `generate` talk to the running game through `gamebridge.py`. It never writes `rtx.conf`, `user.conf` or `!advanced_material_editor`.

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
