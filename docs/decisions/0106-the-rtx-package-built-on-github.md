# 0106: The RTX package is built on GitHub, its native binaries included, and reports its hashes

- Status: Accepted 2026-11-04 (changes how [ADR 0016](0016-one-workshop-item-kept-current.md) keeps the
  item current and what [ADR 0033](0033-one-repository-package-inputs-in-git-lfs.md) takes from
  `packages/`)
- Decided by: the user's item 45 of R16: "the RTX package's action should report the SHA256 HASH of all
  files in the .gma files and the .gma file itself used to upload to the workshop. All binaries have to
  be freshly built (not uploaded from our local) and the .gma has to packed on GitHub. Note there is
  only 2 GB of artifact storage, thus only one most recent workshop package .gma should be kept in
  action."

## Context

Until R16 the item's package was built on the developer's machine by the git hooks
(`tools/publish_workshop.py`) from `packages/`, whose 54 native binaries had been built locally and
imported with `tools/inputs.py`. GitHub's `package.yml` built the same package from the same stored
binaries and kept only a summary. The R16 survey (RESEARCH.md, "R16: where the package's binaries come
from") found a reachable source for all but a few of those binaries:

- the runtime's `d3d9.dll` and its two USD plugins: the fork commit in `runtime/base.json` with
  `runtime/patches`; its 38 vendor binaries are fetched by that same build (packman, submodules, clones);
- `gmcl_RTXFixesBinary_win64.dll`: the public fixes commit `f28bd5a9` with the four GPL patches already
  in `packages/fixes/licenses` gives exactly the native tree of the unpushed commit `913bb6b` it was
  built from;
- `gmcl_rtxwater_win64.dll`: the public commit `b5c194ec` (native RTX Water Version 4, what ships);
- `gmcl_rtxdebug_win64.dll`: the complete source copy in `packages/fixes/licenses/rtxdebug/checkout`;
- the material editor's bridge: twelve files of a private repository, now vendored in
  `packages/advanced-material-editor/source` (commit `8ece1415`, byte-identical local build found);
- this repository's client and glass modules;
- ReShade's signed setup (reshade.me), the fixes' `stdshader_dx6.dll` (its author never published the
  source of that build; the binary is in the public fixes repository) and CoACD's `lib_coacd.dll` (its
  own CI's build, in its PyPI wheel) are other people's builds, reachable as published files;
- the Model Hotloader's four natives were built from changes that are staged, uncommitted, in its
  author's working tree: nothing reachable builds them.

## Decision

1. **GitHub builds the package.** `package.yml` builds the runtime (`runtime/build_runtime.ps1
   -Install`, collected by `tools/ci/collect_runtime.py`), the fixes' modules, the debug module and the
   bridge (`tools/ci/build_modules.ps1`, sources and commits in `tools/ci/pins.json`) and this
   repository's modules (`tools/build.ps1`, `tools/ci/collect_repo_build.py`), downloads the published
   builds named in `pins.json` and checks each against its pinned SHA-256 (`tools/ci/fetch_prebuilt.py`),
   and packs the `.gma` from them and `packages/` (`tools/build_package.py --built`).
2. **Every native binary comes from the run.** With `--built`, `tools/inputs.py` takes each `.dll`/`.exe`
   from the run's build folder and fails if one is missing, except those the workflow's `KEEP_PACKAGED`
   names: for now the Model Hotloader's four natives, until their source is in a repository. The run
   never downloads the stored copies of the binaries it makes from Git LFS. Content (Lua, materials, the
   emissives part's `.gma`) still comes from `packages/`.
3. **The run reports its hashes.** `tools/package_report.py` writes into the run's summary the `.gma`'s
   size and SHA-256, every file's path, size and SHA-256, and for each native binary whether it was
   compiled in the run, downloaded by it against a pin, or taken from `packages/`, with its repository,
   commit and recipe. The artifact `rtx-package-report` keeps that report as JSON, as `SHA256SUMS.txt`
   and with the provenance records, for 90 days.
4. **One package artifact.** The `.gma` is the artifact `rtx-package` (zip level 6, about 0.84 GB);
   every run deletes the older `rtx-package` artifacts before uploading its own, so Actions storage
   (2 GB) holds one.
5. **The Workshop gets exactly that `.gma`.** The pre-push hook of main runs `tools/publish_workshop.py
   --from-ci`: it waits for the package run of the pushed commit, downloads its two artifacts, checks the
   `.gma` against the report (name, size, SHA-256), uploads that file with gmpublish, and records the run
   and the SHA-256 in `out/workshop/published.json` and in the item's change note. A push that does not
   touch the package has no run, and uploads nothing. Commits and merges no longer publish. A package
   built on the developer's machine is only compared; uploading it (`--local-upload`) is left to an
   explicit request of the user.
6. **Builds are cached by their sources.** The runtime and the modules are rebuilt when their sources
   change (`tools/ci/cache_key.py`) or `BUILD_SALT` does; otherwise a run reuses the build an earlier run
   of this workflow made from the same sources, and the report names the run that built each binary.

## Consequences

- The item's binaries are no longer byte-identical to the stored ones (builds are not reproducible:
  time stamps, PDB paths), though built from the same sources, except the client module: it is now built
  from the commit being packaged, where `packages/` held a build of `8a11d07`.
- A Workshop update waits for GitHub: about half an hour, longer when the runtime is rebuilt (an hour or
  more on the private repository's two-core runners). Windows minutes count double.
- `packages/` still holds the stored binaries: local package builds and tests use them, and they are the
  fallback the user may choose.
- The Model Hotloader's four natives stay a reported exception until their staged changes are committed
  and pushed to its repository, or their source is vendored here.
- `stdshader_dx6.dll`, the vendor SDK binaries, ReShade and CoACD are fetched, not compiled: their
  sources are not public or not buildable here; their pins make any other bytes fail the run.
