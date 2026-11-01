# G1: fix pass after integration (two parallel tasks)

Both tasks start from `g1-int` at `95bf8e4`: G1-A and G1-B merged, the package part, the glass material
that Remix replaces (`models/props_combine/health_charger_glass`), the BSP import that skips single
brushes, `NLGlassDebris.Prepare()`, the QA add-on. Read [G1-plan.md](G1-plan.md), your original brief
([G1-A-lua.md](G1-A-lua.md) or [G1-B-native.md](G1-B-native.md)) and this file.

## What the game showed (PoC, gm_construct, `tools/qa/nlglass_qa`)

Run `out/qa-poc/g1/02-qa` (screenshots and `console.log` under the main checkout's `out/qa-poc/g1/`):

- Every cause left pieces: bullets, a 400-damage round at a corner and at a centre, a thrown oil drum
  (30 kg, 700 units/s), a thrown ragdoll, an explosion, a scripted `Break`. Panes render as clear
  path-traced glass, pieces as glass, cracks as white lines; one pistol round cracks, three break out the
  region around the hits; a corner round breaks out the corner.
- **Jolt never ran**: `[NLGlass] Jolt unavailable; using capped client physics: Jolt refused convex
  hull` (the earlier run: one degenerate brush; skipping is now in place, then a hull Jolt refused
  stopped the whole world). Everything ran on the 64-piece fallback.
- **A player pushed at 500 units/s into an upright 64x96 pane did not break it.**
- **Tempered glass shows its square cell grid as straight cracks** across the whole pane.
- Crack lines run along the pane's own border.
- Breaking 40 panes within about 1.2 s: frame time mean 17.7 ms, p99 293 ms (fallback physics, and the
  fracture cost below); the settled scene costs nothing measurable (8.9 ms against 8.3 ms empty).

An independent review of both branches found no crash path in the native module and these defects.

## G1-A fix pass (Lua; branch `g1-lua-fix`)

Owns `glass/addon/**` except `debris*.lua` and `world*.lua`, `glass/README.md`, the G1-A harnesses and
tests. Each item needs a harness test that fails before the fix.

1. **Body contact** (`damage.lua:70-80`, `server.lua:71`): `D.FromBody` uses `math.abs(v.n)` and only a
   2D inside test, from an enlarged bounding box, so jumping off a horizontal pane at 200 units/s breaks
   it and a rotated pane breaks with the body tens of units away. Require movement toward the plane from
   the body's side, the body within the outline, and within half the thickness plus the body's half
   width of the plane. And make the game case work: a player moving into an upright pane faster than the
   threshold breaks it (find why `Touch` did not deliver it in 02-qa; use another hook if needed).
2. **Impacts beyond the cell cap** (`fracture.lua:164, 252-261`): the 512-cell cap is reached after about
   four impacts and later hits are credited to the nearest old centre (a probe broke out a hole 23.5
   units from the eighth hit). Refine only the cells under a new impact and coarsen old rings far from
   it, so every hit cracks and breaks out where it landed.
3. **Weak hits** (`fracture.lua:88-90, 236`): energy below the crack floor is discarded, and the floor
   grows with the square root of the area and the thickness squared, so a 256x128 pane never cracks from
   pistol rounds and a 128x128x2 pane ignores every bullet under about 20 damage. Accumulate energy below
   the floor (no crack until it adds up) and cap the floor so a pistol round always cracks an ordinary
   window.
4. **Settings on clients** (`config.lua:10-14`): the replicated convars exist only on the server, so
   clients read nil (cracks always drawn; the menu shows minimums and "annealed"). Create them in both
   realms.
5. **Cost of a hit** (`fracture.lua:251, 262, 277`; `client.lua:23, 32, 73-79`): every hit rebuilds the
   whole fracture from all impacts with two connectivity passes, and a break on a client costs two
   rebuilds, eight `Remaining` passes and two mesh and physics builds (about 10 ms per hit and 25 ms per
   break near the cap, on the server and every client). Make it incremental, cache per revision, build
   once per message; record the per-hit and per-break times in the harness.
6. **Tempered glass**: no square-grid crack network. Before it breaks it may show a small spiderweb at
   the impact; when it breaks the whole pane goes.
7. **Map windows** (`server.lua:76-84`): the covering `Shatter` input sent to the hidden
   `func_breakable_surf` likely plays the engine's own shatter effect and sound (NoDraw does not hide
   them), so players would see two glasses. Fire the map's outputs without the engine's effect where
   possible; document what the engine allows.
