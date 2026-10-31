# hotloader_export.py

Export Model Hotloader characters as a Workshop package add-on folder, through the running game.

It does what the library's Export dialog (lua/mmdhl/workshop_export.lua) does, with the same item
settings (spawn preset, body groups, arms, fits, terms-of-use records) and the same native call
(StartPackageExport), then unpacks the archive Model Hotloader writes into an add-on folder
(addon.json + data_static/mmdhl/...) that package_content.py takes as --addon.

    python hotloader_export.py --game-root <GarrysMod> --asset cf3eec2f --asset e2c25f9e ^
        --title "Evernight and March 7th (Model Hotloader + RTX PBR)" --description-file desc.txt ^
        --file-name evernight-march7th --tag cartoon --out out\packages\x\mmdhl_x

--asset takes the full 64-digit id or any unique prefix. The game must be in a map (client Lua
runs there) with Model Hotloader loaded; the models must be in its library (not shared ones).

The export dialog asks the player to acknowledge the models' terms of use first
(mmdhl_terms_warning_export). This script does not show that dialog and does not change the
setting: use it for private items, and make an item public only after exporting through the dialog.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in [tool/README.md](../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Runs Model Hotloader's own `StartPackageExport` in the running game (rpai bridge), waits for the archive it writes, then unpacks it into `--out` (`addon.json` + `data_static/mmdhl/...`). Writes nothing else. It skips the export dialog's terms-of-use acknowledgement, so it is for private (hidden) items only.

## Exit codes

0 on success; 1 when a step fails (the reason is printed); 2 for a bad command line (argparse).
