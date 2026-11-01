# G1-B: broken glass in a dedicated Jolt world

Read [AGENTS.md](../../AGENTS.md), [G1-plan.md](G1-plan.md) (the design, the user's decisions and the
client API you implement) and [ADR 0070](../decisions/0070-glass-overhaul.md) first, then
[`loader/client`](../../loader/client/README.md): how this repository builds a Garry's Mod client
module with the vendored headers in `third_party/gmod`. VPhysics-Jolt (MIT) is a useful reference for
reading Source collision data into Jolt; do not ship it. Work in `out\worktrees\g1-native` on branch
`g1-native`.

## Build

1. **Jolt Physics, vendored.** A tagged release of `github.com/jrouwe/JoltPhysics` (MIT) under
   `third_party/jolt`, byte-identical to upstream, with its `LICENSE` and a `README.md` naming the tag,
   the archive URL and its SHA-256, and what is included (only what the build needs). Downloading that
   one archive is allowed.
2. **The module** `gmcl_nlglass_win64.dll` (C++20, `glass/native`, CMake; built by `tools/build.ps1` and
   tested by `tools/test.ps1` like the loader's targets; x64 Release with PDB):
   - A Jolt physics system on worker threads (`max(1, min(8, hardware threads - 2))`). Source units
     convert to metres at the boundary (1 unit = 0.0254 m); gravity comes from Lua (`sv_gravity`).
   - **The static map, imported once per map** from the map file's bytes (Lua reads
     `maps/<map>.bsp` from the `GAME` path, which also covers Workshop maps, and passes them): the world
     model's solid brushes as convex hulls (from their planes; choose and document the contents that
     count, the equivalent of brush-only solid traces), displacements as triangle meshes, and the static
     props of the `sprp` game lump (model, origin, angles, solidity) returned to Lua. Lua then gives each
     unique solid prop model's collision (a client-side model with `PhysicsInit`, then
     `GetMeshConvexes`; models without collision are skipped) and the module adds the instances. Handle
     the BSP versions Garry's Mod maps use, and compressed lumps if they occur; a map it cannot read
     leaves an empty world, logs once, and makes the manager use the fallback.
   - **Pieces**: a convex hull from the extruded polygon, glass density and friction, little bounce,
     sleeping tuned so piles settle quickly; a layer filter for the static map and for pieces, with
     piece-against-piece collision switchable.
   - A fixed 1/60 s step with an accumulator and a cap on substeps; interpolated poses for drawing.
   - **The Lua binding** (`require("nlglass")`): initialise with a body budget, load a map, add static
     prop models and instances, finish the world, spawn a piece (hull points, position, angles,
     velocity, angular velocity; returns an id), remove, impulse (origin, radius, speed), set collide,
     step (dt), read the poses of awake pieces into a Lua table without per-frame garbage, sleeping
     state, statistics. Every input is validated, no exception crosses into Lua, memory is bounded by
     the budget, and nothing the module does may crash the game.
3. **The debris manager**, client Lua: `glass/addon/lua/nlglass/debris.lua` defines `NLGlassDebris`
   exactly as the plan's API says, with helpers in `debris_*.lua` and the map import glue in
   `world*.lua`:
   - per piece one mesh (both faces and the edges, normals, UVs) with the frame's material;
   - moving pieces drawn each frame at their interpolated pose; settled pieces merged into a few meshes
     per area of the map, rebuilt only when an area's pieces change (debounced), so a pile costs a
     handful of draws;
   - the per-player client convars `rtx_glass_debris_lifetime` (seconds, default 120, 0 = until
     cleanup), `rtx_glass_debris_budget` (default 2000) and `rtx_glass_debris_collide` (default 1);
     expiry shrinks a piece away over its last second by its transform only (no alpha), as ADR 0061
     did; over the budget the oldest go first; `Clear` on cleanup and map change;
   - `Impulse` wakes and pushes pieces within the radius;
   - a fallback when the module is missing or failed: client-side Source physics pieces
     (`ents.CreateClientProp` and `PhysicsInitConvex`), capped low (about 64), same API, and
     `Backend()` says which is in use.
4. **A performance probe**: client Lua under `tools/qa/` with its `.md` that spawns N pieces over a
   floor area through `NLGlassDebris` (no panes needed), lets them fall and settle, and prints frame-time
   statistics and the manager's counts, for Claude to run in the game.

## Tests and docs

- Native tests (CTest): BSP import from fixtures the tests generate (a small room of brushes with a
  displacement and a static-prop entry; no game files in git), hull building (degenerate input
  refused), 4,000 pieces dropped into the generated room settling within a stated time and CPU budget on
  this machine (record the numbers), the binding's bounds and error handling.
- LuaJIT harness tests for the manager with mocked GMod APIs: budget, expiry, area merging and
  rebuilding, fallback selection, `Clear`, `Impulse`.
- `glass/native/README.md` naming each source file (every CMake folder needs one), `third_party/jolt`'s
  README, a `.md` beside every script, a CHANGELOG line in a section `### G1 (unreleased)`, RESEARCH
  entries for facts you dig up (BSP details, measured numbers), an ADR for module-level choices beyond
  ADR 0070 if you make any.
- `tools\test.ps1 -Config Release` passes.

## Rules

Only this worktree and its `out\`. Never launch Garry's Mod; never write to the PoC or field install;
never touch Steam's files or any `user.conf`; never upload to the Workshop; never push, merge, tag or
commit on `main`. The Jolt archive is the only download. Do not edit G1-A's files (the rest of
`glass/addon/**`, `glass/README.md`, `tools/package_fixes.py`), `packages/` or `tools/workshop.json`
(Claude builds the package part and imports the module binary). Shared docs get additive edits only.

Your final message is your report: files and commits, the Jolt version, the binding's functions, how
the map is imported and what it skips, tests, measured numbers, and known limits.
