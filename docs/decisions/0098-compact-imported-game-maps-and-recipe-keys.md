# 0098: Compact imported game maps, no session budget for them, and recipe-keyed reuse

- Status: Accepted 2026-11-03 (R13-M); amends the bounded ToPBR of [0091](0091-automatic-pbr-fallbacks.md),
  the records of [0093](0093-cached-imported-game-materials.md) and the cache keys of
  [0095](0095-texture-features-and-imported-pbr-overrides.md)
- Decided by: the user's R12-B3 request (2026-11-03, [brief](../handover/R12-B3-game-maps-budget-formats-reuse.md)),
  carried into R13 by the [R13 plan](../handover/R13-plan.md); details in the
  [R13-M report](../handover/R13-M-report.md)

## Context

ToPBR stopped converting imported game maps once a session had written 1 GiB of DDS. R12-B2's
generator change made every drawn character convert again, at about 22.4 MB per uncompressed
2048x2048 map, so the field game ran out after about ten families and 洛茜 got no maps. The hotfix
(fixes `26aec12`) exempted game maps from the budget. Three things remained: maps stored as full
colour images although roughness and metallic are one channel and the octahedral normal two, an
AO map that nothing reads, and cache keys tied to one global version, so any release converted
every character again.

## Decision

1. **Formats.** Imported game maps store the octahedral normal as `BC5_UNORM` (Remix reads `.xy`),
   roughness and metallic as `BC4_UNORM` (Remix reads `.x`), with DX10 headers and full mip
   chains; emission stays uncompressed; AO is no longer written. A base whose sides are not
   multiples of four keeps the uncompressed layout. A 2048x2048 family is 11,185,308 bytes on disk
   instead of 89,478,992, and Remix loads 11,185,308 instead of 67,109,244.
2. **Encoder.** Written in the fixes, with no new dependency: per 4x4 block, endpoints at the
   extremes bound every texel's error by (max - min) / 14; least-squares refinements, the exact
   0/255 mode and (for blocks of at most four levels) palette-aligned endpoints may replace them only
   with a lower squared error and no worse texel. Integer arithmetic gives deterministic bytes.
3. **Validation.** `ValidDDS`, `Inspect` and `ValidRecord` accept the DX10 BC4/BC5 layouts and, by
   the unchanged rule, the uncompressed one, so every existing record and cache entry stays valid.
   Records also check each role's format.
4. **No session budget for imported game maps.** They are bounded by the registry's limits, the
   image bound and the free-space check (64 MiB kept free). Each refusal is one line naming its
   limit and numbers; the worker logs it and the Imported game PBR panel shows it, for every
   material sharing the texture. The opt-in world conversion keeps its 1 GiB per session, its
   uncompressed writer and once-per-session refusal lines.
5. **Reuse across versions.** The content key hashes what changes the bytes: the PMX, the base's
   bytes and name, each map role with its bytes, the layout and `GamePBR::Recipe()`, which lists the
   decoding, masks, class tables (printed from the values in use), channel rules, octahedral
   encoding, mips, formats and encoder. Matching, pairing and the generator number (provenance, now
   8) are not part of it. The completion marker records the recipe and the family's origin.
6. **The format change itself transcodes.** With the source present, a finished earlier family
   with the same inputs (v7, v6, v5 keys, each by its shipped formula) is re-encoded instead of
   converted again, byte-identical to a fresh conversion. Exceptions convert from the readable
   source: a v5/v6 family whose normal, packed or emission map was resized (WIC's premultiplying
   decode, R12-B2), and v5 families for manual choices or for Endfield/WuWa families in a folder
   holding a `*_MRA` map (v5 keys carry neither roles nor layout, and v5 chose Silver there).
   Without the source, stored registry records and manual choices are re-encoded beside the
   originals and saved atomically; a failed save keeps the previous, still valid record.
7. **Earlier files stay.** Superseded uncompressed files are not deleted. A collector that proves
   a file unreferenced by every record, every manual choice and the published USD is a separate
   decision.

## Consequences

- For 洛茜, 阿芙2.0 and endminf (12 families) the replacement-texture VRAM their maps add fell from
  732,669,952 to 139,901,952 bytes in the PoC, and their files from 945,122,708 to 145,408,760 bytes
  ([R13-M report](../handover/R13-M-report.md)); emission maps keep their size.
- Remix preloads every map the previous session published (`preload_textures`), so the first
  session after this change also holds the uncompressed maps it preloads at startup, once.
- Encoding adds about one second per 2048x2048 family on the worker thread.
- A release that changes no conversion reuses every map. A change that does must change the recipe
  (a table value does so by itself; code changes bump the step's tag).
- Downgrading after the migration is not supported: an older module rejects the compact files and
  would drop records whose source is gone.
- Until a collector exists, a migrated family's uncompressed files remain on disk beside it.
