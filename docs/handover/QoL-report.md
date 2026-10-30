# QoL report: complete interface translations

2026-10-30. Implemented on `codex/translation-review`, from `main` at `7d79c12`.
The user expanded the audit to every bundled add-on interface. The implementation is recorded in
[ADR 0038](../decisions/0038-complete-bundled-interface-translations.md).

## Result

The requested Simplified Chinese, Traditional Chinese, Japanese, Korean, French and Russian catalogs
have complete key coverage. Existing Arabic and Spanish Motion Importer catalogs also pass validation.
There are **47,918 non-English catalog entries** across these components:

| Catalog | English keys | Translation coverage |
|---|---:|---|
| Companion tab, guide and notices | 169 | six languages |
| Newly localized bundled interfaces | 472 | six languages |
| Remix runtime | 3,298 | six languages |
| Bodygroup Tool | 104 | six languages |
| Destruction | 204 | six languages |
| Material Editor | 1,141 | six languages |
| Material parameter help | 83 | six languages |
| Motion Importer | 364 | six languages plus Arabic and Spanish |
| Model Hotloader | 2,030 | six languages |

Added Korean to Destruction and distinct Traditional Chinese catalogs and selectors to Bodygroup Tool,
Material Editor, its parameter help, Destruction and Motion Importer. Localized water, glass, portal,
light, sky, progress, context-menu and debug interfaces that previously had no translation path.
Tool IDs, convars, preset keys, filenames and user-provided model/bone/bodygroup names stay literal.

Wording fixes include the eclipse-progress label, the Korean waxing-moon typo, French sky-control
instructions, Russian sky descriptions, radiance-cache terminology, and 13 count-dependent messages.
English labels now describe glass strength, collision cost and airborne droplets clearly. Motion-wheel
state notices are localized in all its languages. The guide reflects frame generation being off by
default and names the corrected migration button.

Material Editor's reverse lookup was leaving generic labels in English when one locale used different
words for the same term. Colour, Texture path and Strength now agree, and Edit buttons carry explicit
context. Long spawn-menu slider/combo labels use a full-width line; checkboxes wrap. The user explicitly
accepted resizing the **Remix** settings window to reveal long labels, so those full labels are retained.

## Implementation

- `companion/i18n/addons`: reviewable PO sources for the newly localized interfaces, separate from the
  companion namespace. The packager embeds both and ships the GPL-derived catalog sources and license.
- `tools/companion_i18n.py`: strict release checks for missing, empty, fuzzy, duplicate, stale and
  unreviewed English entries; format checks and an explicit draft fallback option.
- `tools/check_addon_i18n.py` and LuaJIT harnesses: native catalog coverage, placeholders, language
  routing, context-sensitive labels, metadata language changes and localized client notices.
- Indexed package inputs retain their licenses and original line endings. Changes to GPL add-on code
  remain in that package part; the derived catalog data carries GPL-2.0 with editable source copies.
- Runtime patches 0005 and 0006: translated weather status values, clear cache names, strict catalog
  embedding, and static migration-button labels with separately formatted counts. The previous
  concatenated “Migrate 83 Developer Settings…” text bypassed lookup. Both migration directions are
  covered, and their behavior is unchanged. No migration button was clicked during testing.

## Validation

- `tools/test.ps1 -Config Release`: all checks passed, including **17/17 CTests** and **248 Python
  tests** (seven expected skips). Final CTests passed again with `--parallel 2`; final Python checks
  passed through `tools/test.ps1 -SkipNative`. The localization subset has 13 passing tests.
- `tools/check_addon_i18n.py`: **0 problems**, including real language-selection and label-switching
  assertions. Catalog exceptions record the exact intended English text, not just a reusable key.
- Runtime `build_runtime.ps1 -Verify`: the worktree matches the base and all six patches, pinned
  submodules and clones. Runtime catalog regressions: **5 passed**. The embedder validated every
  printf conversion and glyph in all **3,298 × 6** translations. The final UI-only incremental build
  used `meson compile -j 2`; shader sources had not changed. Imported DLL SHA-256:
  `7077609e831899082c861c511e75aa3f65ccbb4624bb1212deb07f224c6c133e`.
- Package builds passed `nlctl` validation. The final tested package is
  `0.0.0-dev.20261030111451+a239d15c`, 917 payload files, content digest
  `34dd032a342b7d7a` (prefix). Added files are the translation sources and license.
- PoC `ui-final`: **6,850 text elements** inspected across English and the six requested languages,
  **0 builder errors**, **0 Lua errors**, map loaded, runtime active, normal console quit, exit 0.
  The six apparent `Hair` matches are stored bodygroup filter identifiers, displayed verbatim by
  `cl_90_settings.lua:307`; translating them would change which model part the filter matches.
- All six runtime fonts were inspected in the foreground. The subsequent `migration-final` run loaded
  the rebuilt runtime, logged **French, 3,298 translated texts**, and logged **no untranslated UI text**.
  It completed its screenshot, reported zero Lua errors and quit normally with exit 0.

