# R20-D: Source effects, native camera modes and dupe icons

Branch `r20-render`, from `9669f50`. Implements items 44 and 51 of
[R20-plan.md](R20-plan.md) under the [render brief](R20-D-render-compat.md).

## Built

- The guard observes `cam.End`, with one wrapper per closer. Native inspection established
  that End and End3D are different functions sharing the 3D counter; End2D, End3D2D and
  EndOrthoView have independent counters. Generic Start selects its mode and cleanup from
  the view type. Wrong-mode closers do not dispatch natively, and supported aliases balance
  both real and virtual pushes. Color-material helpers clear stale inert shader bindings.
- `_nativeloader_effect_categories.lua` automatically observes emitter particles, material
  changes, sprites/beams, DecalEx and already drawn materials. It recognizes packed `$flags`
  and DX fallback shader names, publishes three NoSave categories, and leaves named decal
  selection/random state alone. No add-on registration is required, including R20-C's effects.
  The observer is inert on server/RTX-off starts and never loads an undrawn character library.
- Runtime patches 0034 and 0035 join the categories with saved settings, retain effect vertex
  colors/texture factors, rasterize offscreen color/alpha canvases before RTX-only filtering,
  and translate premultiplied transmission filters. A zero-color, zero-alpha background is
  transparent instead of an opaque black rectangle. Changing effect alpha and filter draws
  bypass static opacity micromaps. No GPU record grows and no global alpha cutoff changes.
- The compiled-in project fallback introduced in patch 0012 now uses the renamed repository.
  Its correction is in patch 0034, preserving the historical patch series rather than editing
  an old patch and re-exporting the range. Each new patch was exported individually with an
  absolute output path.
- The diagnostic label has complete zh-CN, zh-TW, ja, ko, fr and ru translations. Technical
  option keys remain literal. ADRs [0120](../decisions/0120-camera-closers-share-the-guards-stack.md),
  [0121](../decisions/0121-source-effect-categories-for-the-session.md) and
  [0122](../decisions/0122-raster-canvases-keep-their-native-draws.md) record the decisions;
  0122 corrects 0120's initial assumption about the 2D closer.

The observer bounds work to twelve discoveries and twelve lookups per frame, 4,096 names,
64 hashes per material and 4,096 published hashes per category. Publications are sorted,
deduplicated, changed-only, at most four per second, with failure backoff. Shared white/error
textures are excluded. Renderer forwarding stays in tail position so foreign callers retain
the guard's shader policy and original attribution.

## Native and source findings

The readonly REA/Ghidra evidence is `out/r20d/camera-native-evidence.json` (nine records), for
PoC `bin/win64/client.dll`, SHA-256
`c994603b24197396d83315eb685ebdda0a5437aa30a3ea3c5091599b4fb66e9c`.

| Entry | Native function | Counter |
|---|---|---|
| End3D | `0x1800bc200` | `0x1808fb59c` |
| End | `0x1800bc2c0` | `0x1808fb59c` |
| End2D | `0x1800bbff0` | `0x1808fb598` |
| End3D2D | `0x1800bc0e0` | `0x1808fb5a0` |
| EndOrthoView | `0x1800bc380` | `0x1808fb5a4` |

The corresponding End3D, End and End2D dossiers are
`ev_294352dd77bd161c5b00e294705782734a602ffdfa33ef9a55e4f143165c6e50`,
`ev_121b08ecda0fe6a3612fe2c3dac4e4d2b5b50e5bcaa99e7fe690a71721f5c0cf`
and `ev_f4d4f4eeb2069cc88ef4a695e88f2a6cfb6991ddc730c554f7a4334049835d3a`.
These are static native observations, not a claim of executed decompiler source. Live valid
pairings were checked separately. No game code was copied into this repository.

Physics Blood uses packed flags and `UnlitGeneric_DX6`, float render-target canvases, dynamic
meshes and the premultiplied filter equation `Dst * (Src + 1 - SrcAlpha)`. Its alpha self-test
computes `(204/255 + 204/255) * 128/255`: native returned 205, the old runtime 255, and the
corrected runtime 205. The old runtime discarded alpha-only draws before recognizing an
offscreen raster target; unsupported filter blending separately fell back to opaque.

