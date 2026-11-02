# test_eye_whites.py

Includes six generated soft-material lifecycle scenarios, for 26 controller/name/texture cases.

`python -m unittest discover -s tools/tests -p test_eye_whites.py -v` runs the production companion's
eye-white name recognition, texture identity and lifecycle/option-write fixtures through LuaJIT.
Finds LuaJIT on PATH or the machine's normal user install; explicitly skips when unavailable.
Inputs: Lua sources and [eye_whites_harness.lua](eye_whites_harness.lua.md). No game, network or disk
writes. Output: unittest results. Exit 0 when all scenarios pass, 1 on a failed assertion.
