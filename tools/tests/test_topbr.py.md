# test_topbr.py

Also runs `game_pbr_panel_harness.lua` against the packaged imported-game PBR interface, checking
texture-scoped actions, source-less automatic/none choices and drawn-only thumbnails.

Runs topbr_harness.lua with local LuaJIT against the indexed packaged driver. Uses no game or
network; reads only repository inputs. `python -m unittest discover -s tools/tests -p test_topbr.py`.
Exit 0 on success; a missing LuaJIT is a reported skip, assertion failures are nonzero.
