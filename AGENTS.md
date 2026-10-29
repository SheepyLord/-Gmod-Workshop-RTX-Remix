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
- Where we are and what is next: [docs/ROADMAP.md](docs/ROADMAP.md) (current: **M0-M7 and R1 (whole-repo review, fixes) done; R2 (field parity with the classic install) in progress**)
- Picking up a milestone from another agent: [docs/handover/](docs/handover/README.md) (your brief is there)
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
| `third_party/` | Vendored third-party code, byte-identical to upstream, each with its licence: `lzma/` (LZMA SDK decoder) |
| `dist/` | What the end-user bundle ships besides `winmm.dll`: the default `native-loader/config.json` and the player README ([ADR 0017](docs/decisions/0017-release-bundle-and-ci.md)) |
| `.github/workflows/` | CI: `build.yml` runs `tools\test.ps1 -Config Release` on every push and pull request and keeps the bundle as an artifact; a `v*` tag releases it |
| `docs/` | Architecture, package format, on-disk layout, testing, roadmap, research, decisions |
| `CHANGELOG.md` | Notable changes, newest first |

## Rules

1. **Develop against the PoC install.** `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` is a
   byte-exact vanilla copy made for experiments. The field install `...\common\GarrysMod` is the
   user's real game: change it only when the user asks in this conversation, after backing up what
   you will touch. `GarrysMod_RTX_c` and `GarrysMod_RTX_c_backups` are reference only; never write there.
2. **Never write Steam's files on disk.** Depot files in any install stay byte-identical; anything we
   need differently happens in memory or through a declared, journaled override (later milestones).
   [`tools/steam/verify_install.py`](tools/steam/verify_install.py.md) proves an install is still vanilla.
3. **Never touch Remix `user.conf`**, and never overwrite a file the user edited (compare hashes first).
4. **Native code is opt-in.** Only allowlisted packages may deploy or load native code
   ([ADR 0003](docs/decisions/0003-native-trust-allowlist.md)). Do not loosen the allowlist, the path
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
     those changes on a branch first. Install the hooks once per clone:
     `python tools\publish_workshop.py --install-hooks`.
6. **No binaries in git.** No game files, Remix runtime files, `.gma` packages or build outputs.
   Test fixtures are generated by the tests.
7. **Licences.** This repo is MIT. `garrys-mod-rtx-remixed` is GPL-2.0: read it for behaviour, do not
   copy its code. Third-party code goes in `third_party/<name>/` with its licence file.
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
