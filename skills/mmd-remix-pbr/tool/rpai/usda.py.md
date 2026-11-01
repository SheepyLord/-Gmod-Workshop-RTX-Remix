# usda.py

Write the Remix replacement mod.

Layout under ``rtx-remix/mods/<mod>/``::

    mod.usda                 root layer; one sublayer per model
    models/<model>.usda      ``over "mat_<HASH>"`` shader inputs
    textures/<model>/*.dds   content-named, never overwritten in place

The runtime watches only the root file's modification time
(``UsdMod::Impl::haveFilesChanged``), so every publish rewrites ``mod.usda``
atomically, which triggers its async reload. A brand-new mod folder is only
discovered by the Remix menu's "Rescan Mods & Reload USD Stage" or a restart.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

`material_block(..., emissive_adaptive_intensity=A)` accepts an optional literal adaptive intensity.
For an emissive map it writes `float inputs:emissive_adaptive_intensity` beside the unchanged fixed
`emissive_intensity`; with no emissive map neither emission input is written. `None` omits the new
input, and `0` writes an explicit opt-out. `check_adaptive_intensity` rejects values outside the
runtime's finite 0..65504 range. Adaptive values use nine significant digits.

`write_model_layer` accepts `(hash, maps, fallback[, subsurface[, adaptive]])` tuples; the old
three/four-field tuples still work. The publisher decides which maps carry eye classes and
calculates the final adaptive value; this writer does not infer classes from texture filenames.

## Side effects

Writes the Remix mod under `rtx-remix\mods\<mod>`: `models\<model>.usda`, content-named DDS (never overwritten in place) and an atomically rewritten `mod.usda`, which makes the runtime reload.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
