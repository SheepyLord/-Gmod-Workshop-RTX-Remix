# Native loader glass (G1)

An original MIT add-on replaces Glass-Rewrite-Remix. One frozen server entity represents each
convex pane; broken pieces exist only in G1-B's client debris world. This is G1-A's integration fix pass.
Combine it with G1-B's fix pass before packaging/game acceptance. No GPL code or material files were copied.
The add-on draws glass with `models/props_combine/health_charger_glass`, the material the old add-on used, which the fixes part's Remix mod `base_mod/breakable_glass` replaces with translucent PBR glass (texture hash `C0C4BC4C02DBDF70`).

## Files

| File under `addon/lua/` | Responsibility |
|---|---|
| `autorun/nlglass.lua` | Shared bootstrap, downloads of client Lua, six size/kind spawn presets |
| `entities/nlglass_pane/shared.lua`, `init.lua`, `cl_init.lua` | Pane entity, frozen collision, damage callbacks, property-only duplication/save restore |
| `nlglass/fracture.lua` | Plain Lua deterministic convex subdivision, support connectivity, cracks and piece velocities |
| `nlglass/config.lua` | Shared setting names, defaults and ranges; replicated convars in both realms |
| `nlglass/geometry.lua` | Frames, convex outlines from brush surfaces/physics, validation, collision points, render triangles |
| `nlglass/damage.lua` | Single impact representation for damage, collisions, bodies and fallback breaks |
| `nlglass/protocol.lua` | Bounded snapshot and compact impact encoding |
| `nlglass/server.lua` | Authoritative registry, remaining-cell collision, map adapters, break/late-join/blast events, admin settings |
| `nlglass/client.lua` | Network replay, cached pane/frosted crack meshes, matching frozen prediction collision, debris API calls |
| `nlglass/menu.lua` | Spawn-menu settings and `glass_open_panel` compatibility command |
| `nlglass/i18n.lua`, `i18n_data.lua` | Language selector and generated MIT translations |
| `weapons/gmod_tool/stools/procedural_glass_tool.lua` | Existing tool name, prop conversion, new panes, per-pane kind/strength |

Every script has a sidecar describing inputs, outputs and effects. `addon/LICENSE` is MIT;
[i18n/](i18n/README.md) holds independent MIT catalogs. G1-B owns `nlglass/debris*.lua`,
`nlglass/world*.lua` and `native/`; this fix pass does not edit those files.

## Damage and fracture

See [ADR 0071](../docs/decisions/0071-glass-impact-model.md). Energies are gameplay units:
`0.5 * mass_kg * relative_speed_units_per_second²` for physics, players, NPCs and vehicles.
`CollisionData.HitObject` supplies the real PhysObj mass. Player/NPC fallback mass is 85 kg;
body contacts require at least 250 units/s toward the plane from the body's side, a centre within
remaining glass and actual plane proximity (half thickness plus oriented body half width).
Players also use a pre-movement hull sweep, retaining incoming movement plus base velocity
(including the QA `SetVelocity` push) before collision stops it. Player/NPC hulls stay axis aligned;
vehicles use their oriented half widths.
Contacts are event-driven and
deferred out of physics callbacks; there is no server Think/Tick scan of idle panes.

A 96×64, thickness-1 annealed pane at strength 1 has a 450,000 breaking threshold and a 36,000
crack threshold. All positive weak energy accumulates; there is no visible crack until it reaches
`min(8% of threshold, 36,000)`. The breaking threshold scales with thickness squared, strength, square root of area (reference
6144 units², minimum scale 0.35), and 3.5 for tempered. DamageInfo energy is damage × 12,000 for
bullets/buckshot/crush, × 16,000 for other blunt damage, × 20,000 for blast. Thus a 15-damage pistol
hit cracks, three such hits break a region, and an 85 kg running body at 400 units/s supplies 6,800,000.
Walking at 200 units/s stays below the default contact-speed gate.
These are tunable game defaults, not engineering strength predictions. Thickness is in Source units.
Native windows keep engine health: our accumulated damage controls their visual cracks only.

