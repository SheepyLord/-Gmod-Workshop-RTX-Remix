# test_render_guard_addons.py

Runs twenty-four R8-C LuaJIT scenarios through the production guard using
[render_guard_harness.lua](render_guard_harness.lua.md) and the authored
[add-on call replays](render_guard_addon_replays.lua.md). Run from the repo root:

    python -m unittest discover -s tools/tests -p 'test_render_guard*.py' -v

The normal tools/test.ps1 discovers these tests. LuaJIT is required to execute them; unittest
reports a skip if it is absent. Each scenario runs in a separate process with a 20-second timeout.
Only repository code/fixtures are read; no third-party Lua, native game, GPU or config is used.
Inputs are the actual companion guard and harness paths. One additional static test checks exact
bundled path exemptions against package file indexes/SHA-256 values and the companion/glass Lua,
with no internal collisions or extra trusted names. The Lua cases replay all 344 exemptions and
both PBR readers/hotloader, untrusted shader draws/reuse, label collisions, material mutations,
1,200-path/image/trusted/repeat cost bounds. No wall-time threshold is asserted. No persistent side effects. A failed
assertion/process makes unittest exit nonzero; zero means success. The combined guard suite has
47 unittest methods and 49 LuaJIT scenario invocations, including the existing containment regressions
and one static test. [bench_render_guard.py](bench_render_guard.py.md) separately records timing.
