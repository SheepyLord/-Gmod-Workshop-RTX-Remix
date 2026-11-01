# 0072: Bounded glass world import, reusable poses and area batching

- Status: Accepted 2026-10-31 (G1-B implementation).
- Decided by: G1-B, implementing the module and debris-manager choices delegated by
  [the brief](../handover/G1-B-native.md), under the user's [0070](0070-glass-overhaul.md).

## Context

Cosmetic broken glass needs static collision without access to engine internals, no per-frame Lua
allocation for native poses, and a cheap settled pile. Missing or malformed map collision must not
leave shards falling forever. The native budget and import bounds must also constrain hostile input.

## Decision

- Vendor unchanged Jolt 5.3.0 library source with its archive hash, static CRT, an SSE2 baseline,
  no profiler/debug renderer or floating-point traps. Only our `gmcl_nlglass_win64.dll` is shipped.
- Convert Source Z-up coordinates at 0.0254 metres/unit, with Source pitch/yaw/roll and world spin
  in degrees/s. Glass density is 2500 kg/m³, friction .65, restitution .025, CCD enabled. Step at
  1/60 s with four substeps maximum; count discarded time. Use up to eight workers and join before
  any Lua access. Scratch has a preallocated reserve and Jolt's heap fallback, avoiding its
  fixed-only allocator's `abort` path; table capacities bound the work.
- Parse little-endian VBSP 19-21, including reordered v21 headers and Source LZMA collision lumps.
  Traverse model 0's node tree to leaf-brush references; do not import entity brush models. Solid
  contents are `MASK_SOLID_BRUSHONLY` (`0x400b`: SOLID, WINDOW, GRATE, MOVEABLE). Displacements
  (powers 2-4) become two-sided meshes; authored non-surface triangles are holes. Static-prop
  `sprp` records v4-11 supply model/transform/solidity; v11 uniform scale is applied. Lua asks a
  temporary client model for collision convexes once per unique model, skips unavailable or
  over-complex collision and adds the solid instances. No MDL file parsing or external asset reads.
- Reject malformed, unsupported, empty or over-limit world collision as a whole, release the
  imported static bodies, log once and use the fallback. No native import retries until a new map.
  Add-on/client shutdown releases all pieces, static bodies, cached shapes and worker threads.
- Enforce a hard 8192-piece native limit. The manager reserves that maximum once per map and
  applies the player's current 0-8192 budget independently, so raising it does not reimport a map.
  Native callers can reserve less. Detailed import bounds are in [the native README](../../glass/native/README.md).
- Reuse native pose storage and caller-owned Lua rows `{x,y,z,pitch,yaw,roll,sleeping}`. Emit awake
  pieces plus one final sleeping pose. Raw table access avoids metamethod execution. Invalid calls
  return `nil, reason`; no C++ exception escapes a Lua callback. Identifiers are never reused.
- One mesh per moving piece; settle into 256-unit XYZ areas grouped by material/color, up to 60000
  vertices per batch. Invalidate changed batches immediately, debounce 100 ms and rebuild at most
  two areas/frame. Unbatch a piece before wake/removal or its last-second transform-only shrink.
- The capped 64-piece Source fallback uses `COLLISION_GROUP_WORLD`, which conservatively avoids
  all gameplay bodies. It forgoes inter-piece collision; the collide setting controls Jolt only.
  A runtime failure migrates the newest surviving pieces at their last displayed poses.

## Consequences

No Steam files, engine physics or server bodies are involved. Newer/custom BSP/static-prop formats
use fallback until supported. Moving doors, brush entities and dynamic props are absent from the
static world, as required for map-only cosmetic debris. Client collision cannot recover a model
whose collision data the engine does not expose. Holding the native maximum costs more memory
than reserving the default 2000 pieces, but keeps map import and menu budget changes independent.
The native benchmark measures physics; real Remix frame-time and material acceptance still need
Claude's in-game [probe](../../tools/qa/glass_debris_jolt_probe.lua.md).

## Alternatives considered

- Import all brushes: includes doors and breakable entity glass, leaving invisible blockers.
- Depend on engine collision memory or parse MDL/PHY: expands ABI/file-format coupling unnecessarily.
- Allocate pose tables/Vector userdata each frame: puts avoidable pressure on Lua GC.
- Keep stale merged geometry during debounce: removed/woken/shrinking glass remains visible twice.
- Use a gameplay collision group in fallback: lets cosmetic debris touch players and props.
