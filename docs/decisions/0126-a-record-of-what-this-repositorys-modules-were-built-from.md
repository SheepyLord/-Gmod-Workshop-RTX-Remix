# 0126: A record of what this repository's own modules were built from

- Status: Accepted 2026-11-06 (after R20; does for the modules of `tools/ci/pins.json` `repository_builds`
  what [ADR 0034](0034-the-runtimes-build-inputs-recorded.md) does for the runtime)
- Context: the R20 report's open items ([R20-report.md](../handover/R20-report.md)), after the finding of
  integration QA (R20-Q)

## Context

The RTX package ships two native modules this repository compiles itself: the RTX client module
`gmsv_nlrtxclient_win64.dll` (`loader/client`, linking `nl_core`) in the fixes part, and the glass
module `gmcl_nlglass_win64.dll` (`glass/native`, linking Jolt Physics) in the glass part. Release
builds on GitHub compile both from source ([ADR 0106](0106-the-rtx-package-built-on-github.md));
development builds, which the git hooks publish to the Workshop item
([ADR 0108](0108-releases-built-on-github-by-hand-development-built-here.md)), take the copies stored
in `packages/`, imported by hand after a local build.

Nothing tied a stored copy to its source. R20-Q found that the stored client module was still the build
of round R4: its configuration parser (from `nl_core`) rejected round R6's `remix.performance_tier`
key, so the RTX multiplayer bootstrap failed in the menu, and every local Workshop build since R6 had
shipped it. The runtime's `d3d9.dll` has had that protection since R3: `runtime/base.json` `packaged`
records what it was built from and `tools/check_repo.py` fails while `runtime/` differs.

MSVC links are not reproducible: every build differs in the link time stamps, the PDB's GUID and path,
and the names it gives anonymous namespaces (a hash of the source file's path, in RTTI names). So a
stored module cannot be checked against a build by its hash, and importing a new build at every check
would add a Git LFS object each time (AGENTS.md rule 6) and change the Workshop item.

## Decision

1. **Each repository build declares its sources.** Its `pins.json` entry names `sources`, the files and
   folders it is compiled and linked from (the root `CMakeLists.txt` and `CMakePresets.json`, the
   module's folder, the libraries it links, the headers it includes), and `not_sources`, the folders
   inside them that build only tests. Markdown is never a source.
2. **The record.** `packaged` holds the SHA-256 of the stored module and of each source (every file's
   path and content, with line endings as git stores them), the commit, the build folder and compiler,
   and how it was made: `imported` or `kept`.
3. **The check.** `tools/check_repo.py` (rule 8) fails while a module has no record, a source differs
   from it (changed, missing, new or no longer declared), or `packages/<part>/files.json` lists another
   file than the recorded one. It names the sources and the command that fixes it.
4. **One way to write it.** `tools/ci/repo_builds.py refresh` builds this checkout's Release preset (or
   takes an up-to-date Release build of a checkout with the same sources), refuses a build that read a
   file of the repository outside the sources (Ninja's inputs and header log), compares the build with
   the stored module with what every link changes zeroed, and imports it with `tools/inputs.py` (one
   module per import) only when it is another image. Either way it writes the record.
5. **The declaration is checked continuously.** `tools/tests/test_repo_builds.py` compares each module's
   sources with what this checkout's Ninja build read, after the native build `tools/test.ps1` runs.
6. **The first records keep both stored modules.** Builds of commit `a5a3ff1` in folders as long as the
   ones the stored modules were linked in (`out\worktrees\rbv-cl` for `r20-qa`, `rbv-glass` for
   `r19-glass`) are the same images: the client module (R20-Q's build, `f23c711c...`) differs only in the
   link time stamps and the PDB's GUID and path; the glass module (R19-G's, `10cefd57...`) also in five
   anonymous-namespace names. Since R19-G only the loader's version in the root `CMakeLists.txt` changed
   among the glass module's sources, and it does not contain the version. No module was imported.

## Consequences

- A change to `loader/core` (the configuration and catalog code the client module links), to
  `loader/client`, to the root CMake files or to the third-party code a module links makes it stale
  until `refresh` runs: the check fails in `tools\test.ps1`. Run it on the branch, before the merge.
- The record is conservative: it does not know which `nl_core` functions the linker keeps, so a change
  that leaves the module's code as it was (a comment, the loader's version) still asks for a refresh.
  `refresh` then keeps the stored module when it was linked in a folder whose path is as long as this
  build's; otherwise it imports the new build (about 0.2 MB of Git LFS for the client module, 0.6 MB for
  the glass module) and the Workshop item updates with it.
- CMake-level sources (`CMakeLists.txt`, presets, `configure_file` templates) are declared by reading the
  build; Ninja's logs check only what the compiler and linker read.
- The release workflow is unchanged: it still compiles both modules from source and ignores the stored
  copies.
