# R13-M report: compact imported game maps, reuse across versions

Status: **done locally** on `r13-maps` and fixes `claude/r13-maps`; nothing pushed, merged or published.
Brief: [R12-B3](R12-B3-game-maps-budget-formats-reuse.md) items 2 and 3 and the item-1 remainders, as
the [R13 plan](R13-plan.md) assigns them. Decision: [ADR 0098](../decisions/0098-compact-imported-game-maps-and-recipe-keys.md).
Evidence is under this worktree's `out/r13-m/` (paths below are relative to it).

## What changed and why

**Codex's unfinished work** (`codex/r12-b3-wip`, `44559f4`) was read, not merged. It was based on the
shipped `026708a` rather than the hotfix and had never compiled: one test called `Policy::ValidMakeDDS`,
a rename slip. Its direction was right and is kept (DX10 BC4/BC5, no AO, transcoding finished
outputs, registry and override migration). Its details were rewritten:

- Its uncompressed writer generated mips differently from the shipped one, so transcoded and fresh
  families could differ.
- v5 families were keyed without a guard for their missing layout.
- The writer chose formats from file-name suffixes.
- The resize check reopened files through WIC on every pass.
- Its encoder's refinements had no error bound.

Fixes commit `913bb6b` (`claude/r13-maps`, from the hotfix `26aec12`):

- **Compact maps** (`dds_codec.h`, standard C++ only). The octahedral normal is stored as BC5 (Remix
  reads `.xy`), roughness and metallic as BC4 (Remix reads `.x`), with DX10 headers and full mip
  chains. Emission stays uncompressed, and the AO map, which nothing reads, is no longer written. A
  base whose sides are not multiples of four keeps the uncompressed layout. The encoder puts a
  block's endpoints at its extremes, which bounds every texel's error by (max - min) / 14. Two
  least-squares refinements, the exact-0/255 mode and, for blocks of at most four levels,
  palette-aligned endpoints may replace them only with a lower squared error and no worse texel.
  The arithmetic is integer, so the bytes are deterministic.
- **Validation.** `ValidDDS`, `Inspect` and `ValidRecord` accept the DX10 layouts. The uncompressed
  rule is unchanged, so every existing record stays valid. Records now also check each role's format.
- **Publication and refusals** (`dds_publish.h`). Imported game maps publish through a flushed,
  validated staging file and a write-through replace; an invalid file in the way is kept as
  `.rejected-<tick>`. They have no session budget. Each refusal throws one line naming its limit and
  numbers, which the worker logs ("Game maps skipped: <base> (<line>)") and the Imported game PBR
  panel shows, in state `error`, for every material sharing that texture. The world conversion keeps
  its 1 GiB budget and its uncompressed writer, and logs the same lines once per session.
- **Reuse across versions.** `GamePBR::Recipe()` lists what changes the bytes: decoding, masks, the
  class tables (printed from the values in use), channel rules, octahedral encoding, mips, formats
  and the encoder. The content key hashes the PMX, the base's bytes and name, each map role with
  its bytes, the layout and the recipe. The generator number (now 8) is provenance only. The
  completion marker records the recipe and the family's origin.
- **Migration with the source present.** A missing current family is re-encoded from a finished
  earlier family with the same inputs (the v7, v6 and v5 keys, each by its shipped formula) instead
  of converted again. Exceptions convert from the source:
  - a v5/v6 family whose normal, packed or emission map was resized, since it came from WIC's
    premultiplying decode;
  - a v5 family for a manual choice, or for an Endfield/WuWa family in a folder holding a `*_MRA` map
    (v5 keys carry neither roles nor layout, and v5 chose Silver there).
- **Migration without the source.** `Registry::Compact` re-encodes a stored record beside the
  originals (`<name>_bc5.dds` / `_bc4.dds`), validates the new files and saves the registry
  atomically. `GameOverrides::Store::Compact` does the same for a manual choice through `Set`. A
  failed save keeps the previous record, which is still valid.
- **Item 1's remainders.** The panel shows the refusal line instead of "DDS publication failed". A
  map already stored in its format survives an interrupted pass, so a family stopped halfway
  completes on its next pass.

The loader side (this branch):

- One import of the DLL into `packages/fixes`.
- The GPL source copy refreshed: 35 files reconstruct from `7094baf` after CRLF normalization.
- `tools/tests/test_topbr_registry.py` builds and runs the new SDK-free test from that copy,
  including a second build with another generator number.
- The panel harness checks that a refusal reaches the status text.
- ADR 0098, CHANGELOG `### R13`, RESEARCH and TESTING.

## Measured sizes

