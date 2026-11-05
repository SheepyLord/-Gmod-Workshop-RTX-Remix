# RTX fixes package inputs

The GPL-2.0 fixes are imported from the user's fork; [LICENSE](LICENSE) applies. Binary payload
changes go through [`inputs.py import`](../../tools/inputs.py.md). Part notes and corresponding
source under `licenses/` are reserved documentation, excluded from the payload index. The package
builder includes the existing `licenses/oversized-skinning/` tree in the remixbinary add-on as its
native source bundle, including the R6 change below.

## R19 Lua inputs, ToPBR switches and the flashlight

Imported 2026-11-05 with `inputs.py --file`; every other indexed input is unchanged
([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)).

- `modules/gmcl_RTXFixesBinary_win64.dll` (5,512,192 bytes, SHA-256 `ba3fb505...4a0da`): the public
  base with the five patches, the fifth being [lua-paths.patch](licenses/oversized-skinning/autopbr/lua-paths.patch).
  Paths the module's Lua functions take stay inside the game (no network share, drive or `..`):
  ToPBR's output folder, game-map sources, VMT and VTF reads, Remix material and dome-light textures,
  and Remix options that name files. ToPBR turns on only while the player's `rtx_topbr_enabled` (world
  conversion) or `rtx_topbr_game_maps` (imported game maps) is on.
  [Source and rebuild](licenses/oversized-skinning/autopbr/Source.md).
- `modules/gmcl_rtxwater_win64.dll` (281,088 bytes, SHA-256 `970f9dbd...fe5a9`): Version 4 with
  [rtxwater-lua-input.patch](licenses/oversized-skinning/rtxwater/rtxwater-lua-input.patch): surface
  polygons of an even length of at least six, texture paths below the game folder.
  [Source and rebuild](licenses/oversized-skinning/rtxwater/Source.md).
- `remixlua/sv/sv_remix_flashlight.lua`: a 0.3 s cooldown per player on switches, colours coalesced to
  one broadcast per 0.1 s, and no flashlight where the gamemode or `CanUseFlashlight()` refuses one
  (the dead, spectators). `remixlua/cl/remixapi/cl_remix_flashlight.lua`: a repeated "on" replaces the
  player's light instead of leaking it.

## R8-B Backrooms native candidate (pending import)

The local source commit `7094baf6edf6797fd5c3f0b58ca668f9307b4906` ports the Backrooms
model-miss cache, lazy model-transform read and optional PAS visibility onto the packaged R6
source, preserving its oversized-skinning and memory-limit protections. It adds validation,
owned visibility restoration at module close and offline production-code regressions. The
existing remixbinary Lua already provides the add-on's lighting API and patch synchronization.
The DLL/PDB are built under `out/`; Claude imports the DLL after review. The package index and
binary inputs are unchanged by R8-B. See [source, pins, hashes and rebuild notes](licenses/oversized-skinning/backrooms/Source.md).
This layer is inside the already bundled `licenses/oversized-skinning/` source tree.

## R6 T5 memory-limit compatibility

The current module uses fixes source commit `a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`, a single
commit on the preceding packaged source `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe`. The module
no longer submits unsupported resource-limit options at map load. The old Lua method is a
documented no-op that logs once when explicitly called, preserves the two numeric arguments and
`true` result, and never writes configuration. See the [source, pins and rebuild notes](licenses/oversized-skinning/memory-limits/Source.md).

## R6 T5 ToPBR compression

All 83 DDS files in `garrysmod/rtx-remix/mods/~gmod_topbr/textures` are now BC7_UNORM (linear):
33 normal maps and 50 roughness maps, all referenced as `colorSpace = "raw"`. Their names,
dimensions and 816 mip levels remain; the material files are unchanged. DDS size falls from
142,869,484 to 35,729,420 bytes (75%); xz input size falls from 16,454,204 to 15,000,576 bytes.
See [encoder, measurements and import instructions](licenses/topbr-bc7/README.md) and the
[per-file conversion record](licenses/topbr-bc7/conversion.json). Rendering acceptance belongs
to R6 integration; offline decoding alone does not prove the rendered look.

## R11 automatic PBR

The R11-B DLL is built from fixes `633fd5e000aca862a8ae58b5c722d678ac4fa053` on the shipped
R8/R11-A base, preserving the oversized/model/PAS and memory-limit fixes. It is 5,167,104 bytes,
SHA-256 `526a6584d4ab68e657b7f1cead25db88beb6cbfa568ad31f92028ddc3345f792`.
Only the rebuilt DLL and ToPBR client driver were imported, each with `inputs.py --file`; every
other indexed fixes input is retained. [Corresponding source and rebuild tests](licenses/oversized-skinning/autopbr/Source.md)
are nested in the existing bundled source tree. Vanilla ToPBR stays opt-in; imported game maps
have an independent default-on setting. R11-B retains successful game materials by live hotloader
texture identity when their source is unavailable, with complete DDS validation and persistent
record-version policy ([ADR 0093](../../docs/decisions/0093-cached-imported-game-materials.md)).
The second review restores once-per-worker texture resolution and keeps USD publication ownership
across restarts, retaining backups for foreign/edited files and missing/damaged ownership records.
Runtime patch 0020 supplies absolute authored-pack precedence
([ADR 0092](../../docs/decisions/0092-generated-fallback-mods-rank-last.md)).
