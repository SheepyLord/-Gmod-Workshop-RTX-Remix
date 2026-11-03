# test_mmd_reimport.py

Runs [mmd_reimport_harness.lua](mmd_reimport_harness.lua.md) with LuaJIT through unittest discovery.
Extracts complete production functions for rig caching, model lookup, library deletion and ragdoll
spawning; loads actors and persistence directly. The extraction excludes unrelated GLua `continue`
loops. Exercises retained mounted archives with absent metadata, distinct client/server registries,
NPC/ragdoll/player/arms readiness, changed fits, model-only conversion caches, failed writes/mounts
and existing bound entities. Fourteen realm/scenario cases also cover a sidecar disappearing before
the withdrawal callback and reloading Lua while its guarded SetModel wrapper stays installed.
Writes only generated snippets in `out/tmp`, removes scratch when done.
No game, user source or installed data is touched. Requires LuaJIT (otherwise one explicit skip).
Exit 0 on pass, nonzero on an assertion, Lua error or timeout.
