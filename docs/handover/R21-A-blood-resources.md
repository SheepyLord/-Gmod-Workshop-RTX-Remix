# R21-A: Blood Overhaul's resources in the blood part, with their author's permission

Worktree `out/worktrees/r21-blood`, branch `r21-blood`, from `r21-int`. Implementer: Codex
(gpt-6.1-sol). ADR number: **0124**. Read first: [R21-plan.md](R21-plan.md) (the user's words and the
rules for every task), [AGENTS.md](../../AGENTS.md) (rules 6 and 7 especially),
[packages/README.md](../../packages/README.md), the part's
[README](../../packages/blood-overhaul-rtx/README.md), `licenses/CREDITS.txt` and
`licenses/provenance.json`, [ADR 0118](../decisions/0118-bundled-toolgun-screen-and-owned-blood-patterns.md),
[ADR 0119](../decisions/0119-client-blood-impacts-with-bounded-spatter.md), the R20-C brief and report
([R20-C-blood-and-toolgun.md](R20-C-blood-and-toolgun.md), [R20-C-report.md](R20-C-report.md)),
`tools/prepare_blood.py.md`, `tools/prepare_blood_particles.py.md`, the `blood-overhaul-rtx` entry of
`tools/workshop.json`, the companion's blood Lua (`companion/nativeloader/lua/nativeloader/blood_*.lua`,
`lua/autorun/!nativeloader_blood.lua`, `lua/autorun/client/nativeloader_blood_menu.lua`) and the part's
`nlblood/lua/nlblood/shapes.lua` and `schemes.lua`. Then the source project's own README:
`H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx\README.md` (its pipeline, the Remix traps, the
colour schemes, the decal mixer).

## The user's item

> Permission is obtained from the author of the resources of Blood Overhaul, please package them and
> publish and I will update the credit section.

R20 item 48 asked for the user's Blood Overhaul add-on "with PBR we made" in the RTX package. R20-C
shipped only what this project made, because no permission to redistribute Crunchy's files was assumed.
That permission now exists (the user obtained it on 2026-11-06). The Workshop page's credit section is
the user's to update; the package's own credits are yours to make true.

## Facts

- The source project (read only): `H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx`.
  `dist/addon` is the user's whole add-on (Crunchy's files plus the new textures, VMTs and Lua; the
  field's `garrysmod\addons\Blood Overhaul` holds the same tree, 185 MB); `dist/remix_mod/blood_overhaul_rtx`
  is its PBR (177 DDS, 182 material overrides keyed by XXH64 and XXH3; the field copy is
  `rtx-remix\mods\blood_overhaul_rtx`); `backup/Blood Overhaul (original)` is Crunchy's add-on as it was,
  with `backup/blood_overhaul_md5.txt`.
- `provenance.json` lists 132 files R20-C left out as "Crunchy original or derivative" (`bo_blood1..8`
  and their neutral `_n` textures, flesh and alien flesh normal maps, the stains, their DDS maps, the old
  droplet) and 138 it replaced with owned-only files (the old Lua, the `decals/blood*_subrect` and
  `decals/antlion` overrides, the per-family VMTs, the unfiltered USD layers). R20-C never considered
  Crunchy's stock-name files (`materials/decals/blood1..8`, `yblood1..6`, `bloodstain_*`,
  `decals/flesh`, `decals/alienflesh`).
- Crunchy's add-on is Workshop 2683396098. The user's Steam library has it
  (`H:\SteamLibrary\steamapps\workshop\content\4000\2683396098\gmpublisher.gma`), so the PoC and the field
  may mount it; the field also keeps the legacy `Blood Overhaul` folder. Crunchy's own VMTs blend with
  modulate-2x, which Remix turns into an opacity from luminance (yellow blood nearly vanishes); the
  user's add-on made every blood decal a tintable alpha decal, checked in game.

## What to build

