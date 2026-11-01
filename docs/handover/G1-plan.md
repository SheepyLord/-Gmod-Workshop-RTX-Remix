# G1: a glass overhaul (plan)

Decided by the user (2026-10-31), see the end: a new MIT glass system replacing Glass-Rewrite-Remix,
our own Jolt module for broken glass, broken glass that collides only with the map and itself, and both
glass kinds (annealed and tempered) adjustable in the Lua menu.
[ADR 0070](../decisions/0070-glass-overhaul.md) records the decisions.

The user's request (2026-10-31): the glass is the original repository's proof of concept and needs an
overhaul to behave like real glass:

1. Only bullets scatter glass; other causes, such as a body hitting a pane, make it disappear.
2. The break pattern and the region that gets the impact's speed are the same wherever the pane is hit.
3. A pane that took damage but did not break shows no cracks.
4. Many broken panes, and piles of pieces, make the game lag (Source physics). Broken glass only has to
   collide with the map and with itself; a dedicated engine such as Jolt could simulate many pieces.

## What there is now

`Glass-Rewrite-Remix`, GPL-2.0, from `garrys-mod-rtx-remixed` through the user's fixes fork, shipped in
`packages/fixes` (2,477 Lua lines). One server entity, `procedural_shard`, is every unbroken pane, every
piece and every piece of a piece: server VPhysics, a mesh networked to every client, one draw per piece.
Map `func_breakable_surf` windows are replaced by it at map start (losing their map outputs); native
`func_breakable` glass keeps the engine's behaviour and spawns server pieces on `break_breakable`
([ADR 0040](../decisions/0040-native-map-glass-debris.md)); broken pieces are loose physics, at most
256, 120 s ([ADR 0061](../decisions/0061-loose-glass-breaks-again-and-expires.md)).

Why each reported point happens (`lua/entities/procedural_shard.lua` unless named):

1. **Breaks other than bullets.** Each cause has its own code with its own thresholds: `OnTakeDamage`
   (488), `PhysicsCollide` (561) and a player-only `Touch` (658). The collision path reads the hitter's
   mass from `HitObject:GetPhysicsObject()`, which a physics object does not have, so every prop and
   ragdoll counts as 1 kg, and it reads an undefined `damage_type`. Native panes get their impact point
   and force only from `EntityTakeDamage` (`rtx_map_glass.lua`); a break that came another way scatters
   from the pane's centre with no force. Where exactly a body hit loses the pieces is reproduced first in
   G1's baseline QA, but the redesign removes the separate paths altogether.
2. **Same pattern everywhere.** `Split` (200) cuts with "radial" planes whose directions come from
   world-horizontal angles and "concentric" planes along the impact direction, which for a window slice
   the pane parallel to its faces instead of into rings. The speed given to pieces is one vector for all.
3. **No cracks.** `rtx_glass_rigidity` defaults to 0, so any hit breaks the pane at once; cracks appear
   on 30% of the hits below the threshold only; and `ShowCracks` runs on the server and its crack lines
   are never sent, so a client has nothing to draw. Once cracks show, `showing_cracks` ignores later hits.
4. **Lag.** Every piece is a server entity with VPhysics and a networked mesh, a pile collides pairwise
   in VPhysics, and each piece is drawn on its own.

## Design (recommended)

**A new glass system, MIT, in this repository** (`glass/`, a new part of the RTX package), written from
scratch (rule 7: the GPL add-on is read for behaviour only). The package stops shipping
Glass-Rewrite-Remix. Spawn-menu glass, the glass tool, the settings page and its translations carry over
with the same names where they make sense.

**Panes are server-authoritative; broken glass is client-side.**

- A pane is a flat convex outline in its own plane, a thickness, a glass kind and a strength. Panes come
  from the spawn menu and tool, from map `func_breakable_surf` (replaced, as now, but its outputs fired
  by the new pane) and from native `func_breakable` glass (the engine keeps health and outputs; the
  system watches it).
- **One damage entry point** takes every cause: bullets, melee, explosions and crush (through
  `EntityTakeDamage`), props, ragdolls and other physics objects (`PhysicsCollide`, with the hitter's
  real mass), players, NPCs and vehicles moving into a pane, and scripted `Break` inputs. Each becomes
  an impact: a point on the pane, a direction, an energy and a kind (sharp, blunt, blast). A pane always
  breaks into pieces; it never just disappears.
- **Cracks.** An impact below the breaking energy cracks the pane where it hit; cracks grow with more
  hits and the pane breaks when its accumulated damage passes its strength (default: a pistol round
  cracks a window, a few rounds or one body break it; settings scale it). The server sends each pane's
  impacts (point, energy, seed: a few bytes), so every player sees the same cracks, also after joining.
- **Breaking follows the impact.** Each client builds the same fracture from the pane, the impact and a
  seed: radial cracks from the impact point and rings around it, small pieces near the impact and large
  ones far away. Pieces near the impact fly along the impact's direction, faster the closer they were;
  far pieces fall. In a large pane only the region around the impact breaks out; the rest stays in the
  frame, cracked, until it is hit again. The cracks a player saw become the edges of the pieces. The
  server runs the same fracture to know which cells stay and rebuilds the pane's collision from them,
  so bullets and players meet the remaining glass and pass through the hole. Tempered glass instead
  turns entirely into small cubes the moment it breaks.
- **Broken glass is simulated on each client and collides only with the map and other pieces**, as
  the request says: no server entities, nothing networked per piece, no physgun or `+use`, players and
  props pass through it. Explosions push it (a server event). Pieces settle, sleep and expire
  (lifetime and budget settings as now, at a much higher budget).

