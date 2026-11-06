# r20_blood_poc.lua

The diagnostic stores GetBloodColor's result before tostring: some ragdolls return zero Lua
results. Earlier accepted combat runs retain three logging-only errors at this line, after their
targets were fully spawned/aimed; shot, effect, panel, budget and restoration evidence is intact.

The runner prefixes R20C_QA_MODE. A probe mode runs only the material/HUD comparison and leaves
90 seconds for diagnostics; ordinary modes run the combat matrix. Weapons aim at a chest bone
from closer range with view punch reset, so thin ragdoll collision meshes are actually hit. Extra
colour 1/2/6 hits and a visibly green custom colour complement the twelve-scheme CPU checks; all
edited custom RGB controls are saved and restored by the probe.

A first material-comparison frame draws known stock particles and the new droplet with lighting
on/off at a larger, stationary size in free air. These test-only particles expire before combat
measurement and are not part of the effect's resource counts.

Integration diagnostics report whether D's generic observer was present at InitPostEntity;
the probe never starts it or supplies a per-add-on hash list. Material comparisons run only in a
separate probe session: their shared texture hash must not affect classification in acceptance
runs. Ordinary combat uses only the production material/shader path.

The material diagnostic reports shader, base-texture dimensions/tint, r_drawparticles and world
validity. Particle samples include RGB. Once production ragdoll adapters exist, temporary dispatch
adapters are skipped so the fixture cannot replace the implementation being tested.

After the last planned frame it leaves 35 game seconds for additional diagnostics under the same
owned lock, then prints NL_SHOT_DONE. Extra screenshot acknowledgements only resume normal time.
The complete companion's sharp-screen panel is skipped when testing the two raw parts RTX-off.

The server fixture queues its cheat/Lua/AI/time controls before map initialization, and the client
closes unrelated Derma notices before each shot. This avoids racing the session runner's later
console setup during heavy first-load model/shader work.

Temporary Impact/Impact_GMOD/RagdollImpact adapters log dispatch data and immediately forward to
the native effect with overrides disabled; these diagnose the ragdoll path without changing physics.
The first eight owned particles are sampled after .3 game seconds to diagnose movement/lifetime;
no velocity, gravity or lifetime is changed by the sampler.

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
