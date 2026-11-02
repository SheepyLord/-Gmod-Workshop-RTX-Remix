# nativeloader_eye_whites.lua

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