1. **Selection.** Everything R20-C left out only for want of permission ships now: Blood Overhaul's
   textures (`bo_blood1..8` natural and neutral, the flesh and alien flesh maps, the stains), the
   stock-name decal files as the user's add-on ships them (Crunchy's `materials/decals/blood1..8`,
   `yblood1..6` with their `_subrect` VMTs, `bloodstain_*`, `decals/flesh`, `decals/alienflesh`, and the
   user's `decals/antlion/shot*`), and every PBR map and material override made from them. Ship the bytes
   of `dist/addon` and `dist/remix_mod` (record which files are Crunchy's unchanged and which the user
   changed, from the md5 list). What stays out: the old Lua (the companion's mixer, schemes and menu
   replace it), the old flying droplet `particle/bo_droplets` (R20-C's analytic droplet replaced it;
   ship it only if shipped code still uses it), source and reference images, GMAs, ZIPs, previews,
   backups, logs and development files. `tools/prepare_blood.py` makes the selection and records every
   selected and excluded file with its SHA-256 and reason in `provenance.json`, as it does now.
2. **One coherent add-on.** The companion keeps R20-C's design (settings in RTX Remix / Blood, the
   private mixer and schemes, the bounded impacts, the exact-path guard against the legacy modules,
   distinct deployed folders). Then:
   - The mixer's shape list gains Blood Overhaul's eight shapes, as in the user's original (26 shapes,
     world sizes from `dist/addon/lua/bloodoverhaul/sh_shapes.lua`), in every family the companion has
     (red, yellow, green, worker), with world and model VMTs made the way R20-C made the eighteen's.
   - The engine's own blood (bleeding NPCs, the `Blood`/`YellowBlood` decals C++ places, flesh
     impacts, stains) shows Blood Overhaul's textures with PBR, as in the user's add-on. Colour schemes
     reach those materials if the original add-on recoloured them (read its `cl_core.lua`); turning the
     blood settings off undoes whatever Lua changed.
   - One Remix layer: R20-C's entries plus every override for the newly shipped textures, both hash
     kinds, R20-C's sprite opacity materials kept; every referenced DDS shipped and every shipped DDS
     referenced (test it).
   - Every R20-C file, test and doc that says no Crunchy content or no stock material is in the part
     says what is true now.
3. **Coexistence.** With Crunchy's own add-on mounted, and with a field-style legacy `Blood Overhaul`
   folder, in both virtual-path precedence orders you can produce: no Lua error, one mixer, and a record
   of which VMT wins and how it renders under RTX. If Crunchy's modulate-2x VMTs win and blood
   disappears under RTX, fix it if a safe fix exists, else document it with the workaround.
4. **Credits and licence.** `CREDITS.txt` and the part's README: Blood Overhaul's resources by Crunchy
   (Workshop 2683396098) and the PBR made from them are included with their author's permission,
   obtained by SheepyLord on 2026-11-06; they are not under this repository's MIT licence and remain the
   author's (rule 7: a part keeps its sources' terms beside it). Keep the AI-generation disclosure and
   the prompts. Do not edit the Workshop page.
5. **Size.** Report the part's indexed inputs, binaries and compressed bytes before and after, and the
   package's size change. Expect roughly 100 MB more in Git LFS; import each binary once, at the end.
6. **ADR 0124** superseding ADR 0118's exclusions and its "no stock blood material is replaced", with
   the reasons and the consequences (the stock decals look like Blood Overhaul while the package is
   active; what the off switch does and does not undo).

## QA (PoC, RTX on)

Shoot citizens and Combine (red) and antlions or zombies (yellow): engine decals, flesh impacts and
stains show Blood Overhaul's textures with their PBR (wet roughness, meniscus normals) and yellow blood
stays visible; the mixer draws the eight original shapes among the eighteen; each family's scheme
recolours them; blood settings off restores what they changed; R20-C's impacts still keep their budgets;
Physics Blood (3818841829) still renders as R20-D left it; the coexistence cases above. Screenshots and
logs under your worktree's `out\r21a\`. `tools\test.ps1 -Config Release` passes.
