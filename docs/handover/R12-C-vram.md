# R12-C: where the VRAM goes, and less of it (brief)

Read [AGENTS.md](../../AGENTS.md), [R12-plan.md](R12-plan.md) (item 40, Claude's measurements, the rules
for every task), [R5-stability-proposal.md](R5-stability-proposal.md) (the earlier VRAM analysis and the
`[RTX VRAM]` log) and the R6 performance tier records.

**Where you work.** Branch `r12-vram` in `out/worktrees/r12-vram` (from `main`). **Owns:** measurement
tools (`tools/**`), `runtime/**` (new patches, rebuild with `runtime/build_runtime.ps1`), `loader/**`,
`dist/**`, `companion/**` except `nativeloader_eye_whites.lua` (R12-D's), ADR 0096, the R12-C report and
additive shared-doc lines. **Does not touch:** `packages/fixes` and the fixes branch (R12-B's),
`persistence.lua`, `actors.lua`, `server.lua` of the hotloader (R12-A's). For changes there, or anywhere
else you do not own, write exact proposals in your report; Claude assigns them.

## Phase 1: attribution (no product change)

The user: "(Important) Garry's Mod currently uses so much VRAM in the active session." Find out what holds
the ~13 GB of D3D9 app textures and the rest of the ~20 GB in the field, with evidence:

- A breakdown you can trust: by D3D9 texture size/format/pool and, where possible, by Source texture name
  or group (the material system can tell which names are loaded), plus the Remix side (replacement
  textures, render targets, OMM, retained). Add logging or a probe if needed (runtime patch or tool).
- Experiments that isolate the suspects, each before/after: the hotloader library (empty versus the PoC's
  9 assets; are unspawned characters' materials or textures loaded, and by whom), eye-white proxies for
  characters nobody spawned, R11-B's `FindMaterial` in `QueueGameMaterial` (R12-B fixes it; measure
  before and after), the user's Workshop add-ons (the PoC can mount the same subscriptions with
  `--workshop --addons`), the spawn menu and its icons, render resolution, the quality tier, map changes
  (does memory come back), DXVK's retained memory. Field sessions only under the activity gate, read-only.

## Phase 2: optimize

Implement the safe, high-yield fixes in your paths, each measured before/after in the same conditions,
and write the rest as proposals. Constraints: what the player sees stays the same unless a setting says
otherwise; never change the Remix texture hashes of existing content without a decision record that
explains the cost (replacements and categories are keyed by them); nothing loads that the session does not
use; memory returns when characters, maps or sessions go.

Report: `docs/handover/R12-C-report.md` (the attribution table with evidence, what changed and what it
saved, proposals with expected savings).