Evidence is retained under `out/qol-translations-20261030` in the main checkout; the original working
records are in `out/worktrees/translation-review/out/translation-audit`. PoC `config.json` and
`config.cfg` were restored to their saved hashes. Shared video registry values matched the snapshot,
so no registry write was needed. The field install and its running game were left alone. No Remix
`user.conf` was edited.

## Test constraints and remaining project issues

Normal RTX starts crashed during native setup with both the published package and the new package,
before the UI test ran. One startup logged 75.5/85.2 GiB of system commit in use. The successful UI
checks used `gm_flatgrass` and process-only overrides for low graphics, importance-sampled indirect
lighting and disabled ray tracing. They validate interface behavior and fonts, not default-setting
rendering stability under concurrent game load. A later RTX-on attempt with about 25 GiB of system
commit headroom still failed before the UI script. Its minidump identifies a null read in the unchanged
Steam `studiorender.dll` at offset `0x5d353` (the PoC and field binary hashes match). The cause is
unresolved; only exception/module metadata was inspected. The dump is kept locally in the evidence
folder and was not uploaded.

The nested worktree's 264-character staging path was rejected as a reparse point. A shorter, checked
staging root under the main checkout's `out/localization-build` completed packaging without relaxing
path rules. This existing path-length limitation remains. Runtime crash-report prompts can block
startup; the user declined the upload prompt. The flag that grants automatic upload consent was never
used. Use Python 3.12 with Pillow for screenshots and the test-console transport for protected commands.

No public release, tag, visibility change, field installation or Workshop item deletion is part of
this batch. Original add-on checkouts and the runtime fork's original checkout were left unchanged;
runtime changes are isolated in `out/worktrees/runtime-translations` and exported as patches.
Delivery uses the project's normal main merge/push and hidden-item publish hooks after validation.

## Native package addon cards (2026-10-30)

Implemented on `codex/native-addon-menu` from main `19d3e41`, as loader **0.7.0**
([ADR 0039](../decisions/0039-native-package-addon-presentation.md)). Current deployed Workshop
packages receive inert display archives; GMod mounts those while the loader continues to validate
and deploy the original native archives. Exact read-only filesystem redirects also provide a blue
card style and restore the existing Workshop description flow. No whitelist or trust rule is relaxed.
No depot or Workshop file is edited. Failed/unhandled packages retain ordinary error reporting.

The PoC main-menu test used Workshop enabled and RTX disabled. It mounted **761 of 761** subscriptions,
logged all four archive reads and the menu script read, showed all four native cards blue, and
showed the runtime's actual description. Neither requested console warning appeared. The session
quit normally with exit 0. PoC config files and its own video registry changes were restored; the
PoC keeps the tested 0.7.0 loader. Evidence lives in the task worktree's `out/native-addon-menu`.

The earlier Steam publication failure was a false presence check: the old registry PID made
`SteamAPI_IsSteamRunning` return false although real API initialization succeeded. A fallback for
one reviewed publisher/API build uses an isolated copy with only that preflight branch skipped,
after successful real initialization. Original authentication and ownership checks remain.

Validation completed: `tools/test.ps1 -Config Release` passed all **17 CTests** and **255 Python
tests** (seven expected skips). The proxy test group includes nine presentation/cache/IAT cases;
21 publisher tests include seven new fallback cases. Six assertions executed the actual generated
menu functions in Node, including disabled/floating cards and unrelated invalid addons. The branch
package passed nlctl validation: 917 payload files, digest `ef5a6e4d8ba631ac` (prefix). Its content
matches the previous main translation build; that update was still awaiting successful publication.

Installed the tested 0.7.0 bootstrap in the PoC and field install for the requested menu fix. The
field's earlier DLL, installer receipt and config are hash-verified in main-checkout
`out/field-backups/20261030-loader-0.7.0`, with `SHA256SUMS.txt`. Read-only apply and activation
previews passed. The field config is byte-identical; no game was running or stopped. The change
takes effect on the next launch. No Remix user.conf, Steam launch setting or depot file was edited.

## Modern House map glass (2026-10-30)

The user's map-glass request is implemented on `codex/map-glass` from main `28805d5`
([ADR 0040](../decisions/0040-native-map-glass-debris.md)). The bundled addon previously converted
only `func_breakable_surf`, while Modern House uses ordinary `func_breakable` brushes. The original
baseline removed the tested pane with zero procedural shards.

The new server handler caches native glass physics meshes and creates independent debris only
after the engine's real break event. Original health, filters, inputs and break outputs remain in
control. It covers 44 glass physics panes in Modern House, including horizontal/rotated shapes.
The shader and render mesh are those of the existing procedural glass addon. Map fragments remain
until cleanup or the 256-piece oldest-first budget. Existing count, velocity and collision settings
apply. Large full mesh resyncs use bounded packets; mesh bounds match received vertices.

The first fixed standalone run produced 18 shards, all with valid physics; all 18 remained after
30 seconds. The complete-package RTX run then showed reflective fragments, delivered the native
OnBreak output, handled scripted horizontal-glass breaks, kept the pile at 256 pieces, rebuilt
256/256 client meshes on full resync, cleared to zero on map cleanup and produced 18 new pieces
after breaking a restored pane. It loaded Modern House, logged zero Lua errors and quit normally.

