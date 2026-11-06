# companion_qol_harness.lua

LuaJIT harness for R20-B's real startup hint/defaults autoruns. Invoked by
[test_companion_qol.py](test_companion_qol.py.md): `luajit companion_qol_harness.lua REPO SCENARIO [ARG1 [ARG2]]`.
Mocks persisted client ConVars/DATA, loader JSON, native snapshots, hook registration/removal,
notifications, sound and ordered timers. A new map reloads the autorun with fresh Lua locals while
preserving DATA. The disk-only getter and every Remix setter raise if called.

Scenarios cover all 18 upscaler/frame-generation combinations; NVIDIA/non-NVIDIA/mixed/unknown
adapters and explicit backend support; opt-outs and invalid status; unavailable/malformed/throwing
readouts, failed marker persistence and bounded retries; delay after drawing, late readiness, two
maps and a new process startup; old/fresh/changed sky pairs, missing ConVars and persistent markers.
The migration harness rejects queued console writes, ensuring values change synchronously before
the sky starts. It never launches a game, writes a real file or needs a GPU. Output `PASS <scenario>`;
exit 0 when assertions pass, otherwise LuaJIT's nonzero exit with the failed assertion.
