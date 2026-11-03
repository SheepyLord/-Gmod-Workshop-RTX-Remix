# R13-D: the option crash (runtime patch 0029)

**Status:** done. The cause is proven, and runtime patch 0029 fixes it. `main` `d2cf1bf` is pushed
and published to Workshop item 3829070317: version `0.0.0-dev.20261103205209+3061335f`, digest
`9366a66b...`, carrying `d3d9.dll` `b6fc1ae2`.

The task came from R13's project manager ([R13 report](R13-report.md), open items). One R13 PoC
session died about 15 s into idle with an access violation reading `0x50` in
`RtxOptionImpl::resolveValue`. The access happened under `RtxOptionManager::applyPendingValues`, on
the render thread. The task: find the cause, fix it with consistent locking as patch 0029, verify the
fix, and ship it.

## In short

- **Cause (proven).** `remixapi_SetConfigVariable` runs on the game's thread. The RTX fixes'
  `RemixConfig.SetConfigVariable` reaches it from Lua; the companion's sky alone sends its changed
  values every 20 ms. It called `RtxOptionImpl::readOption`, which did three things without the
  runtime's option update mutex:
  - inserted into the option's layer values;
  - wrote the value;
  - marked the option dirty.

  Meanwhile the render thread's `applyPendingValues` walked the dirty option map under that mutex.
  A unit test that does the same on two threads crashes the old code within two seconds. A caught
  crash is at `resolveValue+0x3e`, with the dump's registers, reading `0x50`, like the field crash.
- **More of the same.** Several other paths read or wrote option layer values, or the dirty map,
  without the mutex:
  - the layer acquire and release that mods' graphs use (R13-B's candidate);
  - the Remix menu's layer actions, which run on the game's thread;
  - two kinds of onChange callbacks.

  All of them now take it, in one lock order.
- **A second bug: lost settings.** `applyPendingValues` released the mutex between its passes even
  with no callback to run. A burst of writes from another thread could therefore keep it going to its
  pass limit, and its final clear then dropped the newest marks. Such a write took effect only when
  the option changed again. The stress test found this on the old code and on a first version of the
  fix. Patch 0029 fixes it too.
- **Verified:**
  - `build_runtime.ps1 -Verify`;
  - all 34 runtime unit tests, including the new `test_rtx_option_threads` (15 of 15 runs);
  - the GPU probe's `r13` and `game` sequences, identical to the published runtime in every memory
    mode;
  - seven PoC sessions. A Lua stress crashed the published runtime in the game within 10 s, with
    R13's signature; 0029 took the same load for 220 s. One idle 0029 start ended in NVIDIA's Vulkan
    driver, outside the option code, and two repeats were clean;
  - `tools\test.ps1 -Config Release`.

## 1. The crash, read from the dump

The dump (`out/r13/int/rec-medium/game/crash-reports/reports-7761cafb-....dmp` in the `r13-int`
worktree) holds only thread stacks. No heap and no module data, so the dirty map itself cannot be
read. The registers are enough:

- **The exception:** `EXCEPTION_ACCESS_VIOLATION` at `d3d9.dll+0x1b7e4e`, reading `0x50`, on thread
  72244 (render). Registers: `rcx=rdi=0`, `rdx=r14=0x58`, `rbp=r8=0`, `rbx=rsi=0`.
- **The instruction.** `rtx_option.*` did not change between that build and 0028. In the 0028 build,
  `resolveValue` (RVA `0x1b7dc0`) has at `+0x3e` the instruction `mov edx, dword ptr [rcx+50h]`,
  reading `m_type` for `GenericValueWrapper optionValue(m_type)`. `RtxOptionImpl` lays out its vptr,
  `minValue` and `maxValue` (two `std::optional<GenericValue>`), `m_hash`, `m_name`, `m_category`,
  `m_environment` and `m_description` first, so `m_type` is at `0x50`.
- **So `this` was null:** `rcx=0`, `rdx=0x58` is `&m_resolvedValue`, `r8=0` is no excluded layer.
  The loop `for (auto& rtxOption : dirtyOptions) rtxOption.second->updateResolvedValue()` got an
  entry whose value was `nullptr`.
- **How a null gets in.** `markDirty()` is `getDirtyOptionMap()[m_hash] = this` (an
  `std::unordered_map`). `operator[]` links a new node holding a value-initialized `nullptr` and
  stores `this` only afterwards. Correctly locked, no reader ever sees that. A thread walking the map
  while another inserts can, and concurrent inserts, rehashes and clears corrupt it.
- **The game's thread** (16144) was inside `D3D9DeviceEx::DrawIndexedPrimitive` ->
  `PrepareDrawGeometryForRT` -> `setupCategoriesForHeuristics` / `needsTerrainBaking`, holding the
  update mutex's address twice on its stack. It was a reader waiting for the lock the crashing thread
  held. It is the same thread that runs Lua's timers between frames.

