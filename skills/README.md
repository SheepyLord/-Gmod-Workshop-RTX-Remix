# Agent skills

Skills are folders an agent loads when a task matches: a `SKILL.md` (YAML front matter with `name`
and a `description` that says when to use it, then the procedure), with `references/` for depth and
`scripts/` or `tool/` for the code the procedure runs. They hold the methods, standards and lessons
of this project's art work, written so that an agent that never saw those sessions can repeat them.

| Skill | Use it to | Made from |
|---|---|---|
| [`mmd-remix-pbr`](mmd-remix-pbr/SKILL.md) | Give an MMD character imported with Model Hotloader (or a compiled port) AI-generated PBR materials: upscaled albedo, normal, roughness, metal and emissive maps, keyed by live Remix texture hashes, hot-loaded into the game and checked with measured A/B (AABB) tests. Includes the `rpai` tool and the per-character presets | Guinevere/Guinaifen, Firefly, Hyacine, Robin, Cyrene, Castorice, Eldreda, Hiyuki, Evernight, March 7th (2026-10-24 to 10-31) |
| [`remix-map-pbr`](remix-map-pbr/SKILL.md) | Remaster a map for RTX Remix: extract its materials, classify them, generate PBR maps with AI, build the Remix mod (material overrides, lights, sky, mirrors, caustics), tour and compare it in game | gm_poolrooms RTX, Modern House RTX, Backrooms RTX (2026-10-26 to 10-29) |
| [`workshop-content-pack`](workshop-content-pack/SKILL.md) | Pack a character (its Model Hotloader package and PBR mod) or a map remaster, with the add-ons it depends on, into a hidden Workshop item that the native loader deploys from any subscription | Guinaifen RTX (3829348717), Robin RTX (3829892354), Evernight and March 7th (3830769477) |

A typical character goes `mmd-remix-pbr` (make and verify the materials), then
`workshop-content-pack` (ship them). A map goes `remix-map-pbr`, then `workshop-content-pack`.

## Installing a skill

Claude Code reads personal skills from `%USERPROFILE%\.claude\skills\<name>\`. Copy the folder
there, or link it so the repository stays the one copy:

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\mmd-remix-pbr" -Target "<repo>\skills\mmd-remix-pbr"
```

Other agents (Codex and the like) can read the `SKILL.md` directly: each skill names the files to
read next. `mmd-remix-pbr` also needs its runtime, which is not in the repository: a Python 3.12
venv with PyTorch (CUDA), the PBRify weights (CC0) and the RTX Remix Toolkit's NVTT exporter, all
under `%USERPROFILE%\.rpai` (`tool/setup.ps1` creates it; it downloads, so ask first).

## Rules every skill keeps

- **Measure, do not eyeball.** Before/after numbers with a noise floor (AABB), not impressions.
- **Leave the user's setup alone:** never edit Remix `user.conf` or `rtx.conf` without asking, never
  write into `rtx-remix\mods\!advanced_material_editor`, never restart or stop a game you did not
  start, and restore every scene change you make.
- **Downloads and uploads are asked for**, except what the project's standing permissions allow
  (AGENTS.md rule 5): Workshop test items are uploaded hidden and never deleted; making one public
  needs the user's go-ahead, and so does anything with unclear redistribution rights or adult content.
- **Derived assets keep their source's terms.** A map or model by another author stays local or in a
  hidden item unless its terms allow redistribution (Modern House's derived textures stay local).
- **Licences:** the skills and their scripts are this repository's (MIT). The map pipelines they
  describe live in the user's GPL-2.0 fork `garrys-mod-rtx-remixed`; the skills point to those
  scripts and never copy them.

## Keeping them current

A skill changes when a method or a standard does: update its `SKILL.md` (and the reference it
points to) in the same change, with the evidence, and say so in [CHANGELOG.md](../CHANGELOG.md).
Every script keeps a `<script>.md` beside it, as everywhere in this repository.

`mmd-remix-pbr` was copied on 2026-10-31 from the user's installed copy
(`%USERPROFILE%\.claude\skills\mmd-remix-pbr`, a plain folder that character sessions edit), after the
Evernight/March 7th session finished its edits; the per-script `.md` files were added here. When the
installed copy changes again, copy it back here (or replace it with a junction to this folder) so the
two do not drift apart.