8. **Drawing** (`client.lua:110-126`): no new `Matrix()`, `LocalToWorld` or class lookups per pane per
   frame; cache them; skip panes far away or behind the camera.
9. **Resync** (`client.lua:77`, `server.lua:248-255`): a revision mismatch resends every pane, and a
   joining player receives everything twice. Resync only the pane that mismatched; one initial push.
10. **Tiny edges** (`fracture.lua:70, 78`): cells with edges one 1/1024 step long are dropped by the
    piece mesh builder (7 of 14,598 cells in a probe). Merge vertices closer than 1/256 when clipping.
11. **Smaller ones**: map glass records the last impact of every hit, not only of cracking ones; the
    explosion push is sent after the break, so the pane's own pieces get it; the menu's budget slider
    stops at 8,192 like its convar; crack lines are not drawn along the pane's own border.

## G1-B fix pass (native and debris manager; branch `g1-native-fix`)

Owns `glass/native/**`, `third_party/jolt/**` (unchanged unless needed), `glass/addon/lua/nlglass/debris*.lua`,
`glass/addon/lua/nlglass/world*.lua`, the G1-B harnesses and tests, the QA probe of G1-B.

1. **One shape never disables the world** (`world.cpp:157`, `world.lua:74`): a hull or a prop convex Jolt
   refuses is skipped and counted (statistics), like a brush that cannot become a hull; only a map with no
   usable collision falls back. Clip brush hulls in double precision and deduplicate robustly (a 62-sided
   prism gave 282 float points and was refused). Test with generated fixtures, including a shape Jolt
   refuses.
2. **Displacements are transposed** (`bsp.cpp:146-151`): the fast index walks toward `quad[nearest+1]`;
   Source (`CCoreDispInfo::GenerateDispSurf`) walks toward corner 3, so uneven terrain is mirrored. Fix
   it and assert the position of one raised vertex in a fixture; check that tag bit 0 marks ordinary
   triangles on real maps.
3. **Per-frame cost** (`debris.lua:231-275`, `world.cpp:254-263`): Lua walks every piece three times a
   frame and ignores the changed list `ReadPoses` fills; natively each substep scans all 8,192 slots twice
   and locks per piece through `GetBodyInterface()` (9.7 ms per active step at 4,000 pieces). Use the
   changed list, `GetBodyInterfaceNoLock` and Jolt's active bodies; cap substeps by measured step time.
   Consider stepping Jolt asynchronously (start a step after reading poses, read it the next frame) so the
   game thread does not wait; measure and record before and after.
4. **Pile rebuilds** (`debris.lua:25-31, 65-91`): any change to a settled area destroys its merged meshes
   at once, so the pile draws piece by piece and rebuilds in one burst. Keep the old meshes until the new
   ones exist and spread rebuilds over frames.
5. **A full contact cache** (`world.cpp:258`, `debris.lua:226-228`): Jolt keeps running safely; count it
   and continue instead of throwing and dropping to the fallback.
6. **The map import** (`debris.lua:113-132`, `world.lua:52-64`): `Init(8192)` reserves about 144 MiB of
   temporary memory and the import parses the whole BSP on the game thread. Size memory to need, and move
   the parse and the static world build to a worker thread inside the module (Lua passes the bytes and
   polls), so a map with glass does not stall a frame for long.

## Both

`tools\test.ps1 -Config Release` passes. Never launch Garry's Mod; Claude runs the game checks. Never
write to the PoC or field install, touch Steam's files or `user.conf`, upload, or push, merge, tag or
commit on `main`. No downloads. Shared documents get additive edits only. Commit on your branch; your
final message is your report: what changed per item, tests and measured numbers, what remains for the game.
