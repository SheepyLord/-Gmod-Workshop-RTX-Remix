# test_mp_bootstrap.py

Runs six discovered unittest cases and fourteen LuaJIT scenarios against the complete production
client bootstrap and the actual packaged cl_rtx.lua model-reload section. Use tools/test.ps1 or
`python -m unittest discover -s tools/tests -p test_mp_bootstrap.py`
from the repository root. Includes approved/denied fallback boundaries, initialization order and
hook ownership, require caching, literal catalog reads, scoped absent-server-channel networking,
preserved engine network errors/arguments/returns, unchanged globals, errors and early exits. LuaJIT is optional
on CI; no game, GPU, temporary files, network or user configuration is needed. Exit zero on success.

The model-reload cases use packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua
by default. Set NATIVELOADER_TEST_RTX_LUA to a staged source path to validate a pending import.
These cases assert the normal initial/map-initialization timer behavior and the verified late-load
cache-flush guard; bootstrap scenarios also verify the marker is private to each owned environment.
