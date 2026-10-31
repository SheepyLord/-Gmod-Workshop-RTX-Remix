# compose.py

Turn one albedo texture into Remix-ready PBR maps.

1. Albedo: the original image from the PMX folder (never the game's VTF), AI
   upscaled when it is smaller than ``max_size``. A low-frequency colour fix
   puts the source's colours back under the AI detail, as PBRify's
   "Color Fix" chain does, so painted anime colours do not drift.
2. PBRify generates DirectX tangent-space normals, roughness and height from
   the albedo at the final size.
3. The texture-space class map scales each generated map per texel: base
   roughness and metallic come from the class, the AI roughness keeps only its
   local variation, normal strength fades to flat on faces and eyes. Classes
   with an ``emissive`` weight (iris, eye white, highlight) get an emissive
   map: the albedo's own colour times that weight. Classes with ``delight``
   (skin) have the shading painted into the albedo softened (``delight()``).
4. Normals are re-encoded as Remix's hemispherical octahedral format.

Steps 1-2 are cached in ``work/<model>/raw``, so changing class parameters
re-composes in seconds instead of re-running the upscaler (minutes per sheet).

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Writes the generated maps under the model's work folder (`raw/` cache and final PNGs) and removes stale cache files of the texture it recomposes.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
