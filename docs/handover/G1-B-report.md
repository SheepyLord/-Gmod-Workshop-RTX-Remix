# G1-B report: native glass world and client debris manager

Complete for implementation and offline acceptance, 2026-11-01, on `g1-native`, based on
`a99ca20`. Claude owns integration, packaging, real-map and in-game acceptance. No game was
launched; no game install, Steam file, real `user.conf`, package input, Workshop item or remote
branch was changed. No push, merge, tag or main commit occurred. The sole download was Jolt's
tagged release archive into this worktree's ignored `out/vendor`.

## Commits and files

- `74b25bc`: vendor Jolt Physics 5.3.0 unchanged, with MIT licence, archive URL/hash and initial
  G1-B status. All 444 upstream files were checked against the archive; our README is additional.
- `88d3e47`: native world/module, build integration, debris manager, fallback, QA probe, generated
  native fixtures, LuaJIT harness, companion documentation and [ADR 0072](../decisions/0072-glass-debris-world-and-batching.md).
- The following validation/report commit strengthens compressed-prop/hole coverage, runs the
  benchmark at the manager's capacity and records this handover. All commits carry the requested
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>` trailer.

The files are:

- `third_party/jolt/`: pinned `v5.3.0`, `Jolt/`, upstream `Build/CMakeLists.txt`, `LICENSE`, our
  `README.md`; archive SHA-256 `ee47dbd3de026829bc9734eeed960118c3d0a1a61b16e172009731a407d1466a`.
- `glass/native/`: `geometry.h`, `bsp.h/.cpp`, `world.h/.cpp`, `module.cpp`, `CMakeLists.txt`,
  `README.md`; tests in `tests/fixture.h`, `fake_lua.h`, `test_glass.cpp`, `test_binding.cpp`.
- `glass/addon/lua/nlglass/`: `debris.lua`, `debris_mesh.lua`, `debris_fallback.lua`, `world.lua`,
  each with adjacent `.md`. No G1-A-owned file was edited.
- `tools/tests/glass_debris_harness.lua`, `test_glass_debris.py` and their docs;
  `tools/qa/glass_debris_jolt_probe.lua` and its doc. The older `glass_debris_probe.lua` and its
  doc are byte-identical to the branch base, preserving the legacy baseline probe.
- Root CMake adds `glass/native`; additive CHANGELOG, COMPONENTS, RESEARCH, ROADMAP, TESTING and
  decision/handover index entries record implementation and validation.

## Module and binding

Release output, relative to this worktree:

```text
out/build/win64-release/glass/native/gmcl_nlglass_win64.dll
out/build/win64-release/glass/native/gmcl_nlglass_win64.pdb
```

The DLL is 1,355,776 bytes; PDB 15,224,832 bytes. DLL SHA-256 is
`3e11a4e3b26213961b0832a920abc10e360beedd7c126e744be525c01f351d9d`.
PE machine is `0x8664`, PE32+, with exactly `gmod13_open` and `gmod13_close` exported.
The evidence record is `out/g1-native/artifact.json`. No binary is committed.

`require("nlglass")` installs global `nlglass` and returns the API from module open. Exported
functions are `Init`, `LoadMap`, `AddModel`, `AddProp`, `FinishWorld`, `Spawn`, `Remove`, `Impulse`,
`SetCollide`, `SetGravity`, `Step`, `ReadPoses`, `IsSleeping`, `Stats`, `Clear`, `Shutdown`.
Signatures, result tables and numeric bounds are in [the native README](../../glass/native/README.md).
Failures return `nil, reason`; stale removes return false. Arguments and output tables use raw
access, no metamethods or Lua error longjmps. Actual callback tests check types, finite values,
integer/body/geometry bounds, stack balance, foreign/non-client realms and failure paths.

All positions/velocities cross the Source/metre boundary at 0.0254 m/unit. Source Euler angles
and world spin are degrees. Glass density is 2500 kg/m³, friction .65, low restitution and CCD;
sleep settings settle piles quickly. Eight workers are used on this 32-thread machine, according
to `max(1, min(8, hardware_threads - 2))`. Updates join before Lua access. Fixed steps are 1/60 s,
maximum four/frame, with excess time counted/discarded. Pose buffers and Lua rows are reused;
awake poses plus one final sleeping pose are emitted, with interpolation for drawing.

## Static world import

Lua reads `maps/<map>.bsp` from `GAME`, after a size check; mounted Workshop maps therefore use
the normal game VFS. The native reader accepts little-endian VBSP 19-21, including reordered v21
directories and Source LZMA collision/`sprp` data. It traverses model 0's tree to referenced solid
brushes and clips their halfspaces into hulls. Contents are `MASK_SOLID_BRUSHONLY` (`0x400b`:
solid/window/grate/moveable). Displacements of powers 2-4 become two-sided triangle meshes,
omitting non-surface triangle tags. `sprp` v4-11 supplies solid prop model/origin/angles/solidity;
v11 uniform scale is supported.

Two unique collision models or 64 instances are processed per client frame. A temporary
`ClientsideModel` with `PhysicsInit`/`GetMeshConvexes` supplies each unique model's convexes and
is always removed. Missing collision and over-complex collision are skipped/counted. Player and
monster clips, water, non-solid decorations, entity brush models, moving doors, gameplay bodies
and dynamic props are absent. Unsupported/malformed/empty/over-limit world collision fails the
whole import; the manager logs once, releases the native world and falls back. No import retry
loop runs. Cleanup retains map collision; map/client shutdown releases it and the worker pool.

## Manager and integration

`NLGlassDebris` implements the plan's five functions exactly: `Spawn(frame, pieces)`,
`Impulse(origin, radius, speed)`, `Clear()`, `Count()`, `Backend()`. It adds `Stats()` (reused
QA table) and `Shutdown()`. The three archived per-player convars have the agreed defaults:
lifetime 120 (0 until cleanup), budget 2000, collide 1. Budget is 0-8192. It reserves 8192 native
bodies once per map, so increasing the player's limit does not reread the BSP. Pending import
pieces are bounded; oldest pieces go first over budget, and expiry shrinks by transform only
during the final second. Clear removes our bodies/entities/meshes, never user assets.

Moving shards have both faces/edges, normals, pane UVs, material and optional color. Settled
shards batch per 256-unit XYZ area/material/color, capped at 60000 vertices/mesh. Changed areas
invalidate immediately, debounce 100 ms and rebuild at most two/frame. Wake, removal and shrink
unbatch immediately. Explosions also affect pieces still waiting for world import.

The Source fallback is limited to 64 client props and uses `PhysicsInitConvex`. Its conservative
`COLLISION_GROUP_WORLD` avoids gameplay contacts and forgoes piece-piece collision; the collide
convar applies to Jolt only. Native runtime failure migrates the newest surviving pieces at their
last displayed poses. `Backend()` is `none` before initialization or when no creation API exists,
`jolt` when ready, or `vphysics` for fallback.

For Claude: include `nlglass/debris.lua` before G1-A's calls. Ensure all four B Lua files are
client-delivered if using server `AddCSLuaFile` registration. The settings menu should bound the
budget slider at 8192. Import the DLL into the existing allowlisted package with the ordinary
package tooling and include Jolt's MIT notice (`third_party/jolt/LICENSE`); no allowlist changes
are required. G1-B has not modified `packages/`, `tools/workshop.json`, fixes packaging or A's files.

## Validation and measurements

`tools/test.ps1 -Config Release` passes conventions, **25 CTest targets** and **402 Python tests**
(349 tools + 28 gmapack + 25 steam; two expected fixture skips). The native glass target contains
11 cases. `out/test-release-complete.log` preserves the final full gate, and `out/native-tests-qa.log`
records strengthened fixtures and the reserve-matched benchmark. The LuaJIT manager/probe harness
passes **523 assertions**, executing the actual helpers and QA probe under engine doubles.

Native coverage includes generated BSP room/displacement/solid and non-solid prop data, both leaf
layouts, v21 directory order, LZMA leaves and compressed props, displacement holes, malformed-range
and mutation sweeps, degenerate hulls, collision against displacement/scaled prop, input bounds,
interpolation, final sleep pose, impulse wake and contact-overflow refusal. Disabling piece
collision removes that overflow. No generated game/binary fixture is committed.

Ryzen 9 9950X3D, 16 cores/32 hardware threads, Release, eight Jolt workers, 8192 reserved bodies,
4000 live axis-aligned 4x4x0.6-unit shards in four layers, no initial spin/velocity:

| Measurement | Result |
|---|---:|
| Spawn | 42.35 ms |
| All 4000 asleep | 11.0167 simulated seconds |
| Simulation wall time | 6.384 s |
| Total process CPU, all threads (`GetProcessTimes`) | 31.281 s |
| Active fixed step, mean / max | 9.657 / 17.063 ms |
| Settled step + pose output, 120 samples | 0.1225 ms mean |

Test limits are 15 simulated seconds, 30 wall seconds and 120 process CPU seconds. This measures
the native core; it excludes Lua/mesh work and Remix drawing. Earlier 4000-reserve numbers remain
in [RESEARCH](../RESEARCH.md) for provenance; the 8192-reserve figures match the actual manager.

## Known limits and remaining acceptance

- Actual mounted-map BSP variants/model collision and the live GMod ABI still need game checks;
  offline fixtures do not certify all community maps. Unsupported formats intentionally fall back.
- Real Remix materials, handedness on real displacements/prop instances, partial-map geometry
  and game frame-time parity are unverified here. Moving pieces draw individually and have
  measurable cost. The few-percent frame-rate target has not been demonstrated by these tests.
- The fallback omits piece-piece contact. Jolt omits dynamic/moving world entities as designed.
  Native capacity is 8192, fallback 64; complex/missing client prop collision is skipped.
- BSP parsing/cooking is synchronous once per map; model extraction/instances are spread over
  frames. Reserving the maximum uses more memory than the default player budget alone.
- The new [Jolt performance probe](../../tools/qa/glass_debris_jolt_probe.lua.md) measures a five-second
  empty baseline, falling shards and ten final seconds, reporting frame-time percentiles and
  manager/body/draw counts. It restores temporary client settings while preserving intervening
  edits. Claude should retain the console evidence, confirm the final moving count is zero and
  compare with the unchanged legacy probe/baseline. No in-game probe was run by G1-B.

No question or additional permission is needed for integration within the project's existing rules.
