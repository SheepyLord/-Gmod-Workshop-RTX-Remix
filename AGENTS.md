# AGENTS.md

Start here. This file tells an agent (or a human) what this repo is, the rules that are not
negotiable, and how to build, test and document a change.

## What this repo is

A **native loader for vanilla 64-bit Garry's Mod**. The user drops one file, `bin\win64\winmm.dll`,
into an otherwise untouched Steam install. At start-up it reads **packages** (`.gma` files from the
Workshop or local folders), deploys their native payloads (the NVIDIA RTX Remix runtime, `gmcl_`
binary modules, files under the game root such as `rtx-remix\mods`) and loads the Remix runtime
before the engine creates its Direct3D 9 device. It replaces the old workflow of keeping a separate,
patched copy of GMod managed by RTXLauncher.

- How it works: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- What each component does: [docs/COMPONENTS.md](docs/COMPONENTS.md)
- Where we are and what is next: [docs/ROADMAP.md](docs/ROADMAP.md) (current: **M0-M7, R1, R3, R4 (reviews, fixes, the QoL round's review and field QA; loader 0.10.1), R5 (the user's QoL report), R6 (performance tiers and stability evidence; loader 0.11.0) and C-16 (steady anime eye whites) done; R2 (field parity with the classic install) in progress**)
- Picking up a milestone from another agent: [docs/handover/](docs/handover/README.md) (your brief is there; the latest round is [C16-report.md](docs/handover/C16-report.md), after [R6-report.md](docs/handover/R6-report.md) and [R5-qol.md](docs/handover/R5-qol.md))
- Why it is built this way: [docs/decisions/](docs/decisions/README.md)
- Facts gathered about GMod, Remix and the existing RTX tooling: [docs/RESEARCH.md](docs/RESEARCH.md)
- This machine (installs, toolchain): [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)

## Repo map

| Path | What |
|---|---|
| `loader/` | C++20 loader: `core/` library (`nl_core`), `tests/`, `proxy/` (the `winmm.dll`), `cli/` (`nlctl.exe`) |
| `tools/` | Build, test and maintenance scripts; each has a `.md` beside it |
| `tools/steam/` | Steam depot manifest tools: verify an install, build the vanilla PoC copy |
| `tools/gmapack/` | Vendored `.gma` reader and writer (Python) |
| `tools/sky/` | Tools that make the runtime's sky textures (the Moon, the night sky image) |
| `packages/` | Every input of the RTX package's eleven parts, so this repo alone builds it: text as it is, binaries xz-compressed in Git LFS, each part indexed in `files.json` ([packages/README.md](packages/README.md), [ADR 0033](docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)) |
| `runtime/` | This project's changes to the Remix runtime fork, as patches against the fork commit in `base.json`, with what else the build has (submodule settings, clones; [ADR 0034](docs/decisions/0034-the-runtimes-build-inputs-recorded.md)), and the script that rebuilds `d3d9.dll` from them ([runtime/README.md](runtime/README.md)) |
| `third_party/` | Vendored third-party code, byte-identical to upstream, each with its licence: `lzma/` (LZMA SDK decoder); `jolt/` (Jolt Physics 5.3.0, linked into the glass module); `reshade/` holds only ReShade's licence, for the unchanged ReShade binary the RTX package carries |
| `skills/` | Agent skills, each a `SKILL.md` with references and scripts: AI PBR materials for MMD characters (`mmd-remix-pbr`, with the `rpai` tool) and for maps (`remix-map-pbr`), and Workshop content packs with their dependencies (`workshop-content-pack`) ([skills/README.md](skills/README.md)) |
| `dist/` | What the end-user bundle ships besides `winmm.dll`: the default `native-loader/config.json` and the player README ([ADR 0017](docs/decisions/0017-release-bundle-and-ci.md)) |
| `glass/` | The glass system (G1, [ADR 0070](docs/decisions/0070-glass-overhaul.md)): `addon/` (the Lua add-on: panes, damage, cracks, fracture, broken-glass manager), `native/` (the Jolt client module for broken glass) |
| `.github/workflows/` | CI: `build.yml` runs `tools\test.ps1 -Config Release` on every push and pull request and keeps the bundle as an artifact; a `v*` tag releases it. `package.yml` builds the RTX package from `packages/` (Git LFS, cached) |
| `docs/` | Architecture, package format, on-disk layout, testing, roadmap, research, decisions |
| `CHANGELOG.md` | Notable changes, newest first |

