# 0076: Consolidate glass piles with shared scratch and staged resource retirement

- Status: Accepted 2026-11-01 (G1-B second pass, implementation delegated by the user).
- Amends settled batching in [0075](0075-glass-background-work-and-staged-piles.md).

## Context

The game reports 388 draws for 2,000 sleeping pieces and a roughly 3 ms frame-cost increase.
The manager's old small cells/chunks fragment piles; constructing transient transformed vertices
also creates tens of MiB of GC pressure. The brief requests few settled draws and bounded rebuilds.

## Decision

- Use 1024-unit XYZ cells offset by half a cell, grouped by material. Store tint/alpha in vertices
  rather than grouping by color. Chunk at 24,000 vertices, comfortably below the engine mesh limit.
- One active snapshot shares at most 24,000 pooled vertex records across every area. Transform
  with one numeric Source rotation basis per piece, mutating existing position/normal vectors.
  Uploads copy scratch; no live GPU mesh depends on Lua retaining the records unchanged.
- Debounce 200 ms after the last change, but start by 750 ms during continuing arrivals. Prepare
  at most 1,800 vertices/frame and stop after a measured 0.6 ms allowance, checked per piece.
  At most one upload/frame. Upload calls are indivisible and are measured for game QA.
- Retain old valid chunks until the complete replacement exists. Hide an affected chunk
  immediately on wake/removal/shrink, returning survivors to individual rendering. Cancel stale
  staging; a failed upload retains old geometry and retries. Retire at most two old/staged GPU
  meshes/frame. Cleanup destroys all outstanding resources; bounded scratch survives `Clear`.

## Consequences

Stable piles schedule no rebuilds and cost fewer draws. One changed member can temporarily expose
more individual survivors than the earlier small chunks, requiring efficient moving/individual
drawing. Large material changes and engine upload/synchronization costs still need real-game
measurement; mock frame times do not establish the brief's 1 ms/16 ms targets.

## Alternatives considered

Keeping 6,000-vertex chunks limits upload size but costs more stable draws. Rebuilding one giant
mesh in a frame increases bursts. Streaming a partially open engine mesh across frames is unsafe
for render state; pooled Lua preparation keeps complete uploads within one call/frame instead.
