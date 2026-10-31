# recolour_skin.py

Recolour a skin sheet to a reference skin tone (made for Evernight, on the user's request).

The base tone (median of bright, low-chroma texels) of the source moves to the reference's in CIELAB
a*/b*; lightness is kept unless --match-lightness. Shading and blush keep --keep of their chroma
around the base, and texels far from skin (lips, nipples, red inner parts) take only part of the
shift, fading with their chroma distance from the base. Alpha is copied unchanged.

    python recolour_skin.py --src body.png --ref <ref folder or images> --out body_whitened.png         --pmx model.pmx --materials 0,1,2,3,4

With --pmx and --materials the source base is measured only where those materials' UV triangles
lie; without them the sheet's background fill counts too (Evernight's peach fill pushed the base
to b* 9.3 against 6.0 on the mesh, and the body came out cool). The result goes to a per-texture
"albedo_source" in the model's preset (README, "Recoloured albedo").

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in [tool/README.md](../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads the source sheet, the reference images and (optionally) the PMX; writes only the `--out` PNG. Body-skin work: run it only when the user asks (SKILL.md, ground rules).

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
