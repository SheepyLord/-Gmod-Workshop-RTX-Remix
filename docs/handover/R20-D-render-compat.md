# R20-D: particle and decal add-ons under RTX, and the dupe icon (items 44 and 51)

Worktree `out/worktrees/r20-render`, branch `r20-render`, from `r20-int`. Implementer: Codex
(gpt-6.1-sol). Read first: [R20-plan.md](R20-plan.md) (the user's words and the rules for every task),
[AGENTS.md](../../AGENTS.md), [ADR 0022](../decisions/0022-companion-rtx-session-guard.md),
[ADR 0056](../decisions/0056-guard-and-startup-fallbacks.md),
`companion/nativeloader/lua/autorun/_nativeloader_guard.lua.md`,
[ADR 0081](../decisions/0081-mmd-alpha-texture-category.md) and
`companion/nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua.md` (how the companion tags
textures into a runtime category for the session), [runtime/README.md](../../runtime/README.md),
[docs/RESEARCH.md](../RESEARCH.md) (search it for decals, particles, render targets).

## The user's items

> 44. Improve the compatibility to vanilla particle / decal related addons to make them display
> correctly, eg. Physics Blood. https://steamcommunity.com/sharedfiles/filedetails/?id=3818841829
>
> 51. When saving dupe, the dupe can be saved, and used correctly, but throw an error: `cam.End
> underflow` at `gamemodes/sandbox/entities/weapons/gmod_tool/stools/duplicator/icon.lua:151` and
> `:213` (the full text is in the plan).

## Facts

- **51.** The guard wraps `cam.Start` with the pop `cam.End3D`
  (`_nativeloader_guard.lua:1284`, `pair(cam, "Start", "End3D", "camera", ...)`) and never wraps
  `cam.End`. The stock duplicator icon (the PoC's
  `garrysmod/gamemodes/sandbox/entities/weapons/gmod_tool/stools/duplicator/icon.lua`, lines 104-213)
  draws 32 `cam.Start(view)`/`cam.End()` pairs per entity per pass. Each pair leaves an entry in the
  guard's camera stack; at 32 (`chainDepth(stacks[kind]) >= 32`, line 1191) the guard rejects the next
  push ("tracked stack limit") with a virtual scope, the native `cam.Start` never runs, and the stock
  `cam.End()` underflows. Any add-on that ends `cam.Start*` with `cam.End` (the documented pairing for
  `cam.Start`) hits the same.
- **44.** Physics Blood is subscribed; its archive is extracted (read only) at
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r20\physics_blood` (copy it under your `out\` to
  install it into the PoC as a local add-on). 55 Lua files: flow meshes (`cl_bodyflow`, `cl_flow*`),
  droplets, pools on render-target canvases and atlases (`cl_poolcanvas`, `cl_poolatlas`, `cl_pools`),
  ground stains, wound effects, an LOD and a profiler.
- Known Remix traps for blood decals (from Blood Overhaul RTX's README,
  `H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx\README.md`): modulate-2x blending turns
  into an opacity from the colour's luminance; `alpha_test_type`; the runtime hashes textures with
  XXH64 here; `$color` reaches Remix as a texture factor; per-decal vertex colour does not.
- The guard's other rejections (render targets, MRT, depth targets, inert effect state, copies) are
  logged; read the guard's `.md` for how to see them.

## What to build

1. **The dupe icon (51), at the root.** Every native pop of a tracked push must pop the guard's stack:
   `cam.End` for `cam.Start` and every other alias the game accepts (check whether `cam.End`,
   `cam.End2D` and `cam.End3D` are one native function and what each `cam.Start*` may be closed with).
   Look through the guard's other pairs for the same class of bug. A regression test reproduces
   icon.lua's pattern (64 and more `cam.Start`/`cam.End` pairs in one protected callback, nested
   `cam.Start3D`/`cam.End`, and mismatched closers) with no rejection and balanced native calls; and the
   real dupe save in the PoC prints no error and writes an icon that shows the props.
2. **Particle and decal add-ons (44).** In the PoC with RTX on and off, run Physics Blood and at least
   two other popular vanilla add-ons that draw particles or decals from Lua (pick from what is
   subscribed in Steam's `workshop\content\4000` or common ones you can find; read their Lua, not the
   user's logs), and list exactly what displays wrong under RTX and why: guard rejections, how Remix
   classifies Lua particles, sprites, dynamic meshes and decals (missing, opaque or black quads,
   z-fighting, wrong blending, lit or shadowed wrongly, ghosting under DLSS), render-target canvases
   used as textures, and anything else. Then fix it generically, not per add-on where you can avoid it:
   the guard where it blocks legitimate rendering, session-only runtime categories for textures that
   Lua particles and decals draw (like the MMD alpha category: NoSave, joined with the player's saved
   categories, never written to `rtx.conf` or `user.conf`), runtime patches where the runtime must
   change (follow runtime/README.md; build in the existing clone
   `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r17\out\runtime-src`, where R17-R19
   built, on your own branch `codex/r20-render` from `51cf1b8b` (the current patch series; it has four
   uncommitted files of its own: leave them as they are); export your patch with `git format-patch -1
   --start-number <N>` and an absolute `-o`, never by re-exporting the range; import `d3d9.dll` once at
   the end). Vanilla behaviour with RTX off stays the same. R20-C
   (parallel) makes a new blood impact effect on the engine's particle and decal paths and relies on
   your mechanism; R20-C must not need to register anything.
3. If you rebuild the runtime, also update runtime patch 0012's compiled-in fallback text to the
   renamed repository (`https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix`); otherwise leave it.
4. **Docs.** ADRs 0120-0122 as needed (the guard's camera pops; the particle and decal categories;
   any runtime change), the guard's `.md`, every changed script's `.md`, RESEARCH (what you measured
   and found, file:line), CHANGELOG `### R20`, COMPONENTS, TESTING, runtime/README.md for a patch.

## Tests and evidence

- Guard tests in the existing harnesses (find them from the guard's `.md`), tests for any category
  logic, runtime unit tests for a runtime change.
- PoC (under the lock): before and after screenshots of each add-on's effects (Physics Blood's
  droplets, pools, flows, stains; the others'), RTX on and off, with what the guard logged; the dupe
  save (no error, the icon); frame time with the effects at their heaviest. Under `out\r20d\`.

## Your paths

`companion/nativeloader/lua/autorun/_nativeloader_guard.lua` (+ `.md`), new companion files for the
categories, `runtime/` (patches and records) and `packages/runtime` (one `d3d9.dll` import) if the
runtime must change, `loader/guard/` only if the guard's native half must change, `companion/i18n/`
for any new text, `tools/tests/` and `companion/tests/` for your tests, the docs named above.
