# 0080: Reduce individual glass draw work and report its frame cost

- Status: Accepted 2026-11-01 (G1-B second pass, implementation delegated by the user).
- Complements [0079](0079-glass-pile-consolidation.md); native ABI, collision and sleep tuning stay
  as recorded in [0072](0072-glass-debris-world-and-batching.md).

## Context

With 1,453 moving pieces, the game frame averages 33.83 ms while Jolt takes about 1.6 ms.
The brief calls out per-piece Lua rendering and asks for view/distance rejection and direct
manager timings. There is no authorization to run the game in this pass.

## Decision

- Maintain only individual pieces in material groups, bind once for each visible group, and
  retain one Matrix/scale Vector per piece. Change matrix translation/angles after a published
  pose; change scale when necessary (including reapplying non-unit shrink after rotation).
  Hidden pieces defer matrix work. Merged piles leave the individual renderer entirely.
- Capture the current render view once/pass, including scripted camera origin/angles/FOV/aspect.
  Use conservative sphere/frustum tests for individuals and settled areas. Limit cosmetic drawing
  to 8192 units plus sphere radius. Beyond 256 units, skip individual pieces whose projected radius
  is under 0.75 pixels. Screen height sets the pixel scale. Missing camera context disables culling.
  This affects rendering only; physics, lifetime and explosions remain active while hidden.
- Report Think/draw CPU milliseconds as 120-frame rolling averages, last samples and peaks since
  Clear. Sum eligible translucent passes with the same FrameNumber before sampling draw time/calls.
  Publish completed/current/average calls, sample counts and culled-piece counts in reused Stats.
  Include rebuild/upload last and peak times to identify stalls after a burst has ended.
- Leave native sleeping unchanged: its current 0.35 s/0.06 m/s defaults already allow rapid rest.
  Do not introduce contact heuristics that could freeze airborne shards while fixing rendering.

## Consequences

Off-camera or subpixel cosmetic debris can disappear from secondary reflections, as implied by
the requested view culling; moving back restores it without rebuilding. A material group still
submits one mesh per visible moving piece. Timings measure client hooks and include pile work,
but exclude asynchronous Jolt worker time, GPU execution, and Spawn/fracture outside Think.
Actual fifty-pane <20 ms and settled +1 ms/no >16 ms targets need Claude's game measurements.

## Alternatives considered

Repeated material binds and unconditional matrix writes retain engine-call overhead. A fresh
render table/matrix per piece creates needless GC. Using the player's position for culling breaks
scripted/third-person views. Timing each render pass as a separate frame undercounts multi-pass
work; resetting timing on Stats reads would also make QA sampling intervals change the results.
