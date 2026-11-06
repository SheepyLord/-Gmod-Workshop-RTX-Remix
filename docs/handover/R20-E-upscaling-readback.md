# R20-E: a live upscaling readback for the startup hint (item 45, native half)

Worktree `out/worktrees/r20-native`, branch `r20-native`, from `r20-int`. Implementer: Codex
(gpt-6.1-sol). Read first: [R20-plan.md](R20-plan.md) (the user's words and the rules for every task),
[AGENTS.md](../../AGENTS.md), [runtime/README.md](../../runtime/README.md),
[tools/ci/README.md](../../tools/ci/README.md) (how the fixes' module is built from a public base and
GPL patches in `packages/fixes/licenses`), and R20-B's consumer: `git show
r20-qol:companion/nativeloader/lua/autorun/client/nativeloader_upscaling_hint.lua` and its `.md`
(branch `r20-qol`, commit `f7f8764` or later).

## Why this task exists

R20-B wrote the startup hint the user asked for ("Add a game hint to remind user to enable frame
generation / up scaling if they didn't enable it when the game start"). It found that Lua cannot read
the runtime's effective settings: the fixes' `RemixConfig.GetConfigVariable` reads `rtx.conf` from disk
(`packages/fixes/licenses/oversized-skinning/memory-limits/source/remixapi/remixapi.cpp:1111`), and the
runtime applies its device-dependent graphics and DLSS presets later (`rtx_options.cpp:411`,
`updateGraphicsPresets`). So R20-B's hint reads an optional native function and stays silent without
it. You provide that function.

## The contract (R20-B's consumer, unchanged)

`RemixConfig.GetUpscalingState()` returns a fresh table, or nil when not known yet:

| Field | Meaning |
|---|---|
| `ready` | true only after the startup graphics and DLSS presets and pending option callbacks resolved |
| `upscaler` | the effective `rtx.upscalerType`, integer 0-5 |
| `frame_generation` | the effective `rtx.frameGenerationType`, integer 0-2 |
| `dlss_supported` | true only when DLSS is usable on the selected device |
| `dlss_frame_generation_supported` | true only when DLSS frame generation is usable |
| `fsr_frame_generation_supported` | true only when FSR 3 frame generation is usable |

Read R20-B's file for the exact checks it makes; match them. If the contract needs to change, say so in
your report instead of changing R20-B's files.

## What to build

1. **The runtime side.** The fork already has a thread-safe string map that plugins read with
   `remixapi_GetGameValue` (`public/include/remix/remix_c.h:756-790`). Prefer publishing the state there
   under reserved read-only keys the runtime writes (effective values and capabilities, refreshed when
   presets resolve and whenever one of these options changes), over adding API functions; a key a
   plugin writes must not be able to fake them. Write it as one runtime patch numbered **0040** (R20-D
   may add 0034-0039 in parallel; Claude renumbers at the merge). Work in your own worktree of the
   runtime repository: `git -C H:\BACKUP_20260815\Modding\dxvk-remix-gmod worktree add <your
   worktree>\out\runtime-src -b codex/r20-native 51cf1b8b` (51cf1b8b is the current series; R20-D uses
   the clone in `out/worktrees/r17/out/runtime-src`, do not touch it). Build it with
   `runtime\build_runtime.ps1` to test, but **do not import `d3d9.dll`**: Claude builds the runtime
   once with every R20 runtime patch and imports it once. A runtime unit test for the publisher.
2. **The fixes' module side.** A GPL patch in `packages/fixes/licenses/oversized-skinning/` (its own
   folder, with a README like its neighbours) that adds `RemixConfig.GetUpscalingState()` to
   `gmcl_RTXFixesBinary`, reading those keys through the API, defensive against an older runtime (no
   keys: return nil). List it in `tools/ci/pins.json` (`fixes.patches`, and the new `patched_tree`
   ids as `patched_tree_why` describes), build with `tools\ci\build_modules.ps1` (its `.md` has the
   local command), and import the module into `packages/fixes` once at the end with
   `tools\inputs.py import`.
3. **Proof in the PoC** (under the lock): your runtime and module, a small Lua probe (not R20-B's
   files) printing `RemixConfig.GetUpscalingState()` at startup and after changing the upscaler and
   frame generation in memory (`RemixConfig.SetConfigVariable`; never save, never write `user.conf`),
   `ready` false until the presets resolve. Note the GPU's capability values. Evidence under
   `out\r20e\`.
4. **Docs.** ADR 0123 (the readback: keys, who writes them, the contract), runtime/README.md (the patch
   and that it is not yet in the imported `d3d9.dll`), `packages/fixes` licence README for the patch,
   `tools/ci/README.md` if the pins change shape, CHANGELOG `### R20`, RESEARCH (file:line you relied
   on), TESTING.

## Your paths

`runtime/patches/0040-*.patch` and `runtime/README.md` (and whatever runtime records its README says a
patch updates), `packages/fixes/licenses/oversized-skinning/<your folder>/`, `packages/fixes` (the
module import), `tools/ci/pins.json`, `tools/tests/` for tests, the docs named above. Not R20-B's
companion files.
