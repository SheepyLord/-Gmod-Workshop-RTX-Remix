# 0097: Persistent manual eye-white choices for spawned characters

- Status: Implemented for R12-D; integration belongs to Claude
- Decided by: the user's item 38 in the [R12 plan](../handover/R12-plan.md)

## Context

[ADR 0088](0088-imported-character-eye-whites.md) deliberately leaves unnamed or combined surfaces
unclassified. The player needs to select a separate white surface even when its name is ambiguous,
and to exclude a false positive. R12-C is investigating VRAM, so a material library scan must not
instantiate textures belonging to unused characters.

## Decision

Put **Choose eye-white materials** beside the existing brightness control. Its client window targets
the looked-at character, or offers a list of spawned characters. Each row has a texture thumbnail,
native name, automatic/manual status, an eye-white checkbox and a return-to-automatic button. A
choice applies live to every instance of that asset through the unchanged proxy/alias/brightness
path. An explicit boolean overrides name detection in both directions; removing the value restores
automatic detection. Global disablement and real PBR replacements retain their existing behavior.

Keep choices in client DATA `nativeloader/eye_white_choices.json`, schema 1: full content asset ID →
slot/native material name → boolean. Full content identity prevents a truncated path-prefix collision;
the slot disambiguates duplicate material names. These keys survive maps, restarts and a re-import
of the same asset from another source folder, independently of generated VMT naming/version changes.
A changed PMX has a different asset identity and deliberately receives separate choices.

Bound the file at 1 MiB and 4,096 explicit choices. Reject malformed, oversized or unknown-version
data without replacing it. Check existence separately from size: the tested game reports 0 for a
missing file, which must remain a writable empty state. Before a write compare existing bytes to the loaded baseline; reject an
external edit rather than destroying it. Verify written bytes before changing live selection. A bad
file blocks saving and displays a translated explanation; it does not prevent automatic detection.

Only use metadata already in `mmdhl.assets` for entities from `mmdhl.Entities()` and `GetAsset()`.
Exclude editor previews. Do not request/import assets or inspect unused library materials. Validate
the full asset, its generated `mmd/<first 16 hex>/<part>` VMT and real `mmd/t/<hex>` VTF before saving.
The existing validated RGBA8888 proxy encoder and allocation limits remain authoritative for binding.
Only 24 rows are populated per page, four per frame, and thumbnails reuse original textures. On the
next sweep, removing the last spawned instance restores bindings and removes aliases, retaining
saved choices. Immediate manual unmarking also restores owned public/soft bindings.

All implementation stays in the existing trusted controller so no render-guard permission grows.
No runtime, native ABI, package input, asset manifest, network message or Remix config file changes.
The button is the menu's only change; the template and six catalogs gain additive translations.

## Alternatives

- Broadening ambiguous names such as `bai` would alter other models without evidence of their geometry.
- A global texture-hash choice would brighten other materials sharing an atlas, unlike a per-surface
  choice. Hash-scoped PBR overrides belong to the separate R12-B task.
- Source paths or display names would break on moved folders and collide across different characters.
- Eager library thumbnails would allocate textures for characters nobody spawned.

## Evidence

[R12-D report](../handover/R12-D-report.md) records the Release suite, Lua lifecycle/UI fixtures and
PoC screenshots, including the actual material missed by name detection and restoration receipts.