**Physics for broken glass: Jolt in our own client module.** A native module (`gmcl_nlglass_win64.dll`,
this repository's code, MIT; Jolt Physics vendored under `third_party/jolt`, MIT) runs a separate Jolt
world per map: the static map imported once (brushes from the map file, displacements, static props'
collision through Lua) and every piece as a small convex body. It steps on worker threads, sleeps what
has settled, and returns poses to Lua. Target: thousands of pieces and settled piles at no visible cost.

VPhysics-Jolt is not usable as the engine: its own README says its authors cannot redistribute the
code and headers needed to build it for Garry's Mod (CS:GO's VPhysics interface); it would replace all
of the game's physics (it lacks breakable constraints and airboat-style vehicles); and replacing
`vphysics.dll` on disk breaks rule 2. Its MIT code is a reference for reading Source collision data.

**Rendering under Remix.** Pieces still moving are drawn one by one; settled pieces are merged into a
few meshes per area, rebuilt only when the set changes, so a pile costs a handful of draws. Panes,
pieces and cracks use materials checked under path tracing (the existing glass material; cracks as thin
frosted geometry on both faces).

## Tasks (Codex, with Claude as project manager)

Two parallel tasks, each on its own branch and worktree, meeting only at the client API below.

| Task | Brief | Scope | Owns |
|---|---|---|---|
| G1-A | [G1-A-lua.md](G1-A-lua.md) | The glass system in Lua: panes, the damage entry point, cracks and their network state, the deterministic fracture for both kinds, the server's remaining-glass collision, map glass, explosions sent to clients, drawing panes and cracks, spawn menu, tool, settings menu and translations; leaving Glass-Rewrite-Remix out of the fixes part | `glass/addon/**` except B's files, `glass/README.md`, the fixes packager's exclusion |
| G1-B | [G1-B-native.md](G1-B-native.md) | Broken glass: the native module (Jolt world, map import, piece bodies, sleeping, the Lua binding), the debris manager (`NLGlassDebris`: spawning, drawing moving pieces, merging settled ones, budget, lifetime, explosions), a fallback without the module; build and tests | `glass/native/**`, `third_party/jolt/**`, `glass/addon/lua/nlglass/debris*.lua`, `glass/addon/lua/nlglass/world*.lua` |

Shared documents (CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS) get additive edits only. Then
Claude makes the package part (`tools/workshop.json`, `packages/glass` through `tools/inputs.py import`,
the module binary included), measures the old system first (the baseline for point 4, and where point
1's pieces go missing), runs each acceptance case on the PoC, and publishes.

### The client API between them

`glass/addon/lua/nlglass/debris.lua` (G1-B) defines the client global `NLGlassDebris`; G1-A's client
code calls only this:

```lua
-- frame: the pane's frame. Pane-local (x, y, z) maps to the world with
--   LocalToWorld(Vector(x, y, z), angle_zero, frame.origin, frame.angles):
--   x and y lie in the pane, z along its normal; a piece spans z = -thickness/2 .. +thickness/2.
--   frame.material: the VMT path the pane is drawn with; frame.color: Color or nil.
-- pieces: { { poly = { {x, y}, ... },  -- convex, counter-clockwise seen from +z, pane-local units
--             thickness = number,     -- units
--             velocity = Vector,      -- world, units/s
--             spin = Vector,          -- world rotation axis * degrees/s
--             seed = integer }, ... }
NLGlassDebris.Spawn(frame, pieces)
NLGlassDebris.Impulse(origin, radius, speed) -- an explosion: pieces within radius pushed away, up to speed
NLGlassDebris.Clear()                        -- map cleanup
NLGlassDebris.Prepare()                      -- integration: import the map before the first break
NLGlassDebris.Count()                        -- live pieces
NLGlassDebris.Backend()                      -- "jolt", "vphysics" (fallback) or "none"
```

Debris settings are per player, created by G1-B as client convars and shown in G1-A's settings menu:
`rtx_glass_debris_lifetime` (seconds, default 120, 0 = until cleanup), `rtx_glass_debris_budget`
(pieces, default 2000) and `rtx_glass_debris_collide` (pieces collide with each other, default 1).

## Acceptance (PoC, in game)

1. Bullets, melee, a thrown prop, a ragdoll, a running player, an explosion and a scripted break all
   leave pieces; no pane disappears without them.
2. A corner hit breaks out the corner, a centre hit the centre; small fast pieces at the impact, large
   slow ones away from it; the same seed gives the same pieces on two clients.
3. A hit below the breaking energy leaves cracks every player sees, also after joining; more hits grow
   them, and the pane breaks along them.
4. Fifty broken windows (thousands of pieces) and the resulting piles keep the frame rate within a few
   percent of the same scene without glass; the baseline is measured with the old system first.

## The user's decisions (2026-10-31)

1. **A new MIT glass system that replaces Glass-Rewrite-Remix in the package** (not a rework of the GPL
   add-on).
2. **Broken glass physics: our own Jolt module** (not client-side Source physics; VPhysics-Jolt as the
   engine is not viable, above).
3. **Broken glass collides only with the map and other pieces, simulated on each client**: pieces may
   differ slightly between players and cannot be picked up or pushed by props or players; explosions
   push them.
4. **Both glass kinds, adjustable in the Lua menu**: annealed (cracks from the impact, the region
   around it breaks out, the rest stays cracked in the frame) and tempered (the whole pane turns into
   small cubes). The settings menu chooses the kind for map windows and for spawned glass, and the
   tool sets it per pane.
