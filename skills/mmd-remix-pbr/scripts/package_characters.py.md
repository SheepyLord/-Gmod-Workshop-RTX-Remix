# package_characters.py

Package published rpai characters into a folder for reuse.

    python package_characters.py --dest "H:\path\to\package" ^
        --character guinevere=new_mmd_model_9cdc990f="E:\...\桂乃芬.pmx" ^
        --character hyacine=hyacine_r18_6ca2dcc3

Layout:
    remix_mod/<mod>/       drop-in Remix mod: mod.usda (only the packaged layers), models/*.usda and
                           exactly the DDS files those layers reference
    characters/<name>/     maps/ (final PNGs), raw/ (AI cache), masks/, classes/hashes/generated.json,
                           preview.jpg, compare_*.jpg, preset.json (per-model settings, when present)
    tool/                  a copy of rpai (skip with --no-tool)
    package.json, README.md

The destination must be empty or new, unless --update is given. Every referenced DDS is checked
against the live mod after copying.

Published USD layers are copied and checked **byte for byte**, preserving all shader inputs,
including `emissive_adaptive_intensity` and the older-runtime `emissive_intensity` fallback.
The generated README explains both modes. Packaging does not add or tune emission: publish the
desired ratio first, or use [set_adaptive_emission.py](set_adaptive_emission.py.md) on a staged mod.
The Python entry point also accepts an argument list for offline tests.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in [tool/README.md](../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads the live `ai_pbr` mod, rpai's work folders and presets; writes only `--dest` (empty or new, unless `--update`), then checks every copied DDS against the live mod.

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
