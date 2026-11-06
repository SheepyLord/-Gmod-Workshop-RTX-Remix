# r20_blood_poc.lua

Shared, **test-only** PoC acceptance driver. Copy as a temporary add-on's `lua/autorun/r20c_qa.lua`
under the shared PoC lock; never include in a shipping package. Launch with `-multirun -noworkshop`,
local add-ons enabled, sv_cheats/sv_allowcslua 1 and ai_disabled 1, using `poc_session.py --lua-shots 300`.

Uses actual stock pistol/shotgun/AR2 shots on citizens, Combine, zombies, antlions and frozen
ragdolls; a listen multiplayer session adds a bot player. A server NPC also fires a bullet so the
observing client receives a remote shooter's stock dispatch. Frames use host_timescale .03 for the
brief impact; each screenshot acknowledgement resumes normal time. Tests stock and enhanced
impacts, blue/rainbow/custom schemes, a bounded many-hit frame-time run and both settings panels.
`R20C_*` JSON lines report readiness, panels, frame times and effect counts; NL_SHOT lines use the
standard driver handshake. Missing parts/targets report R20C_ERROR; bot without a slot reports SKIP.

Side effects are confined to the test game: actors, weapons, temporary cheat/time controls and
client settings, restored on completion (the session driver also restores field/cloud settings).
`r20c_*` console commands/networked test entity flags exist only in this fixture. Restore the PoC
snapshot and remove the temporary add-on before releasing the lock. No process exit code.