## Rules

1. **Develop against the PoC install.** `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` is a
   byte-exact vanilla copy made for experiments. The field install `...\common\GarrysMod` is the
   user's real game: change it only when the user asks in this conversation, after backing up what
   you will touch. The user replaced `GarrysMod_RTX_c` with this project's implementation on
   2026-10-30: it is no longer a classic RTX baseline. Never write there or in
   `GarrysMod_RTX_c_backups`; prepare a fresh legacy fixture under `out` for migration tests.
2. **Never write Steam's files on disk.** Depot files in any install stay byte-identical; anything we
   need differently happens in memory or through a declared, journaled override (later milestones).
   [`tools/steam/verify_install.py`](tools/steam/verify_install.py.md) proves an install is still vanilla.
   The user's legacy-migration request (2026-10-30) permits one narrow exception: restore recognized
   pre-existing RTXLauncher modifications to hash-verified stock bytes, with the old bytes archived
   first in the deployment transaction ([ADR 0042](docs/decisions/0042-legacy-remix-migration.md)).
   This never permits patching an otherwise vanilla depot file on disk.
3. **Never touch Remix `user.conf`**, and never destroy a file the user edited (compare hashes first).
   A package's `replace-owned` file that changed is put back, and whatever was in its place is kept
   (`native-loader\backup\edits`, or `backup\originals`, put back when the package goes); a
   `create-only` file the user changed stays theirs ([ADR 0035](docs/decisions/0035-restore-automatically.md),
   the user, 2026-10-29).
4. **Native code is opt-in.** Only allowlisted packages may deploy or load native code
   ([ADR 0003](docs/decisions/0003-native-trust-allowlist.md)); a package from any other subscribed
   Workshop item may hold content only ([ADR 0027](docs/decisions/0027-content-packages-from-any-subscription.md)). Do not loosen the allowlist, the path
   rules or the off switches without a new decision record that the user agreed to.
5. **Ask before anything outward-facing:** pushing to `origin`, publishing or updating a Workshop
   item, changing Steam settings or launch options, deleting user data.
   - **Standing permission** (the user, 2026-10-28;
     [ADR 0019](docs/decisions/0019-agents-push-main-and-update-workshop.md)): agents push `main` to
     `origin` and update the project's Workshop items (3829070317 and test items) without asking, once
     `tools\test.ps1` passes. Other branches, tags (a `v*` tag makes a public release) and force pushes
     still need asking.
   - **Test items** (the user, 2026-10-28): agents may upload test items for this project to the
     Workshop, and update them, without asking. Keep them hidden. Modern House RTX is one: 3829275998
     ([ADR 0023](docs/decisions/0023-content-packages-and-modern-house-item.md)).
   - **Never remove or delete anything on the Workshop until the user says the project is done.** That
     covers the test items too (the first is 3829070317,
     [ADR 0015](docs/decisions/0015-workshop-route-for-native-packages.md)).
   - Making an item public, or publishing another real package, still needs the user's go-ahead.
   - **Item 3829070317 is the project's distribution item** (the user, 2026-10-28;
     [ADR 0016](docs/decisions/0016-one-workshop-item-kept-current.md)). It holds the combined RTX
     package, and commits, merges and pushes of `main` keep it current: git hooks run
     [`tools/publish_workshop.py`](tools/publish_workshop.py.md) in the background. That update needs
     no asking. A commit on `main` therefore publishes whatever its packaging inputs hold, so test
     those changes on a branch first. The build checks the package with the **main checkout's** built
     `nlctl.exe`: after a manifest change (a new key or kind), run `tools\build.ps1 -Config Release`
     there before the merge, or the publish fails. Install the hooks once per clone:
     `python tools\publish_workshop.py --install-hooks` (they also run Git LFS's hooks; a push without
     git-lfs is refused). The package is built from `packages/` alone, so a part changes only by an
     import committed here; the add-ons' own repositories do not reach the item.
6. **No binaries in git, except the RTX package's inputs in `packages/`** (the user, 2026-10-30;
   [ADR 0033](docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)): there every binary is
   stored xz-compressed in Git LFS, and only through `tools\inputs.py import`, which indexes it. No game
   files, build outputs or `.gma` packages anywhere else. Test fixtures are generated by the tests. Mind
   the LFS quota (10 GiB of storage and of downloads a month; a pushed object is never freed): import
   only what a part ships.
