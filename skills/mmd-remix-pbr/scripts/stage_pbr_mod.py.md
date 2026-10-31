# stage_pbr_mod.py

Stage the Remix mod folder of a Workshop character package from the live ai_pbr mod.

Copies only the DDS files the named layers reference, checks every copy by SHA-256, copies the
layers and writes a mod.usda that lists them. The folder is the --mod input of package_content.py.

    python stage_pbr_mod.py --src <GarrysMod>\rtx-remix\mods\ai_pbr --dest out\packages\x\pbr_x ^
        --layer evernight_cf3eec2f --layer model_e2c25f9e --doc "X RTX PBR, packaged for the Workshop."

Layer names are the rpai model keys (`rpai status` lists them). The destination must not exist.
Nothing is written outside it.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in [tool/README.md](../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads the live `ai_pbr` mod; writes only `--dest`, which must not exist yet: the named layers, exactly the DDS files they reference (each copy checked by SHA-256) and a `mod.usda` listing them.

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
