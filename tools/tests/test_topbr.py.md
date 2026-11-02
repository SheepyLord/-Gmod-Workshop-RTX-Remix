# test_topbr.py

Runs topbr_harness.lua with local LuaJIT against the indexed packaged driver. Uses no game or
network; reads only repository inputs. `python -m unittest discover -s tools/tests -p test_topbr.py`.
Exit 0 on success; a missing LuaJIT is a reported skip, assertion failures are nonzero.
