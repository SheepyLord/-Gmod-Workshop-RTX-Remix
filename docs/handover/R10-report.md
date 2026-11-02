# R10: the user's character report of 2026-11-02 (report)

[Plan](R10-plan.md); Codex's reports: [R10-E](R10-E-report.md) (item 31, eye whites) and
[R10-H](R10-H-report.md) (items 33 and 34, NPCs after a map change and VMD expressions); ADRs
[0088](../decisions/0088-imported-character-eye-whites.md), [0089](../decisions/0089-pmx-identities-and-geometry-checked-vmd-expressions.md)
and [0090](../decisions/0090-ready-carriers-before-actor-publication.md).

## Review and integration (Claude)

- **R10-E.** The companion gives only a named eye-white material its own copy of the atlas, one RGB
  low bit different, and tells the runtime (`rtx.gmod.eyeWhiteAliases`, NoSave) that the copy is the
  atlas. Patch 0019 looks replacement materials up by the atlas, so packs keep their eye materials,
  and otherwise gives the copy C-16's adaptive emission from its own albedo (0.625, Robin's measured
  sclera level). Texture categories (MMD alpha, imported normals) follow the atlas too. The PBR tool
  is unaffected: it groups live hashes by base texture name, and the copy's name is no asset texture.
  Review change (`46d6187`): the copies are cached in `garrysmod/data/nativeloader/eye_whites`, 5-85 MiB
  each, and nothing removed them; the cache now stays under 1 GiB, oldest first, never a copy bound in
  the session (harness scenario `cache_cap`).
- **Runtime import.** `runtime/build_runtime.ps1` in R10-E's build tree (HEAD `381271b1`: the base and
  patches 0001-0019) rebuilt and imported `d3d9.dll`, SHA-256 `c61f1725...` (`ee59753`). Codex tested
  `3e5c8486...` from the same tree; the rebuild is not byte-identical, so the PoC check below uses the
  imported DLL.
- **R10-H.** Expressions bind by the PMX name first, decoded from the VMD's CP932 bytes as nanoem does;
  meanings only for names the model lacks, with sides measured on the model. NPC entries are published
  only once the carrier is mounted and the current map has precached the model; a mount from an earlier
  map is checked, not trusted. Codex could not reproduce the user's exact "model not found" on the PoC.
- **Tests on `r10-int`.** `tools\test.ps1 -Config Release`: 26 of 26 CTests, the Python suites (498, 28
  and 25 tests, one skip each in the two small ones), "All checks passed".

## PoC check of the merged package (Claude)

The combined package from `r10-int`, `0.0.0-dev.20261102121250+988a3f12` (1,064 files, digest
`425e24de...`), deployed as a local package with RTX on (`out/r10-qa` in the `r10-int` worktree). A first
run deployed nothing: the package path was given relative, and the loader resolved it against the game
folder ("file not found"); an absolute path fixed it.

**Eye whites** (Linlong, no pack; R10-E's front camera, boxes and placement; noon and night):

| | off | 100 % | 200 % |
|---|---:|---:|---:|
| Eye white over cheek, noon | 0.17 | 0.75 | 1.21 |
| Eye white over cheek, night | 0.31 | 1.05 | 1.74 |
| A face patch outside the eyes over cheek, noon / night | 0.98 / 0.92 | 0.98 / 0.92 | 0.96 / 0.91 |

The same as R10-E's numbers with its own DLL (0.18/0.74/1.21 at noon, 0.26/1.02/1.69 at night). The
status line shows the imported runtime accepting the option (`supported=true`), only `eye_white_4`
bound to the copy (`0x72639b32...` aliasing the atlas `0xbd866dd5...`), the original atlas back when the
checkbox is off, 117 ms to prepare the copy once and the same frame time in every variant (9.3 ms
median). At 100 % Linlong's eye whites look light beige: her painted eye white is cream (sRGB 249, 237,
221 in `face.png`, linear 0.95, 0.85, 0.72), and the emission has the albedo's colour, as the packs' does;
lit only by the bluish sky it looked grey. Evidence: `linlong-eyes-sheet.png`, `linlong-eye-zoom.png`.

