# R12-B3: imported game PBR keeps converting (the user's critical bug)

A fix after R12. Codex in `out/worktrees/r12-pbr` (`r12-pbr`, now at `main`) and
`out/worktrees/r12-fixes` (fixes `codex/r12-pbr`, at the shipped `026708a`). Rules:
[R12-plan.md](R12-plan.md). ADR: **0098** (new; it amends the bounded ToPBR of
[0091](../decisions/0091-automatic-pbr-fallbacks.md) and [0095](../decisions/0095-texture-features-and-imported-pbr-overrides.md)).

## The user's words (2026-11-03, in the session "Case Resolve", verbatim)

> No, send to main session and let main fix it. This is a critical bug and needs to be addressed now.
>
> * Raise or lift the 1 GiB limit for imported game maps, and log a clear "budget used up" message instead of the generic failure.
> * Store roughness, metallic and AO more compactly than full colour maps. That would also cut disk use and the 4.1–4.6 GB of replacement textures in VRAM seen in the R12 field check.
> * After a version change, keep converted maps whose inputs haven't changed instead of converting every character again.

## The bug

The session "Case Resolve" found it; its notes are in the main checkout's
`out/r12/rossina/FINDINGS.md`. The field game was not changed and its console log was not read.

- **The limit.** `TextureProcessor::WriteTextureToDDS` (fixes `source/material_pipeline/to_pbr/to_pbr.cpp:477-588`)
  refuses any write once `m_generatedDDSBytes` would pass 1 GiB. The counter (`to_pbr.h:655`) is only
  ever increased (`:581`); it resets only when the module reloads at a game restart.
- **In the field.** Game PID 4120 wrote 56 maps (1,068,156,512 bytes) by 22:20:05 local.
  `game_991AF3B052DC62B2` stopped after its metallic map. Every later conversion failed with
  "DDS publication failed". 洛茜 got none of her maps: `E:\G\Upload\Rossina_rc\洛茜\洛茜.pmx`, asset
  `ffba9981377a62fe…`, families `T_actor_wulfa_*`.
- **Why it filled so early.** Generator 7 (R12-B2) changed every content key, so every game
  character drawn converted again. Every map is uncompressed RGBA8 with mips, 22.4 MB at 2048², so
  1 GiB is about ten families; 洛茜 alone needs about 358 MB.

Claude's further findings in the shipped source:

- **AO is never used.** `game_pbr.h:288` writes `_ao.dds`, but the registry keeps only normal,
  roughness, metallic and emission (the `convert` lambda in `to_pbr.cpp`), and `usda.cpp` has no AO
  input.
- **Roughness and metallic are single-channel data.** They are one value copied into R, G and B
  (`game_pbr.h:269-271`). The normal map is octahedral, in two channels (`usda.cpp:323`,
  `encoding = 0`).
- **One salt for everything.** The content key's salt (`game_pbr.h:229`, `…4507`) and the marker
  `r12-game-v7` (`:236`, `:291`) tie every cached output to one global version.
- **Validation is one layout.** `Policy::ValidDDS` (`pbr_policy.h:39-54`) accepts only the legacy
  32-bit uncompressed layout with a full mip chain, and `GameRegistry::Inspect`/`ValidRecord` rely on it.

## What to do

1. **No 1 GiB stop for imported game maps.** They stop counting against the per-session budget. They
   stay bounded by the registry's limits, the per-image bounds and the existing free-space check,
   with its headroom. Use a much larger cap only if you find a real risk; the opt-in world ToPBR keeps
   a budget. Every refusal logs one clear line naming the limit and its numbers: the session budget,
   free disk space or image bounds. The Imported game PBR panel shows that line, not "DDS publication
   failed". A family stopped halfway, such as `game_991AF3B052DC62B2`, completes on its next pass.
2. **Compact maps.**
   - Formats: roughness and metallic in BC4 (DXGI `BC4_UNORM`, DX10 header); the octahedral normal in
     BC5 (`BC5_UNORM`). Keep full mip chains.
   - Stop writing AO.
   - Emission is rare: measure it, and keep it uncompressed unless a compact format is visibly safe.
   - Encoder: write the BC4/BC5 encoder in the fixes, with no new dependency. An SDK-free test proves
     its error bounds on generated gradients and edges and on real maps.
   - Validation: `ValidDDS`, `Inspect` and `ValidRecord` accept the new DX10 layouts and still accept
     the legacy RGBA8 one, so existing records stay valid.
   - The opt-in world ToPBR may use the same writer for the same kinds of map if its tests pass;
     otherwise leave it.
3. **Reuse across versions.**
   - Key: a version change must not convert again maps whose inputs and conversion are unchanged.
     Key the content on what changes the bytes: base, PMX, maps with their roles, layout, the
     conversion parameters actually used, and the output format. Matching and pairing changes are not
     part of the key.
   - Marker: record the recipe in the completion marker.
   - The format change in this fix: transcode finished outputs (RGBA8 to BC4/BC5) instead of
     converting again from sources. This covers R11-B's records for characters whose source folder is
     gone too, and their registry entries (file, size, digest) are updated atomically.
   - Exception: a v5/v6 output where a packed or normal map was resized was made by the WIC
     premultiplied decode that R12-B2 fixed. Convert it again when its source is readable; with no
     source, keep the old maps.

## Acceptance

- **Native regressions:**
  - A session that writes more than 1 GiB of game maps never stops converting.
  - A forced refusal (budget, disk, bounds) gives the clear message and the panel error.
  - The BC4/BC5 error bounds hold.
  - `ValidDDS` and `Inspect` accept the new layouts and still accept legacy RGBA8.
  - An unrelated version bump converts nothing.
  - The format migration only transcodes, with the source hidden, and updates the registry.
  - A resized-map v6 output with its source present converts again.
- **Sizes:** bytes per family for a 2048² family, before and after.
- **PoC:**
  - Characters: read-only copies of 洛茜, 阿芙2.0 (`out/r12-b/source/Alf2`) and endminf under your
    `out/`.
  - Conversion: all three convert. Roughness, metallic and normal render in Remix with no texture
    load errors in this session's Remix log; take screenshots.
  - Migration: pre-existing RGBA8 outputs migrate.
  - Memory: replacement-texture VRAM for the same characters, before and after.
  - Restore the PoC exactly.
- **Delivery:** one DLL import; the GPL source copy refreshed; `tools\test.ps1 -Config Release`
  passes; commits on both branches. Never push, merge or publish.
- **Docs:**
  - ADR 0098.
  - CHANGELOG under `### R12`.
  - RESEARCH: the field facts and the sizes.
  - TESTING.
  - A "Follow-up: R12-B3" section in [R12-B-report.md](R12-B-report.md).
  - Commit this brief as it is.