Each cracking hit establishes 8–16 seeded rays and polygonal rings with spacing that grows
outward. Only cells in its contact neighbourhood subdivide; repeated hits reuse those cuts.
Live cells and their complete subdivision groups are retained. Above the 200-cell annealed limit, complete
old groups far from the new hit return to their exact convex parent. Groups containing a released
cell cannot coarsen, so holes never refill. Eight active centres describe crack growth; a new distant
hit reclaims a distant slot while keeping its actual location. Old distant cracks may simplify.
A pathological perforated pane with no room to refine/coarsen releases its remaining glass at the
current hit. A 100-impact generated probe reaches the cap without that fallback.

The second pass lowers the active topology budget to **200 annealed / 300 tempered** cells,
within the unchanged 512-cell snapshot ceiling ([ADR 0076](../docs/decisions/0076-glass-bounded-break-density.md)).
Annealed cuts keep small inner rings and use fewer large far cells when the outer ring budget
is exhausted; complete distant groups coarsen before new cuts exceed 200. Tempered divides the
full pane bounds into near-square tiles with at most 300 rows times columns, including narrow
panes. No pieces are discarded and their total area is preserved.

Whole-break counts below use piece size 8, seed 171, thickness/strength 1, a centre or a corner
2 units inside each edge. `Fresh / damaged` means an untouched pane versus 24 prior spatial
visual-only hits, as an engine-owned window can receive before its native break:

| Pane | Annealed centre | Annealed corner | Tempered centre / corner |
|---|---:|---:|---:|
| 96x64 | 89 / 160 | 52 / 197 | 96 / 96 |
| 256x128 | 116 / 170 | 63 / 184 | 300 / 300 |
| 128x256 | 116 / 151 | 65 / 182 | 300 / 300 |

The cap also applies to partial breakouts and repeated hits, rather than trimming the debris
list after fracture. The density harness checks piece sizes 4/8/64 and extreme aspect ratios.

All coordinates use a 1/1024 wire grid, an integer Park–Miller generator, an integer circle table
and integer square roots. Hull/Clip merge vertices closer than 1/256 before sending any piece to
G1-B's mesh builder. No global random generator, trigonometry or libm roots affect the cells.
Tempered glass starts as one intact convex, shows a small spiderweb near impacts and generates a
bounded uniform grid only when the whole pane shatters. Its grid is never rendered as cracks.

Cracks use cell edges, excluding the pane's original border. Their visible extent grows with
energy; thin frosted strips sit on both faces. Remaining polygons and cracks are cached. Support
connectivity uses shared edges and runs once per breakout, never on an ordinary cracking hit.
Complete groups and immutable cell arrays let snapshots retain pre-break state without recomputing
history. Server collision rebuilds only at breakout; clients mirror remaining convexes for prediction.
No convex covers a hole. A physics-build failure releases the remaining glass with pieces.
See [ADR 0075](../docs/decisions/0075-incremental-glass-topology.md).

Cracks use `VertexLitGeneric` and the white `models/debug/debugwhite` base texture, with no
self-illumination. They keep the 0.10/0.065-unit half widths and outward normals on both faces.
The material name `nlglass_frost_lit` also avoids reusing an old unlit material after Lua refresh.
Remix should shade the strips with the scene; a dark room/night check remains part of game QA.

Near pieces receive the impact direction with squared distance falloff and seeded spin. Far pieces
have little or no initial velocity and fall in G1-B's gravity. A scripted break releases the whole
pane. Native break/removal uses its last recorded impact, otherwise the breaker's position/velocity,
otherwise the pane centre with nominal energy. Cleanup suppresses pending native breaks.

## State and map logic

