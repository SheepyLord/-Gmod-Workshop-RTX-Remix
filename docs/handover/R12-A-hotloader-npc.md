# R12-A: NPCs after a character is removed and imported again (brief)

Read [AGENTS.md](../../AGENTS.md), [R12-plan.md](R12-plan.md) (item 36 and the rules for every task),
[ADR 0090](../decisions/0090-ready-carriers-before-actor-publication.md) and the R10 report's item 33.

**Where you work.** Branch `r12-hotloader` in `out/worktrees/r12-hotloader` (from `main`).
**Owns:** `packages/model-hotloader/mmd_hotloader/lua/**` (text), its tests and QA tools
(`tools/qa/**` for hotloader sessions, `tools/tests/**` harnesses you add), ADR 0094, the R12-A report, and
additive lines in the shared docs. **Does not touch:** the hotloader's binaries, `packages/fixes`,
`companion/**`, `runtime/**`, `loader/**`, other parts.

## The bug

The user removed endminf from the Model Hotloader library and imported it again in the same session:
a ragdoll spawns, an NPC does not, with `[Model Hotloader restore] Cached model carrier is missing or
outdated. Reapply/import the model.` from `persistence.lua:211` (`report`), called by the `Entity:SetModel`
wrapper (`persistence.lua:236-245`, `mmdhl.EnsureModel(path)` failing), from `SpawnActorNative`
(`actors.lua:356`, `ent:SetModel(rig.model)`) and `server.lua:108`. Another add-on (`compositeentities`)
also wraps `SetModel`; the hotloader's wrapper sits under it.

## What to do

1. Reproduce on the PoC with a character imported from a copy of an `E:\G\Upload` folder (endminf's is
   named in the plan): spawn an NPC, delete the entry, import it again, spawn a ragdoll and an NPC. Also
   cover a player model and a re-import that changes the carrier (another option or a changed source).
2. Find why `EnsureModel` keeps or rejects a stale carrier after deletion and re-import (caches keyed by
   model path or asset id, mounted packages, the client/server split, the readiness work of ADR 0090) and
   fix it at the cause, for every spawn kind. A deleted entry's state must not survive into its re-import;
   an entity that still uses the old carrier must not break.
3. Regressions: a Lua harness for delete + re-import + NPC/ragdoll/player readiness; the PoC sequence above
   with screenshots and the console part of your session.

Report: `docs/handover/R12-A-report.md` (cause, fix, evidence).
