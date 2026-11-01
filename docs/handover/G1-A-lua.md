# G1-A: the glass system in Lua

Read [AGENTS.md](../../AGENTS.md), [G1-plan.md](G1-plan.md) (the design, the user's decisions and the
client API you call) and [ADR 0070](../decisions/0070-glass-overhaul.md) first. The shipped
Glass-Rewrite-Remix (`packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix`, with ADRs
[0040](../decisions/0040-native-map-glass-debris.md) and [0061](../decisions/0061-loose-glass-breaks-again-and-expires.md)
and RESEARCH's "Loose glass physics in GMod") is GPL-2.0: read it for behaviour only, never copy its
code (rule 7). Work in `out\worktrees\g1-lua` on branch `g1-lua`.

## Build

A new GMod add-on, MIT, in `glass/addon` (shared, server and client Lua; `glass/addon/lua/nlglass/` for
modules), plus `glass/README.md`.

1. **Panes.** A scripted entity (for example `nlglass_pane`) is a pane: a convex outline in its own
   plane (pane-local 2D, the frame convention of the plan's API), a thickness, a kind (annealed or
   tempered) and a strength. The server owns it: frozen VPhysics collision built from the cells that
   are still in the frame (all of them while intact), so bullets and players meet the remaining glass
   and pass through a hole. Clients draw the intact pane or its remaining cells with the glass material
   the old add-on used (`rtx/replace_me/glassmat`, whose Remix replacement ships in the fixes part;
   reference it, do not copy files). Panes come from:
   - the spawn menu (a few sizes, both kinds) and the glass tool (what the old
     `procedural_glass_tool.lua` offered, plus setting a pane's kind and strength);
   - map `func_breakable_surf`, replaced at map start and after cleanup as today (outline from its brush
     surface, its material). Keep the map's logic tied to the window breaking working where the engine
     allows (investigate: keeping the original hidden and non-solid and firing its `Break` or `Shatter`
     input when the pane breaks, or another way); document what cannot be kept;
   - native `func_breakable` glass (physics material `glass`): watched only. The engine keeps its
     health, collisions and outputs; the system cracks it visually and breaks it into pieces when the
     engine breaks it.
2. **One damage entry point** (server) turns every cause into an impact: a point on the pane, a
   direction, an energy and a kind (sharp, blunt or blast), with attacker and inflictor:
   - `EntityTakeDamage` / `OnTakeDamage`: bullets, buckshot, melee, explosions, crush, physics damage;
   - `PhysicsCollide` on a pane: props, ragdolls and any physics object, with the hitter's real mass
     (`data.HitObject:GetMass()`) and the relative speed, energy `0.5 m v^2`;
   - players, NPCs and vehicles moving into a pane (their mass from physics or a setting);
   - scripted `Break` inputs;
   - native panes: `break_breakable` and removal. A break with no recorded impact uses the breaker's
     position and velocity, else the pane's centre with a nominal impulse: never a pane without pieces.
3. **Strength and cracks.** Per kind, scaled by thickness, area and a strength setting: an impact below
   the crack energy does nothing; above it the pane cracks where it was hit (a sharp impact leaves a
   hole mark with radial cracks); cracks grow with more damage; the pane breaks when its accumulated
   damage passes its strength. Defaults: a pistol round cracks an ordinary window, a few rounds or one
   body breaks it; tempered glass takes more and then shatters entirely. The server keeps each pane's
   impacts (bounded, merged when full) and sends them (pane, point, energy, kind, seed: a few bytes
   each); a joining player receives the current list. Clients draw the cracks from the same fracture
   pattern, out to an extent that grows with the damage, as thin frosted geometry on both faces, so the
   cracks a player sees become the edges of the pieces.
4. **The fracture**, a shared module that runs under plain LuaJIT (no GMod globals), deterministic: the
   outline, thickness, kind, impacts and a seed give the cells (convex polygons), which cells break out,
   and each piece's velocity and spin. Use your own seeded generator (no `math.random`); keep the cell
   set independent of platform differences in math functions.
   - Annealed: radial cracks from the impact (more with more energy), rings around it with spacing that
     grows outward, so cells are small near the impact and large far away; the breakout region grows
     with the energy; cells outside it stay in the frame, except cells no longer connected to the frame,
     which fall. A corner hit breaks out the corner, a centre hit the centre.
   - Tempered: the whole pane turns into small, nearly uniform cells.
   - Pieces near the impact fly along the impact direction, faster the closer they were; far pieces
     fall; spin varies with the seed. A hit on cells that stayed breaks them out the same way.
5. **Breaking.** The server computes the fracture, updates the pane (collision and drawing from the
   remaining cells; removed when none remain) and sends the break (pane, the breaking impact, seed).
   Each client computes the same fracture and calls `NLGlassDebris.Spawn(frame, pieces)` for the cells
   that broke out, plays the break sound and an impact effect. Code against the API in the plan; in
   your tests use a stub.
6. **Explosions.** The server sends blast events (origin, radius, magnitude; at most one per explosion
   and tick) for blast damage it sees; clients call `NLGlassDebris.Impulse`.
7. **The settings menu** (the spawn-menu settings page, as the old one): the kind for map windows and
   for spawned glass, strength, cracks on or off, piece size, velocity transfer, player break speed and
   mass, and G1-B's per-player debris settings (`rtx_glass_debris_lifetime`, `rtx_glass_debris_budget`,
   `rtx_glass_debris_collide`, created by G1-B as client convars; you show them), with Reset to
   Defaults. Translate the menu for every language the project ships, the way the companion's catalogs
   are built; the new catalogs are MIT like the add-on.
8. **Leave Glass-Rewrite-Remix out of the package.** `tools/package_fixes.py` stops packing that add-on
   folder and its translation catalogs, nothing else, with a test. Its Remix glass material stays (the
   new system uses it).
9. **Keep working:** map cleanup, saves and duplicates where reasonable (a pane's properties persist;
   its broken state need not), late join, other add-ons, and no per-tick server work for idle panes.

## Tests and docs

- LuaJIT harness tests with mocked GMod APIs, the way `tools/tests/glass_map_harness.lua` and
  `test_glass_map.py` test add-on Lua today: every damage cause (bullet, blast, prop with its mass,
  ragdoll, player, scripted, a native pane with and without a recorded impact); crack accumulation, its
  network messages and late join; fracture determinism (same inputs give the same cells and pieces, in
  one state and a fresh one); impact dependence (corner against centre: the breakout region, piece size
  near and far, velocity falloff); tempered shatter; the remaining-cell collision; the packager exclusion.
- `glass/README.md` (what it is, its files, settings, the API with G1-B), a `.md` beside every script,
  a CHANGELOG line in a section `### G1 (unreleased)`, an ADR for the damage and strength model if you
  decide more than ADR 0070 says, RESEARCH entries for facts you dig up (file:line).
- `tools\test.ps1 -Config Release` passes.

## Rules

Only this worktree and its `out\`. Never launch Garry's Mod; never write to the PoC or field install;
never touch Steam's files or any `user.conf`; never upload to the Workshop; never push, merge, tag or
commit on `main`. No GPL code copied. Do not edit G1-B's files (`glass/native/**`, `third_party/jolt/**`,
`glass/addon/lua/nlglass/debris*.lua`, `glass/addon/lua/nlglass/world*.lua`), `packages/` or
`tools/workshop.json` (Claude builds the package part). Shared docs get additive edits only.

Your final message is your report: files and commits, the damage model and defaults you chose and why,
how the fracture works, what map logic of `func_breakable_surf` is kept, tests and results, and what is
left for the in-game checks.
