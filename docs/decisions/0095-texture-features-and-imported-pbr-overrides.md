# 0095: Match imported game maps by UV features and keep player choices by texture

- Status: Accepted for R12-B, 2026-11-02
- Decided by: the user's R12 items 37 and 39
- Extends [0091](0091-automatic-pbr-fallbacks.md) and [0093](0093-cached-imported-game-materials.md);
  preserves authored priority from [0092](0092-generated-fallback-mods-rank-last.md)

## Decision

Keep exact canonical base/map stems as the first pairing route. For renamed bases, compare spatial
edge distributions at corresponding UV coordinates against supported normal/packed families.
Use aspect, island outlines and internal boundaries; do not rotate, translate or warp a different
atlas into a match. A small English/Chinese vocabulary adds at most .08 support after spatial evidence.
Accept only raw correlation >= .28, total score >= .36 and runner-up margin >= .12. Otherwise abstain.
Original PMX face/eye/skin protection still decides which pixels can change. Log the base, family,
score, margin, spatial evidence, acceptance and reason. Native discovery is the measurement tool's
implementation too; names-hidden measurements disable canonical pairing and vocabulary support.

All scans/decodes run on the worker. A cached folder has at most 4096 entries, depth six, 64 family
stems, 96 feature decodes, 256 MiB compressed inputs and 256 million source pixels. Each descriptor
has at most 128 pixels on its longest edge; source images remain bounded at 4096 squared. Eight
folders are cached per worker. Exhausted or incomplete candidate scans fail closed. Clear/restart
rebuilds descriptors. Converted map keys include input bytes, semantic channel roles, layout and
generator v6. The automatic registry format and validated missing-source restoration stay unchanged.

Add a separate durable `game_overrides.registry`, keyed by the actual live `mmd/t/<16 hex>` identity.
A player may choose a candidate family or individual source-folder maps with an explicit game
layout, disable game maps for that texture, or return to automatic. Manual choices outrank fresh
automatic matches and the automatic cache. They record source/base/map provenance and the converted
DDS filenames, sizes, content digests, constants and generator. Restoring a choice needs only valid,
unchanged DDS and current drawn hashes; it never needs the old source or a character name.

None is persistent. Returning to automatic removes the choice. Missing/changed manual DDS suppress
that choice without falling back to automatic. Unreadable/unknown override data stays intact and
suppresses automatic use until it is readable. Saves preserve previous/edited bytes and use the
existing flushed, closed staging file and write-through atomic replacement. Failure keeps the prior
in-memory and on-disk choice. The file is capped at 8 MiB, 4096 choices and 16384 bytes per row.

An edit retracts/refreshes all observed materials sharing that texture, including choices made while
the game-map switch is off. Publication still obeys the switch, authored-hash guard and runtime patch
0020. The interface belongs in the RTX menu's Imported game PBR panel, also reachable through
`rtx_topbr_game_editor`. List the looked-at character's materials, drawn-only thumbnails, current
state, families and files. Use the bundled add-on i18n function; keep the new phrases and all six
translations in the GPL fixes part, without changing another R12 task's companion paths.

Embed the panel in the existing trusted `cl_rtx_topbr_conversion.lua` path. The render guard's
exact exemption list is verified against indexed Lua inputs; adding another executable Lua path
would require changing that shared companion list. The embedded panel needs no exemption change.

Before resolving a material/texture identity, require drawn frame hashes. Library enumeration must
not load unseen characters' textures through `FindMaterial`. Native tests exercise this ordering.

## Limits and evidence

Features deliberately abstain for weak or repeated layouts. A successful canonical-name pairing is
the corpus comparison's reference, not an independent human UV annotation. Source-only emitters,
unknown game formats and unsupported images are not guessed into a family. A manual map selection
is explicit player intent and still uses the original UV protection and known-layout validation.
The [R12-B report](../handover/R12-B-report.md) records the measured agreement/abstention, rendered
PoC evidence and restoration, final DLL identity and remaining limitations.
