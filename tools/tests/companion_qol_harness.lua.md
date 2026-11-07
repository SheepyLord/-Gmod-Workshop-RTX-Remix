# companion_qol_harness.lua

LuaJIT harness for R20-B's real startup hint/defaults autoruns. Invoked by
[test_companion_qol.py](test_companion_qol.py.md): `luajit companion_qol_harness.lua REPO SCENARIO [ARG1 [ARG2]]`.
Mocks persisted client ConVars/DATA, loader JSON, native snapshots, hook registration/removal,
notifications, sound and ordered timers. A new map reloads the autorun with fresh Lua locals while
preserving DATA. The disk-only getter and every Remix setter raise if called.
Their counters are also checked outside the consumer's protected calls, so swallowing a forbidden
API error cannot conceal a file read or settings write from the test.

Scenarios cover all 18 upscaler/frame-generation combinations; NVIDIA/non-NVIDIA/mixed/unknown
adapters and explicit backend support; opt-outs and invalid status; unavailable/malformed/throwing
readouts, failed marker persistence and bounded retries; delay after drawing, late readiness, two
maps and a new process startup; old/fresh/changed sky pairs, missing ConVars and persistent markers.
The `notice` scenario (R22, arguments: screen width and height) records VGUI calls and checks the
top-right notice: the hint's text, at the right edge below an existing Hotloader notice, scaled with
the screen, removed after 15 seconds, the sandbox hint unchanged. `notice-hints-off` (`cl_showhints 0`,
as in the user's game) shows the notice without the sandbox hint or its sound; `notice-opt-out` (the RTX
tab's checkbox off) shows neither and reads nothing.
UI scenarios keep the guide/cursor, pause menu or Remix menu open beyond the readiness budget,
then verify one fresh decision after closing; changing both features to on during the wait stays silent.
The migration harness rejects queued console writes, ensuring values change synchronously before
the sky starts. It never launches a game, writes a real file or needs a GPU. Output `PASS <scenario>`;
exit 0 when assertions pass, otherwise LuaJIT's nonzero exit with the failed assertion.
