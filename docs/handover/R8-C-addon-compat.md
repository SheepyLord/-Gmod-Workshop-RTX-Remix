# R8-C: vanilla graphics add-ons under RTX, again (brief)

Read [AGENTS.md](../../AGENTS.md), [R8-plan.md](R8-plan.md), [ADR 0054](../decisions/0054-rtx-rendering-startup-boundaries.md),
[ADR 0056](../decisions/0056-guard-and-startup-fallbacks.md), the C-13 audit
([C13-render-api.md](../audits/C13-render-api.md), [.json](../audits/C13-render-api.json)), the C13
sections of [TESTING.md](../TESTING.md#c13-graphics-add-ons-and-map-loading) and
[RESEARCH.md](../RESEARCH.md#c13-graphics-add-ons-and-map-loading), and the guard itself
(`companion/nativeloader/lua/autorun/_nativeloader_guard.lua` and the early stage the loader prepares).
Work on branch `r8-compat` in `out/worktrees/r8-compat`. Owns: `companion/**` (except
`companion/nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua`), `loader/**` where the guard's
early stage needs it, `tools/tests/*guard*` and new tests, `docs/audits/**`, ADR 0086, and additive edits to
CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS. Does not touch `glass/**`, `packages/**`, `runtime/**`.

## The user's request (2026-11-01)

C-13 asked that graphics add-ons such as Quick Bloom/HDR (2811767286), Real CSM (2817072898) and Life Mod:
Advanced Graphic Settings (1837527967) never fail a map load under RTX: better error handling and blocking
of unsafe methods, based on the vanilla Lua entry points of the GMod wiki; also GShader Library
(3542644649) with its sub-add-ons (collection 3728139288), and custom DX11 shader APIs such as
https://github.com/Akabenko/LUX-Gmod-shaderapidx11/. Now: "this addon still crashes the game or cause
instability and errors in a tester's computer: 3542644649. Treat this task as incomplete, reinvestigate
this part about vanilla addon compatibility."

## Evidence

- PoC run `out/qa-poc/r8/07-gshader` (read only; `console.log` is Claude's own session): gm_construct, RTX,
  single player, with GShader Library, FXAA (3555378834), SSDO (3707449642), SSR (3586554495) and NikNaks
  (2861839844) as local add-on folders. The map loads and the game quits normally on this machine. The
  guard rejects `lua/autorun/client/worldpos.lua:27` (`GetRenderTargetEx`, "unknown image format") by
  raising an error inside GShader's own `Initialize` dispatch (`!!shaderlib.lua:800`); it is contained,
  but players see it as a Lua error and the add-on's setup stops there. The engine then logs a run of
  "Failed to create shader" lines.
- Extracted sources (read only): `out/r8-c13/src/<id>/` for the five add-ons above; `out/r8-c13/details.json`
  has the Workshop descriptions of all 22 collection items and the three named add-ons;
  `out/r8-c13/collection.json` the collection. The installed copies are under
  `H:\SteamLibrary\steamapps\workshop\content\4000\<id>` (read only; also Quick Bloom, Real CSM, Life Mod).
- GShader Library replaces `_rt_ResolvedFullFrameDepth`, creates `_rt_WPDepth`, `_rt_NormalsTangents` and
  `_rt_Bumps`, draws screen quads with MRT and ps30 `screenspace_general` shaders, rebuilds world
  materials (`bumps_building.lua`, `lightmaps_building.lua`), wraps `DynamicLight` and `ProjectedTexture`
  early (`!!` autoruns), and hooks `RenderScene`.

## What to build

1. **No guard-made Lua errors.** A blocked call returns a safe, documented fallback instead of raising:
   for example a render target in a supported format of the requested size (or a shared inert target),
   a no-op for unsupported MRT/depth work, the engine's own texture for a reserved name. One bounded
   console note per add-on and call site; the add-on's setup continues.
2. **Find what can still crash or destabilize a session** with these add-ons under RTX, in single player
   and multiplayer (remote autoruns): every call on GShader's paths and the three named add-ons' paths
   that can reach a native fault, a device loss or broken world rendering (formats Remix's D3D9 cannot
   create, depth/INTZ/NULL formats, huge or zero-sized targets, MRT size mismatches, copies into depth,
   world materials switched to custom shaders or render targets, recursive views). Block or neutralize
   them under RTX before they reach the engine; leave RTX-off sessions unchanged.
3. **Screen-space shader effects under RTX.** Decide and document a policy for GShader-style post effects
   (their ps30 shaders fail to create under Remix, and they would draw over the path-traced image):
   inert under RTX by default, without Lua errors, so the add-ons stay installed and work when RTX is off.
4. **Tests:** LuaJIT harness cases that replay the extracted add-ons' calls (GShader Library with FXAA,
   SSDO, SSR, NikNaks; Quick Bloom; Real CSM; Life Mod) through the guard: no error escapes, fallbacks are
   returned, stock behaviour is preserved with RTX off and for legitimate calls.
5. **QA steps for Claude** (PoC): the add-on sets above in single player on gm_construct and a second map,
   and on a listen server with a second client (`tools` has the multiplayer session helpers), with what
   each must show.

You may read the add-ons' public source repositories (for example github.com/Akabenko/GShader-library) into
`out/r8-c13/` for analysis; never execute downloaded code. `tools\test.ps1 -Config Release` must pass;
commit on `r8-compat` (no push, merge, package import, game launch, install change or Workshop update).
Report in `docs/handover/R8-C-report.md`: what can crash and why, what changed, the policy, tests, limits.
