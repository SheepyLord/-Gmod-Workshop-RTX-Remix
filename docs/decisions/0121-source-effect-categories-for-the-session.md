# 0121: Observe Source effect materials and categorize their textures for this session

- Status: Accepted 2026-11-06
- Decided by: Codex under the user's autonomous R20-D brief (item 44)
- Builds on: [0081](0081-mmd-alpha-texture-category.md)'s transient categories

## Decision

The companion observes the standard emitter Add, particle SetMaterial, sprite/beam draw and
decal APIs, and inspects materials already present in the native draw tracker. Add-ons need
no registration and keep their own material, particle and mesh objects. The observer requires
the local RTX guard's session proof; server and RTX-off starts install nothing.

Publish three NoSave runtime options under `rtx.gmod`: `particleTexturesForSession`,
`decalTexturesForSession` and `legacyEffectTexturesForSession`. Particle and decal tags join
the saved categories. The third list preserves effect meshes' vertex color and texture factors
without assuming they are billboards or applying decal geometry offsets. Decal metadata
(`$decal`, DecalModulate) wins over automatic particle inference for a material. UnlitGeneric
materials with vertex color, vertex alpha and translucent/additive blending qualify for the
color-only list; Sprite and Spritecard qualify as particles. Shared white, error and framebuffer
textures are excluded to avoid changing unrelated draws that use those textures.

Only hashes already reported for a real draw authorize a material lookup. No library preloads,
VMT reads, material mutation, persistent option writes or source-name exceptions are added.
Discovery and lookups each process at most twelve entries per frame, retain at most 4,096
candidate/effect names, refresh resolved hashes every two seconds, retry unresolved hashes and
remove unobserved entries after 120 seconds. Publications are sorted, deduplicated, limited to
four per second, and failed writes back off to sixty seconds per option. Non-effect materials
leave the retained list after inspection.

The runtime joins categories on D3D9 and external submissions, preserves vertex color and
texture-factor operations before material translation, and invalidates preserved draws on
category changes. Saved categories and explicit material replacements keep their existing
behavior. No RTX configuration file is rewritten.

## Consequences and limits

The engine particle/decal routes used by R20-C inherit this behavior automatically. A newly
drawn material can need a few frames before the native tracker has a hash. Texture categories
apply to every draw sharing that hash; they are not per-particle material overrides. Unknown
custom shaders, arbitrary destination-dependent blend equations and raster-only shader features
remain outside a general path-tracing equivalence guarantee. Color-only meshes retain ordinary
geometry and therefore do not get the particle renderer's billboard approximation. No global
alpha cutoff, lighting or reconstruction setting changes.
