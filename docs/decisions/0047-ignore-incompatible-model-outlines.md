# 0047: Ignore incompatible model outline meshes

- Status: Accepted 2026-10-30
- Decided by: the user's request 4, which explicitly permits removing or ignoring outlines

## Context

An inverted outline shell can surround the visible model and block its lighting even when its
outward faces are correctly culled. Ganyu also has a second skin whose dedicated black hei
material exposes an outline shell. Suppressing only the shell's direct shadow leaves other
rendering paths dependent on its geometry.

## Decision

Hide incompatible outline meshes from rendering by default, with a translated RTX-tab opt-out.
The runtime handles opaque front-culled model shells, excluding particles, beams, hair cards,
sky, terrain, world UI and decals. The companion recognizes explicit outline material names and
the dedicated hei/touming slots of the supplied MMD template family, including skin, submaterial
and private local-body proxy bindings. It tracks late texture hashes and excludes any image
shared with an ordinary loaded-model material.

The companion writes only its own NoSave runtime options. These invalidate preserved draw
translation when changed. Its hash list joins the existing Hidden category without replacing
the user's list. Hidden instances remain available for captures but have no ray-tracing mask;
their primary geometry, shadows and reflections cannot cover or darken the model. No original
material or entity override is edited. Disabling the control restores ordinary rendering.

## Consequences

The incompatible outline silhouette is omitted, as authorized. Other materials retain their
normal rendering and shadows. This does not infer that every black material is an outline.
Native lifetime tests verify transient option routing; Lua tests cover shared images, late
hashes, skin/submaterial/proxy bindings, toggles, missing APIs and retries. GPU acceptance
includes Ganyu's actual alternate skin and a stock-model outline fixture.
