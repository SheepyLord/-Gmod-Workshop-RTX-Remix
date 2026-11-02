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
