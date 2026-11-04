# R15 report: painted shadows, solid hair, and the release candidate

The user's items (2026-11-04), in the [plan](R15-plan.md): 43, hide 目影 in imported models
automatically, more robustly; 44, better handling of materials with alpha, with Laevatain's hair as the
example ("I removed Alphatest to make it look correct ... You are allowed to switch away from Alphatest
if needed"); then the most recent loader release, as the release candidate.

Claude did the work in the main session on `r15`; Codex only translated (R14's rule for this session).
Decision: [ADR 0104](../decisions/0104-painted-shadows-and-solid-hair.md).

## What changed

**Painted shadows** (item 43). [`painted_shadows.lua`](../../companion/nativeloader/lua/nativeloader/painted_shadows.lua.md)
finds them by name and by their properties; [`nativeloader_imported_parts.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader_imported_parts.lua.md)
leaves them out of the draw in RTX sessions through a new, `pcall`-guarded hook in the Model Hotloader's
`mmdhl.SyncMaterialState` (`mmdhl.RenderHiddenParts`). Bodygroups, saves, dupes and files do not change.
Rendering > Model outlines: **Hide painted shadows**, on by default.

**Solid hair** (item 44). [`solid_hair.lua`](../../companion/nativeloader/lua/nativeloader/solid_hair.lua.md)
samples a hair part's texture alpha (a few rows per frame). When the texture is mostly opaque but the
0.5 alpha test cuts holes into it, the part's material loses `$alphatest` and its soft copy loses
`$translucent`, in memory: the user's own fix, put back when the setting is off. Rendering > Model
outlines: **Solid hair**, on by default.

<!-- PoC results, field check and release to follow -->