## 2. The cause, in the code

These are the callers that read or wrote option layer values, or the dirty map, without the update
mutex, and the threads they run on:

| Where | Thread | Before 0029 |
|---|---|---|
| `remixapi_SetConfigVariable` -> `readOption` (`rtx_remix_api.cpp:1776`, `rtx_option.cpp:448`) | game | layer insert, value write, `markDirty`: only the API's `s_mutex` |
| `acquireLayer` -> `applyToAllOptions`, `releaseLayer` -> `unregisterLayer` | render (graph `RtxOptionLayerAction`), start-up | registry change, every option's layer values, `markDirty`: only the layer mutex |
| Menu: Discard Changes (`reload`), Save, Delete All (`removeFromAllOptions`), the migrations (`migrateMiscategorizedOptions`, the texture move), Unblock (`clearFromStrongerLayers`) | game (`ImGUI::render` runs in `D3D9SwapChainEx::Present`) | no lock |
| Menu: unsaved and misplaced counts, `hasValues`, `forEachChange`, `hasValueInLayer`; the Option Layers list walking the layer registry | game | no lock |
| `graphicsPresetOnChange` (Quality -> User on a switch to Custom), the deprecated-option migrations (`clearFromStrongerLayers`) | render, in onChange callbacks, which `applyPendingValues` runs without the lock | no lock |

- **Callers in GMod.** The companion's sky (`nativeloader_sky.lua`) calls
  `RemixConfig.SetConfigVariable` every `nativeloader_sky_interval`, 0.02 s by default, for each
  changed sun, moon and star value. Imported normals, MMD alpha, eye whites, model layers, the
  settings menu and several fixes add-ons call it when their inputs change. That fits an
  intermittent crash: about one session in ten in R13.
- **R13-B's candidate is real, but not this crash.** Graph components initialize, update and clean
  up on the render thread (`SceneManager` -> `m_graphManager.update(ctx)`), the same thread as the
  crashed loop. No mod in the RTX package uses graph layer actions.
- **Dynamic options cannot be destroyed** while in the dirty map. `findOrCreateDynamicOptionLocked`
  allocates them with `new`, and nothing deletes an `RtxOptionImpl` ("Never deleted; the registry
  holds raw pointers for the process lifetime"). Options marked dirty before they are published are
  alive too.

## 3. The stress test

`tests/rtx/unit/test_rtx_option_threads.cpp` is new in patch 0029. It runs the game's side against
a stand-in render thread that loops `applyPendingValues`:

- **`test_apiWritesDuringResolve`:** two seconds of `readOption` writes as fast as possible, the way
  `remixapi_SetConfigVariable` makes them, on 32 options. Then 500 rounds: write each option once,
  wait for two whole resolves, check that each write resolved.
- **`test_layerChurnDuringApiWrites`:** the render thread acquires and releases a layer with a value
  for every test option, as a graph does, while the game's thread writes and calls
  `getBlockingLayer`. Then 100 checked rounds.
- **`test_menuActionsDuringResolve`:** the game's thread migrates the user layer's misplaced values,
  reloads a file layer (Discard Changes) and clears stronger layers (Unblock), while the render
  thread edits the same options. Every option must end with the file's value.

| Code | Result |
|---|---|
| 0028 (no fix) | 3 of 3 runs crashed within 1.3-2.1 s (two access violations, one fail-fast). Under a Win32 debug loop (8 runs launched under it, 16 attached after start), timing changes. 2 attached runs crashed with access violations; the one recorded with registers is the field crash: reading `0x50` at the test's `resolveValue+0x3e` (`rtx_option.cpp:1151`), `rcx=rbx=rsi=rdi=rbp=r8=0`, `rdx=r14=0x58`. The other runs failed in round 1 with a lost write (for example `value0 resolved to 768, not 100`; one launched run's detail was not kept, exit 1). |
| First fix (the locks, but passes still unlocked between them) | 1 of 3 runs passed. Two lost a write in a later round (313 and 208), dropped by the final clear after the pass limit. |
| Patch 0029 | 15 of 15 runs passed: 1.46-1.74 million API writes, 6,237-20,109 layer cycles, 2,249-2,702 menu rounds against 2.3-2.9 million render-thread edits, and every checked write resolved. |

The debug loop (`catch_crash.py`), `dirty_map.py` and `symaddr.py` are with R13's dump tools in the
main checkout's `out/r13/verify/`.

## 4. The fix (patch 0029, runtime `a816a673`)

The rule is now written at `getUpdateMutex()` in `rtx_option.h`. Whatever reads or writes an
option's layer values, a resolved value that owns memory, or the dirty option map holds the update
mutex. Functions marked "Caller holds the update mutex" do not take it themselves. Layers join and
leave the registry under the layer mutex and then the update mutex, so holding either one keeps the
registry stable.

