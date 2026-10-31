# gamebridge.py

Talk to a running Garry's Mod (Source engine) instance.

Source executes the payload of a ``WM_COPYDATA`` message sent to its
``Valve001`` window as console text (the mechanism behind ``-hijack``).
Measured on the x86-64 RTX client: ``echo RPAI_PING_2`` sent this way is
printed to the console immediately. Lua runs through ``lua_run_cl`` (falling
back to the server's ``SendLua`` in single player), reading its code from
``garrysmod/data/rpai`` and answering with a JSON file in the same folder.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Sends console text to the game's `Valve001` window (`WM_COPYDATA`); writes a request file into the game's `garrysmod\data\rpai` and deletes the answer file after reading it. Picks the window by class and by the game root of its `gmod.exe`.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