| 2048x2048, full mip chain | Bytes |
|---|---:|
| Uncompressed map (before) | 22,369,748 |
| BC5 normal | 5,592,580 |
| BC4 roughness or metallic | 2,796,364 |
| **Family on disk** (before: normal, roughness, metallic, AO) | **89,478,992 -> 11,185,308** |
| **Family Remix loads** (before: without AO) | **67,109,244 -> 11,185,308** |
| Emission map, when there is one (unchanged) | 22,369,748 |

Real maps (`probe-field-2.log`, production conversion of 洛茜, 阿芙2.0 and endminf; 12 families,
two with emission):

- Disk: 945,122,708 -> 145,408,760 bytes. What Remix loads: 732,609,912 -> 145,408,760.
- Every block stayed within its bound. RMS error in 8-bit units: normal 0.27-3.30, roughness
  0.12-1.20, metallic 0-1.18.
- Conversion with encoding took 0.44-2.90 s per family.
- Against the exhaustive optimum on sampled field blocks, normal maps are within about 12%; quantized
  roughness reaches the optimum (0.53 against 0.54). RESEARCH has the details.

## Native regressions

`native.ps1 -Bulk` (`native-bulk.log`) passes every SDK-free fixes regression:

- The existing game-channel, registry and matching tests, adapted to the new writer.
- `tests/game_dds_test.cpp`:
  - **A session that writes more than 1 GiB of game maps never stops:** 1,096,117,652 bytes in 49
    publications, none refused.
  - **A forced refusal** (disk, bounds, budget) gives the exact one-line message. It propagates out of
    a conversion mid-family, the maps written before it stay, and the next pass completes the rest.
  - **The BC4/BC5 error bound** holds on gradients, edges, anti-aliased masks, noise and real
    quantized roughness blocks; every two-valued block is exact.
  - **`ValidDDS` and `Inspect`** accept the DX10 layouts and still accept the uncompressed one; other
    DX10 variants (cube, array, BC1, unaligned, truncated) are refused.
  - **An unrelated version bump converts nothing:** a second build with
    `/DTOPBR_GAME_GENERATOR_VERSION=999` reuses the first build's maps (0 conversions, 0 writes).
  - **The format migration only transcodes, with the source hidden, and updates the registry:**
    3 maps transcoded, the registry rewritten atomically and reloaded with the new names, sizes and
    digests, the converter never called. A failed save keeps the previous record, and the next
    attempt reuses the compact files. Manual choices migrate the same way.
  - **A resized-map v6 output with its source present converts again**, while the same v7 output
    transcodes. v7/v6/v5 transcoding is byte-identical to a fresh conversion.

`probe-field-2.log` read the field's existing outputs only:

- For all 12 families, the shipped v7 key (and v5 for endminf) found the field's finished family.
- Every stored base level equals today's conversion of the same inputs.
- The new uncompressed writer reproduces those files byte for byte.

## PoC

Hold: lock taken 11:26:33 UTC (R13-A held it before; no field game was running, so none was
ended), released 11:42:21 UTC (`poc/hold`). The library and ToPBR cache were moved aside whole, so only
the three test characters loaded; the loader state, deployed files, bootstrap and `config.cfg` were
copied (2,424 files, 8.83 GB). Sessions: gm_flatgrass, 1280x720, high tier (the low tier skips
the top replacement mip), `-multirun`, no Workshop; each quit normally with exit 0, zero Lua errors
and no device loss. Source copies, verified identical to their originals: `source/Rossina`,
`source/Alf2` (R12-B's copy), `source/endminf` (`source-copies.json`).

| Phase | Fixes DLL | What happened |
|---|---|---|
| A | shipped `a6432a44` | Imported the three copies (assets `ffba9981…`, `f68499a5…`, `a9c7045d…`, as in the field), spawned them frozen; 12 families converted to the uncompressed layout (945,122,708 bytes, as the probe predicted). |
| B | candidate `447b9dde`, endminf's source hidden | 洛茜's 4 and 阿芙2.0's 5 families "transcoded from r12-game-v7"; endminf's 3 records "stored compactly without their source" and restored. No family converted from its source. |
| C | candidate, every source back | 洛茜 and 阿芙2.0 "cached (0 maps written)"; endminf re-encoded once from its v7 family under the current key (its source-less `_bc` copies remain). |

**Replacement-texture VRAM for the same characters** (Remix `usedMaterialTextureBytes`, before and
after spawning; `poc/hold/analysis.json`):

| | Before spawning | After | Their maps |
|---|---:|---:|---:|
| A, uncompressed (clean start) | 2,683,580,928 | 3,416,250,880 | **732,669,952** |
| B, compact | 3,389,395,456 | 3,529,297,408 | **139,901,952** |

Phase B's delta is the compact files new to that session (predicted 139,816,228; endminf's emission
keeps its already loaded file). Phase B started 705,814,528 bytes higher, and phase C 118,640,640
higher, than the clean start: see the finding below.

