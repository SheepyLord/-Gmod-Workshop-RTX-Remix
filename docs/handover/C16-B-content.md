# C16-B: the PBR tool writes scene-adaptive emission for the eyes

Read [AGENTS.md](../../AGENTS.md), [C16-plan.md](C16-plan.md) and the skill
[`skills/mmd-remix-pbr`](../../skills/mmd-remix-pbr/SKILL.md) (its `references/standards.md`,
`references/runtime-notes.md`) first. Work in `out\worktrees\c16-content` on branch `c16-content`.

## Build

1. **rpai writes the new input.** For a material whose emissive map carries eye classes (`sclera`,
   `eye`, `highlight` in the standards table), rpai's USD writer adds
   `float inputs:emissive_adaptive_intensity = <value>` next to `emissive_intensity`, which stays as
   the fallback for runtimes without the feature. The value comes from a new class field (for example
   `emissive_adaptive` in the class table and presets) or a publish option
   (`--emissive-adaptive-intensity`); choose the one that fits rpai's existing design and say why.
   The default is provisional: Claude will tune it in the game. Start from the value that gives the
   eye white the same emission as today's `0.025 x emissive_intensity` at a mid exposure, and write
   down how you derived it.
2. **Already published packs.** A script in the skill's `scripts/` (with its `.md`), for example
   `set_adaptive_emission.py --mod <mod folder> --value <v> [--dry-run]`, that adds or updates the
   input in an existing pack's USD for the materials with an emissive map, without regenerating
   textures, keeping every other byte as it is. Show it on copies of `pbr_robin`,
   `pbr_evernight_march7th` and `pbr_guinaifen` (read them from
   `H:\SteamLibrary\steamapps\common\GarrysMod_PoC\rtx-remix\mods\`, write only under this worktree's
   `out\`) and report which materials it changes.
3. **package_characters.py** carries the input into packages it builds.

## Tests and docs

- Unit tests for the writer and the script (input added once, value updated, materials without an
  emissive map untouched, dry run writes nothing, idempotent).
- `skills/mmd-remix-pbr`: the eye section of `references/standards.md` (the new rule and why: the
  auto-exposure conflict it replaces), `SKILL.md`, the scripts' `.md` files, `references/runtime-notes.md`
  (the input and that older runtimes ignore it).
- `tools\test.ps1 -Config Release` passes; a CHANGELOG line under `## [Unreleased]` in a section
  `### C-16 (unreleased)`.

## Rules

Only this worktree and its `out\`. Never launch Garry's Mod; never write to the PoC or field install
(read the PoC's mod folders only); never touch Steam's files or any `user.conf`; never upload to the
Workshop; never push, merge, tag or commit on `main`. Shared docs get additive edits only.

Your final message is your report: what changed (files, commits), the field or option you chose and
why, the provisional default and its derivation, the materials the script changes in each pack,
tests and results.
