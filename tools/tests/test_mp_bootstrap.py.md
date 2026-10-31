# test_mp_bootstrap.py

Runs nine discovered unittest cases and twenty-two LuaJIT scenarios against the complete production
client bootstrap and the actual packaged cl_rtx.lua. Use tools/test.ps1 or
`python -m unittest discover -s tools/tests -p test_mp_bootstrap.py`
from the repository root. Includes approved/denied fallback boundaries, initialization order and
hook ownership, require caching, literal catalog reads, scoped absent-server-channel networking,
preserved engine network errors/arguments/returns, unchanged globals, errors and early exits. LuaJIT is optional
on CI; no game, GPU, temporary files, network or user configuration is needed. Exit zero on success.

The model-reload and normal-load-marker cases use packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua
by default. Set NATIVELOADER_TEST_RTX_LUA to a staged source path to validate a pending import.
These cases assert the normal initial/map-initialization timer behavior and the verified late-load
cache-flush guard; bootstrap scenarios also verify the marker is private to each owned environment.
`test_the_final_flush_runs_with_queued_rendering_off` (R4-28): the map-initialization flush switches
`mat_queue_mode` to 0, waits frames, flushes with it off and puts the player's value back; already
off it flushes at once; a switch that does not take skips the flush with a message.

[ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md) cases: a realm whose normal
loading already ran the payload (cl_rtx.lua's NATIVELOADER_RTX_NORMAL_LOAD, also checked in the
actual file) finishes without a second run on a listen host or an sv_allowcslua 1 server, and
elsewhere leaves out only the add-on that set it; a realm without hook/CompileString finishes instead of
being recompiled on every poll; a server-delivered entity class keeps its definition; and owned
OnGamemodeLoaded, PostGamemodeLoaded and Initialize callbacks are replayed before InitPostEntity.
