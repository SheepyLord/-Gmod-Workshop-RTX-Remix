# sourcemodel.py

Compiled Source models (.mdl) as input, beside Model Hotloader imports.

Some characters reach the game as a compiled addon (a QC compile of the PMX:
``models/<path>.mdl`` with VMT/VTF materials, e.g. sheepylord's ports) rather
than through Model Hotloader. The PMX still holds the UVs, material names and
original images, so only the link from a PMX material to the game's texture
changes: the MDL lists its materials and their folders ($cdmaterials), each
VMT names its $basetexture, and that VTF is what Remix hashes. The compile
names its materials after the PMX ones, so they are matched by name (Robin,
robin_zzz.mdl, 2026-10-25: 11 of 11).

Garry's Mod mounts legacy folder addons over ``garrysmod/``, so files are
looked up in the MDL's own addon first, then in every other folder addon,
then in ``garrysmod/`` itself.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads compiled models and their VMT/VTF files; remembers a PMX's `--mdl` in a small JSON registry under `RPAI_HOME`.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
