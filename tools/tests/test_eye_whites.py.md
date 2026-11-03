# test_eye_whites.py

Runs 45 cases, including six generated soft-material lifecycle scenarios, manual mark/unmark,
explicit false/true precedence, restart/map reload, same-asset re-import, full asset isolation,
reset, damaged/externally changed persistence, saved-choice bounds, paged UI toggle/reset/thumbnail,
no texture work for unspawned characters, previews or foreign paths, size rejection before reading,
failed-write rollback, absent-file size variants and preservation of normal Derma dragging/resizing behavior.

`python -m unittest discover -s tools/tests -p test_eye_whites.py -v` runs the production companion's
eye-white name recognition, texture identity and lifecycle/option-write fixtures through LuaJIT.
Finds LuaJIT on PATH or the machine's normal user install; explicitly skips when unavailable.
Inputs: Lua sources and [eye_whites_harness.lua](eye_whites_harness.lua.md). No game, network or disk
writes (DATA persistence is mocked). Output: unittest results. Exit 0 when all scenarios pass,
1 on a failed assertion.
