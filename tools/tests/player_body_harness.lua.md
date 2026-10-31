# player_body_harness.lua

Runs the actual bundled body entity, category registrar and RTX menu with a LuaJIT GMod API double.
Called by [test_player_body.py](test_player_body.py.md); arguments are those three production paths.
No game, network or files are changed: render, file and entity calls are recorded in memory.
Checks private textures even for white inputs and the legacy unique-hash preference, cached copies,
skin changes, body groups, death/spectator/third-person behavior, draw-state cleanup, world-Z offsets
on proxy bones only, rejection of shared material names and the menu bindings. Exits nonzero on an
assertion; prints PASS on success.

The bone double runs BuildBonePositions during DrawModel and rejects source-player bone reads
or setup from that callback. It verifies repeated callbacks do not accumulate offsets, each new
draw refreshes the snapshot, bone counts are bounded, and invalid names, unused bones, missing
source/destination matrices and model/name mismatches cannot be written. It also exercises engines
without the optional bone-flag API/enum and ensures unexpected draw errors are not swallowed.
