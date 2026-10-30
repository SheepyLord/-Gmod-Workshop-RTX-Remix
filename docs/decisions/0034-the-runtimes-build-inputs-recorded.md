# 0034. The runtime's build inputs, all recorded and checked

- Status: Accepted 2026-10-29 (Claude, in the R3 fixes the user asked for; amends how
  [ADR 0033](0033-one-repository-package-inputs-in-git-lfs.md) describes the runtime)
- Context: review R3, finding R3-014 ([R3-triage.md](../handover/R3-triage.md))

## Context

ADR 0033 keeps the runtime as `runtime/patches` on a fork commit (`runtime/base.json`), and the built
`d3d9.dll` in `packages/runtime`. R3-014 found that nothing tied the two together:
`runtime/build_runtime.ps1` accepted an existing worktree by its commit subjects, ignored submodules and
untracked files, and no check noticed a patch changed without a new build.

Making the script compare exactly found that the packaged `d3d9.dll` was built from more than the
patches ([RESEARCH.md](../RESEARCH.md) section 31): the fork's checkout, which the build worktree
copied, has NVAPI R615 checked out while its tree records R570; three uncommitted RTXDI shader changes
in the `rtxdi` submodule; and two git clones the tree does not record at all, `submodules/dlss` (DLSS
310.9.1 SDK, which meson reads) and `submodules/sharc` (SHARC v1.8.3). Patch 0001 snapshotted the
superproject only. A build from the patches alone would not have been the shipped runtime.

## Decision

1. `runtime/base.json` names everything the build has beyond the fork commit and the patches:
   `submodules` (a submodule checked out at another `commit` than the tree records, and/or with a
   `patch` from `runtime/submodules/`) and `clones` (a git repository the build reads, by `url` and
   `commit`). Each entry says `why`.
2. `build_runtime.ps1` sets them up in a new worktree, and for any worktree checks, before building,
   that what is checked out is exactly that: the commit's tree equals the tree the patches make (built
   in a scratch index, so the fork's repository is only read), no uncommitted change, no untracked
   folder but the named clones, every submodule and clone at its commit and holding exactly its patch.
   `-Verify` runs only the checks.
3. After an import the script writes `packaged` in `base.json`: the DLL's SHA-256 and what it was
   built from (commit, `submodules`, `clones`, each patch file's SHA-256). `tools/check_repo.py`, run by
   `tools/test.ps1` locally and in CI, fails while `runtime/` differs from that record or
   `packages/runtime` holds another DLL. A patch change thus cannot reach `main` without the DLL built
   from it.
4. The present record was checked with `-Verify` against the worktree the packaged DLL was built in
   (`claude/sky-night`, `f9937026`): it is what `base.json` now describes, and its DLL is the packaged
   one. Recording NVAPI R615 and the RTXDI changes keeps the runtime players have tested; whether they
   belong in the fork itself is the fork's maintainers' call.

## Consequences

- `runtime/` again describes the shipped runtime completely, and the test suite keeps it so.
- A runtime change is: change the fork worktree, export the patches (and any submodule patch), run
  `build_runtime.ps1`, commit `runtime/` and `packages/runtime` together.
- A build in a new worktree needs the network (submodules, the two clones); it has not been run since
  this decision. `-Verify` on the existing worktree has.
