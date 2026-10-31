# R6: performance and stability (plan)

Claude is the project manager of this round; the coding is done by Codex (`gpt-6.1-sol`, reasoning
effort max, Fast tier), six tasks in parallel, each in its own git worktree and branch, run from Claude
Code through OpenAI's `codex` plugin (`codex-companion.mjs task --background --write --cwd <worktree>
--prompt-file <brief>`; model, effort and tier come from `~\.codex\config.toml`, which also lists the
writable roots outside a worktree). Claude reviews, integrates, tests in the game and publishes.

The user's request (2026-10-31), answering [R5-stability-proposal.md](R5-stability-proposal.md):

> yes, please go ahead with stability proposals 1 - 6 and 8, 9, 11. Also, currently the remix default
> setting is for the best consumer GPU available, please find a way to turn the default settings to
> enhance performance and stability. (This is related to the performance and stability)

Proposals 7 (safe mode) and 10 (asking the tester, `evictManagedOnUnlock`) are not part of R6.

## Decisions taken for the user's open questions (proposal section 6)

| # | Question | Decision |
|---|---|---|
| 1 | Loader layers first in `DXVK_CONFIG_FILE` | Yes (proposal 1, approved) |
| 2 | Low-VRAM tiers | Generalised into **performance tiers**: `high`, `medium`, `low`, chosen at activation from the GPU (below). The user's "find a way to turn the default settings to enhance performance and stability" is answered by these tiers: the package's classic settings stay the `high` tier (the RTX 5090 they were tuned on keeps its look), and smaller GPUs get lighter settings automatically. On by default; `remix.performance_tier` in `config.json` overrides it |
| 3 | Low-tier values | Start from proposal 2's (`rtx.lowMemoryGpu`, a 512 MiB micromap cap, sky probe 1024, fog grid scale 8, terrain 2048), measured and extended by T6 |
| 4 | Local crash data | Keep the log text and the dumps that already exist locally, copied into a bounded folder (last five sessions, at most 200 MB); never uploaded, never deleted at the source |
| 6 | Night sky on low tiers | (b): ship 4096 px copies (mip 0 dropped, no re-encode) and point the `low` tier at them |
| 7 | Sentry | Unchanged in R6 |
| 9 | The fixes' `SetMemoryLimits` | Removed (proposal 9, approved) |
| — | Memory telemetry (proposal 5) | On by default: local files only, bounded (last two hours), about 1 MB per two hours |
| — | GPU crash dumps (proposal 4) | `config.json` switch only in R6 (`next_start`, `always`, `off`; default `off`) |

## Performance tiers

Detection (T1), at RTX activation, through DXGI (`graphics_adapters()` already enumerates adapters):

- Take the NVIDIA adapter (vendor `0x10DE`) with the most `DedicatedVideoMemory`. None: today's
  non-NVIDIA path (`non-nvidia.conf`), no tier layer.
- **VRAM tier:** at most 8.5 GiB `low`; at most 12.5 GiB `medium`; more `high`.
- **Class tier** from the adapter's description, `RTX <generation><class>0` (e.g. `RTX 4060 Ti`,
  `RTX 3080`, `RTX 5090`): class 9 or 8 `high`, 7 `medium`, 6 or 5 `low`; `Ti`/`Super` change nothing;
  `Laptop` in the name moves one step down. Names that do not match (RTX A-series, Quadro, future
  names) use the VRAM tier alone.
- **Tier** = the lower of the two. `remix.performance_tier` (`auto` default, `high`, `medium`, `low`)
  overrides it.
- `high` lists no tier layer. `medium` and `low` list the runtime package's tier layer **first** (it
  must beat the package's classic layer, proposal 1). If the package has no tier file (an older
  package), `low` falls back to a built-in text with proposal 2's values and `medium` lists nothing.

## Interfaces between the tasks

- **I1, tier layer files (T6 makes them, T1 lists them):** in the runtime package, deployed under
  `native-loader/packages/<runtime id>/<version>_<generation>/config/dxvk-tiers/medium.conf` and
  `.../low.conf`, beside today's `config/dxvk/*.conf`. Plain Remix layers holding `rtx.*` keys only.
  They are ordinary payload files of the runtime part: no new manifest key or kind, so loaders before
  R6 ignore them.
- **I2, `status.json` `activation.performance_tier` (T1 writes, T3 shows):**
  `{"tier": "high|medium|low", "source": "auto|config|fallback", "reason": "<one line>",
  "adapter": "<description>", "dedicated_vram_mib": <int>, "layer": "<listed copy or empty>"}`.
- **I3, the low tier's night sky (T6):** `atmosphere/stars_4096.dds`, `galaxy_4096.dds`,
  `nebula_4096.dds` beside today's files in the runtime folder; `low.conf` points
  `rtx.atmosphere.starMapTexture`, `starMapGalaxyTexture` and `starMapNebulaTexture` at them.
- **I4, GPU crash dumps (T1 sets, T2 collects):** `diagnostics.gpu_crash_dumps` in `config.json`;
  when on, `DXVK_AFTERMATH_DUMP_PATH` is the absolute path of `native-loader\logs\gpu\`.
- **I5, the previous session (T2):** `status.json` `previous_session`
  `{"reason": "device_lost|cs_exception|allocation_failed|out_of_memory|crash|clean|unknown",
  "time_utc": "<ISO 8601>", "folder": "<relative path or empty>"}`.
- **I6, telemetry files:** `native-loader\logs\memory.csv` (T2, the bootstrap);
  `garrysmod\data\native-loader\vram.csv` (T3, the companion).
- **I7, `rtx-remix\logs\last_gpu_crash.json` (T4 writes, T2 reads when present):**
  `{"schema": 1, "time_utc": "...", "event": "device_lost", "frame": <int>,
  "heaps": [{"index": <int>, "budget": <bytes>, "usage": <bytes>}],
  "dxvk": {"allocated": <bytes>, "used": <bytes>}, "categories": {"<name>": <bytes>}}`. Every field
  optional for the reader.

## The tasks

| Task | Brief | Branch / worktree | Proposals |
|---|---|---|---|
| T1 | [R6-T1-loader-layers.md](R6-T1-loader-layers.md) | `r6-t1-layers` | 1, 2 (tiers), 4 |
| T2 | [R6-T2-evidence-telemetry.md](R6-T2-evidence-telemetry.md) | `r6-t2-evidence` | 3, 5 (bootstrap part), 11 (menu panel RAM warning) |
| T3 | [R6-T3-companion-docs.md](R6-T3-companion-docs.md) | `r6-t3-companion` | 5 (companion part), 11 (guide, docs, skill), the tier line in the RTX tab |
| T4 | [R6-T4-runtime-logs.md](R6-T4-runtime-logs.md) | `r6-t4-runtime` | 8 |
| T5 | [R6-T5-fixes-memlimits.md](R6-T5-fixes-memlimits.md) | `r6-t5-fixes` | 9, 11 (`~gmod_topbr` BC7) |
| T6 | [R6-T6-performance-tiers.md](R6-T6-performance-tiers.md) | `r6-t6-tiers` | the user's defaults request, 2's values, 6 |

Worktrees are `out\worktrees\<branch>`, cut from `main` at the commit that added these briefs.

## Rules for every task

1. Work only in your worktree and on your branch. Commit there. Never push, merge, tag, or commit
   on `main`: a commit on `main` publishes the Workshop item.
2. **Never launch Garry's Mod**, except T6, which alone may run sessions on the PoC install
   (`H:\SteamLibrary\steamapps\common\GarrysMod_PoC`, `tools\poc_session.py`). Nobody touches the field
   install (`H:\SteamLibrary\steamapps\common\GarrysMod`), Steam's files, or any `user.conf`.
3. Follow [AGENTS.md](../../AGENTS.md): a `.md` beside every script, `docs/COMPONENTS.md` for new
   folders, `CHANGELOG.md` lines under `## [Unreleased]` in a section `### R6 <task> (unreleased)`,
   `docs/RESEARCH.md` facts, `docs/TESTING.md` for new checks. Shared docs get additive edits only.
4. ADR numbers are reserved: T1 0062, T2 0063, T6 0064, T4 0065 if it needs one, T5 0066 if it needs
   one. Add your row to `docs/decisions/README.md`.
5. `packages/` changes only through `python tools\inputs.py import`; keep the staged files under your
   worktree's `out\` and give the exact import commands in your report.
6. Do not bump the loader version (`CMakeLists.txt`); the integration does.
7. In files several tasks touch (`loader/core/src/status.cpp`, `loader/cli/nlctl.cpp`,
   `loader/proxy/diagnostics.cpp`, `loader/core/src/config.cpp`, the menu panel, the docs), keep your
   edits additive and local: new functions or blocks, no reformatting, no reordering.
8. Temporary files under your worktree's `out\` only.
9. Before you finish: `tools\test.ps1 -Config Release` passes in your worktree.
10. Your final message is your report: what changed (files), decisions you made and why, tests run
    and their results, what you could not verify, open questions. Be specific; no marketing.
