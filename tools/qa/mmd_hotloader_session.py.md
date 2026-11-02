# mmd_hotloader_session.py

Attaches the R10-H NPC/expression probes to a PoC game started and owned by
`poc_session.py`. Requires the shared main-checkout `out/r10/poc.lock` to say
`R10-H`. Refuses other evidence destinations and never targets the field game.

```powershell
# Acquire the shared lock first; deploy the reviewed local package with poc_session config.
python tools/poc_session.py --evidence out/r10/poc run --name expressions --addons --settle 0 --lua-shots 360 --screenshots 0 --console "sv_cheats 1"
# In a separate terminal while that run is alive:
python tools/qa/mmd_hotloader_session.py --mode expressions --out out/r10/expression-evidence
python tools/qa/mmd_hotloader_session.py --mode npc --out out/r10/npc-evidence --maps gm_flatgrass gm_construct
python tools/qa/mmd_hotloader_session.py --mode npc --prefix e2c25f9e --cold-first --out out/r10/cold-evidence --maps gm_flatgrass
```

`npc`: ragdoll and NPC spawns through the library's actual client RequestSpawn
and server-status path, then stock-menu and hotloader NPC spawns on the
starting map and after each full `map` transition. `expressions`: Guinaifen and
Robin, each with real built/playback smile, wink and blink motions, per-tick
weights and paused screenshots. Runs only in the existing PoC process and uses
its current single-player/listen-server setting. Give the owning session enough
`--lua-shots` time; the probe finishes that wait with `NL_SHOT_DONE`, then the
owning session quits normally and collects logs. Console Lua travels hex-encoded
like poc_session's payloads.

`--prefix` selects another cached library character for NPC tests. `--cold-first`
spawns only its ragdoll on map one, then requests its first NPC on map two, to
cover the user's original order without deleting a library or generated rig.

Inputs: PoC library, deployed add-ons and the two adjacent Lua probes. Outputs:
`events.json`, six PNGs and six weight-probe JSONs under `--out`; console output
identifies every milestone, plus two mapping-window PNGs. See the Lua sidecars
for generated in-game QA data.
It changes `ai_disabled`/`sv_cheats` for the session, aims the test player toward
nearby ground, spawns QA entities and removes each inspected menu NPC, and changes maps in
NPC mode. Does not rewrite config, lock, Steam settings, user.conf or any field
file. After the owning game exits, restore the PoC's Workshop-only loader config
and release the lock. Exit 0 on completion, nonzero on an exception or timeout.
