# 0081: MMD alpha as a scoped texture category

- Status: Accepted 2026-11-01
- Decided by: the user's R7-A request and [implementation brief](../handover/R7-A-mmd-alpha.md)

## Context

Columbina's mask has white lattice bars at alpha 166/255 and panes at 66/255. Source's DX7
alpha test ignores the VMT's reference, while Remix's classic 0.79 stochastic threshold lets the
blended bars cast shadows without appearing in the primary surface. The project manager's
0.5-threshold experiment restores them, but a global change would also change map glass.

## Decision

Add saved `rtx.mmdAlphaTextures` and default-0.5 `rtx.mmdAlphaCutoff`. The companion registers
loaded Model Hotloader character base-texture hashes in the separate NoSave
`rtx.gmod.mmdAlphaTexturesForSession`; the runtime joins both sets on D3D9, preserved-draw and
external submissions. Both lists and the cutoff invalidate preserved draw translation.

For categorized draws using legacy alpha state, replace the alpha-test reference with the
cutoff, preserving the comparison operation. Promote final blended opacity at or above the
cutoff to 1, after vertex/texture alpha operations and blend inversion, before lighting and ray
classification. Lower opacities retain the existing blend/stochastic behavior. Replacement
materials with authored alpha and explicit forced cutout/hair categories retain precedence.

The per-surface cutoff has 1/2048 resolution, including exact 0.5, and occupies unused surface
bits without growing the GPU record. The shared opacity evaluator serves primary, visibility,
PSR and indirect paths and micromap baking. Its enabled bit and cutoff are included in micromap
identity; categorized micromaps always evaluate the required vertex/texture operations. Category
or cutoff changes also invalidate accumulated material history. Whole blended/cutout meshes
remain nonopaque, preserving [ADR 0048](0048-layered-alpha-cutouts.md)'s candidate rejection and
cached/shared BLAS flag rules.

The companion accepts only loaded generated character material names backed by real `mmd/`
textures. It retries late mounts/uploads, refreshes hash revisions, releases removed assets,
and bounds lookups and publication. It writes no materials or persistent Remix options. No new
translated opt-out is needed for this scoped correctness fix. The hotloader's existing soft
triangle pass remains useful for opacity below 0.5 and needs no code change for this fix.

## Consequences

The lattice becomes an opaque lit surface with matching visibility, while panes below the
cutoff remain soft. Other textures keep the classic thresholds. Identical texture hashes shared
by another draw inherit the category too: this is a texture rule, not a material-name shader
override. Source's non-RTX rendering and the imported hotloader are unchanged. The rebuilt DLL
must be imported and checked in game by Claude; the R7-A worktree does not deploy or publish it.

## Alternatives considered

- Lower the global stochastic threshold: changes unrelated map/prop materials.
- Change only primary-ray threshold classification: leaves shadows, indirect throughput and
  micromap classifications inconsistent.
- Force all MMD draws to cutouts: discards useful soft coverage below 0.5.
- Remove the hotloader soft pass: returns to the alpha test alone and loses sheer detail.
