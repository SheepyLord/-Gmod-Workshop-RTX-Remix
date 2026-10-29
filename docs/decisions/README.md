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
| [0007](0007-transactional-deployment.md) | Deployment is one journaled transaction per run, rolled back on failure | Accepted 2026-10-27 |
| [0008](0008-activation-at-startup.md) | Activation at start-up: preload the runtime, config layers, environment, launch arguments | Accepted 2026-10-27; revised before merge for transactional activation and user layers |
| [0009](0009-startup-deployment-last-good.md) | Startup deployment keeps the last good generation when an allowlisted source fails | Accepted 2026-10-27 |
| [0010](0010-rtx-session-extras.md) | RTX-session extras: in-memory patch sets, module overrides and session console variables | Accepted 2026-10-28 |
| [0011](0011-lua-addon-folders.md) | Packages may deploy GMod add-on folders (`garrysmod/addons/<addon>/`) | Accepted 2026-10-28; confirmed by the user 2026-10-28 |
| [0012](0012-distribution-route.md) | Native packages are released outside the Workshop; the Workshop stays a supported source | Accepted 2026-10-28; superseded in part by 0015 |
| [0013](0013-rtx-only-addons-hidden-without-rtx.md) | Add-ons of RTX-only packages are hidden from sessions without RTX, in memory | Accepted 2026-10-28 |
| [0014](0014-r1-hardening.md) | R1 hardening: no `garrysmod/cfg` area, files only inside named folders, deployed files checked by size and time at activation, a restore that keeps the user's own changes | Accepted 2026-10-28; supersedes the `garrysmod/cfg` area of the M2 path rules |
| [0015](0015-workshop-route-for-native-packages.md) | Native packages can be distributed through the Workshop, packed with `gmapack`; their Lua comes through the loader's add-on folders, since GMod does not mount such an item | Accepted 2026-10-28 (the user, with the private upload test); supersedes part of 0012 |
| [0016](0016-one-workshop-item-kept-current.md) | Item 3829070317 carries one combined RTX package (runtime and fixes); commits and merges on `main` and pushes of `main` keep it current through git hooks | Accepted 2026-10-28 (the user) |
| [0017](0017-release-bundle-and-ci.md) | GitHub builds the loader on every push; the release bundle (winmm.dll, a README and a default `config.json` that allows item 3829070317) is extracted into the game folder | Accepted 2026-10-28 (the user) |
| [0018](0018-rtx-sessions-in-a-borderless-window.md) | RTX sessions run in a borderless window the size of the primary display, unless the player chose a window mode: the Remix runtime crashes on exclusive-fullscreen mode switches | Accepted 2026-10-28 |
| [0019](0019-agents-push-main-and-update-workshop.md) | Agents push `main` and update the project's Workshop items without asking; other branches, tags, force pushes and visibility still need the user | Accepted 2026-10-28 (the user) |
| [0020](0020-classic-rtx-settings-as-defaults.md) | The classic RTX install's settings are the package's defaults: Remix's in its defaults layer, the RTX add-ons' as first-run defaults in the companion | Accepted 2026-10-29 (the user) |
| [0021](0021-remix-defaults-in-one-low-layer.md) | Remix defaults ship as one low `DXVK_CONFIG_FILE` layer; `DXVK_RTX_CONFIG_FILE` stays unset, so the player's saved `rtx.conf` and `user.conf` win; forced windowed mode | Accepted 2026-10-29; supersedes 0008's layer-order assumption |
| [0022](0022-companion-rtx-session-guard.md) | The companion guards RTX sessions against add-ons that undo them, gathers the RTX menus into one tab with more Remix settings, and carries an illustrated guide | Accepted 2026-10-29 (the user) |
| [0023](0023-content-packages-and-modern-house-item.md) | Content packages carry Remix mods and their Lua; Modern House RTX is its own hidden Workshop item (3829275998); the Emissives mod ships in the RTX package, Water and Poolday do not | Accepted 2026-10-29 (the user) |
| [0024](0024-bundled-addons-and-module-dependencies.md) | The RTX package bundles the user's five add-ons and Model Hotloader's natives, rebuilt from their sources at every publish; loader 0.3.0 loads a module's runtime DLL first, in every session (`module_dependencies`) | Accepted 2026-10-29 (the user) |
| [0025](0025-unsubscribe-removes-the-package.md) | Unsubscribing from a Workshop item removes its package completely: Steam lists the item nowhere and its folder is gone, so start-up removes the package and keeps no rollback copy (loader 0.3.1); amends 0007 and 0009 | Accepted 2026-10-29 (the user) |
| [0026](0026-addon-file-from-its-repository.md) | A bundled add-on may take single files from its own repository (`package_content.py --addon-file`): Model Hotloader's fixed install check comes from its main checkout until the classic install has it; extends 0024 | Accepted 2026-10-29 (the user) |

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
