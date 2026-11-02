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