**Rendering.** Roughness, metallic and normal render in every session.

- Screenshots: `poc/sessions/{A,B,C}/shot-*.png`, seven per phase. Each phase has the final image,
  the roughness view (25), the shading-normal view (16) and the base-reflectivity view (94), and a
  close-up of each character.
- Remix's log for each session has no texture error or warning that mentions `~gmod_topbr`. The only
  flagged lines are its existing "suboptimal replacement texture" notes on the package's water,
  mirror and Emissives mods.
- 洛茜's 8192x8192 body texture shows the new line in both the log and its panel state: "image
  bounds exceeded: body.png is 8192x8192 (67108864 pixels); the limit is 4096x4096 and 16777216 pixels".
- Inside the characters, the debug views of A (uncompressed) and B (compact) differ less than those of
  B and C, which use identical compact maps:

  | Mean largest-channel difference | A against B | B against C (control) |
  |---|---:|---:|
  | Roughness | 8.5 | 14.6 |
  | Shading normal | 37.0 | 51.7 |
  | Base reflectivity | 1.17 | 1.68 |

  That is, separate spawns and camera jitter dominate, and the compression error (measured above in
  texture space) is below that floor. `poc/hold/interior-diff-*.json`, `debug-views-*-diff.png`.

**Restoration** (`poc/hold/restoration.json`):

- Every copied file is restored with its bytes and timestamp, and the journal is exact.
- The library and cache moved back with identical inventories; the test's are kept in `poc/hold/test`.
- 418 new files (package payloads, backups) are archived. The prior console was moved back unread,
  and `user.conf` is unchanged.
- The depot check reports 2,877 files OK and no missing or mismatched file. No PoC process remains.

## Finding for R13 (not changed here)

Game-map materials carry `preload_textures = 1` (`usda.cpp:350-357`, so generated normals do not stay
at their smallest mip). Remix therefore preloads every normal, roughness and metallic map that the
previous session published at the next start, before any character is drawn. It keeps them when
ToPBR replaces the USD and the characters use other files.

- In the PoC that was 705,814,528 bytes after the uncompressed run, and 118,640,640 after the compact
  one, held until the game exited.
- In the field it may explain part of the 4.13 GB of replacement textures with nothing spawned in
  the R12 field check (not measured here).
- After this change the cost is about a sixth. The first session after the update also preloads the
  old uncompressed maps once.
- Options:
  - ToPBR publishes a snapshot without game maps when the module unloads, so the next start preloads
    nothing.
  - The runtime (R13-B) releases replacement textures that no mod references after a USD reload.
  - Game maps drop the preload, and the smallest-mip problem is fixed another way.

## Tests

- Native: `native-bulk.log` (above).
- Loader-side ToPBR suites: the 4 tests pass in 11.6 s, including `test_compact_game_maps`.
- `tools/test.ps1 -Config Release` (`release-final.log`) passes: 26 CTests and 531 + 28 + 25 Python
  tests (two existing skips), "All checks passed."
- `inputs.py verify --deep`: 11 parts, 0 problems.
- The indexed combined package validates with this worktree's Release `nlctl` (`indexed-package.json`):
  version `0.0.0-dev.20261103114745+1bf609da`, 1,102 files, digest
  `c7c556506db45b9962e6d6a1750e11e64cbd1528d46248b75de346e003964b4c`.

## Not done, or for a decision

- **Superseded uncompressed files are not deleted.** The field cache is 4,567,891,854 bytes, of which
  886,402,452 are AO maps nothing reads. After migration the old families stay beside the compact
  ones until a collector exists. A collector would delete a family only when no registry record, no
  manual choice and no published USD references it. Deleting generated files is a new decision.
- **Emission stays uncompressed** (the brief's default). In the field, 17 of 58 families have an
  emission map, 308,982,548 bytes, and half of them light at most 1.1% of their texels. BC7 (or BC1)
  would need a visual check.
- **The opt-in world conversion** keeps its uncompressed writer. The same writer would fit its
  normal and roughness maps, but its formats were not reviewed here.
- **Downgrades are not supported.** An older module rejects the compact files and drops records
  whose source is gone.
- **Duplicates.** endminf's source-less `_bc` copies remain beside the current-key files once its
  source returns (phase C); they are small duplicates.
