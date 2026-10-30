# test_glass_map.py

Runs glass_map_harness.lua under LuaJIT against the actual indexed addon sources. Generated fixtures
and the comment-normalized legacy networking file stay under repository out/tmp and are removed
afterward. Skipped without LuaJIT; the full test runner discovers it. Exit follows unittest. No game,
Workshop operation, registry change or user configuration is involved.