The lock order is: the API's `s_mutex` (already documented in `rtx_remix_api.cpp`), the layer mutex,
the update mutex, then the registry write and snapshot mutexes. The leaf mutexes come last: rejected
keys, the namespace registry, the dynamic request queue.

- **Take the update mutex themselves:**
  - `readOption`;
  - `clearFromStrongerLayers`;
  - `RtxOptionLayer`'s `reload`, `save`, `migrateMiscategorizedOptions`, `hasValues`,
    `hasUnsavedChanges`, `countMiscategorizedOptions` and `forEachChange`.

  `save` copies the values under the lock and writes the file after releasing it, because a save
  retries a held file for up to 10 x 50 ms. Its unsaved-changes cache is recalculated on the next
  query.
- **`acquireLayer` and `releaseLayer`** take the update mutex after the layer mutex, as
  `applyPendingValues` does. A layer's file is still read under the layer mutex only.
- **These hold the lock around helpers marked "Caller holds":**
  - the menu's Delete All buttons and its texture migration;
  - the Unblock popup's quality-layer check;
  - `graphicsPresetOnChange`'s move;
  - `logEffectiveValues`.

  The menu's Option Layers list holds the layer mutex. Nothing it calls takes that mutex, and the
  update mutex comes after it.
- **`applyPendingValues`** keeps the update mutex between its passes unless a pass runs a callback,
  and up to its final clear. A mark from another thread then lands before or after a whole pass: it
  is resolved in this frame or the next. Only a pass with a callback can lead to the next one and up
  to `maxResolves`. Upstream's final clear, which stops a callback cycle, is unchanged, so both cycle
  tests in `test_rtx_option` still pass.

Upstream code paths that run on one thread behave as before. The diff is 13 files, +392/-28,
including the 308-line test.

## 5. Verification

- **`runtime\build_runtime.ps1 -Fork <src> -Worktree <src> -Verify`:** the tree is base
  `c6b48ed1` with the 29 patches (tree `7bb69706`), with 2 submodule settings and 2 clones. Built
  `d3d9.dll`: 397,905,920 bytes, SHA-256
  `b6fc1ae2bd542fc51cf8093db51c4dd88daeffc125726a60edc4774095589b65`, version
  `remix-main+a816a673`.
- **The import.** The DLL was built with `-NoImport`, tested, and then imported once with the
  script's own two steps (`tools\inputs.py import runtime --file ...` and the `packaged` record in
  `base.json`, by `out/r13-d/write_packaged.ps1`). A second build would have changed the PE
  timestamp and GUID, so this keeps the tested DLL the shipped one. `-Verify` agrees afterwards.
- **Runtime unit tests** (`meson test --no-rebuild`, `_CompRelease_x64`): 33 of 34 pass under meson.
  The 34th, `test_remix_categories`, cannot load `d3d9.dll` under meson, because its definition
  leaves the dependency folders off `PATH` (as R13-B found). With them on `PATH` it passes.
  `test_rtx_option`, `test_rtx_option_dynamic` and `test_option_layer_export` pass, including the
  cycle and chain tests.
- **GPU probe** (`tools/qa/build_managed_texture_probe.ps1`, `out/r13-d/run_probe.py`). It ran the
  `r13` and `game` sequences on the published 0028 runtime (`91f0696c`, copies and budget off, then
  both on) and on 0029 (off, CPU copies released, a 1 MiB budget, both). All 12 runs exit 0 and are
  identical:
  - `r13`: hashes `0x3b0ee339a0e9da94` and, after the rewrite, `0x7d5f528ad278de3a`; sampled texel
    (2080, 2080); unmarked write 3117438 then 5614131, hash `0x7de71b987af57fd0`; 1.03-1.19 billion
    hash reads from the second thread, none wrong;
  - `game`: `0x93e625c1683421dc`, pixel 1122867.

  These are the values R13-B recorded.
- **PoC sessions and `tools\test.ps1 -Config Release`:** section 6.

## 6. In the game

The PoC sessions ran through `out/r13-d/lab.py`, on gm_construct at 1920x1080 with R13's crashed
settings: memory profile recommended, tier medium, `-insecure`. Each hold did the following:

- took the shared PoC lock;
- snapshotted the PoC's mutable trees (large files hard-linked, the rest copied);
- allowed only the given package;
- restored everything exactly afterwards, checking `user.conf` and GMod's shared video settings.

The stress (`r13d_stress.lua`) calls `RemixConfig.SetConfigVariable` 250 times per Think for the
sky's seven sun, moon and star values. It opens the user menu after 20 s; that menu asks
`user.conf`'s unsaved state every frame. It stops 20 s before the session ends. "Render" adds 250
calls in each of two render hooks, so the game's thread also writes while it issues draws, as in
R13's crash.

