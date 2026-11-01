# debris_scene.lua

MIT client helper included by `debris.lua`. `Capture(api, dt)` reads nearby Source entities and sends
one snapshot to `SyncBodies`; returns the count of new/moving mirrors or nil/reason. `Reset` releases
cached Source references. Nothing writes to Source, sends network messages or touches files.

At 10 Hz, read at most 32 native live-piece regions closest to the current eye and use `ents.FindInBox`, deduplicating at most
128 candidates, prioritizing nearby players. Every idle worker boundary refreshes at most 96 nearby bodies. Living players/NPCs/
NextBots use collision hulls, dead players are excluded, ragdolls use up to 24 physics bones (or bone
hitboxes without client physics), props use physics convexes or an oriented box. Invalid/oversized
convexes retain a coarse physics AABB. New shapes cap at two/snapshot, eight convexes and 512 points;
after the first, extraction stops once capture has spent 0.5 ms. Engine calls cannot be preempted.

Physics-object validity is checked before equality; replacement gets a fresh identity and shape.
Missing/out-of-region bodies disappear from the next snapshot. Empty scenes keep a cheap fast path.
Statistics: `bodies`, `candidates`, `queries`, latest `cooks` and `capture_ms` (includes native sync).
`capture_peak_ms` retains the maximum until Reset. Living hulls extend eight units below the feet
in the mirror only: Source stays on the floor, and thin pieces get a lateral push instead of being
pinned by a flat hull bottom. Living mass follows `rtx_glass_player_mass` (default 85 kg).
No exit code; this is a runtime module. Engine errors propagate to the game console.
