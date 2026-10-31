# __init__.py

Remix PBR AI: generate and upscale PBR textures for RTX Remix replacements.

The pipeline reads a PMX model, finds the Remix texture hashes of its
textures in a running Garry's Mod RTX session, runs AI upscaling and PBR map
generation, and publishes the result as a hot-reloadable Remix mod.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

None (package marker).

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
