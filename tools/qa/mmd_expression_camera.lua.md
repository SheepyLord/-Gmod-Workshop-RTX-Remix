# mmd_expression_camera.lua

Client half of [mmd_hotloader_session.py](mmd_hotloader_session.py.md). Set
`R10MMDTarget` to the probed NPC's entity index before injection. Pins CalcView
25 units in front of the eyes (head-bone fallback), 32-degree FOV; hides HUD/view
model and the game menu. The external driver hides the console, since Lua is
not allowed to run that console command.

Reads only the current entity. Writes no files and changes no archived settings.
Hooks and the target variable last this map; unset the target to release the
camera, or exit normally. Prints `R10_QA_CAMERA` on installation. No exit code;
Lua errors are failures. Inject using `poc_session.client_lua_lines` as the driver
does; no add-on deployment is needed.
