# Decision records

One file per decision, numbered in order: `NNNN-short-title.md`. An accepted record is never
rewritten; a later record supersedes it and both say so. Add one whenever a choice would surprise
someone reading the code later, or when [AGENTS.md](../../AGENTS.md) rules change.

| # | Decision | Status |
|---|---|---|
| [0001](0001-bootstrap-winmm-proxy.md) | The bootstrap is a `winmm.dll` proxy that works at the EXE entry point | Accepted 2026-10-27 |
| [0002](0002-source-agnostic-payloads.md) | Payloads are source-agnostic; Workshop route decided after a private upload test | Accepted 2026-10-27 |
| [0003](0003-native-trust-allowlist.md) | Only allowlisted packages may deploy native code until signatures exist | Accepted 2026-10-27 |
| [0004](0004-runtime-in-versioned-folder.md) | The Remix runtime is preloaded from a versioned folder, not copied into `bin\win64` | Accepted 2026-10-27; folder name refined by 0007 |
| [0005](0005-repo-conventions.md) | Agent-facing repo conventions and MIT licence | Accepted 2026-10-27 |
| [0006](0006-package-precedence-and-planning.md) | Package precedence (dev folder > local > Workshop) and planning rules | Accepted 2026-10-27 |
| [0007](0007-transactional-deployment.md) | Deployment is one journaled transaction per run, rolled back on failure | Accepted 2026-10-27; its rules for changed and foreign files superseded by 0035 |
| [0008](0008-activation-at-startup.md) | Activation at start-up: preload the runtime, config layers, environment, launch arguments | Accepted 2026-10-27; revised before merge for transactional activation and user layers; its layer paths amended by 0036 |
| [0009](0009-startup-deployment-last-good.md) | Startup deployment keeps the last good generation when an allowlisted source fails | Accepted 2026-10-27 |
| [0010](0010-rtx-session-extras.md) | RTX-session extras: in-memory patch sets, module overrides and session console variables | Accepted 2026-10-28 |
| [0011](0011-lua-addon-folders.md) | Packages may deploy GMod add-on folders (`garrysmod/addons/<addon>/`) | Accepted 2026-10-28; confirmed by the user 2026-10-28; a player's folder of the same name no longer blocks the package (0035) |
| [0012](0012-distribution-route.md) | Native packages are released outside the Workshop; the Workshop stays a supported source | Accepted 2026-10-28; superseded in part by 0015 |
| [0013](0013-rtx-only-addons-hidden-without-rtx.md) | Add-ons of RTX-only packages are hidden from sessions without RTX, in memory | Accepted 2026-10-28 |
| [0014](0014-r1-hardening.md) | R1 hardening: no `garrysmod/cfg` area, files only inside named folders, deployed files checked by size and time at activation, a restore that keeps the user's own changes | Accepted 2026-10-28; supersedes the `garrysmod/cfg` area of the M2 path rules |
| [0015](0015-workshop-route-for-native-packages.md) | Native packages can be distributed through the Workshop, packed with `gmapack`; their Lua comes through the loader's add-on folders, since GMod does not mount such an item | Accepted 2026-10-28 (the user, with the private upload test); supersedes part of 0012 |
| [0016](0016-one-workshop-item-kept-current.md) | Item 3829070317 carries one combined RTX package (runtime and fixes); commits and merges on `main` and pushes of `main` keep it current through git hooks | Accepted 2026-10-28 (the user) |
| [0017](0017-release-bundle-and-ci.md) | GitHub builds the loader on every push; the release bundle (winmm.dll, a README and a default `config.json` that allows item 3829070317) is extracted into the game folder | Accepted 2026-10-28 (the user) |
| [0018](0018-rtx-sessions-in-a-borderless-window.md) | RTX sessions run in a borderless window the size of the primary display, unless the player chose a window mode: the Remix runtime crashes on exclusive-fullscreen mode switches | Accepted 2026-10-28 |
| [0019](0019-agents-push-main-and-update-workshop.md) | Agents push `main` and update the project's Workshop items without asking; other branches, tags, force pushes and visibility still need the user | Accepted 2026-10-28 (the user) |
| [0020](0020-classic-rtx-settings-as-defaults.md) | The classic RTX install's settings are the package's defaults: Remix's in its defaults layer, the RTX add-ons' as first-run defaults in the companion | Accepted 2026-10-29 (the user); its frame-generation defaults amended by 0037 |
| [0021](0021-remix-defaults-in-one-low-layer.md) | Remix defaults ship as one low `DXVK_CONFIG_FILE` layer; `DXVK_RTX_CONFIG_FILE` stays unset, so the player's saved `rtx.conf` and `user.conf` win; forced windowed mode | Accepted 2026-10-29; supersedes 0008's layer-order assumption; its list-length consequence amended by 0036 |
| [0022](0022-companion-rtx-session-guard.md) | The companion guards RTX sessions against add-ons that undo them, gathers the RTX menus into one tab with more Remix settings, and carries an illustrated guide | Accepted 2026-10-29 (the user); startup replay superseded by [0044](0044-remix-settings-persistence.md) |
| [0023](0023-content-packages-and-modern-house-item.md) | Content packages carry Remix mods and their Lua; Modern House RTX is its own hidden Workshop item (3829275998); the Emissives mod ships in the RTX package, Water and Poolday do not | Accepted 2026-10-29 (the user); a player's copy of a mod no longer blocks the package (0035) |
| [0024](0024-bundled-addons-and-module-dependencies.md) | The RTX package bundles the user's five add-ons and Model Hotloader's natives, rebuilt from their sources at every publish; loader 0.3.0 loads a module's runtime DLL first, in every session (`module_dependencies`) | Accepted 2026-10-29 (the user); its hooks in the add-ons' repositories superseded by 0033 |
| [0025](0025-unsubscribe-removes-the-package.md) | Unsubscribing from a Workshop item removes its package completely: Steam lists the item nowhere and its folder is gone, so start-up removes the package and keeps no rollback copy (loader 0.3.1); amends 0007 and 0009 | Accepted 2026-10-29 (the user) |
| [0026](0026-addon-file-from-its-repository.md) | A bundled add-on may take single files from its own repository (`package_content.py --addon-file`): Model Hotloader's fixed install check comes from its main checkout until the classic install has it; extends 0024 | Accepted 2026-10-29 (the user) |
| [0027](0027-content-packages-from-any-subscription.md) | Content packages from any subscribed Workshop item deploy without the allowlist: discovery opens the subscriptions, and a package found there may hold only Remix mods and Lua add-ons (GMod's Workshop whitelist); native code still needs the allowlist; `allow.subscribed_content` switches it off (loader 0.4.0); amends 0003 | Accepted 2026-10-29 (the user) |
| [0028](0028-reshade-in-rtx-sessions.md) | ReShade in RTX sessions: a Direct3D 9 ReShade never loads into one (the runtime's `d3d9.dll` is bound) and its files are never written; the RTX package carries ReShade 6.8.0 unchanged as the Vulkan layer `VK_LAYER_nativeloader_reshade`, enabled by `remix.reshade` (auto, on, off) with settings of its own in `native-loader\reshade`, made once from the game's `ReShade.ini` (loader 0.5.0) | Accepted 2026-10-29 (the user) |
| [0029](0029-companion-translations.md) | The companion's tab, guide and notice in six languages, from gettext files in `companion/i18n` that people review and edit, built into the add-on when the RTX package is made; the language follows `gmod_language` or `nativeloader_language` | Accepted 2026-10-29 (the user) |
| [0030](0030-non-nvidia-gpus-and-late-runtime-dlls.md) | The runtime's late bare-name DLLs (FSR, NRC's CUDA) load right after it, by absolute path, because by then no search finds the runtime folder (`PATH` is rewritten, `AddDllDirectory` folders unread); without an NVIDIA GPU the bootstrap adds a layer with Remix's automatic graphics preset, above the package's and below the user's files; amends 0010, 0020 and 0021 | Accepted 2026-10-29 (the user); amended by 0036 (the package's layers listed as short copies) |
| [0031](0031-physical-sky-time-and-weather.md) | The companion turns on the runtime's physical sky and drives it: one clock places the sun, the moon and the stars (by default where the map's own sun is), and the runtime's twelve weather presets are blended by the companion, scaled for GMod's maps; a map's own sky add-on keeps its sky until the player changes a setting | Accepted 2026-10-29 (the user) |
| [0032](0032-real-moon-stars-eclipses-and-fog-presets.md) | The runtime draws the real Moon (NASA maps, lit as a sphere) and a night sky image (Night Sky HD LE's star, galaxy and nebula layers, turned by the sidereal time), and lunar and solar eclipses wherever the geometry has them; the sky owns its textures; the companion places eclipses by stage and offers Remix's fog presets under Remix settings (runtime-b6) | Accepted 2026-10-29 (the user) |
| [0033](0033-one-repository-package-inputs-in-git-lfs.md) | One repository builds the RTX package: every part's inputs in `packages/` (text as it is, binaries xz-compressed in Git LFS, indexed), unpacked into `out/inputs` for the packagers; the runtime fork's changes as patches in `runtime/`; no hooks or paths into other repositories; CI builds the package | Accepted 2026-10-30 (the user); its runtime description amended by 0034 |
| [0034](0034-the-runtimes-build-inputs-recorded.md) | The runtime's build inputs beyond the patches (submodules at other commits or patched, untracked clones the build reads) recorded in `runtime/base.json`; `build_runtime.ps1` checks a worktree is exactly that; `packaged` records what the stored DLL was built from, and `check_repo.py` fails while `runtime/` differs | Accepted 2026-10-29 (R3 fixes) |
| [0035](0035-restore-automatically.md) | Restore automatically: a `replace-owned` file that changed is put back at the next start (the changed copy kept in `backup/edits`), a file in a package's way is taken over (kept in `backup/originals`, put back when no generation names its path, and at uninstall); `load_first` files load only as deployed; `install-loader.ps1` keeps a foreign `winmm.dll` and puts it back at `-Uninstall` (loader 0.6.0); supersedes part of 0007, 0011 and 0023; amends AGENTS.md rule 3 | Accepted 2026-10-29 (the user, on R3-001) |
| [0036](0036-remix-layers-as-short-copies.md) | The runtime reads the package's Remix layers from short copies (`native-loader/remix/dxvk-<n>.conf`, `rtx-<n>.conf`) the bootstrap writes at each RTX start from the checked payload: the runtime ignores a `DXVK_CONFIG_FILE` of 260 characters or more, which the published package reached without an NVIDIA GPU (R3-017); amends 0008, 0021 and 0030 | Accepted 2026-10-29 (the user, on R3-017) |
| [0037](0037-frame-generation-off-by-default.md) | Frame generation is off by default, at one generated frame (2x) when a player turns DLSS-G on: the classic install's DLSS-G at 3x crashed RTX 30, RTX 40 and AMD GPUs at start, and Remix's menu hides the multiplier where multi-frame generation is unsupported; `remix_defaults.py` forces the three options; amends 0020 | Accepted 2026-10-29 (the user, emergency fix) |
| [0038](0038-complete-bundled-interface-translations.md) | Complete bundled interfaces, separate Traditional Chinese, Korean Destruction, strict catalog builds and client-localized notices | Accepted 2026-10-30 (the user) |
| [0039](0039-native-package-addon-presentation.md) | Inert display archives suppress native-container mount warnings; exact read redirects provide blue addon cards and normal Workshop descriptions; guarded publisher retry for a stale Steam presence check | Accepted 2026-10-30 (the user) |
| [0040](0040-native-map-glass-debris.md) | Native glass brushes keep map behavior and leave persistent convex physics shards; bounded debris and late-join mesh updates | Accepted 2026-10-30 (the user); persistence, no recursive fracture and the map-only budget superseded by [0061](0061-loose-glass-breaks-again-and-expires.md) |
| [0041](0041-hotloader-remix-depth-materials.md) | Hotloader avoids unavailable DepthWrite materials and Source depth passes on fixed-function Remix; programmable Source keeps its depth shader and cutouts | Accepted 2026-10-30 (the user) |
| [0042](0042-legacy-remix-migration.md) | Archive recognized legacy Remix installs and restore known modified depot files transactionally | Accepted 2026-10-30 |
| [0043](0043-player-body-viewmodel-and-shadows.md) | Independent first-person arms, private local-body categories and RTX-tab shadow/height controls | Accepted 2026-10-30 |
| [0044](0044-remix-settings-persistence.md) | Explicit GMod startup overrides, guarded numeric controls and atomic checked Remix saves | Accepted 2026-10-30 |
| [0045](0045-diagnostic-consent-and-welcome.md) | Explicit saved diagnostic consent, legacy SDK archival and an interactive twelve-second welcome timeout | Accepted 2026-10-30 |
| [0046](0046-toolgun-screen-after-upscaling.md) | Full-resolution live toolgun screen with private depth masking and a translated opt-out | Accepted 2026-10-30; mechanism superseded by [0057](0057-toolgun-screen-as-2d-overlay.md) |
| [0047](0047-ignore-incompatible-model-outlines.md) | Default-on suppression of incompatible outline shells through transient owned options and a translated opt-out | Accepted 2026-10-30; the shell rule made an opt-in by [0059](0059-outline-shell-rule-opt-in.md) |
| [0048](0048-layered-alpha-cutouts.md) | Reject transparent cutout candidates before ray commitment and keep cached acceleration opacity flags current | Accepted 2026-10-30 |
| [0049](0049-importer-normals-material-labels-and-motion-access.md) | Additive imported-model geometry normals, original AME material labels/current-row handoff, and a dedicated VMD launcher | Accepted 2026-10-30; the launcher tab superseded by [0060](0060-motion-tab-hosts-the-importer.md) |
| [0050](0050-startup-text-and-main-menu-diagnostics.md) | Editable localized project splash and local main-menu system/version/hash diagnostics | Accepted 2026-10-30 |
| [0051](0051-path-bounce-defaults.md) | Default minimum/maximum path bounces to 1/12 while preserving explicit overrides | Accepted 2026-10-30 |
| [0052](0052-scoped-rtx-multiplayer-bootstrap.md) | Verified RTX-owner multiplayer scripts and exact rendering recipe exception, preserving community Lua and unsafe debug gates | Accepted; amended by [0056](0056-guard-and-startup-fallbacks.md) |
| [0053](0053-oversized-hardware-skinning.md) | Share a scoped dynamic/direct hardware draw path for certified oversized groups and existing user-forced weighted draws | Accepted |
| [0054](0054-rtx-rendering-startup-boundaries.md) | RTX-only process backend selection and verified early client guard, with bounded Lua rendering compatibility and explicit evidence limits | Accepted design; validation in progress; amended by [0056](0056-guard-and-startup-fallbacks.md) |
| [0055](0055-legacy-migration-never-blocks.md) | The legacy migration never blocks the package: unplannable migrations are notes, links stay, other builds keep Steam's files, adopted files are archived | Accepted |
| [0056](0056-guard-and-startup-fallbacks.md) | A guard that cannot be prepared early never disables RTX (autorun fallback, kept-aside cache); the view's proof is local to the machine; the crashing opt-out stays vanilla; bootstrap and quarantine fixes | Accepted (R4) |
| [0057](0057-toolgun-screen-as-2d-overlay.md) | The toolgun screen is redrawn as projected 2D triangles after upscaling, since Remix takes perspective draws into its scene | Accepted (R4) |
| [0058](0058-gmpublish-preflight-fallback-recorded.md) | The gmpublish preflight fallback for a stale Steam process id, kept and bounded | Accepted (R4) |
| [0059](0059-outline-shell-rule-opt-in.md) | The front-cull outline shell rule is an opt-in (`nativeloader_ignore_outline_shells`, default 0); `nativeloader_ignore_outlines` keeps only the name rule, for materials of loaded models; amends 0047 | Accepted (R4) |
| [0060](0060-motion-tab-hosts-the-importer.md) | The Motion importer tab is the importer: the add-on's importer and Motion Manager built into the tab by its own builders (its windows use them too), in External Models' look | Accepted (R4) |
| [0061](0061-loose-glass-breaks-again-and-expires.md) | Broken glass (map debris and the add-on's fragments) is loose physics that players pass through, breaks again until it is dust, shares one 256-piece budget and fades out after `rtx_glass_debris_lifetime` (default 120 s); supersedes part of 0040 | Accepted 2026-10-31 (R5, the user's report) |
| [0065](0065-runtime-memory-diagnostics.md) | Shared runtime VRAM snapshots at cuts, five-minute intervals and device loss; atomic local crash marker and device-lifetime OMM warning limits | Accepted 2026-10-31 (R6 T4) |

| [0062](0062-loader-layers-performance-tiers-and-gpu-dumps.md) | Loader Remix layers first, GPU performance tiers and opt-in one-start GPU dumps; amends 0030's layer placement | Accepted 2026-10-31 (R6) |

## Template

```markdown
# NNNN: Title

- Status: Proposed | Accepted YYYY-MM-DD | Superseded by NNNN
- Decided by: who agreed

## Context
What forces the decision; facts with sources (link docs/RESEARCH.md).

## Decision
What we do.

## Consequences
What gets easier, what gets harder, what to watch.

## Alternatives considered
Each with the reason it lost.
```
