# QoL report: complete interface translations

Latest batch: [player body, first-person arms and shadows](#player-body-first-person-arms-and-shadows-2026-10-30).

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


## Legacy Remix migration (2026-10-30)

Implemented on codex/legacy-remix-migration, based on e3c5a48. Loader 0.8.0 recognizes an
independently installed Remix by its bounded, statically parsed PE exports. It archives the old
runtime, known addon/mod roots, loose fixes and factory configs; stages and verifies our shipment
and clean stock recovery before replacing anything. Archive, stock restoration and package
installation use one durable deployment transaction. No old DLL is loaded for identification.
[ADR 0042](../decisions/0042-legacy-remix-migration.md) records the narrow depot-restoration
exception authorized by this request, exact hash/build guards, protected files and recovery limits.

The user replaced GarrysMod_RTX_c with this implementation. It and its backups were not touched;
AGENTS, ENVIRONMENT and the handover now identify it correctly. The field install was only read
for verified stock recovery; its bootstrap receipt remains 0.7.0. No Steam launch options changed.

The isolated out/legacy-game fixture starts from 2,877 Steam-verified files and the actual pinned
Xenthio nightly aaefa35 / runtime ZIPs, with all seven x64 launcher patches. The launcher's optional
fallback guard was independently probed and skipped as Unsupported, without changing bytes.
The fixture's original state, upstream hashes and recovery sources are in out/legacy-research.

Acceptance evidence in this worktree's out/legacy-acceptance:

- plan.json: zero writes; archive 496 old files and restore ten known modified depot files.
- 01-automatic-migration: first launch migrates and activates the packaged runtime/shader,
  reaches gm_construct in 20 s, zero Lua errors, normal quit/exit 0. Startup completes in 12.1 s.
- backup-audit.json: all 496 backup sizes/hashes match. Independent depot verification reports
  2,877 stock files, zero missing/changed/unverified/linked, with the intentional autoexec userconfig
  exception. The obsolete legacy Lua sentinel is gone; six protected user-file sentinels match.
- 02-rtx-off removes the source; 03-rtx-disabled-package-present retains it with remix.enabled=false.
  Both load system Direct3D at DX95, report zero patches/overrides, zero Lua errors and normal exit 0.
- Real uninstall retains the archive and leaves all 2,877 depot files stock. Old runtime/addons do
  not reactivate. Reconstructing the fixture from verified backup bytes then tests missing stock
  and an incorrect executable/client/server build: both fail with zero writes and all 496 originals
  intact. No field files are changed for these negative checks.
- 04-final-reinstall-migration validates the final build guard and a new permanent archive 1-2;
  archive 1 remains intact. It loads our runtime/shader, reaches the map, and exits normally with
  zero Lua errors. Ray tracing is True in the runtime log. final-audit.json verifies both archives,
  all protected sentinels and restored video-registry values. user.conf retains its original hash.
- After the game's generated create-only PBR file settles, a repeat apply is unchanged with zero
  operations. Generated regression tests also cover an RTX-off first deployment: old uninstall
  originals are transferred to the permanent archive, so a later uninstall cannot revive old Lua.

The complete Release suite passes 18 CTest groups and 258 Python tests. The migration CTest
interrupts and fails every filesystem operation and interrupts recovery too, requiring the complete
old or new state. PE tests include sparse distant/page-crossing tables, malformed RVAs, aliases,
forwarders, x86/x64 and reparse points. The bootstrap still imports only KERNEL32.dll.

The 919 payload hashes in the complete package are unchanged. Its manifest version and archive
description change to explain loader 0.8.0 migration; the branch build was validated by nlctl and
compared against the current Workshop archive (new metadata digest b71d8797b9c272ed). Its temporary
combiner folder was placed under the main out directory because nested worktree paths exceed the
existing package-reader path limit; source and validation still use this branch. No game binaries
or evidence logs are committed.

Known boundary: only the recorded GMod build/legacy depot edits are automatically restored. An
offline legacy install may lack six stock originals that RTXLauncher overwrote without backups.
Missing sources, unknown edits and other builds stop safely, with the missing file in the report;
--legacy-source supplies an explicit verified vanilla root. Custom configs remain with a note
about any RTX commands they still contain. No human assistance was needed for this task.


## Player body, first-person arms and shadows (2026-10-30)

Implemented on codex/player-body-arms from 369dac9. [ADR 0043](../decisions/0043-player-body-viewmodel-and-shadows.md)
records the rendering and compatibility decisions. The runtime's explicit enableInPrimarySpace
branch discarded every viewmodel candidate. Its removal makes first-person arms/weapons independent
of body visibility while preserving ViewModel.enable and the usual perspective correction.

The default layer no longer carries 549 captured player hashes or three body hashes, and returns
the primary-space body default to false. Original player/hand/ragdoll materials are migrated out
of the player category in memory when automatic categorization is enabled. This handles existing
saved configurations too: the read-only RTX_c inspection found 529 player hashes in rtx.conf and
four in user.conf. The native removal API only knows categories in its own cache, so the migration
supplies the missing local player-bit bookkeeping before targeted removal and preserves unrelated
category flags. Saved configuration files are not changed.

The shadow body is one independent client entity with a copied player bone pose, skin, body groups
and player color. Only its private copied textures receive player categories. A guaranteed pixel
change preserves alpha even for white inputs; copies are cached. Source eye shaders use a diffuse
fallback, internal compiled material flags are filtered while semantic alpha/cull flags remain,
and categorization waits for real draw hashes. The generic model fixer respects the proxy's custom
draw hook; per-index overrides and lighting are restored after drawing. No real-player bones,
camera or collision are moved. Weapon proxy ownership remains separate.

The new RTX Remix / Rendering / Player models panel has Local player shadow and Body height offset
(units), using archived rtx_pseudoplayer and rtx_pseudoplayer_offset_z. The UI range is -32 to 64;
render offsets are bounded to 128 units. Positive height changes world Z in either legacy angle
mode. All five labels/help strings are translated in zh-CN, zh-TW, ja, ko, fr and ru (174 companion
strings per catalog; 472 bundled interface strings per catalog remain complete).

The verified runtime source tree is the existing runtime-translations worktree, now on local
codex/player-body-arms-runtime, commit 2ba777de. Patch 0007 contains the nine-line C++ removal.
build_runtime.ps1 -Verify confirmed the seven-patch tree, NVAPI/RTXDI settings and DLSS/SHARC clones.
Only rtx_instance_manager.cpp changed; incremental meson compile -j 2 reused the verified shader
stamp. The rebuilt DLL is 362,792,960 bytes, SHA-256
ca3ce8dc21f052bf6026c74b776c8d2e4186c33e42023e29f2776852e865cefc.
It was imported only through inputs.py; no ABI or shader source changed.

Evidence is under the main out/player-body-evidence directory and this worktree's out:

- baseline-actors-chunked reproduces the reported bug with the old shipped runtime: primary-off
  hides the world model/ragdoll and leaves the first-person weapon; primary-on shows the models
  and removes the viewmodel. Source hand/viewmodel callbacks keep running in both states.
- release-validation runs the full changed package through seven views: primary off/on, world
  models with the body shadow enabled, visible body, ground shadow, 16-unit raised shadow and
  shadow disabled. Arms, world model and ragdoll remain visible; the own shadow moves and then
  disappears. Normal quit/exit 0, zero Lua errors, no proxy draw, duplicate-variable or early
  procedural-lookup errors. Shared material category bits remain clear; player/camera/root-bone
  positions remain unchanged. The controlled point light is destroyed at the end.
- legacy-settings-validation repeats those seven views with a temporary rtx.conf containing five
  explicitly authored shared-player hashes. Migration succeeds, other category bits are preserved,
  and rtx.conf/user.conf hashes remain unchanged. The temporary file is removed after verification.
- ui-diagnostic builds the actual registered player panel using stock Derma controls. After its
  first layout/convar synchronization, changing its checkbox and slider reads back shadow=1 and
  height=8; the screenshot shows both controls and help. Earlier helper attempts set controls before
  their first synchronization and are not reported as product passes.
- The clean fixture is out/legacy-game, whose depot files were verified for the previous batch.
  RTX_c and its backups were never written. Root user.conf files were never edited. Saved PoC
  policy/bootstrap/engine config, fresh-fixture policy/client/server config and video registry
  values were restored and hash-checked. Reused-PoC test shadow/height values were reset off/zero.

The final tools/test.ps1 -Config Release run passes all 18 CTest groups and 261 Python tests.
Lua tests execute the actual entity, category module, model-fixer guard and menu; cases cover legacy
unique_hashes=0, white textures, both offset modes, no real-player bone writes, skin/body groups,
death/spectator/third-person hiding, draw failure cleanup, saved category migration with missing
native bookkeeping, unrelated decal preservation and pending procedural hashes. Full package
validation passes: 919 files, with 14 changed payloads; only d3d9.dll changes among binaries. No Lua
source sidecars are deployed. Short temporary combiner paths avoid the existing long-worktree path
limit. A local wrapper retries a transient Windows directory-rename sharing denial without changing
product code.

Validation boundaries: several reused-PoC runs failed in the existing native hardware-skinning/model
cache reload before the probe began, including a RenderFinal trampoline exception. Those runs stay
in the private evidence and are not counted as passes; this task does not claim to fix that startup
instability. Fresh-fixture package runs started and quit normally. Controlled shadow sampling uses
importance-sampled GI after startup; the shipping GI defaults are unchanged. Existing legacy
pseudoweapon and built-in engine material diagnostics are outside the body-proxy change. The old
world-weapon proxy still follows its separate existing controls and the body primary-space setting.
No real field-install files were written, and no new public release or Workshop item was created.

## Remix settings persistence (2026-10-30)

User request 9: fix purity becoming zero at launch and saved settings being overridden or lost.
The Common Remix panel no longer binds empty-string settings to numeric widgets. Numeric overrides
require an explicit selection; old drafts are kept but inactive. Startup replay is a new opt-in,
off by default, so Alt+X saves remain authoritative at the next launch. Choices and numeric values
are validated; programmatic initialization and synchronization send nothing. The panel explains
that it shows its override drafts, not a live Remix readout, in all six languages. Fog ownership
tracks whether a preset was actually applied in this session.

Runtime patch 0008 makes Save atomic, checks failures, and advances the saved baseline only after
success. Failed Reload keeps active values. Legitimate zero settings remain supported. No manual
user.conf changes or field-install writes.

Validation: `tools/test.ps1 -Config Release` passed (18 CTest groups, 262 Python tests), as did the
seven Lua lifecycle scenarios, the dedicated runtime option-layer export/save/reload tests, the
native rebuild and eight-patch recipe verification. All six companion catalogs contain 178
translations; all six bundled-add-on catalogs still contain 472 translations.

The PoC hit the existing HWSkin model-cache reload crash before the probe. Two clean acceptance
sessions on the isolated stock fixture (`legacy-live-first`, `legacy-live-restart`) loaded the map,
quit normally, reported zero Lua errors and captured screenshots. A test-only GI=0 layer isolated
the earlier NRC/model-cache issues; runtime and Lua bytes matched the shipment. The menu sent no
numeric startup writes with legacy zeros, nor when opened or reopened. Explicit purity 0 and 1.61
each reached Remix once. The next process retained the selected draft and sent no stale menu writes;
Remix loaded purity 1.12 from its own configuration. The independent map-light wrapper's positive
sky-brightness update was identified separately from menu writes.

Both test installs' bootstrap, config, client/server VDF and video preferences were restored and
hash-verified. Native user config files remained unchanged; the test addon and marker were removed.
Evidence and delivery receipts are under out/settings-evidence and out/settings-*.log.

The in-game guide's Common Remix paragraph also describes opt-in replay, native saving and numeric
selection in all six languages. ADR 0022's status records the superseded startup-replay behavior.

## Welcome privacy and toolgun screen (2026-10-30, requests 21–22)

The runtime now requires a saved explicit diagnostic choice under a versioned policy. Missing
preferences and legacy checked defaults decline both reports. Unconfirmed SDK databases, including
queued data, are archived before initialization; no upload is granted by closing the welcome
window. Failed writes roll back consent. The crash question defaults to No. The welcome closes
after twelve visible seconds unless clicked, scrolled or navigated; permanent dismissal is
independent and can be reversed in Permissions. All new messages have six native translations.

Live acceptance used disposable LOCALAPPDATA and SDK-log folders. An unattended opening logged a
roughly twelve-second timeout. In welcome-final-permanent, clicking the title kept it open past
the deadline, then Never Show This Again saved neverShowFirstUseGuide=True while both grants stayed
False. welcome-final-restart, under the same profile and a newer package version, loaded and quit
without reopening the guide. The API's NoSave layer and the public cursor state were also corrected;
the welcome can be closed even when opened through the API and GMod releases its mouse correctly.

The companion redraws only the toolgun's live screen at full output resolution after upscaling.
Its original renderer and custom screen add-ons retain ownership of the animated texture. A private
gun/hands depth mask and actual viewmodel FOV keep the redraw aligned. RTX Remix / Rendering /
Toolgun screen contains its default-on toggle, translated in all six languages.

Nine Lua harness scenarios cover bone-zero weights, inverse bind transforms, live texture changes,
projection, unsupported views, stale frames, allocation retry, resize and failure unwinding.
toolgun-final-fg captured off/on comparisons at native resolution, DLSS and DLSS-G with subscribed
Dynamic Toolgun Screen. The backend actually resolved dlfg.enable=True (FSR False); live counters
advanced, screen text remained animated and aligned, and the module reported no errors. Assets
were mounted only from an owned fixture cache and are not redistributed. Private evidence is under
out/welcome-evidence.

## Layered model cutouts and outlines (2026-10-30, requests 3–4)

The runtime now rejects transparent alpha-tested candidates before committing ray hits. This
keeps valid coincident faces eligible and avoids the offset/retrace that could skip them. The
same alpha evaluation runs in ray-query and trace-ray paths, primary/PSR and indirect traversal.
NRC, SHARC, POM, portal and WBOIT variants retain matching payloads. Cached acceleration flags
also follow material/skin opacity changes and mixed shared geometry. Ray budgets and user.conf
remain unchanged. The targeted facial shadow policies explored during diagnosis are not shipped.

Incompatible outline geometry is ignored by default, as permitted in request 4. The runtime
handles front-culled opaque shells; the companion handles explicit outline names and the supplied
MMD family's dedicated hei/touming materials, including skin, submaterial and local-body proxy
bindings. It protects shared ordinary textures and owns only transient native options. The RTX
tab's Model outlines panel has a translated opt-out. No original model material is edited.

All three supplied cached Workshop models passed separate cold-process captures with micromaps
disabled: initial spawn, two seconds and fourteen seconds. Ganyu's live metadata shows two skins;
Lynette and March 7th show one. All three GBuffer ray modes, Ganyu's second skin and return to its
transparent skin, outline off/on and normal micromaps were exercised without Lua errors or an
abnormal exit. RTXDebug read the effective outline ConVar. A stock-model front-cull fixture checks
suppression separately from the user assets. No user asset is redistributed.

Native release and dedicated unit shader builds validated 104 any-hit and 104 closest-hit
entry-point stages. Runtime policy/export and transient outline-option suites pass. The outline
Lua harness has twelve lifecycle cases, and the toolgun harness has nine. All six companion
catalogs contain 184 translated messages; bundled catalogs retain 472; native catalogs contain
3303. The final import and package checks below complete the local validation.

Private evidence is under out/welcome-evidence; source-build/test logs are out/welcome-*.log.
Earlier unsuccessful sampler, offset, ray-limit and facial-policy experiments are not acceptance
passes. A local package-force test hit a transient Windows sharing denial and passed on retry;
final required checks are repeated after importing the verified runtime.

Final source build: native commit ccad20be, verified ten-patch tree
ac55626fec2a98faa62872c7cde648085a15226c. The full shader pass and subsequent C++ link produced
395512832-byte d3d9.dll, SHA-256
415fc0b353ad75375845ec92a75fc5001511a0496460dff420e6558d8cd7e5e9. Only this final DLL was imported
into Git LFS. Deep input verification reports zero problems. tools/test.ps1 -Config Release passes
18 CTests and 264 Python tests (28 + 25 + 211, with seven environment-dependent skips). The first
full run caught the new test's discovery import; the standalone lookup was corrected before the
passing repeat. No loader or packager behavior changed in this batch.

The checked branch package is 0.0.0-dev.20261031042614+22315109, content digest
a17e4e1b308f86bd1cbb46b8105205bdbfe1592081ba4f03bcbe2e9ac421e82a, validated by nlctl. Its only
payload differences from the published baseline are d3d9.dll, the menu, the two new client modules
and generated companion translations; no files are removed. package-shipping-models captures all
eight ray-mode/skin stages, including effective skin 1/2, and package-shipping-toolgun captures six
native/DLSS/frame-generation comparisons. Both load this actual GMA with an empty dev-folder list
and no loose test add-on, report zero Lua errors, and exit normally. Rendering probes explicitly
close the welcome through its transient API option; earlier captures covered by the welcome are
not visual acceptance. The separate welcome tests establish its timeout and dismissal behavior.

The fixture's original bootstrap, config, VDF and video settings were restored and hash-checked;
borrowed cache GMAs and generated option documentation were removed from the fixture. Native
user.conf retains its original SHA-256, and rtx.conf/dxvk.conf remain absent. Neither the real
GarrysMod install nor GarrysMod_RTX_c or its backups was written. Main's publish hooks update hidden
item 3829070317; out/workshop/published.json records the resulting upload and content digest.
