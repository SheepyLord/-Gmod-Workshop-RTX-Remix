# Native loader glass (G1)

An original MIT add-on replaces Glass-Rewrite-Remix. One frozen server entity represents each
convex pane; broken pieces exist only in G1-B's client debris world. This worktree implements G1-A.
Combine it with G1-B before packaging or game acceptance. No GPL code or material files were copied.
The add-on references the fixes part's existing `rtx/replace_me/glassmat` material and Remix replacement.

## Files

| File under `addon/lua/` | Responsibility |
|---|---|
| `autorun/nlglass.lua` | Shared bootstrap, downloads of client Lua, six size/kind spawn presets |
| `entities/nlglass_pane/shared.lua`, `init.lua`, `cl_init.lua` | Pane entity, frozen collision, damage callbacks, property-only duplication/save restore |
| `nlglass/fracture.lua` | Plain Lua deterministic convex subdivision, support connectivity, cracks and piece velocities |
| `nlglass/config.lua` | Shared setting names, defaults and ranges; server convars |
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
`nlglass/world*.lua` and `native/`, absent on the G1-A branch.

## Damage and fracture

See [ADR 0071](../docs/decisions/0071-glass-impact-model.md). Energies are gameplay units:
`0.5 * mass_kg * relative_speed_units_per_second²` for physics, players, NPCs and vehicles.
`CollisionData.HitObject` supplies the real PhysObj mass. Player/NPC fallback mass is 85 kg;
body contacts require at least 180 units/s towards the pane normal. Contacts are event-driven and
deferred out of physics callbacks; there is no server Think/Tick scan of idle panes.

A 96×64, thickness-1 annealed pane at strength 1 has a 450,000 breaking threshold and a 36,000
crack threshold. Threshold scales with thickness squared, strength, square root of area (reference
6144 units², minimum scale 0.35), and 3.5 for tempered. DamageInfo energy is damage × 12,000 for
bullets/buckshot/crush, × 16,000 for other blunt damage, × 20,000 for blast. Thus a 15-damage pistol
hit cracks, three such hits break a region, and an 85 kg body at 200 units/s supplies 1,700,000.
These are tunable game defaults, not engineering strength predictions. Thickness is in Source units.
Native windows keep engine health: our accumulated damage controls their visual cracks only.

The first accepted hit establishes 8–16 seeded rays, more for higher initial energy, and homothetic
polygonal rings whose spacing grows outward. Convex clipping gives small cells near the hit and
larger cells far away. Subsequent spatially separate hits subdivide the existing cuts; repeated
nearby hits grow their crack extent without moving the original cuts. Annealed breakout removes
whole inner rings and any cells no longer connected along an edge to the frame. Later breaks grow
holes; an impact in retained glass can establish another centre. Tempered uses a nearly uniform
grid and releases the whole pane at its higher threshold.

All fracture coordinates use a 1/1024-unit grid, an integer Park–Miller generator, an integer circle
table and integer square roots. No global random generator, trigonometry or libm square roots affect
the cells. Impact history is bounded at eight slots, merging into the nearest when full; a ninth cut
or a cut that would exceed 512 cells also merges. Merging retains the old cut's location/seed, a
deliberate limit on very heavily damaged panes. Tempered adapts its minimum piece size to keep a
large pane below the cell bound. Strength/settings are quantized before networking.

Cracks use the same cell edges as the eventual pieces. Their visible extent grows with accumulated
energy; sharp hits thicken the fine central/radial geometry into a hole mark. Thin frosted strips sit
on both pane faces. Meshes rebuild only when state changes. The server rebuilds VPhysics only when
glass breaks out; clients mirror remaining convexes for prediction, including late entity creation.
No convex covers an opening. A physics-build failure falls back to a full cosmetic break.

