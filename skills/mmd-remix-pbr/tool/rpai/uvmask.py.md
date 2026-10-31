# uvmask.py

Rasterise PMX material classes into texture space.

Every material's UV triangles are drawn into a class-id image the size of the
generated maps, lowest priority first (classify.PRIORITY), so the texels of a
shared atlas learn which kind of surface they belong to. Texels no triangle
covers take the nearest covered class, so mip levels and bilinear filtering
never pull in an unrelated default along island borders.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

None: rasterises classes in memory.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
