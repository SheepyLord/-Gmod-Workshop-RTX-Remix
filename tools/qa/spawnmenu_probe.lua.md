# spawnmenu_probe.lua

Client Lua for `poc_session.py run --lua tools\qa\spawnmenu_probe.lua --lua-shots 60`: opens the spawn
menu (`+menu`) and shows the creation tabs the RTX package adds or changes, one screenshot each:
`external_models` (Model Hotloader: check the "Recalculate normals for RTX" label, review R4) and
`motion_importer` (the in-place importer). Prints `NL_QA_TABS [...]` with every creation tab's name and
`NL_QA_TAB_MISSING <tab>` for a tab it could not find. Closes the menu (`-menu`) at the end. Side
effects: none beyond the open menu during the run. Exit codes: none (client Lua).