The shader's shared filter opacity helper computes `clamp(alpha - luminance(color), 0, 1)`.
The private legacy blend value fits the existing four-bit field; authored MDL/UI values remain
0..10. Authored material alpha state retains precedence.

## Tests and evidence

All evidence is under this worktree's `out/r20d`. Third-party fixtures are ignored local copies,
not redistributed inputs. Their original archive hashes are in `fixture-sources.json`:
Physics Blood 3818841829 (55 Lua files), Draconic Base 1847505933, Client Ragdoll Blood
3404773897 and its subscribed Zippy's Library dependency 3146473253. The latter's original
archive has a bad whole-archive CRC; only the test copy's trailer was cleared so the extractor
could validate/extract its per-file data. Nothing in Workshop storage was changed.

- Guard: 25 LuaJIT tests, including 257 sequential icon-style camera pairs, 3D aliases, nested
  generic 2D scopes, independent native mode counters, wrong-mode refusal, virtual pushes,
  cleanup and orthographic scopes. Existing add-on replays pass 25 tests.
- Observer: twelve real-script scenarios for packed DX7 flags, API forwarding, shared textures,
  late/changed hashes, name/hash budgets, retries, inert starts and color-material helpers.
  A combined observer/guard replay preserves untrusted shader refusals and original callers.
- Runtime: dedicated Release/Ninja unit build, both shader/embed passes; test_gmod_effects
  checks NoSave lifetime/invalidation and snapshots plus sixteen filter-equation combinations
  and saturation. The rebuilt suite passed 35 cases at the default budget; the unchanged threading
  stress case timed out at 120 seconds, then passed alone at 293.28 seconds with a 360-second
  allowance (`runtime-filter-thread-pass.log`). All 36 cases therefore passed; the time allowance
  change is reported rather than treating the timeout as an initial pass. The main wrapper verifies the exact source/dependency/patch tree and builds
  both passes. Receipts: `runtime-filter-build.log`, `runtime-filter-unit-build.log` and the
  `runtime-filter-unit-*` test receipts. The initial unit folder needed its unchanged XeSS DLL
  and RemixCategories plugin staged; generated RtxOptions.md was refreshed for the new options.
- `companion_i18n.py update` then all six translations and `check`: complete. Unrelated catalog
  reference-only churn was omitted. The normal tools suite discovers the observer scenarios.
- Final repository Release gate: `tools/test.ps1 -Config Release`, with process-local serial CTest dispatch (same 27 tests/assertions), passes before the last commit; receipt `release-final-success.log`. The default six-way run hit fixture startup timeouts on the shared host; serial execution passed all 27 without relaxing a test.

The locked controlled comparison snapshots/restores the PoC's add-ons, native-loader/runtime
trees, Lua modules, data, settings, configs and shared video registry. Each game uses -multirun,
quits normally and executes the field settings before quit. It keeps only its own console output.
The field game was neither launched nor ended. No user.conf or Steam depot file was changed.

Accepted baseline: `10-comparison/before` reproduces **97 cam.End underflows** on the actual
two-prop stock dupe save. `11-filter/after` has **zero Lua errors**, balanced native camera
diagnostics, the corrected canvas alpha, and no filter rectangles. Its initial JPEG still had
black preview lighting; the final color correction is separately accepted in `21-preview`. Its
heavy phase reached **420 droplets and 13 pools**; 12-second sample: **103.01 FPS**, median
**9.378 ms**, p99 **17.348 ms** on RTX 5090 at 1280x720. These are development measurements,
not a general performance guarantee. `12-final` records the corrected dust/front-flow framing: baseline 97 camera underflows,
RTX and vanilla zero Lua errors, all five captures completed, seventeen actual blood-impact
ParticleEffect calls in each phase, and a visibly flowing front-body stream. RTX: 105.15 FPS,
median 9.229 ms, p99 17.365 ms; baseline: 104.18 FPS, 9.298 / 18.505 ms; native: 720.03 FPS,
1.290 / 2.572 ms. The adaptive governor peaked at 383 drops/16 pools in that RTX run; the separate
11-filter run reached the 420-drop cap. Background model-import activity can affect these samples.

