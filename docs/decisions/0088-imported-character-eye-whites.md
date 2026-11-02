# 0088: Isolated texture identities for imported eye-white surfaces

- Status: Implemented 2026-11-02 for R10-E; Claude reviews and imports the runtime
- Decided by: the user's [R10-E request](../handover/R10-E-eye-whites.md), implementation by Codex

## Context

Most named eye whites share an atlas with skin, mouth, lashes and brows. A texture-hash emission
category would brighten those surfaces too. C-16 works for authored PBR materials; plain imported
materials have no adaptive input. The correction must identify surfaces, preserve painted shading
and existing packs, and provide an archived live brightness control. See the
[research](../RESEARCH.md#r10-e-imported-eye-white-surfaces-2026-11-02).

## Decision

Match native and available English material names, restricted to loaded Model Hotloader public
materials backed by real generated `mmd/t/` textures. Recognize 白目, 白眼, 眼白, 目白 and explicit
sclera/shirome/eye-white spellings, prefixes, sides, numbered and expression variants. Shadow,
highlight, lashes, liner, brows, blindfold, cornea and dark rim names override a positive translation.
Corpus UV inspection admits exact `eyeball` and painted `目白底` backing, but excludes `目白框`,
`目白边`, `eye_back` and `眼角膜`. Unnamed/combined eye-face meshes remain unchanged.

Give only the selected IMaterial a separate **texture identity**. Clone its generated RGBA8888 VTF,
toggling one RGB low bit in the top mip, preferably under a transparent corner texel. Preserve alpha,
every other texel, lower mips, sampler, UVs and material parameters. Cache by the clone's SHA-256 in
owned DATA storage; never overwrite differing existing bytes. Unsupported layouts and excessive
sizes fail closed. Eligible parts sharing one atlas reuse one clone; no hotloader hook is needed.

Immutable original and proxy helpers are warmed on separate frames in a tiny offscreen 2D target,
allowing Source's queued texture tracker to settle and RemixMaterial to discover both hashes. Before rebinding a world
material, successfully write the **NoSave** `rtx.gmod.eyeWhiteAliases` registry (`proxy=original`
pairs). Runtime patch 0019 validates the bounded, non-chaining map: malformed, duplicate, zero, self
or chained aliases fail closed. Registry changes invalidate preserved draw translation. The shared
original atlas is never a key. The companion's existing exact bundled render-guard path list gains
the controller and its two pure modules, without a wildcard or permissions for other add-ons.

D3D9 and external/CS submissions inherit the original atlas's texture categories (especially MMD
alpha and generated normals). Each thread/owner uses a revisioned alias snapshot, copied under the
existing option update mutex; stable draws take no per-lookup lock and never read a mutating live map.

Material resolution keeps explicit overrides first, then looks for a mod material using the original
atlas hash. A replacement follows the existing copy/merge path with no second emission. Only an
aliased draw without a replacement gets its own albedo as emission, neutral white tint and adaptive
intensity **0.625**, through C-16's existing luminance/packing/shader path. This is `.025/.6*15`,
verified against Robin's published map (0.627605 measured after DDS/sRGB quantization). Fixed fallback
is zero, so disabling adaptation cannot introduce a fixed night glow. Other material properties stay
as supplied by legacy conversion.

The menu beside Model outlines adds:

| Archived player setting | Default | Behavior |
|---|---:|---|
| `nativeloader_eye_whites` | 1 | “Steady eye whites for imported characters”: automatic fallback; disabling restores owned original bindings |
| `nativeloader_eye_white_brightness` | 100 | “Eye-white brightness”: 0–200 percent, live scaling of automatic and C-16 authored eye emission |

The controller writes `rtx.gmod.automaticEyeWhites` and `rtx.gmod.eyeWhiteBrightness`, both NoSave.
Brightness multiplies C-16's scale/luminance once, preserving saved `rtx.adaptiveEmission.scale`.
Zero removes adaptive emission; diffuse/reflected light continues. Existing packs combine sclera,
iris and catchlights in one adaptive map, so their adaptive eye emission scales together. The
checkbox leaves authored pack emission enabled. English and the six companion catalogs translate
both controls and help.

The multiplier affects every positive adaptive input; current C-16 character packs use those inputs
for their combined eye emission maps. Fixed emitters remain unchanged.

## Lifecycle and costs

Generated soft-triangle copies are covered too: accept only the same asset/slot's
`mmdhl_soft_v<version>_<64 hex asset>_<slot>` material, share the eye alias, and restore owned bindings.
Other parts' copies, foreign names and user edits remain untouched; late/inherited copies are retried.

Discover at most 128 slots and service eight names per frame; prepare at most one atlas per second,
bounded at 128 MiB per atlas and 256 MiB per session (a 4096² RGBA atlas with mips needs about 85 MiB).
Reuse textures across instances/players. Publish
at most ten times per second; retry refused writes. Restore only a binding still equal to the owned
proxy's normalized texture name, preserving subsequent user edits and entity/submaterial overrides. Lua
ITexture wrappers need not compare equal for the same native texture. Removing an asset restores
its binding and drops its registry entries. Owned cached images remain reusable across sessions.

Discovery is client-local, including other players' loaded assets. No network message, native ABI,
asset manifest, trust rule, shader variant or GPU record grows. Older runtimes refusing the new
option receive no texture changes. Preparation has a one-time CPU/file-I/O cost and duplicates the
atlas allocation; status reports bytes and maximum preparation time. Steady rendering adds no
character draw. The helper draws only while resolving an identity.

## Alternatives

- A shared-atlas category cannot distinguish white geometry from skin, including coincident UVs.
- A UV mask requires mesh/morph UV extraction, conservative rasterization, padding and mip rules;
  overlapping UVs still cannot isolate both. Surface identity avoids those filtering leaks.
- A custom per-draw native marker needs the hotloader's native ABI or Source shader implementation
  outside this task's permitted hooks. Existing public materials/APIs suffice. A future incompatible
  hotloader fails closed instead of mutating unknown materials.

## Delivery

Keep patch 0019 and its runtime tests here. Build with `runtime/build_runtime.ps1 -NoImport` and test
a local combined package. Leave `packages/runtime` and `runtime/base.json` unchanged for Claude's
reviewed import. The existing packaged-runtime provenance check consequently reports the intentional
source/import mismatch until integration; do not bypass it or fabricate a packaged record. The
[R10-E report](../handover/R10-E-report.md) records actual gates, PoC measurements and DLL identity.
