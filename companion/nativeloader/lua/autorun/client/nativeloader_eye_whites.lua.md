# nativeloader_eye_whites.lua

R12-D adds `nativeloader_eye_white_materials`, opened by **Choose eye-white materials** beside
brightness in RTX Remix → Rendering → Model outlines. It preselects the character being looked at
(or the only spawned character). The window lists names, original texture thumbnails, automatic/manual
status, a live eye-white checkbox and **Use automatic detection**. Pages contain at most 24 materials,
populated four per frame; thumbnails share the original texture without creating another atlas.
Rows use explicit light backgrounds and dark names/status/checkbox text for readable contrast.
The global enablement and brightness still apply, as do real PBR replacements' precedence.

Client-local choices, including explicit `false`, live in DATA `nativeloader/eye_white_choices.json`
(schema 1, at most 1 MiB / 4,096 choices). File existence is tested separately from file size so a
missing file cannot be mistaken for an unreadable empty file. A full 64-hex content asset ID plus slot/native material name
identifies a choice independently of the source location and generated renderer version. Re-importing
the same asset, changing map or restarting preserves it. Reset removes the manual value. A malformed,
oversized or unknown-version file is kept and blocks saving; an externally changed file also blocks
saving. Writes are read back before applying a choice. A failed write leaves the previous live choice.
No network, hotloader manifest or Remix user.conf is written.

`NATIVELOADER_EYE_WHITES.Materials(asset)` reads spawned character metadata without loading textures;
`SetChoice(asset, oneBasedSlot, true|false|nil)` validates the spawned owner, public VMT and generated
VTF before persisting and scheduling the existing alias path. `Open(entity)` opens the same window.
Discovery now uses `mmdhl.Entities()` / `GetAsset()` and already available `mmdhl.assets` metadata;
unspawned library entries and editor previews cause no Material calls or proxy work. Public paths must
belong to the asset's first 16 hex digits. Removing the last instance restores owned bindings at the
next discovery sweep. See [ADR 0097](../../../../../docs/decisions/0097-manual-eye-white-materials.md).

Generated `mmdhl.softMaterials[asset].soft[slot]` copies of an eligible eye part receive the same
identity, including copies created late or inheriting the proxy. Only a strict generated name matching
that asset's full 64-digit ID and slot is accepted. Owned soft bindings are restored on disable,
removal and shutdown; subsequent user changes and other parts' copies are preserved. This covers
the native renderer's separate soft-triangle draw under RTX without changing the hotloader.

RTX companion controller for [ADR 0088](../../../../../docs/decisions/0088-imported-character-eye-whites.md).
Discovers loaded `mmdhl.assets` materials using the shared native/English name matcher; validates
public `mmd/<16 hex>/<part>` materials and real `mmd/t/<hex>` textures. No hotloader patch is needed:
its native renderer binds these same public IMaterials. Foreign entity/submaterial overrides stay
untouched. Existing manifests may omit English names; any provided `en`, `englishName` or `nameEnglish`
is checked, and both fields are exercised by the catalogue scan.

For each distinct eligible atlas it creates a validated, byte-different VTF under
`garrysmod/data/nativeloader/eye_whites/<sha256>.vtf`. Existing different bytes are never overwritten.
Two immutable helper materials bind the original and proxy textures in a four-pixel offscreen 2D
target on separate frames so Remix's queued tracker can discover their hashes. A successful **NoSave**
`rtx.gmod.eyeWhiteAliases` write precedes binding the proxy to the eye-white public material. The
runtime looks up replacement materials by the original hash first; otherwise it uses scene-adaptive
emission from the selected draw's albedo. No shared face material is changed. The proxy changes one
RGB low bit and preserves alpha and mip levels, so geometry boundaries, filtering and soft coverage
are retained without UV masks.

`nativeloader_eye_whites` (archived, default 1) writes `rtx.gmod.automaticEyeWhites` and restores original
bindings when disabled. `nativeloader_eye_white_brightness` (archived, 0–200 percent, default 100) writes
`rtx.gmod.eyeWhiteBrightness`: both automatic and C-16 PBR eye emission respond live. It does not write
`rtx.adaptiveEmission.scale`, user.conf or any persistent Remix option. A runtime refusing the new
option receives no material changes; failed writes retry with bounded backoff.

Discovery visits at most 128 slots per frame, resource/hash work eight names, preparation one atlas
per second (max 128 MiB per atlas and 256 MiB per session), publication at most ten times per second.
Textures are shared across eligible parts of one atlas. Prepared images stay cached for the process;
the DATA cache is kept under 1 GiB: before a new proxy is written, the oldest files go first (a deleted
proxy is rebuilt when needed again), never one this session bound;
removed assets release bindings and registry entries. Restoration compares the current texture's normalized name
with the owned proxy, preserving subsequent user changes. `nativeloader_eye_whites_status` prints
support, enablement, percent, material counts, proxy byte count, maximum preparation time and aliases.

Side effects: deterministic owned DATA texture cache, temporary helper target, selected material
bindings and NoSave options. Shutdown restores owned bindings. No exit codes (client Lua).
