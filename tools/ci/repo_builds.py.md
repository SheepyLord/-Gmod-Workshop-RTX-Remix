# repo_builds.py

Keeps the record of what each native module this repository compiles itself, and stores in `packages/`,
was built from ([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)):
`gmsv_nlrtxclient_win64.dll` (the RTX client module, `fixes/modules/`) and `gmcl_nlglass_win64.dll` (the
glass module, `glass/bin/`). It is to them what `runtime/base.json` `packaged` is to the runtime's
`d3d9.dll`. [`check_repo.py`](../check_repo.py.md) calls it and fails while a module's sources differ
from its record, so a stale build no longer ships unnoticed (R20-Q found the R4 build of the client
module in every local package since R6).

```powershell
python tools\ci\repo_builds.py status                       # each module: current, or what differs
python tools\ci\repo_builds.py refresh                      # every module that is not current
python tools\ci\repo_builds.py refresh glass/bin/gmcl_nlglass_win64.dll   # or the CMake target: nl_glass_client
python tools\ci\repo_builds.py refresh <module> --build-dir <checkout>\out\build\win64-release
```

## The record

Each entry of [`pins.json`](pins.json) `repository_builds` has, besides `part`, `path`, `from` and
`target` (which [`collect_repo_build.py`](collect_repo_build.py.md) reads):

| Key | What |
|---|---|
| `sources` | The files and folders of this repository the module is compiled and linked from: the root `CMakeLists.txt` and `CMakePresets.json` (build options, version, the preset), the module's folder, the libraries it links (`loader/core`, `third_party/lzma`, `third_party/jolt`) and the headers it includes (`third_party/gmod`) |
| `not_sources` | Folders inside those that build only tests (`loader/client/tests`, `glass/native/tests`) |
| `packaged` | Written by `refresh`: `sha256` of the module stored in `packages/`, `sources` (each source's SHA-256), `commit` (the checkout's commit, "(with uncommitted changes)" when its sources had any), `build` (the build folder and compiler) and `how` (`imported: built from these sources`, or `kept: a build of these sources is the same image`) |

A source's SHA-256 covers the path and content of every file below it, with line endings as git stores
them (a checkout's CRLF does not change it, as in [`cache_key.py`](cache_key.py.md)). Markdown files are
documentation, never sources. `check_repo.py` reports, per module: no record; a source changed, missing,
new or no longer declared; or a stored file (its `files.json` SHA-256) that is not the recorded one.

## refresh

For each module named (or each one that is not current):

1. Without `--build-dir`: runs `tools\build.ps1 -Config Release -NoTests` in this checkout (Ninja builds
   only what changed). With it: takes that build as it is; it must be the `out\build\win64-release`
   folder of the checkout it builds, and that checkout's sources of the module must be this one's.
2. Refuses a build that is not a Ninja Release build, a module Ninja would still rebuild (`ninja -n`), and
   sources that changed while it built.
3. **Checks the sources:** every file of the source tree the build read, from `ninja -t inputs` (the
   sources of the module and of the libraries it links) and `ninja -t deps` (every header they
   included), must lie under `sources` and not under `not_sources`. Otherwise it stops and names the
   files: add them to `sources`.
4. **Compares** the build with the stored module (decompressed from `packages/`, checked against
   `files.json`; a Git LFS pointer stops it with the `git lfs pull --include` command to run). Two links
   of the same sources differ in the link time stamps (file header, export and debug directories), the
   checksum, the CodeView record (the PDB's GUID, age and path) and the names MSVC gives anonymous
   namespaces (a hash of the source file's path, in RTTI names); with those zeroed, the same image is
   kept: nothing is imported, no Git LFS object is added and the Workshop item does not change. A PDB
   path of another length moves the data after it, so this only matches builds made in folders whose
   paths are as long as the stored module's (its PDB path is in its CodeView record).
5. Otherwise **imports** the build with [`inputs.py`](../inputs.py.md) (`import <part> --file`, one
   module per import) and records it.

Commit the changed `pins.json` (and `packages/<part>` after an import) on a branch: a commit on `main`
publishes the package (AGENTS.md rule 5).

**Exit:** 0 every module current (`status`) or refreshed; 1 a module not current (`status`) or a refresh
refused (the reason on stderr; nothing is imported or recorded for that module); 2 bad arguments.
Tested by [test_repo_builds.py](../tests/test_repo_builds.py.md) and
[test_check_repo.py](../tests/test_check_repo.py.md).
