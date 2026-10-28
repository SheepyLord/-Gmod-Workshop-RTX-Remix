# Changelog

Notable changes to this repo. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the loader's CMake project version once it ships; until then everything is under
`Unreleased`, grouped by milestone.

## [Unreleased]

### Added (handover)

- `docs/handover/`: the M1 brief for Codex (scope, boundaries, definition of done, report format),
  the Codex set-up notes and paste-ready prompt, and the conventions for briefs and reports.
- AGENTS.md rule 8: parallel milestones run on their own branch and worktree and keep to their paths.

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