`21-preview` accepts the production stock dupe save: colored drum/crate JPEG
`after/trees/garrysmod/dupes/4b4d99dde23b04986635e04328d8b1ab.jpg`, zero Lua/guard/cleanup errors,
129 preview draws and eight distinct cached material identities. The last small optimization
looks up only the representative used map, avoiding other skins. No extra model renderer was
substituted in that acceptance probe. The guard catches late definitions and callback-local
suppression intent, uses a global unlit studio override, and restores it on every return/error.
The 300-draw transient-wrapper regression prevents the cache-exhaustion bug discovered in testing.
Entity submaterials and world materials are untouched.

Each accepted session has five captures: droplets/pools/stains, a body-flow view, Draconic dust,
Client Ragdoll Blood and the saved dupe. The actual dupe and its JPEG are preserved in the
archived `garrysmod/dupes` tree. The heavy probe calls the add-ons' own public/effect APIs;
the ragdoll run records actual `blood_impact_red_01` ParticleEffect calls.

Earlier folders are investigations, not acceptance substitutes. The first attempt used a Python
without Pillow; later runs use installed Python 3.12. Early camera diagnostics intentionally
exposed the mode assumption, and `jit.util` was unavailable in GMod; these were removed from
acceptance probes. One dust camera was inside a wall in both renderers and was reframed. Repeated fresh model
imports also exhausted scratch space and raised unrelated Model Hotloader notifications in
12-final; the snapshots were restored, obsolete generated GMA copies were removed, and warm
generated data was reused for later icon checks. A snapshot-copy failure occurred before any
PoC-tree mutation; its dead owned lock was verified and cleared. No user data was deleted.

The PoC is still byte-identical to its original cached depot manifests
4001/7488132547021413298 and 4002/7341198560151933050: **7,279,873,012 verified bytes**, zero
missing/mismatched/reparse/unverified files (`10-comparison/stock-verification.json`). Its
pre-existing autoexec is reported separately as user config. Borrowing the current field
manifests instead reports 46 differences because Steam updated the field after the PoC copy;
the PoC was not rewritten to conceal this age difference.

## Runtime delivery and integration

Source clone: the assigned R17 clone on `codex/r20-render`, starting at 51cf1b8b. Source commits
are a5251896 (0034) and 1d53ee00 (0035). The recorded NVAPI/RTXDI changes and DLSS/SHARC clones
were left as they were. Release DLL: **417,502,720 bytes**, SHA-256
`0c961bd62c758d0e2d716c0371c5a772f4fc0aeaf760e5f723df82ea9522968e`.
Exactly one final import/record update was performed (`runtime-import.log` and
`runtime-import-receipt.json`); no intermediate DLL was imported. Deep verification reports
11 parts, zero problems (`runtime-inputs-verify.log`). Local package overlays were used for iteration and validated with this branch's nlctl.

No push, merge, tag, publish, Workshop mutation or GitHub workflow was performed. The integrator
should combine the other tasks' new Lua paths in the guard's exact bundled inventory and merge
catalog entries by msgid, then run the aggregate gates before publishing.

## Open limits

- Raster preview fallback uses a representative base map and flat shading. Multi-material,
  translucent and custom-shader thumbnails are approximate; explicit caller overrides are kept.
  This does not affect the world/path-traced material or the saved dupe data.

- Legacy colored transmission is the runtime's scalar-luminance approximation, not full RGB
  destination multiplication. Source-only shader features such as distance-alpha shading are
  not ported to the path tracer. CPU-prelit add-on colors cannot be separated generically from
  intentional tint.
- Categories are texture-hash rules: another draw sharing a texture inherits them. Arbitrary
  custom shaders/blend equations remain outside general equivalence; authored replacements
  remain the higher-fidelity route. Name/hash budgets intentionally bound coverage.
- Equal-sized offscreen/primary targets remain ambiguous under the runtime's existing size
  heuristic. Explicit ray-traced targets keep precedence. No global category/cutoff override
  was used to hide that limitation.
- Temporal reconstruction may still soften fast/fading sprites. The moving-effect captures and
  timings do not establish pixel-identical DLSS output or field/multiplayer parity. The field
  was not tested; R2/integration remains the project manager's responsibility.