7. **Licences.** This repo is MIT. `garrys-mod-rtx-remixed` is GPL-2.0: read it for behaviour, do not
   copy its code into this repo's code. Its shipped files and local interface changes remain in
   `packages/fixes` under that licence, a separate part the package aggregates. The translated
   interface data in `companion/i18n/addons` is also GPL-2.0; the package carries its editable catalogs
   and `COPYING` ([ADR 0038](docs/decisions/0038-complete-bundled-interface-translations.md)).
   Third-party code goes in `third_party/<name>/` with its licence file; a part in `packages/` keeps
   its source's licence beside it. The repository is private: making it public needs a licence
   review of `packages/` first.

8. **Parallel milestones stay apart.** Each runs on its own branch in its own git worktree, and only
   touches the paths its brief in [docs/handover/](docs/handover/README.md) assigns. Shared docs
   (CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING) get additive edits only, so merges stay trivial.
9. **Temporary and build files stay inside this repo, under the git-ignored `out\`** (the user's
   instruction): builds in `out\build\<preset>`, extra git worktrees in `out\worktrees\<name>`, test
   scratch in `out\tmp` (`tools\test.ps1` and `tools\build.ps1` point `TEMP`/`TMP` there), evidence in
   `out\<purpose>\`. Never the system temp folder or a sibling folder: in M1, Windows Defender blocked
   proxy builds and test hosts that were outside this folder.

## Build and test

```powershell
tools\test.ps1                  # everything: conventions, Python tests, C++ build + CTest
tools\test.ps1 -SkipNative      # no compiler needed
tools\build.ps1 -Config Release # optimised C++ build (PDBs included)
tools\workflow.ps1              # what CI runs: Release checks, then the end-user bundle in out\dist
tools\workflow.ps1 -SkipTests -Install <game root>   # quick loop: build, bundle, put it in a game
git lfs pull; tools\workflow.ps1 -Package             # also the RTX package from packages\ (CI's package.yml)
python tools\build_package.py --compare out\workshop\published.json   # the package alone, against the item
```

Toolchain: VS 2022 Build Tools (MSVC x64), CMake and Ninja bundled with it, Python 3.10+. `vswhere`
cannot see the Build Tools on the main machine; `tools\lib\VsDevEnv.psm1` handles that. Build output
goes to `out\` (git-ignored).

## Documentation duties (every change)

`tools\test.ps1` fails until these hold (checked by [`tools/check_repo.py`](tools/check_repo.py.md)):

- Every script (`.ps1 .psm1 .py .bat .cmd .lua .sh`) has `<script file name>.md` beside it: what it
  does, usage, inputs/outputs, side effects, exit codes. Update it when the script changes.
- Every C++ module folder (one with a `CMakeLists.txt`) has a `README.md` naming each source file.
- [docs/COMPONENTS.md](docs/COMPONENTS.md) lists every folder under `loader/` and `tools/`.
- Relative Markdown links resolve.

Not machine-checked, still required:

- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for every user-visible or
  design-relevant change (new component, changed behaviour, fixed bug, new rule).
- Record design decisions as a new file in [docs/decisions/](docs/decisions/README.md); never rewrite an
  accepted decision, supersede it.
- Update [docs/ROADMAP.md](docs/ROADMAP.md) when a milestone item starts or finishes.
- Add facts you had to dig for (file:line, measured numbers) to [docs/RESEARCH.md](docs/RESEARCH.md).

## Glossary

| Term | Meaning |
|---|---|
| Field install | The user's Steam-managed `GarrysMod` |
| PoC install | `GarrysMod_PoC`, a vanilla copy for development |
| Bootstrap | `bin\win64\winmm.dll`: our proxy of the system `winmm.dll` |
| Package | A `.gma` with `native/manifest.json`; see [docs/PACKAGE_FORMAT.md](docs/PACKAGE_FORMAT.md) |
| Payload | Files a package deploys outside GMod's virtual file system |
| Runtime | The RTX Remix `d3d9.dll` and its dependencies (the user's fork, Remix API 0.1000.1) |
| Journal | `native-loader\state.json`: what the loader deployed, with hashes and backups |
