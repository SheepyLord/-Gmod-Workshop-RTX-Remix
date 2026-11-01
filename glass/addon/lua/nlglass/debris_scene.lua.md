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

Each Source vector is read once (every component read is an engine call, 35 ns in game against
0.5 ns for a Lua number) and the region tests run on plain numbers: 512 bodies against 32 regions
took 3.13 ms with vectors and 0.30 ms with numbers (PoC probe, 2026-11-01). Duplicates from
overlapping region queries are dropped before any engine call.

Every idle worker boundary refreshes at most 96 nearby bodies. Living players/NPCs/
NextBots use collision hulls, dead players are excluded, ragdolls use up to 24 physics bones (or bone
hitboxes without client physics), props use physics convexes or an oriented box. Invalid/oversized
convexes retain a coarse physics AABB, placed with the physics object's pose: `PhysObj:GetAABB` is in
the object's own frame (a client prop at 831,400,-100 reported -14,-14,0 .. 14,14,45). Server props have
no client physics object and use their oriented box. New shapes cap at two/snapshot, eight convexes and 512 points;
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

R8-G Capture(api, dt, flags) defaults to mask 3: objects=1, ragdolls=2, living players=4, living NPCs/NextBots=8. It filters before bounds/shape extraction and on every snapshot, includes kind in row 8, and refreshes discovery immediately when the mask changes. Zero removes mirrors without querying regions. Client ragdolls are classified separately from living actors.

Flag changes also invalidate the Lua shape cache: the native side removes mirrors, so retained categories must resend cold shapes under the existing two-shape limit instead of falsely assuming a convex still exists.