**Expressions** (R10-H's driver, Guinaifen and Robin): each motion holds its own PMX morph at 1 and the
others at 0 (smile: `笑い`, wink: `ウィンク`, blink: `まばたき`). The screenshots show both eyes closed in a
smile for `笑い`, both closed for `まばたき`, and the character's left eye closed for `ウィンク`. The mapping
window, the one the user's screenshot showed, now reads `笑い` -> `笑い [eyes_blink_smile] #16` ("Drives:
笑い [eyes_blink_smile] #16"). Evidence: `expressions-sheet.png`, `mapping-guinaifen-full.png`,
`expressions/`.

**NPCs after a map change** (R10-H's driver, `--cold-first`, Linlong, a character Codex's runs did not
use), in the user's order: Linlong spawned as a ragdoll on gm_construct; after `map gm_flatgrass` her
first NPC came from the library (a new citizen carrier), then from the stock NPC menu, then the library
again; after `map gm_construct` the menu NPC and a library NPC again. Every spawn was attached with a
valid model. Evidence: `npc-linlong/`, `driver-npc.log`.

All three sessions quit normally with no Lua error. The only recurring console line,
`TrackMaterial: Material 'mmdhl_soft_v1_...' not found`, comes from the hotloader's soft copies and is
in R10-H's Workshop-baseline run too, so it predates R10. The PoC is back on its Workshop-only config
(the original's SHA-256, `bb27c0d8...`) and the lock is released.

## Merge, publish and CI

- `main` fast-forwarded to `r10-int` (`0429e9d`). The merge published Workshop item 3829070317 as
  `0.0.0-dev.20261102122205+988a3f12`, content digest `425e24de...`, the package checked on the PoC
  (Steam sent 32.2 MB of changed content). Pushed `96cfa4e..0429e9d` with the new runtime's Git LFS object
  (59 MB); the push's publish found unchanged inputs.
- CI on `0429e9d`: "Build winmm.dll" (run 41444241642) and "Build the RTX package" (run 41444241571)
  passed.

## Field (the user's install and add-ons)

The user's game was idle (over an hour without input); every session used `poc_session.py --root
<field> --allow-steam-managed` with the Workshop and the user's add-ons, single player, and quit
normally. Only each session's own part of `console.log` was read (from its start offset).

| Start | Package | What happened |
|---|---|---|
| 01 | `20261102021900+cef426ad` (R9; Steam fetched the new one during this start) | Guinaifen, the user's example character: ragdoll, library NPC, spawn-menu NPC and library NPC on gm_construct; after `map gm_flatgrass` the spawn-menu NPC came first, as the user does it, and spawned attached with a valid model. **The user's "model not found" did not reproduce on the old package either.** |
| 02, 03 | `20261102122205+988a3f12` (deployed and active) | gm_construct as in 01, with Linlong; the second map was not reached: the test driver lost the console after the map change (below) |
| 04 | the same | Linlong: ragdoll, library NPC, menu NPC, library NPC on gm_construct; after `map gm_flatgrass` the spawn-menu NPC first, then the library; after `map gm_construct` again both. Every spawn attached with a valid model |
| 05 | the same | R10-E's eye-white probe, Linlong at noon (the PoC's placement, camera and boxes): eye white over cheek 0.19 off, 0.78 with the feature on (PoC 0.17 / 0.75); a face patch outside the eyes 1.06 both times; status `supported=true`, `applied=1`, the alias `0x72639b32...=0xbd866dd5...`, the copy prepared once in 118 ms; frame time 10.5 / 10.4 ms median. Only the eye whites changed on screen (`field-eyes-sheet.png`) |

The driver (R10-H's, wrapped by `out/r10/field/field_npc_session.py`) failed after field map changes at
first: right after a field map load the game window briefly fails `poc_session.game_window`'s test and
flips between hung and responsive for a while, and `poc_session.console` gives up while it is hung. The
wrapper reuses the session's window handle and waits until the window has answered for five seconds;
start 04 passed with it.

## Branches, worktrees and evidence

- Only `main` remains, locally and on GitHub: `r10-eyes`, `r10-hotloader` and `r10-int` are merged and
  deleted. The `r10-hotloader` and `r10-int` worktrees are removed (an empty `out/worktrees/r10-int`
  folder was still held open by a process at the time).
- `out/worktrees/r10-eyes` stays as a detached worktree for its runtime build tree,
  `out/runtime-src` inside it: a standalone clone of the fork at HEAD `381271b1` (the base and patches
  0001-0019) with a configured, built `_CompRelease_x64`. The next runtime patch builds incrementally:
  `runtime\build_runtime.ps1 -Fork <that folder> -Worktree <that folder>` after `git am` of the new patch.
- Evidence, without the test packages (`.gma`), is in `out/r10/evidence`: `r10-e` (Codex's catalogue,
  measurements and PoC runs, 326 MiB), `r10-h` (corpus analysis, mappings and PoC runs, 59 MiB), each with
  Codex's prompt, final message and log, and `r10-int-qa` (Claude's PoC and field sessions, 37 MiB).

**Item 33 in short:** neither the PoC (Codex's runs and Claude's, across `map` changes, fresh starts and a
listen server) nor the field, on the old package or the new one, showed the user's error. R10-H's change
(ADR 0090) removes the conditions that could produce it: an NPC entry is offered only once the carrier is
mounted and the current map has precached its model, a mount from an earlier map is checked rather than
trusted, and the hotloader's own spawn checks the same; a spawn that still cannot be made ready now stops
with the hotloader's mount error instead of using a model the map does not have.