| Session | Runtime | Load | Result |
|---|---|---|---|
| s1 | 0028 (published, `91f0696c`) | stress, 60 fps cap | 3.3 million writes in 220 s, normal quit |
| s4 | 0028 | stress and render, uncapped | **crashed within 10 s of the stress**, before its first 10-second report. Access violation reading `0x50` at `d3d9.dll+0x1b7dfe` = `resolveValue+0x3e`, `rcx=rbx=rsi=rdi=rbp=r8=0`, `rdx=r14=0x58`. On the stack: `updateResolvedValue+0x15`, `applyPendingValues+0x2b9`, the update mutex and the dirty map. This is R13's crash |
| s2 | 0029 (`b6fc1ae2`) | stress, 60 fps cap | 4.2 million writes in 280 s at the 60 fps cap (as s1), normal quit |
| s5 | 0029 | stress and render, uncapped | 21 million writes in 220 s at 127 fps, normal quit |
| s3 | 0029 | idle | Ended 12.6 s after launch, at the menu, in NVIDIA's Vulkan driver (see below) |
| s6, s7 | 0029 | idle, 120 s each | normal quits |

- **R13's crash is reproduced in the game.** It happens on the published runtime as soon as Lua's
  writes overlap the render thread's frame end. With the 60 fps cap, the game's thread mostly sleeps
  while the render thread ends its frame, so s1 did not crash, which fits about one session in ten
  in R13. 0029 survives the load that crashes 0028.
- **s3's crash is a different failure.** It is an access violation reading `0xffffffffffffffff` in
  `nvoglv64.dll+0xe622f8`, on the render thread. The thread was in `DxvkDevice::createCommandList` ->
  `DxvkCommandList::beginRecording`, while two driver threads were busy (start-up pipeline
  compilation). There is no option code on that stack, and no driver reset in the System log. Two
  idle repeats on the same package ran cleanly. It is recorded as an open item.
- **The restores.** Every hold restored the PoC exactly (4,145 files each), and `user.conf` and the
  video settings stayed unchanged.
- **Disk space.** The snapshot copies and the set-aside session files (1.2-1.3 GB each) filled H:
  until they were deleted after the seventh hold. Each hold's records (`snapshot.json`,
  `restoration.json`, the session record) are kept.

`tools\test.ps1 -Config Release` passes on the branch, run twice (before and after the commit): the
repository checks, 26 CTests, and 28 + 25 + 539 Python tests.

After `main`'s R13-P commit (docs only) was merged in, `tools\test.ps1 -SkipNative` first failed in
one test. `test_poc_parity`'s round trip requires 20 GiB free on H:, and the labs' set-aside folders
had left 19 GiB. With 26 GiB free it passes: the repository checks and 28 + 25 + 539 Python tests.

**Publication.** `main` `d2cf1bf` was pushed (59 MB of LFS objects: the new `d3d9.dll.xz`). The merge
hook uploaded item 3829070317 as version `0.0.0-dev.20261103205209+3061335f` (digest `9366a66b...`).
Its manifest names `d3d9.dll` `b6fc1ae2`. The push hook found its inputs unchanged. The field
install takes it from the Workshop: its first start downloads, the second deploys.

## 7. Deviations and open items

- **The import used the script's own steps** rather than a second full `build_runtime.ps1` run (see
  section 5).
- **Patch 0029 is a locking audit across upstream files.** It edits 11 runtime sources. As patches
  0024-0028 did, it does not update the fork's `docs/fork-touchpoints.md`.
- **Two races remain, both harmless and deliberately left:**
  - The graph's `requestEnabled`/`requestBlendStrength` (render thread) and the Option Layers
    list's own requests (game thread) write a layer's per-frame request fields without a common
    lock. A request may be lost for one frame. Locking the graph's per-instance update would cost
    every frame.
  - `writeMarkdownDocumentation` reads default values without the lock. It runs only for the
    documentation at start-up, and nothing changes default values after an option is registered.
- **A callback cycle still loses marks.** A cycle that runs `maxResolves` passes in one frame still
  drops marks another thread made during the last pass's callbacks (upstream's cycle guard). Nothing
  in GMod forms such a cycle.
- **s3's start-up crash in NVIDIA's Vulkan driver** (section 6) did not repeat, and nothing ties it
  to this patch. The R13-B report has device losses on the original runtime, and a separate
  device-loss session exists for this machine.
- **Patch number 0029 is also R13-F's.** R13-F (runtime: material preloads at their first draw) is
  writing its own 0029 in parallel; it was told. Whichever lands second renumbers to 0030 and
  rebuilds on top.
- **The PDB.** The tested DLL and its PDB, for symbolizing a crash of this runtime, are kept in this
  worktree's `out/r13-d/runtime-0029`.
