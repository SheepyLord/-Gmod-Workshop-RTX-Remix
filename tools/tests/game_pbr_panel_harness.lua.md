# game_pbr_panel_harness.lua

Executes the marked imported-game PBR panel section of the packaged ToPBR driver under fake
GMod/native/Derma APIs. Verifies looked-at
character metadata, shared texture states, exact individual-map/native action arguments, no-map
and automatic actions without source metadata, menu registration and thumbnails only for drawn
materials. Usage: `luajit tools/tests/game_pbr_panel_harness.lua <cl_rtx_topbr_conversion.lua>`.
Also constructs the console editor at a 720p viewport with its scrolling form.
The fake DForm exposes `Clear`, matching the stock API, and deliberately lacks the spawn-menu-only
`ClearControls` method (the first real editor smoke found that compatibility error).
Known map-layout conflicts are rejected before native submission, including Windows case variants.
The cursor trace points elsewhere while the cursor-independent trace selects the character, guarding
against popup mouse position changing the material picker target.
Reads its input; no filesystem writes, game or network. Exit 0 on success, nonzero on assertion.
