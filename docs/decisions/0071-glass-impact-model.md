# 0071: Bounded impacts, game-unit strength and retained fracture cuts

- Status: Accepted 2026-10-31 as G1-A implementation defaults under [0070](0070-glass-overhaul.md).
- Decided by: Codex implementing the user's G1-A brief; numerical defaults await game tuning by Claude.

## Context

The user wants pistol hits to crack before breaking, bodies to break panes with pieces, location-
dependent holes and pieces, stable cracks shared by all clients and correct remaining collision.
Source damage amounts and kinetic contact energy have different scales. G1-B consumes polygons and
velocities, and cannot own server health or crack history. No per-piece networking or server physics
for broken glass is permitted. [The Lua implementation](../../glass/README.md) records the contract.

## Decision

Use game energy `0.5 m v²`, with physics-object mass and relative Source-unit velocity. Convert
DamageInfo to that scale with 12,000 energy/damage for bullets, buckshot and crush, 16,000 for other
blunt damage, 20,000 for blast. A reference 96×64, thickness-1 annealed pane breaks at 450,000;
cracks start at 8% of its threshold. Scale by thickness squared, strength, sqrt(area/6144) with a
0.35 floor and a 3.5 tempered multiplier. Clamp the final threshold to 1–2,000,000,000 for bounded
wire integers. Player/NPC fallback mass is 85 kg and body contact requires 180 normal units/s.
These gameplay defaults make a 15-damage pistol hit crack, three break a region, and a running body
break it once; they make no claim of calibrated physical glass strength.

Quantize coordinates/settings to a 1/1024 grid before wire/replay. Use an integer seeded generator,
integer circle interpolation and integer square roots, avoiding libm-dependent cell construction.
Keep eight impact centres: nearby hits accumulate there, and full/over-budget histories merge into
the nearest centre with its original seed and cuts. Limit tessellation to 512 cells. Annealed cuts
are growing polygonal rings and rays; tempered uses a nearly uniform grid, adapting spacing on very
large panes. Hole rings only grow. Release unsupported components by shared-edge connectivity to
the original frame; a mere point contact is not support. Crack geometry comes from the cell edges.

Send compact hit events and bounded snapshots, never per-piece meshes. Every breaking event carries
its prior snapshot for reliable scattering after entity removal or missed initial transmission.
Late join reconstructs current cracks, holes and collision without replaying debris. Native glass
uses the same impact/crack model with breaking disabled until its engine break/removal event.
The server alone determines holes; matching frozen client convexes support prediction.

Keep replaced surface brushes hidden/non-solid as a once-only Shatter-input output bridge on first
breakout. Do not claim preservation of engine cell-level partial-shatter output ordering or health
filters. Offline tests verify routing; actual Hammer outputs under the engine remain a game check.
Duplicates retain properties but cannot take another pane's map-output bridge. Cleanup epochs prevent
native removal callbacks from generating pieces during map reset. Physics callbacks defer mutation.

## Consequences

State and computation are bounded, even after repeated damage; very heavily hit windows reuse the
nearest old fracture centre rather than adding unlimited new centres. An annealed pane can continue
supporting gameplay collision around holes. Render meshes update on state changes. Gameplay settings
are server/admin settings; G1-B's debris controls stay per player. A collision initialization failure
releases the whole pane, rather than leaving a placeholder cube or silently deleting its pieces.

## Alternatives considered

- One whole-pane delete for every threshold: loses the requested hole and remaining collision.
- Independent random crack lines and later fracture: visible cracks would move at the break.
- An unbounded list of impacts: growing join packets and server CPU cost.
- Sending every resulting mesh: restores the original per-piece network cost.
- Using engine native health for replaced scripted panes: prevents consistent body/prop energy
  tuning; native `func_breakable` remains engine-owned instead.
