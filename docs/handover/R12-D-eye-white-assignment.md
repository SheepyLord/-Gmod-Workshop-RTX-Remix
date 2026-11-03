# R12-D: choosing a character's eye-white materials by hand (brief)

Read [AGENTS.md](../../AGENTS.md), [R12-plan.md](R12-plan.md) (item 38, the rules for every task),
[ADR 0088](../decisions/0088-imported-character-eye-whites.md), [R10-E-report.md](R10-E-report.md) and
[runtime/README.md](../../runtime/README.md) (patch 0019).

**Where you work.** Branch `r12-eyes` in `out/worktrees/r12-eyes` (from `main`). **Owns:**
`companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua` (and new companion Lua files for
this feature), the companion's i18n catalogs (additive keys), `tools/tests/eye_whites_harness.lua` and
new tests, ADR 0097, the R12-D report, additive shared-doc lines. **Does not touch:** other companion
files except to register a menu entry, `runtime/**`, `packages/**`, `loader/**`.

## What to build

The user: "In some way, allow manual assignment of a material on character to be eye-white." R10-E finds
eye whites by material name only. Let the player mark any material of an imported character as eye white,
and unmark one that was detected wrongly:

- An interface a player finds: from the existing eye-white settings (brightness) and/or for the character
  being looked at, listing that character's materials with a thumbnail and name, showing which are eye
  white (automatic or chosen), with a toggle per material. Changes apply live, without a respawn.
- Stored per character (asset) and material, surviving restarts, re-imports of the same asset and map
  changes; a manual choice outranks the name rule both ways. The marked material gets the same treatment
  as an automatic one (proxy texture, alias, brightness).
- Bounded and safe: only Model Hotloader materials backed by real generated textures; nothing for
  characters nobody spawned (R12-C is measuring VRAM: do not load textures for them).
- Translatable strings in the companion's i18n catalogs.

Evidence: the harness (mark, unmark, persistence, outranking the name rule, re-import), and a PoC check with
a character whose eye whites the name rule misses (find one in `E:\G\Upload` and use a copy), with
screenshots before/after. Report: `docs/handover/R12-D-report.md`.
