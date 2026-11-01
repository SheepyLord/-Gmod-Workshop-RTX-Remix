# R6: performance and stability (report)

The user's request (2026-10-31): stability proposals 1-6, 8, 9 and 11 of
[R5-stability-proposal.md](R5-stability-proposal.md), and Remix defaults that suit smaller GPUs
instead of the best consumer card. Plan and decisions: [R6-plan.md](R6-plan.md). Codex
(`gpt-6.1-sol`, effort max, Fast tier) wrote the code in six parallel tasks; Claude planned, had each
task reviewed independently, sent fix passes back, integrated, tested in the game and published.

## What was built

| Task | Brief | What it does | Reviews and fix passes |
|---|---|---|---|
| T1 | [R6-T1](R6-T1-loader-layers.md) | Loader layers before the package's DXVK copies; performance tiers from the NVIDIA adapter's VRAM and RTX class, `remix.performance_tier`; opt-in `diagnostics.gpu_crash_dumps` (ADR 0062) | one review (P1: an unguarded fallback write), one fix pass |
| T2 | [R6-T2](R6-T2-evidence-telemetry.md) | The previous session's logs, dumps and memory history kept in `native-loader\logs\sessions`; `memory.csv` every 10 s; the home menu's previous failure and low-commit warning; `previous_session` in `status.json` (ADR 0063) | one review, one fix pass |
| T3 | [R6-T3](R6-T3-companion-docs.md) | The companion's VRAM categories every 30 s, the tier line in Start here, the Memory and stability guide page, [STABILITY.md](../STABILITY.md), the MMD PBR skill's 2048 px rule | one review (P1: guide advice that broke older loaders), one fix pass |
| T4 | [R6-T4](R6-T4-runtime-logs.md) | Runtime patch 0015: memory snapshots at camera cuts, every five minutes and at a device loss, `rtx-remix\logs\last_gpu_crash.json`, rate-limited micromap warnings; a safer `build_runtime.ps1` (ADR 0065) | two reviews; two fix passes, two rebuilds |
| T5 | [R6-T5](R6-T5-fixes-memlimits.md) | The fixes without the `SetMemoryLimits(256, 1024)` call; the 83 ToPBR textures in BC7 (ADR 0066) | one review; provenance and doc fixes by Claude |
| T6 | [R6-T6](R6-T6-performance-tiers.md) | The medium and low tier files, 4096 px night-sky copies for low, `tools/sky/drop_top_mip.py`, the tier option test (ADR 0064) | one review, one fix pass; measured by Claude, low changed to 8 bounces |

Integration (`r6-int` in `out\worktrees\r6`):

- T1 and T2 each added a `diagnostics` key with its own `only_keys` list, so a config with both
  failed; one block now takes both, and a wrong `memory_telemetry` value is a note (on), like
  `gpu_crash_dumps`, never the loader off.
- Loader 0.11.0. The player README describes the tiers, the three new settings and the crash
  evidence; the guide, its six translations and STABILITY.md say "loader 0.11.0 or later" where
  they said "R6 loader".
- `poc_session.py` writes `--performance-tier`, `--gpu-crash-dumps` and `--memory-telemetry`.
- The T5 fixes commit is kept as `codex/r6-no-memory-limits` in the fixes checkout, and the PDB
  matching the shipped DLL in the main checkout's `out\fixes-memory-limits-build`.
- The PoC harness (`r6-harness`, Codex, with a 120 s hang grace by Claude): a whole-run
  crash-prompt watchdog (No/OK only), device-loss and hang detection, bounded captures and exit,
  named exit codes; written after a measurement session hung for two hours behind Remix's crash
  prompt (below).

## Tests

- `tools\test.ps1 -Config Release` on `r6-int` after every merge: conventions, 24/24 CTests, the three
  Python groups (final run: all checks, 24/24 CTests, 375 Python tests with two expected skips).
- The package: 1,023 files, 1.79 GB (about 100 MB smaller than R5's, mostly T5's BC7 textures),
  checked by `nlctl`.
