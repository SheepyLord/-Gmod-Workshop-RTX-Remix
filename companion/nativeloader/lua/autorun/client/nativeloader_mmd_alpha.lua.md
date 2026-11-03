# nativeloader_mmd_alpha.lua

Registers Model Hotloader character base-texture hashes with the runtime's MMD alpha category
([ADR 0081](../../../../../docs/decisions/0081-mmd-alpha-texture-category.md)). Loaded `mmdhl.assets`
provides the public `mmd/<16 hex digits>/<part>` material names. Soft copies, depth copies and
public parts share the same textures, so they inherit the category without editing any material.

R12-C: the first lookup reads the existing draw tracker. Until that exact material has a valid,
nonzero draw hash, no `Material`, `TrackMaterial` or VMT existence lookup occurs. An unused library
therefore does not become resident just because the alpha classifier visited its metadata. The
public and soft-copy paths use the same gate; late draws remain retryable within the same budgets.

A part whose every texel is partly transparent (Columbina's lattice mask) is drawn only through the
hotloader's soft copy, never through its public material, so the runtime reports no hash for the
public name (PoC runs `14-mask-diag` and `16-mask-diag2`, 2026-11-01). The soft copy, tracked by its
plain name (`mmdhl_soft_v1_<asset>_<part>`, without the `!`), reports the texture's live hash
(`0x4F9DC84370047174` for the mask). Each sweep therefore also reads the soft-copy names the hotloader
keeps in `mmdhl.softMaterials[<asset>].soft` (created on a part's first draw), finds them as `!` materials
(no VMT on disk) and tracks and looks them up like the public parts, within the same budgets. A
tracked off-screen wrapper of the texture was tried first and never reported a hash in game.

Runs automatically on client `Think`. `nativeloader_mmd_alpha_status` prints its material count and
last accepted list. There is no new setting: this is the scoped correction to Model Hotloader
alpha, with no reason for a translated opt-out. The runtime also accepts a manually saved
`rtx.mmdAlphaTextures` list and `rtx.mmdAlphaCutoff` (default 0.5).

Inputs: the loaded Hotloader asset metadata, mounted materials and base textures,
`RemixMaterial.GetAllTextureHashes`, optional `TrackMaterial`/`GetMaterialHashRevision`, and
`RemixConfig.SetConfigVariable`. Missing APIs are harmless. Missing VMTs, missing/fallback VTFs and
missing hashes retry with exponential delays from 0.25 to 4 seconds. Refused tracking retries;
accepted tracking occurs once per loaded name. The VMT must exist in the virtual filesystem before
a `Material` lookup, avoiding a cached error material during a late mount. Only generated names with real base textures in
`mmd/` qualify; shared error/white textures, props and foreign overrides are excluded.

The discovery sweep runs once per second, visiting at most 128 asset/material slots each frame.
Hash/material reads use a rotating 16-name budget. A hash revision triggers rereads; an eight-second
refresh also handles bindings changed without a revision API. Lists contain canonical 64-bit hex
hashes, sorted and deduplicated. Asset removal releases names on the next completed sweep.
Publication is capped at four attempts per second and only a changed list is written; refused
option writes back off from one to 60 seconds. Discovery, list pruning and list assembly never
enumerate game entities or scan their material slots every frame.

Output/side effects: writes only `rtx.gmod.mmdAlphaTexturesForSession`, a NoSave option which the
runtime joins with the saved category. No files, original materials, entity overrides, assets or
persistent Remix options are changed. There is no exit code. Tests live in
[`companion/tests`](../../../../tests/test_mmd_alpha.py.md).
