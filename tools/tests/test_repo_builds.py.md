# test_repo_builds.py

`python -m unittest discover -s tools/tests -p test_repo_builds.py -v` tests
[`tools/ci/repo_builds.py`](../ci/repo_builds.py.md), the record of what this repository's own native
modules were built from ([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)):

- **Images**: two links of the same sources (another link time, checksum, PDB GUID, PDB path of the same
  length, anonymous-namespace names) are the same image; other code, a PDB path of another length, a
  file that is not a PE32+ image or a truncated one are not. The images are minimal PE32+ files the test
  writes, laid out as MSVC links them.
- **Ninja**: what a build read, from canned `ninja -t inputs` and `-t deps` output (sources and headers;
  not objects, libraries, phony targets or other objects' headers), and which of those files the
  module's sources do not cover (generated files and the compiler's are not sources; `not_sources` is not).
- **refresh** in a scratch checkout with a fake build (Ninja's answers replaced): a first build is
  imported and recorded; a current module is left alone, nothing built; a rebuild that is the same image
  is kept (the stored file and its index unchanged), another image is imported; a stored module that is
  a Git LFS pointer stops it; a build that read files outside the sources, a build during which a source
  changed, a Debug build, a module Ninja would rebuild, another checkout's build of other sources and a
  build folder that is not its checkout's `out\build\win64-release` are refused with nothing written; a
  matching checkout's build is taken without building. The record keeps the rest of `pins.json`, its
  key order and its line endings.
- **This repository**: every repository build names sources that exist, with `not_sources` inside them;
  when this checkout has a Ninja build (`out\build\win64-release` or `win64-debug`), every file of the
  repository each built module read lies under its sources. Otherwise that test is a reported skip.

Scratch under `out\tmp`, removed afterwards. Exit 0 when all pass, 1 otherwise.
