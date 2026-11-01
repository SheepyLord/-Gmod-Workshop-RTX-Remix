# 0076: Bound the fracture before a pane breaks

- Status: Accepted 2026-11-01 as G1-A second-pass implementation under [0070](0070-glass-overhaul.md).
- Decided by: Codex implementing the user's second-pass brief. Supersedes the active topology
  bound of [0075](0075-incremental-glass-topology.md); its 512-cell wire ceiling remains.

## Decision

Keep at most 200 live annealed cells, coarsening complete distant groups before accepting new
cuts. Each fresh radial cut fits that budget: small inner rings remain, while the last far ring
stretches to the frame if more rings would exceed the bound. Existing hole boundaries still
cannot coarsen. A break releases at most the bounded live topology; it never drops polygons
from a debris list after fracture. Dense purely visual native cuts can simplify as before.

Tempered shatter evenly divides the full bounds into near-square rows and columns whose
product is at most 300 and at most the wire ceiling. This avoids the old square-root estimate's
extra partial rows, especially on long thin windows. Clip those tiles to the convex outline.

## Evidence and consequences

The [density harness](../../tools/tests/nlglass_fracture_harness.lua.md) checks both kinds,
centre/corner hits, the three requested sizes, extreme aspect ratios and piece sizes 4/8/64.
After 24 prior spatial hits the requested panes release 151–197 annealed or 96–300 tempered
pieces at default spacing. Area is preserved; near/far sizing and crack-edge regressions pass.
See [glass](../../glass/README.md) for the reproducible count table.

Sustained hits simplify old distant cuts earlier than the original 512-cell policy. Keeping
the actual impact, hole geometry, small near pieces and a bounded cost takes priority over
retaining every distant ring. Remix appearance and many-pane performance remain game checks.
