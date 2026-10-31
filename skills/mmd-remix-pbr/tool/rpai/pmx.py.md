# pmx.py

Minimal PMX 2.0/2.1 reader.

Only what texture work needs is decoded: UVs, vertex positions (to tell where
a UV island sits on the body), triangles, the texture table and the materials
(with their face ranges, sphere maps and flags). Bones, morphs and physics are
skipped over, never parsed.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads a PMX file; writes nothing.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
