# 0093: Retain imported game materials when their local source is unavailable

- Status: Accepted 2026-11-02 (R11-B)
- Decided by: the user's request to keep imported game maps working after their source folder is gone
- Extends [0091](0091-automatic-pbr-fallbacks.md); preserves [0092](0092-generated-fallback-mods-rank-last.md)

## Context

The hotloader retains the imported model and content-named base textures. ToPBR retained converted
DDS, but forgot the material values/texture association at exit. A missing PMX therefore prevented
publication on subsequent sessions. Neither a model's name nor a prior session's Remix hash is
enough evidence to publish a material for a new live texture.

## Decision

The native worker keeps `game_materials.registry` beside `~gmod_topbr/textures`. Each successful
game conversion records the live hotloader base-texture identity (`mmd/t/<16 hex>`), its observed
Remix hashes, the four published DDS channels (normal, roughness, metallic, emission), DDS byte
counts/content digests, material constants, record version and generator version. Paths are safe
filenames relative to that texture directory. The registry uses a bounded text format and an atomic
staging-file replacement; unknown schemas and unreadable registries remain intact without reuse.

Lua submits loaded hotloader materials even when their library source/base metadata is absent.
The client captures the actual base-texture identity and current hashes; all disk work stays on the
worker. A readable PMX with base metadata always runs today's converter, including its content/recipe
key checks, and replaces the saved record on success. A rejected present source does not fall back.
Only when the source is unavailable can the worker restore a matching known texture. Every referenced
DDS must pass complete header/mip-size validation and its saved byte count/content digest. The saved
hashes are provenance; publication uses only the current live hashes.

Record validity is independent of generator version. Updating a generator cannot regenerate a lost
source, so its number does not expire an otherwise valid record. A separate minimum record version,
initially 1, can be raised for a demonstrated correctness defect. Missing/invalid DDS records are
pruned during load or attempted restoration and saved atomically. Records are capped at 4096, hashes
at 64 per record, input at 8 MiB, rows at 4096 bytes, and DDS dimensions at the existing 4096-square bound.

`rtx_topbr_clear` retracts and requeues live registrations but retains this registry and DDS. The
game-map switch still controls both fresh and restored materials. Both paths use the same authored-hash
exclusion and fail-closed scan, followed by the runtime's authored-first priority. Face/eye protection
is the converter's existing decision, retained in the DDS; a face-only conversion creates no record.

## Consequences

A character converted successfully with this version can keep its appearance after the source is
moved or removed. The registry cannot recover characters whose only successful conversion predates
this record: they need their source once to establish the association. No filenames, old generated USD
or model names are guessed. Unpublished AO data remains in the ordinary DDS cache and is not needed
to restore the material. No source model/texture is included in the distributed package.