The server sends a pane definition/frame once, then compact impact events (27 bytes including
ID/revision/flags). Breaks also carry their pre-state so a missing or already removed entity cannot
swallow pieces. Snapshots include bounded live pane topology and complete subdivision groups,
sharing vertex coordinates; a 501-cell probe uses 16,721 bytes. Restore resumes that topology
without history replay or historical debris. This is pane state only: no moving piece/pose stream
or per-piece server entities. Settings remain validated server/admin changes.

Initial state uses one client-readiness request from `InitPostEntity`, with a zero-delay request
only for Lua refresh. A missing revision requests just that pane ID; the server replies with its
snapshot or removal, deduplicating IDs and allowing 16 requests per two-second window. There is
no second PlayerInitialSpawn push. A matching client state applies a break directly; a recovery
snapshot is stored without a build, then its final state builds once. Weak pending hits keep
geometry and collision; unchanged cells retain the pane mesh. Cached meshes/cracks update by
revision and prediction physics rebuilds only on initial attachment or breakout.

Each pane caches its validated entity, Matrix, material, tint and bounds. Only a pose change calls
LocalToWorld and updates that Matrix; a stationary draw has no new Matrix/transform/class lookup.
Panes beyond 8,192 units plus radius, or wholly behind the current eye plane, are skipped.
Reused entity indices are checked on attachment instead of every frame.

Map startup, newly created map brushes, cleanup and save restore are covered. Surface geometry uses
the largest valid brush face, its convex outline and original material metadata; rendering uses the
Remix glass material. Native `func_breakable` with physics material `glass` is watched without
changing health, solid state, render material or engine outputs. Irregular non-convex/multi-surface
windows and moving brush behaviour need game QA; unsupported geometry remains the engine's pane.

For a replaced `func_breakable_surf`, the original brush remains hidden with collision disabled.
Its targetname and Hammer output bindings remain on that entity. The first actual breakout mirrors
captured raw `OnBreak` map keys to an unused native `OnUser1`–`OnUser4` channel and fires `FireUser`
once on the original, keeping Source's target/parameter/delay/count and activator/caller handling.
It never sends engine `Shatter`/`Break` to that brush (those play sound and emit engine shards).
Further script `Break`/`Shatter`
inputs on the original route to the replacement. Removing an unbroken replacement restores the
original's visibility/collision. Restored panes retain their original brush link; duplicates become
independent panes and cannot steal that link.

**The native output bridge needs in-game validation.** Capture requires the original map key
callbacks (Lua hot reload cannot recover them); four occupied user channels disable the bridge
with a diagnostic. Runtime output changes outside those callbacks cannot be mirrored.
The offline harness proves raw routing and once-only dispatch. Per-engine-cell
partial-shatter logic, old brush health/damage filters and output history do not track the new
annealed hole state. If the original was removed by map logic, its output bindings cannot be fired.
Save/dupe keeps outline, thickness, kind and strength; broken state/output history need not persist.

## Settings and tool

Open RTX Remix → Water and glass → Glass settings with the companion, or Utilities → Glass Rewrite
Remixed → Glass settings standalone, or run `glass_open_panel`. The original category and
`GlassSettings` panel ID are kept so the companion can relocate the page. Gameplay settings are
server/admin settings; debris settings are per player, created by G1-B. Labels support English,
Simplified/Traditional Chinese, Japanese, Korean, French and Russian. Non-English translations are
agent-written and await human review. Long slider/combo labels use full-width help lines.