The RTX test uses an RTX 5090 with ray tracing enabled, a low graphics preset and importance-sampled
indirect lighting. A stale crash-report prompt blocked an earlier attempt before engine startup;
that owned process was stopped without answering the prompt. A fresh process-only DXVK_LOG_PATH
under the evidence directory isolated the next test's logs/crash cache. No upload permission or
Remix user.conf was changed. This validates the glass effect, not a fix for earlier unrelated native
renderer crashes.

Evidence and the acceptance payloads are in the task worktree's `out/glass-map`. The field install
is not edited by this batch; the existing loader applies the Workshop package on the next launch.

Final RTX acceptance also retained an intact pane after a nonfatal hit, delivered exactly one
native OnBreak relay output and produced 36 shards after the second, scripted horizontal-pane
break. The tested blast did not break the native brush and produced no extra debris, preserving
its native behavior. Bulk breaks held the pile at 256, all 256 meshes resynced, cleanup left zero
and a restored window produced 18 again. Both complete-package RTX sessions quit normally with
zero Lua errors. Screenshots show reflected glass fragments on the ground.

Release checks passed: `tools/test.ps1 -Config Release` completed all **17 CTests** and **256 Python
tests** (seven expected skips). The final package passed nlctl validation with 923 payload files,
content digest `49b0cd7fa270f9ad` (prefix). Comparison with the current Workshop package shows six
added files and changes only to the Glass-Rewrite-Remix addon plus its manifest. The final package's
functional payload is byte-identical to the successful RTX test; its subsequent changes are docs.
PoC config.json and config.cfg were restored to their saved hashes. Shared video settings matched
the before snapshot, so no registry write was needed. The test's two DATA reports were saved to
evidence and removed from the PoC. No user game was stopped or operated.

## Hotloader DepthWrite shader errors (2026-10-30)

Implemented on `codex/hotloader-depth` from main `77a80dc`
([ADR 0041](../decisions/0041-hotloader-remix-depth-materials.md)). The reported model's 83 material
slots reproduced 83 depth-material creation requests and 131 unknown DepthWrite shader lines.
The fixed-function Remix shader family lacks that programmable shader; Hotloader created it
eagerly while registering the normal color draw.

The bundled Lua renderer now initializes the native backend before caching its flag. Remix uses
valid public color names in unused depth slots and skips Source depth-view draws; its normal color
geometry still supplies the ray tracer. Programmable Source retains the existing depth shader,
real texture bindings, alpha/cull settings and upload retry behavior. Cache version 11 refreshes
existing material maps. No console filter, native binary or asset-format change is involved.

The regression test executes the actual material builders and DrawCarrier for both backends,
including initialization, stale caches, pending Source textures, both depth flags, color/flashlight
draws, state restoration and cached registration. In-game acceptance uses the reported asset from
the PoC cache; no model files are copied to source control or included in the published package.
Evidence is in the task worktree's out/hotloader-depth.

Real acceptance passed on both shader families. The fixed RTX run made zero depth-material
requests and zero Hotloader unknown-shader messages, while executing 614 color draws; both forced
Source depth flags submitted zero draws. The baseline had 83 Hotloader messages (131 total with
48 separate built-in messages). Those built-in messages were unchanged, demonstrating that no
console filtering hid other errors.

The ordinary Source probe did not load the cached model; its status reported a deleted asset.
Source rendering remains covered by the executable regression tests. A separate real Source shader
probe at DX level 95 confirmed valid DepthWrite materials with the original alpha threshold 0.5.
No native binaries or real model files are added to the package; only the renderer Lua changes.

The complete-package acceptance also caught a prior glass-release packaging mistake: its adjacent
procedural_shard.lua.md was being included as Lua by GMod. The fixes packager now keeps *.lua.md
in source inputs and out of deployed scripts, preserving normal README/license files. The new
packaging regression passed. Built-in engine depth warnings remain unchanged; Hotloader-specific
shader requests and warnings are eliminated without filtering console output.

Final complete-package acceptance passed: zero Hotloader depth-material requests, zero Hotloader
unknown-shader lines, zero Lua errors, 619 color draws, normal exit 0. Both forced Source depth flags
were skipped on Remix. The source-documentation packaging regression is fixed in that tested
archive. The real Source shader-only probe confirmed the original DepthWrite recipe at DX level
95; the complete Source model probe lacked its managed cached asset, so it is not reported as a
model-rendering pass. Offline tests execute the real Source builder and draw routing.

The final full suite passed all **17 CTest groups** and **258 Python tests**, including the new
shader-routing and sidecar-packaging regressions. Package validation passed; its 919 payload files
have digest `794173d43f825560` (prefix). Relative to the current Workshop package, only Hotloader's
native_render.lua and the manifest change, and four Lua documentation sidecars are removed from
deployment. Their indexed source copies remain. PoC config.json and config.cfg were restored to
their saved hashes; video settings matched the before snapshot. User.conf and the field install
were not manually edited. No real model data is included in the package or source commit.
