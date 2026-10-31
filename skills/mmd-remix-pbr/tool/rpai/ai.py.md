# ai.py

Tiled inference for PBRify (ESRGAN-family) models through spandrel.

Tiles overlap and are blended with linear feathering, so seams never show in
the generated maps. Inference runs in fp16 when the architecture supports it
and falls back to fp32 if a tile produces non-finite values. A CUDA
out-of-memory error halves the tile size and retries - the game and the Remix
Toolkit usually hold most of the GPU while this runs.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

GPU inference in memory; reads model weights from `RPAI_HOME\models`; writes no files.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
