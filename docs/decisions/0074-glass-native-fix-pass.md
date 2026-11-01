# 0074: Isolate glass collision failures and bound client preparation work

- Status: Accepted 2026-11-01 (G1-B fix pass, implementation authority delegated by the user).
- Amends [0072](0072-glass-debris-world-and-batching.md); implements the native section of
  [the fix brief](../handover/G1-fix-pass.md).

## Context

The game fell back on gm_construct because one Jolt hull failed. Its terrain also lacked SURFACE
bits and was discarded entirely. The original scratch reserve, full-slot pose scans and pile
rebuild bursts add unnecessary client cost. Measurements and format evidence are in
[RESEARCH](../RESEARCH.md).

## Decision

- Structural parser errors still refuse the map. Clip brushes in double precision; skip/count
  individual unusable or Jolt-refused shapes and prop instances. Only a finished world without
  any usable static collision selects fallback. Keep native trust/path/off-switch rules unchanged.
- Displacement columns run toward corner 3. The REMOVE tag marks omitted triangles; the optional
  SURFACE bit is not a prerequisite for collision.

## Consequences

Some bad geometry can be absent, with explicit diagnostic counts, while the rest of the map works.
Generated fixtures and a deliberate read-only map probe validate format and cooking without
redistributing game files. Live prop collision/material/frame-time checks stay with Claude.

## Alternatives considered

Rejecting every map with one refused shape disabled Jolt on a supported stock map. Requiring the
SURFACE bit removed all gm_construct terrain. Neither is useful for cosmetic debris.
