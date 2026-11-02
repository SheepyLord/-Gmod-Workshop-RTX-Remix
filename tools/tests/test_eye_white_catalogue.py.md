# test_eye_white_catalogue.py

Unittest coverage for [eye_white_catalogue.py](../qa/eye_white_catalogue.py.md): production matcher
Unicode/control-character transport, surface/model/shared-atlas counts, near misses and unchanged
manifest bytes/timestamps. `python -m unittest discover -s tools/tests -p test_eye_white_catalogue.py -v`.
Needs LuaJIT. Creates generated fixtures only under `out/tmp`, removed after tests. No game or network.
Exit 0 for success, 1 for assertion failure.
