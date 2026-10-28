# Changelog

Notable changes to this repo. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the loader's CMake project version once it ships; until then everything is under
`Unreleased`, grouped by milestone.

## [Unreleased]

### Added (handover)

- `docs/handover/`: the M1 brief for Codex (scope, boundaries, definition of done, report format),
  the Codex set-up notes and paste-ready prompt, and the conventions for briefs and reports.
- AGENTS.md rule 8: parallel milestones run on their own branch and worktree and keep to their paths.

### Changed (repo rules)

- AGENTS.md rule 9 (user instruction): temporary and build files stay inside the repo under the
  git-ignored `out\` (builds, worktrees, test scratch, evidence). `tools/test.ps1` and
  `tools/build.ps1` point `TEMP`/`TMP` at `out\tmp` while they run.

### Added (M2 part 2: manifests and packages)

- `nl_core`: manifest schema 1 (`nl::manifest::parse`, strict, unknown keys rejected; SemVer; launch
  argument and environment allowlists; root areas and policies) and `check_contents`, which refuses
  unlisted native files. `docs/PACKAGE_FORMAT.md` now specifies what the code enforces.
- `nl_core`: packages from a `.gma` or a development folder (links and reparse points refused);
  `gma::read_entry` reads one file, seeking in plain archives and CRC-checking it.
- `nlctl manifest <file.gma|folder>`.

### Added (M2 part 2: LZMA, JSON, path rules)

- `third_party/lzma`: the LZMA SDK decoder (public domain, 7-Zip tag 26.05, unchanged, hashes in
  its README), built as `nl_lzma`.
- `nl_core`: streaming `lzma::Source` for LZMA-wrapped archives (Workshop `*_legacy.bin`),
  including GMod's 8-byte footer (size, then `0xBEEFCACE`); `open_archive` now reads them.
- `nl_core`: strict JSON parser for manifests and `config.json`; shared UTF-8 validation; path rules
  for anything a package names and the root areas packages may write to.
- `nlctl` reports container, stream size, completeness, CRC trailer and LZMA footer.

### Changed (M2 part 2)

- The 4-byte archive CRC trailer is optional: 19 legacy Workshop items have none and GMod mounts
  them. Only streams cut inside the contents or the trailer are truncated.
- Real data: all 753 installed Workshop archives parse; all 81 legacy items verify (4.4 GB, every
  CRC and footer). `tools/gmapack/gmapack.py` rejects GMod's LZMA footer, so it cannot read them.

### Added (M2 part 1: GMA reader and nlctl)

- `nl_core`: GMA reader for GMAD v1-v3 (header and index with gmapack-compatible limits and
  rejections, single-pass `verify` of every CRC and trailing data, container detection,
  share-all file reading), CRC-32, and JSON string quoting that replaces invalid UTF-8.
- `loader/cli`: `nlctl inspect | verify | scan` (read-only), with a CTest that checks it against
  `tools/gmapack/gmapack.py` on synthetic archives, including damaged ones.
- Test harness: `CHECK_THROWS_AS` and `scratch_dir()` (scratch beside the test executable).
- First real-data run: all 672 installed Workshop `.gma` indexes (98,656 entries) parse without
  errors; the 81 older `*_legacy.bin` items are LZMA-wrapped and wait for the decoder.

### Added (M0: repo scaffold)

- Repo initialised on top of `origin/main` (SheepyLord/-Gmod-Workshop-RTX-Remix).
- Agent-facing docs: `AGENTS.md` (rules, commands, documentation duties), `CLAUDE.md` importing it,
  `docs/` with architecture, components, package format draft, on-disk layout, testing, roadmap,
  environment, research notes and decision records 0001-0005.
- C++ build skeleton: CMake presets `win64-debug` / `win64-release` (MSVC x64, Ninja, static CRT,
  `/W4 /WX`), `nl_core` library and `nl_tests` with an in-repo test harness.
- `tools/build.ps1` (configure, build, CTest) and `tools/lib/VsDevEnv.psm1` (MSVC environment,
  works even when `vswhere` cannot see Build Tools).
- `tools/test.ps1` runs every check; `tools/check_repo.py` enforces the documentation conventions
  (a `.md` beside every script, module READMEs, working links, this changelog, the component map).
- `tools/steam/`: depot manifest parser, `verify_install.py` (is an install vanilla?) and
  `make_vanilla_copy.py` (byte-exact vanilla copy from an existing install, no download), with tests.
  `GarrysMod_PoC` was built with the prototype of this tool on 2026-10-27.
- `tools/diag/pe_imports.py`: lists PE imports/exports (hook-point research).
- `tools/gmapack/`: the GMA File Packer, vendored unchanged except for added script docs.

### Decided

- Bootstrap is a `winmm.dll` proxy that runs its set-up at the EXE entry point (ADR 0001).
- Payloads are source-agnostic; Workshop route decided after a private upload test (ADR 0002).
- Only allowlisted packages may deploy native code until signatures exist (ADR 0003).
- The Remix runtime is preloaded from a versioned folder instead of being copied into `bin\win64` (ADR 0004).
- Repo conventions: script docs, changelog, decision records, MIT licence (ADR 0005).
