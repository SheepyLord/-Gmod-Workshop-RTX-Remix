# 0053: Scoped hardware skinning for oversized groups

- Status: Accepted
- Decided by: the user's item 24 request and the tested scoped native implementation

## Context

Workshop 3830665593's Airi(InuinuBone) player and NPC clothing-fur group contains 40,509 valid,
weighted vertices. The engine's `R_StudioDrawDynamicMesh` warns and returns zero for software
groups at or above 32,768 vertices. The same models also have oversized hair and shoe groups.
All four have compiled hardware-skinning data and no mesh flexes. Their counts, weights, bone
references and MDL/VVD/VTX checksums are valid. The later 62,049-vertex fatal exposed the direct
hardware helper's own software fallback, which lacks the dynamic entry's capacity precheck.
The dynamic-only 0d4 and static-only 034 prototypes are superseded: the latter also left smaller
body meshes invisible under existing user-forced hardware skinning. See
[RESEARCH.md](../RESEARCH.md#oversized-airi-skinning-groups-item-24).

Suppressing the warning would preserve the failed draw. Treating the mesh as unskinned would lose
its weighted deformation. Global skinning changes could alter unrelated or flex-dependent models.
The existing GPL native RTX fixes module provides the draw wrappers for a per-group correction
without changing the engine's software buffer limit.

## Decision

Automatically protect an oversized group only when its compiled hardware data is known and
eligible. Keep the 32,768 boundary tied to the stripgroup's draw vertex count, not the total
model's vertex count. Cover both dynamic and direct hardware entries with the same borrowed-state
scope. Preserve all nine arguments on re-entry and use a thread-local same-group marker to avoid
wrapping twice. Unknown oversized static-fallback config38 bit 0x08 fails closed rather than
entering an unsafe software fallback. Do not blanket-suppress the engine's warning.

The same scope also preserves smaller, non-flex, multi-bone groups already selected by the user's
hardware mode, inside RenderFinal and under the legacy r_hwskin_setbones predicate (mode 1 or
matching bone count). This avoids CPU fallback or double transformation from simultaneous CPU
posing and native indexed bone upload. Ordinary force0 groups, rigid single-bone props, flex/eye
behavior and explicit small-model diagnostic selection retain their paths. No global cvar flips.

At hardware-group creation, certify that every strip's own bone-state assignments cover all
hardware slots it uses. At drawing, require the runtime strip-data fingerprint to match that
certificate. Unknown/changed data and stale palette caches cannot approve an automatic oversized
draw. Complete certificates apply only to oversized groups; smaller user-forced groups retain
their existing remap/cache fallback behavior. Certified oversized groups must upload required
bones despite a zero/mismatched diagnostic filter, without changing the stored filter value.

Retain weighted bone deformation and the compiled strips' palette remaps. Bone upload and affected
rendering state are scoped to the draw and restored with __finally, including config, material,
group and bookkeeping state. A DrawIndexedPrimitive-scoped D3DCOLOR-to-UBYTE4 declaration conversion
preserves bone-index ordering when needed, with a bounded 16-entry cache retaining both COM
references until shutdown. The original declaration and borrowed palette/blend states are restored.

Make the correction in the GPL fixes source and ship it through the normal indexed package input
process with source/licence provenance. Do not copy GPL implementation into the MIT loader, patch
Steam files on disk, modify the user's models/materials, flip global skinning cvars or change
Remix `user.conf`. Native allowlists, path rules, off switches and multiplayer/debug permissions
remain unchanged.

## Consequences

Valid oversized hardware groups can avoid the software path's size rejection while preserving
their animation. Unsupported software-only or flex-dependent geometry may still need an asset
or another scoped rendering solution; this decision does not claim to fix every large model.
The fur's single strip and hair's three palette strips require separate regression coverage.
Normal face-flex rendering and subsequent unrelated draws are essential controls for state leaks.

## Validation and completion

Read-only archive/model validation and matching-engine inspection establish the failing boundary
and valid hardware data. Native local commit `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe` produces
the tested DLL, SHA-256 `5e626e34f412cd55e93a485cd1d777794b339a0cb7a5082935454b72fbc72db7`.
Corresponding source, licence, pins, generated projects and patches ship under the short add-on
path `remixbinary/src/hw` to stay within Windows staging limits.

The final standalone GPL policy CTest passes in Release with /UNDEBUG, including user-mode and
unsupported-mode cases. Final Release passes 20 CTests/277 Python tests (7 skips). Baseline PM
reproduces four warnings at force0/softwareskin1. The 357
preview passes force1 PM skins 0/8, body/hair/boots and arms visibility with no fatal and exit zero.
Final 5e626e34 passes cold default NPC skins 0/8 plus arms. Its actual final GMA also passes
force1 PM skins 0/8 with full body/arms visible, no errors and exit zero. Reviewed GMA
`0.0.0-dev.20261031090406+335c6f09` matches final DLL/source, 998 files/1,837,514,493 bytes,
28 changes/no removals,
payload digest `13f303982ed43e47bccf09847186bd3bb43477cb65dbbcb1c5534117cbae4ba3`.

Final client 18232 passes secure dedicated server 37728 with the final DLL: full Airi rendering,
first-person hands, cslua/cheats off, no insecure, renderer apply/restore and unsafe-command denials.
The Workshop update completed and its archive matches every tested payload file.
[TESTING.md](../TESTING.md#oversized-hardware-skinning-item-24)
records the acceptance protocol and controlled results.

## Alternatives considered

- Hiding the warning leaves the rejected geometry undrawn.
- Raising or bypassing the software count check without a proven buffer/index solution is not a
  rendering fix and could exceed the path's internal limits.
- Disabling skinning loses valid weighted deformation.
- Flipping a global hardware/software cvar changes unrelated models and flex behavior.
- Splitting or re-exporting the user's Workshop asset changes third-party content and is not the
  scoped native correction being investigated.
