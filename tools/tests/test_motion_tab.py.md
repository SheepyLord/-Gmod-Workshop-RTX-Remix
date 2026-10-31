# test_motion_tab.py

Runs [motion_tab_harness.lua](motion_tab_harness.lua.md) under LuaJIT, once per scenario, without
starting Garry's Mod. It loads the companion's Motion importer tab and the shipped Character Motion
Importer files from `packages/character-motion-importer` (catalog code from `sh_core.lua`, then
`cl_menu.lua`, `cl_import_data.lua`, `cl_import_bake.lua`, `cl_importer.lua`) with mocked Derma.

```powershell
python -m unittest discover -s tools/tests -p test_motion_tab.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_tab_fills_in_when_the_addon_arrives` | The tab waits for the add-on, then builds: section buttons and Open in window; the importer's inputs in the desktop importer's order on the left, the bake, options, progress and log on the right; a file chosen through Model Hotloader's picker; the library with its columns and actions; Open in window opening both windows |
| `test_without_file_access_the_importer_explains` | The notice, Resolve and File Access Settings, disabled controls, and everything enabled once file access comes |
| `test_floating_windows_and_console_commands` | `mmdvmd_menu` and `mmdvmd_import` build the windows in Derma's look with their old layout; closing releases the hooks; losing file access closes the importer window and opens Resolve |
| `test_tab_and_window_share_the_inputs` | A file and an option chosen in the window show in the tab |
| `test_addon_without_builders_gets_window_buttons` | An add-on copy without the builders: buttons that open its windows |
| `test_the_importer_scales_with_the_screen_like_external_models` | `MMDVMDNPC.MenuScale()`: 1 at 1080p and below, 2 at 2160p, 4/3 at 1440p, times the player's `mmd_vmd_npc_menu_scale` |
| `test_with_gui_scaler_the_tab_opts_out_of_its_second_scaling` | With GUI Scaler's convar present, the tab, its buttons and each section (one built later too) carry `gScF`, as Model Hotloader's panels do; without it nothing is marked |
| `test_a_failing_builder_is_reported_once_and_offers_the_windows` | A builder that throws: one report, no half-built page left, the window buttons instead, and no second attempt on the next frame |
| `test_title_and_tooltip_follow_the_language` | The tab's title and tooltip through the companion's translations |

LuaJIT is optional: without it (CI) the tests are skipped. Writes nothing. Exit code 0 on success.
