# test_nlglass_r9.py

Runs real production Lua with the existing engine/debris doubles and LuaJIT. Covers empty blasts,
true grenade origins, bounded delivery/cleanup, local/everyone clear permissions, sound defaults,
receipt-frame preview visibility/cancellation, sound distance/frame/second/piece limits and seeded
small irregular shards with conserved area. Run from tools with `python -m unittest
discover -s tests -p test_nlglass_r9.py`. Reads only repo sources, writes no game files, skips when
LuaJIT is unavailable. Exit 0 passes, 1 fails.

Also checks native input/grenade signals, six-child expiry/budget adoption, idle-boundary motion
diagnostics, QA chunk syntax and actual translated text (no shell-encoding question marks).