Near pieces receive the impact direction with squared distance falloff and seeded spin. Far pieces
have little or no initial velocity and fall in G1-B's gravity. A scripted break releases the whole
pane. Native break/removal uses its last recorded impact, otherwise the breaker's position/velocity,
otherwise the pane centre with nominal energy. Cleanup suppresses pending native breaks.

## State and map logic

The server sends a pane definition/frame once, then 19-byte impact payloads (27 bytes including pane
ID, revision and flags). A breaking event additionally contains the preceding bounded state, so a removed/not-yet
transmitted entity cannot swallow its pieces. There is no mesh or per-piece networking. A joining
player gets the current bounded impacts, holes, seed, energy and revision; restoring them creates
cracks/collision, with no historical debris replay. A client requests resynchronization on a missing
revision. The only client-to-server routes are a rate-limited read-only sync and validated admin
setting changes. Other add-ons' native damage hooks are not suppressed.

Map startup, newly created map brushes, cleanup and save restore are covered. Surface geometry uses
the largest valid brush face, its convex outline and original material metadata; rendering uses the
Remix glass material. Native `func_breakable` with physics material `glass` is watched without
changing health, solid state, render material or engine outputs. Irregular non-convex/multi-surface
windows and moving brush behaviour need game QA; unsupported geometry remains the engine's pane.

For a replaced `func_breakable_surf`, the original brush remains hidden with collision disabled.
Its targetname and Hammer output bindings remain on that entity. The first actual breakout fires
its `Shatter` input at normalized centre with a radius covering the original window, passing through
attacker/caller. The bridge bypasses our own input interception once; further script `Break`/`Shatter`
inputs on the original route to the replacement. Removing an unbroken replacement restores the
original's visibility/collision. Restored panes retain their original brush link; duplicates become
independent panes and cannot steal that link.

**This is an engine-input bridge, not a guarantee of every map's outputs.** The actual engine's
`OnBreak`/`OnShatter`/completion outputs, output ordering and hidden-brush behaviour must be checked
by Claude in game. The offline harness proves routing and once-only dispatch. Per-engine-cell
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
| `rtx_glass_player_break_speed` | `180` | Minimum normal contact speed, 0–1000 |
| `rtx_glass_player_mass` | `85` | 1–500 kg fallback where no valid physics mass exists |
| `rtx_glass_debris_lifetime` | `120` | G1-B: seconds, 0 until cleanup |
| `rtx_glass_debris_budget` | `2000` | G1-B: live pieces per player |
| `rtx_glass_debris_collide` | `1` | G1-B: pieces collide with each other |

Reset to Defaults resets client debris settings and, for an admin, server settings. Existing panes
retain their material properties; map cleanup applies new kind/strength/size settings to map windows.
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
```

The original breakable surface brushes remain as hidden, non-solid logic entities. The debris
world's static import must omit breakable brushes as permanent obstacles; verify this at integration.

Frame `origin`/`angles` map pane-local x/y to the pane and z to its normal using `LocalToWorld`;
`material` is a VMT path, `color` a Color. Each piece has CCW `poly = {{x,y},...}`, `thickness`,
world `velocity` and `spin` Vectors, and integer `seed`; it spans z ± thickness/2. Blast messages
are deduplicated by explosion origin/inflictor and tick (unattributed blasts coalesce per tick), then
call `Impulse`. No private debris/world API, native API or server broken-glass entity is used.

## Validation

Run `python -m unittest tests.test_nlglass -v` from `tools/`, then `tools\test.ps1 -Config Release`.
[The fracture harness](../tools/tests/nlglass_fracture_harness.lua.md) runs without GMod globals;
[the engine harness](../tools/tests/nlglass_engine_harness.lua.md) mocks APIs and stubs NLGlassDebris.
Neither starts a game. Claude owns G1-B integration, package assembly, PoC game/map-output/Remix
visual checks, two real clients, collision prediction, body-contact tuning and the 50-window/pile
performance comparison against the original system. No game install or Workshop is touched here.
