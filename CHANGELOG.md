# Changelog

Notable changes to this repo. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the loader's CMake project version once it ships; until then everything is under
`Unreleased`, grouped by milestone.

## [Unreleased]

### Added (M1: inert bootstrap)

- Synthetic executable fixtures stay inside the build directory, respecting the user's chosen
  build location instead of copying binaries to the system temporary directory.
- Test discovery checks paths relative to the repository, so a worktree under an ancestor `out`
  directory still runs all Python suites.
- Chromium helpers using `gmod.exe --type=...` remain pure pass-through; only the main game writes
  the startup log. Smoke tests verify that log's PID, preventing helper logs from masking timing
  evidence or bypassing the command-line off switch.
- `loader/proxy`: x64 `winmm.dll` with generated MASM forwarding for all 181 system ordinals
  (180 names and one ordinal-only export), version identity, host gating, all three off switches,
  PE entry-point hook, guarded UTF-8 startup logging and five-log rotation.
- CTest export/forwarding tests, synthetic-host startup/off-switch/failure/rotation tests, and
  installer ownership/hash/Steam-managed protection tests.
- `tools/install-loader.ps1`: PoC-default DLL/PDB installation, SHA-256 receipt, foreign/user-edit
  refusal, opt-in Steam-managed protection and state-preserving uninstall.
- `tools/smoke_test.ps1`: five PoC map loads, strict console comparison, two inert console tools,
  evidence capture and restoration of prior loader state.

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
