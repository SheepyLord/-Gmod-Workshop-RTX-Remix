# debris_scene.lua

MIT client helper included by `debris.lua`. `Capture(api, dt)` reads nearby Source entities and sends
one snapshot to `SyncBodies`; returns the count of new/moving mirrors or nil/reason. `Reset` releases
cached Source references. Nothing writes to Source, sends network messages or touches files.

At 10 Hz, read at most 32 native live-piece regions closest to the current eye. Query each with a
192-unit extra margin using `ents.FindInBox`, then filter by the union of current bounds and bounds
translated by velocity times 0.25 seconds, clamped to 192 units of displacement. This is discovery
only: snapshots always contain actual Source poses, without forward extrapolation or early kicks.
Inspect at most 512 returned entries total (including duplicates and up to 128 players); retain at
most 128 deduplicated candidates. Bodies moving at least 160 units/s take priority, then players,
then other bodies. The wider query lets an approaching prop enter before crossing a small pile;
ranking before truncation prevents slow bodies from taking every slot. No whole-map scan.

Every idle worker boundary refreshes at most 96 nearby bodies. Living players/NPCs/
NextBots use collision hulls, dead players are excluded, ragdolls use up to 24 physics bones (or bone
hitboxes without client physics), props use physics convexes or an oriented box. Invalid/oversized
convexes retain a coarse physics AABB. New shapes cap at two/snapshot, eight convexes and 512 points;
after the first, extraction stops once capture has spent 0.5 ms. Engine calls cannot be preempted.
Cold physics bodies at least 160 units/s use their AABB immediately, bypassing mesh extraction for
as long as they are fast. On slowing they can upgrade under the ordinary two-shape budget, keeping
their identity. Previously cooked fast bodies retain their convex. Per-bone proximity also uses the
bounded sweep. All original body/geometry caps and the 10 Hz cadence remain in force.

Physics-object validity is checked before equality; replacement gets a fresh identity and shape.
Missing/out-of-region bodies disappear from the next snapshot. Empty scenes keep a cheap fast path.
Statistics: `bodies`, `candidates`, `queries`, latest `cooks` and `capture_ms` (includes native sync).
`capture_peak_ms` retains the maximum until Reset. Living hulls extend eight units below the feet
in the mirror only: Source stays on the floor, and thin pieces get a lateral push instead of being
pinned by a flat hull bottom. Living mass follows `rtx_glass_player_mass` (default 85 kg).
No exit code; this is a runtime module. Engine errors propagate to the game console.

Fast-body statistics: `examined` (latest discovery prefix, <=512), `fast_candidates` (retained latest
discovery), `fast_bodies` (latest snapshot), `fast_boxes` (cumulative cold fast physics bodies) and
`peak_bodies` (maximum snapshot size). Reset clears them. Engine spatial-query/result construction
and individual extraction/native calls are indivisible; count caps are not a wall-clock guarantee.
Finite lookahead, missing client entities/velocities, saturated prefixes and >128-unit native pose
corrections can still miss cosmetic interactions. See the R7-C report and native sweep limits.
