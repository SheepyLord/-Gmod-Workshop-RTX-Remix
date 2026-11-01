# 0077: Defer and coalesce remaining-pane client builds

- Status: Accepted 2026-11-01 under [0070](0070-glass-overhaul.md).
- Decided by: Codex implementing the user's second-pass client-cost request.

## Decision

Apply deterministic impacts and call the public debris Spawn API immediately, preserving sound,
effects and blast ordering. Queue remaining-pane render/crack meshes and prediction collision
for no earlier than the next client frame. Coalesce pending revisions per pane, retaining any
collision dirtiness. Process at most two panes/frame, stopping after a complete pane when 1 ms
has elapsed. FrameNumber prevents multiple Think callbacks bypassing either bound. One mesh
or physics build cannot be preempted; the elapsed-time budget is soft.

Initial snapshots attach immediately. A whole break immediately removes old rendering/collision;
it has no remaining build. Snapshot replacement, pane removal, cleanup and Lua refresh invalidate
queued work. A late entity joining a queued record marks collision dirty even if only a cracking
hit was waiting. No private/native debris API, wire format or server authority changes.

Construct render positions and collision hulls in one extrusion when both change; cache convexes
for attachment. Mesh face fans and crack strips share immutable vertex records and positions.
Winding follows outward normals on both crack faces as well as the pane extrusion.

## Evidence and tradeoffs

The [engine harness](../../tools/tests/nlglass_engine_harness.lua.md) checks frame deferral,
coalescing, count/time limits, latest revision, cancellation, late attachment and geometry sharing.
It reports handler, deferred build and their per-sample total separately. On the same 100-hit
workload, the 200-cell density policy also lowers prepared topology from 502 to 164 cells.
Local mean client break CPU is 1.87 ms in the handler plus 1.01 ms deferred (2.88 ms combined),
against 13.59 ms before this pass. These are mocked engine calls, not live Remix frame times.

Partial-pane rendering and prediction collision can lag the authoritative state by one frame
or more under bursts. The next game check must verify hole traversal and 50-pane falling-frame
cost with G1-B's work. Avoiding a synchronous remaining-pane rebuild inside every message takes
priority over identical-frame prediction geometry; server collision remains authoritative.
