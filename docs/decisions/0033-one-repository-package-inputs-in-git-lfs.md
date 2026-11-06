# 0033: One repository: the RTX package's inputs in packages/ (Git LFS), the runtime as patches

- Status: Accepted 2026-10-30
- Decided by: the user ("please keep everything to https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix,
  main branch. This repo is where we organizes everything. Please do a clean up of what we have. Do
  not depend on other repos. If some files are large please consider GitHub lfs. Setup the full build
  workflow"), Claude choosing how
- Supersedes: AGENTS.md rule 6 ("no binaries in git") for `packages/` only;
  [0024](0024-bundled-addons-and-module-dependencies.md)'s hooks in the add-ons' repositories.
  Amends rule 7 (the RTX fixes, GPL-2.0, are now vendored as a part, kept apart from this repo's code)

## Context

Facts in [RESEARCH.md](../RESEARCH.md) section 30.

- **The package was built from six places outside this repository.** Of its ten parts
  ([0016](0016-one-workshop-item-kept-current.md)): the runtime from a runtime fork worktree and
  scratch folders under `out\`; ReShade's setup from `out\packages`; the RTX fixes from their own
  repository plus binary modules from the classic install; Model Hotloader and the material editor's
  bridge from the classic install; five add-ons from their repositories under `ipg\`; the Emissives
  package from `out\packages\round3`. A clone of this repository could not build the package, and
  nothing recorded which version of each source went into an upload.
- **The runtime's changes lived only in a local branch** of the fork (`claude/sky-night`, four commits
  on `sambow23/dxvk-remix-gmod` `gmod-numos3`), not pushed anywhere the project owns. The fork's tree
  with NVIDIA's SDK submodules is 3.6 GB; its build needs those SDKs and packman downloads.
- **Git LFS on GitHub Free and Pro:** 10 GiB storage and 10 GiB downloads a month, Actions downloads
  included. Over the bandwidth, LFS stops for the month. A pushed LFS object stays stored.
- **The inputs are 1.8 GB, mostly binaries that compress well:** LZMA takes `d3d9.dll` (363 MB, a
  new one for every runtime change) to 17 %, the star layer to 5 %, the whole set to 0.6 GB.
- **The add-ons' repositories are mostly not the package:** the fixes' working tree is 84 GB (map
  sources), the material editor's 3.9 GB and the bullet-break simulator's 3.7 GB (builds, work trees);
  the package takes 0.45 GB, 3 MB and 1 MB of them.

## Decision

1. **`packages/<part>/` holds every input of every part**, exactly the files the part's packager reads
   ([packages/README.md](../../packages/README.md)):
   - text up to 1 MiB stored as it is (byte for byte: `packages/** -text`);
   - every other file stored xz-compressed as `<name>.xz`, which `.gitattributes` puts in Git LFS;
   - `files.json` indexes each file's size, SHA-256, time, the stored form and its LFS oid, and where
     each folder was imported from (path, git origin, commit).
2. **The build reads only this repository.** [`tools/inputs.py`](../../tools/inputs.py.md) `unpack`
   rebuilds `out\inputs\<part>\` from the index (checking every file, restoring its time);
   `tools/workshop.json` names only `out/inputs/...` paths; [`publish_workshop.py`](../../tools/publish_workshop.py.md)
   unpacks before it builds and fingerprints `packages/` by its git tree. [`build_package.py`](../../tools/build_package.py.md)
   is the same build without the upload. `tools\workflow.ps1 -Package` runs it after the Release
   checks.
3. **A part changes only by an import here**, reviewed and committed like code: build the part from
   its new source with its packager, and `inputs.py import` exactly the sources its inventory lists.
   Nothing outside this repository can change the package any more:
   - the post-commit/post-merge hooks ADR 0024 put in the add-ons' repositories are removed, and
     `--install-source-hooks` is gone (`--uninstall-source-hooks` stays, for clones that still have them);
   - each origin is recorded in the part's index instead.
4. **The runtime fork's changes live in [`runtime/`](../../runtime/README.md)** as a `git format-patch`
   series against the fork commit in `runtime/base.json`. [`runtime/build_runtime.ps1`](../../runtime/build_runtime.ps1.md)
   applies it in a worktree of a fork clone, builds twice (the shader stamp, RESEARCH.md section 29)
   and imports `d3d9.dll`. The built runtime is a part like the others, so the package builds without
   the fork. Only a runtime change needs the fork, its base and its SDKs.
5. **This repository's hooks run Git LFS's steps** (`git lfs pre-push` before ours, and post-checkout,
   post-commit, post-merge): they replace the hooks `git lfs install` would write. A clone needs
   git-lfs, and `python tools\publish_workshop.py --install-hooks`.
6. **CI builds the package from the repository.** `.github/workflows/package.yml` (on changes to the
   inputs, and by hand): LFS objects cached between runs, `inputs.py verify`, a Release build of the
   loader, `build_package.py --require-nlctl`; the summary is kept, the 1.8 GB `.gma` only when asked
   for. `build.yml` stays without LFS: its tests verify `packages/` by the pointers' oids.
7. **Licences travel with the parts.** A part keeps its source's licence beside it (`LICENSE`,
   `licenses/`): the RTX fixes are GPL-2.0 and stay a separate, unmodified component that the package
   aggregates; this repository's MIT code copies none of their code.

## Consequences

- One clone, `git lfs pull` and `tools\workflow.ps1 -Package` build what the Workshop item holds. The
  first build from `packages/` gave the published package byte for byte (the same 1,798,746,608-byte
  archive and content digest), so the merge uploaded nothing.
- The repository grows by 0.6 GB of LFS storage and 14 MB of patches. Every new runtime build adds
  about 62 MB of LFS storage for good; an LFS object cannot be removed short of deleting the
  repository. At that rate the free 10 GiB lasts for about 150 runtime builds.
- Updating an add-on is a step here: its own repository no longer reaches the item. The import
  commands for each part are in packages/README.md.
- Clones without git-lfs get pointer files: the loader builds and its tests pass, the package does
  not build, and a push is refused by the pre-push hook.
- The repository is private. Making it public would publish NVIDIA's runtime DLLs, the fixes and
  third-party add-ons in `packages/`: that needs a licence review first.
- The runtime's base stays outside: a rebuild of the runtime from source needs the fork at
  `base.json`'s commit, with its submodules.

## Alternatives considered

- **The fork's source as a subtree here.** 3.6 GB with NVIDIA's SDK submodules, which are other
  repositories in turn, and a build that fetches more; it would still not build from this repository
  alone. The patch series keeps what this project changed, and the built runtime keeps what ships.
- **Submodules for the add-ons.** The package would depend on six other repositories again, and a
  clone would fetch their 90 GB to use 0.45 GB.
- **Binaries in LFS without compression.** Three times the storage, and 363 MB per runtime build.
- **One archive per part.** A one-file change would store the whole part again.
- **Building the runtime in CI.** It needs the fork, its SDKs and about half an hour on a Windows
  runner per run; the runtime changes rarely, and on this machine.