- PoC release QA (loader 0.11.0 over R5's 0.10.1 install, generation 59, 228 changes): all four
  sessions pass (rendering guard and toolgun, spawn menu, map glass on modern_house, spawned glass);
  `winmm.dll`, `config.json`, the registry, `rtx.conf` and `user.conf` unchanged; the only setting
  added is the companion's `nativeloader_vram_telemetry`. In game: auto picks `high` on the RTX 5090
  (32,187 MiB), the R5 runs' two `rtx.resourceLimits` rejections are gone, the runtime's
  `[RTX Memory]` lines and the loader's `memory.csv` and session folders appear.
- Tier measurements: [ADR 0064](../decisions/0064-performance-tier-defaults.md#poc-measurements-2026-10-31).
  Medium and low run 5-9 % faster than high at 4K and use 170-750 MiB less VRAM; low's candidate 4
  bounces measured no faster than 8, so low uses 8. With the rebuilt package
  (`0.0.0-dev.20261101030926+a1592c11`), pinned modern_house: high 52.1 fps, low 56.3 and 56.9 fps,
  the runtime reporting 8 bounces from the tier file itself.
- Evidence: the main checkout's `out\qa-poc\r6\` (`release`, `tiers`, `tiers-pinned`,
  `tiers-final`, `shots`, `verify-before.json`).

## Open issues

- **The recurring driver fault reproduced on the PoC at the `high` tier** (2026-10-31 17:53, the
  classic settings, gm_construct, frame 167, seven seconds after the map loaded): `nvlddmkm` event 153
  twice, then `VK_ERROR_DEVICE_LOST` on queue submission. The R6 evidence worked end to end: T4's
  `[RTX Memory]` device-loss line and `last_gpu_crash.json` (8.6 of 32.9 GB VRAM in use, so not memory
  exhaustion; `"reason": "queue submission"`), and T2's next start archived the session as
  `device_lost`. The same event pair appears six times in the system log on 2026-10-29/30. The game
  then waited on Remix's crash-report prompt with a frozen window for almost two hours; the PoC tool's
  watchdog fix (`r6-harness`) makes unattended runs end promptly. Diagnosing the fault itself needs
  Aftermath dumps (`diagnostics.gpu_crash_dumps`), a task of its own.
- The classic layer (the `high` tier) still sets 15 options this runtime no longer has: old
  exposure, local tonemap and bloom options, `occluderTextures`, `finalizeWithACES`. Remix ignores
  them, so that part of the classic look is not reproduced. R2 (field parity) should map them to
  their current options or drop them.
- A class-limited `low` tier on a card with more than 8 GiB (RTX 3060 12 GB, 4060 Ti 16 GB) gets
  `lowMemoryGpu`'s top-mip drop of replacement textures although its memory does not need it.
- The tier values were measured on an RTX 5090 with the tiers forced; the relative costs carry
  over, but no 8 or 12 GB card was tried.
- Git LFS holds three runtime builds from R6 (two never shipped, about 58 MB each).
- A normal quit is archived as `unknown`: Remix logs no shutdown marker
  (`classify` in `loader/core/src/evidence.cpp` knows only its deliberate-exit line), so every
  ordinary RTX session leaves a folder of about 400 KB in `native-loader\logs\sessions`, and a real
  crash's folder rotates out after five more normal starts. The home menu shows only real failures,
  so players see no false alarm. A clean-exit marker (the companion's `ShutDown` hook, or the
  bootstrap's process detach) would let the collector skip normal sessions.

## Questions for the user

- Field QA needs loader 0.11.0 in the field install (`bin\win64\winmm.dll`, backed up first): may
  Claude replace it? The published package works with the installed 0.10.1 too, at the classic
  settings and without the R6 evidence.
- Should the recurring `nvlddmkm` 153 device loss get a task of its own (Aftermath dumps through
  `diagnostics.gpu_crash_dumps`, then the dump read with NVIDIA's tools)?
- Should R2 map the classic layer's 15 obsolete options to their current names?