| Setting | Default | Meaning |
|---|---|---|
| `rtx_glass_map_kind` | `annealed` | New map windows: `annealed` or `tempered` |
| `rtx_glass_spawn_kind` | `annealed` | Default spawn-menu pane; explicit presets offer both kinds |
| `rtx_glass_strength` | `1` | 0.1–10 strength multiplier for new panes |
| `rtx_glass_show_cracks` | `1` | Draw cracks; gameplay damage still accumulates when off |
| `rtx_glass_piece_size` | `8` | 4–64 units; minimum tile/ring spacing for new panes |
| `rtx_glass_velocity_transfer` | `1` | 0–3 impact velocity multiplier for new panes |
| `rtx_glass_player_break_speed` | `250` | Minimum normal contact speed, 0–1000; walking 200 stays below it, running 400 exceeds it |
| `rtx_glass_player_mass` | `85` | 1–500 kg fallback where no valid physics mass exists |
| `rtx_glass_debris_lifetime` | `120` | G1-B: seconds, 0 until cleanup |
| `rtx_glass_debris_budget` | `2000` | G1-B: live pieces per player |
| `rtx_glass_debris_collide` | `1` | G1-B: pieces collide with each other |

Reset to Defaults resets client debris settings and, for an admin, server settings. Existing panes
retain their material properties; map cleanup applies new kind/strength/size settings to map windows.
Previously archived speed choices are retained; Reset to Defaults restores the new 250-unit/s gate.
Spawn presets are 48×48, 96×64 and 128×128, each annealed or tempered. The existing glass tool name
is retained: left-click converts a prop into a flat convex envelope or resets an existing pane's kind
and strength; right-click makes a pane at a surface. Complex volumetric props are simplified, rather
than wrapped in arbitrary 3D geometry. The tool supports undo, normal sandbox limits and CPPI checks;
its explicit kind/strength override global defaults for that pane.

## G1-B integration

The bootstrap serves all available `nlglass/debris*.lua` and `nlglass/world*.lua` files to remote
clients, and includes `nlglass/debris.lua` on the client. G1-B owns its own client includes and
convars. Omit script `.lua.md` sidecars when assembling the add-on payload. G1-A calls only the
[plan's public API](../docs/handover/G1-plan.md#the-client-api-between-them):

```lua
NLGlassDebris.Spawn(frame, pieces)
NLGlassDebris.Impulse(origin, radius, speed)
NLGlassDebris.Clear()
NLGlassDebris.Prepare() -- integration: called when the client first learns of a pane
```

The original breakable surface brushes remain as hidden, non-solid logic entities. The debris
world's static import must omit breakable brushes as permanent obstacles; verify this at integration.

Frame `origin`/`angles` map pane-local x/y to the pane and z to its normal using `LocalToWorld`;
`material` is a VMT path, `color` a Color. Each piece has CCW `poly = {{x,y},...}`, `thickness`,
world `velocity` and `spin` Vectors, and integer `seed`; it spans z ± thickness/2. Blast messages
are deduplicated by explosion origin/inflictor and tick (unattributed blasts coalesce per tick), then
call `Impulse` after synchronous and one-turn deferred breaks, so the blast also pushes the pane's
own new pieces. No private debris/world API, native API or server broken-glass entity is used.

## Validation

Run `python -m unittest tests.test_nlglass -v` from `tools/`, then `tools\test.ps1 -Config Release`.
[The fracture harness](../tools/tests/nlglass_fracture_harness.lua.md) runs without GMod globals;
[the engine harness](../tools/tests/nlglass_engine_harness.lua.md) mocks APIs and stubs NLGlassDebris.
Neither starts a game. Claude owns G1-B integration, package assembly, PoC game/map-output/Remix
visual checks, two real clients, collision prediction, body-contact tuning and the 50-window/pile
performance comparison against the original system. No game install or Workshop is touched here.

The G1-A fix pass passes 45 glass tests and the full Release gate (25 CTests, 448 Python tests,
two existing skips). Each fix-pass item has a regression that fails against 3096b2e. Generated
probes reach 512 cells across 100 separated impacts, preserve an old hole, check 36,015 edges
across 180 seeds and exercise 200 dense visual-only native hits. See [testing](../docs/TESTING.md)
for before/after pure-fracture and mocked server/client timings. Real game contact timing,
Hammer output semantics, two clients and Remix performance are still acceptance checks.
