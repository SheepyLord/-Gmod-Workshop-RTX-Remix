# M7 report: the field install

- Author: Claude, 2026-10-28, under the user's instruction to plan, build and test M5-M7 without
  further approvals, which includes launching and closing GMod sessions. AGENTS.md rule 1: the field
  install changed only for this milestone, only after a snapshot of what could be touched, and is
  back as it was.
- Plan: [M7-plan.md](M7-plan.md). Tool: [`field_snapshot.py`](../../tools/field_snapshot.py.md)
  (committed with M5/M6 as preparation). Branch: `m7-field` in the main checkout, merged into `main`.

## Result

**RTX on and RTX off both work in the user's Steam-managed install next to everything already there,
and one command put the install back.**

| Session (gm_construct, the user's 44 local add-ons, camera pinned) | `d3d9.dll` | `vulkan-1.dll` | Add-ons mounted | Notes |
|---|---|---|---|---|
| Baseline, no loader | the user's DXVK, `bin\win64` | `bin\win64` | 44 | MMD Hot Loader loaded; `mat_dxlevel` 95 |
| Loader, RTX on | the runtime package | **System32** | 53 (44 + the fixes' 9) | path-traced; 7 patch sets, the fixes' own 7 patches, the shader override, 33 session variables; MMD Hot Loader loaded |
| Loader, RTX off | the user's DXVK, `bin\win64` | `bin\win64` | 44 (the fixes' 9 hidden, ADR 0013) | the same modules as the baseline plus the bootstrap; frame vs baseline block_diff **0.015**; `mat_dxlevel` 95 |

- First RTX start: both packages deployed (445 changes) and the session reached the map in 19 s.
  Remix showed its first-run "Welcome to RTX Remix" panel over the path-traced frame. The field
  install has no Remix `user.conf`, which only Remix writes (rule 3), so the user will see it once too.
- The user's Jolt DLLs are present but not loaded in any of the three sessions: the stock
  `vphysics.dll` loads with and without the loader.
- None of the 33 session variables was archived in the field install's `config.cfg`, so there was
  nothing to record or restore.

**Rollback** (`field_snapshot.py --snapshot out\m7\snapshot rollback`, one command, exit 0,
`clean: true`):

- uninstalled the bootstrap and the packages (exit 0);
- moved into the snapshot's debris folder what the sessions created: `rtx-remix\` (Remix's logs and
  the ToPBR file the fixes rewrote), and in `garrysmod\data` the fixes' `rtx_agent`, `rtx_water` and
  eight `pseudoplayertexture*.png`, plus one user add-on's `sndcap_probe` folder;
- wrote back the 8 files the game rewrote: `config.cfg`, `client.vdf`, `server.vdf`, `cl.db`,
  `console.log`, `GameState.txt`, `modelsounds.cache` and DXVK's `gmod_d3d9.log`;
- made the registry key equal to the export again (nothing to prune);
- checked the result: the folder listings match, all 76 kept files hash as before (among them the
  user's `d3d9.dll`, `vulkan-1.dll`, MMD Hot Loader and Jolt files), and all 2,877 depot files
  verify.

Eight existing files below `garrysmod\data` and `garrysmod\settings` were rewritten by the sessions
and cannot be put back, because only their size and time were recorded. All eight kept their exact
size; only their times changed. They are files the user's own sessions rewrite every time:

- the MMD Hot Loader's `approved.json` and `workshop/state.json`;
- `bbs/filters.json`;
- `settings/mapkeys.res`;
- the fixes' four `pseudoweapontexture*.png`, rewritten with the same sizes as in August.

A no-op rollback straight after the snapshot came back clean too (nothing moved or restored, the
registry identical after the round trip): the tool was proven on the real install before anything
was installed.

## Evidence

All under `out\m7\`:

- `snapshot\`: the snapshot, its copies and the debris;
- `snapshot.out`, `noop-rollback.json`, `rollback.json`;
- `evidence\session.json` and `evidence\00-baseline`, `01-rtx-on`, `02-rtx-off`: each with
  `console.log` (this session's part only: the install's own log is read from where it ended and
  never moved), `modules.json`, screenshots, and for loader sessions `loader.log`, `status.json`
  and `session.json`;
- `baseline-vs-rtx-off.json`.

## Deviations from the plan

- The snapshot covers more than the plan named. M5's sessions showed what a session writes: every
  non-depot file in the root, `garrysmod`, `cfg`, `bin\win64` and `lua\bin` is copied, and size and
  time are recorded below `data` and `settings`. Rollback also prunes registry values a session adds
  and moves new entries aside instead of deleting them.
- `poc_session.py` leaves a Steam-managed install's `console.log` in place, and reads it from the
  offset where it ended.
- The plan's "session variables put back by the restore cfg" had nothing to act on (none recorded).

## Open

- Small files below the watched trees could be copied too, so a rollback can put back rewritten
  add-on state exactly. This time the sizes were identical.
- Installing the loader for real is the user's call:
  - `tools\install-loader.ps1 -GameRoot <field install> -AllowSteamManaged`;
  - a `config.json` that allowlists the two packages;
  - and, once, Remix's "Never Show This Again" on the welcome panel.
