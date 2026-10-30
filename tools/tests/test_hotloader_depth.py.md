# test_hotloader_depth.py

Executes the shipped material builders and DrawCarrier with LuaJIT for Remix and programmable Source.
Extracted production code and generated fixtures stay in repository out/tmp and are removed after
the test. Skipped without LuaJIT. Run `python -m unittest discover -s tools/tests -p test_hotloader_depth.py`.
No game, network, Workshop upload or profile change. Exit follows unittest.
