# hotloader.py

Read Model Hotloader's cache to learn how a PMX appears inside the game.

Model Hotloader imports a PMX into ``garrysmod/data/mmd_hotloader/assets/<id>/``:
a manifest, the PMX copy and a GMA with one VMT per PMX material
(``materials/mmd/<id16>/<name>_<index+1>.vmt``) and one uncompressed VTF per
unique base texture (``materials/mmd/t/<sha16>.vtf``). Remix hashes the GPU
texture, so every PMX material sharing a texture file shares one Remix hash.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads Model Hotloader's cache (`garrysmod\data\mmd_hotloader\assets`); writes nothing.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
