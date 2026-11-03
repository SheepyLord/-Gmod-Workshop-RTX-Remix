# 0096: Draw-gated character classification and an opt-in memory census

- Status: accepted within the user's R12-C implementation brief, 2026-11-03
- Decided by: the user's item 40 and the constraints in [R12-C](../handover/R12-C-vram.md)

## Context

The field session's D3D9 app textures held roughly 13 GB. Existing VRAM telemetry identifies the
allocation category but cannot say which Source texture names or D3D9 formats/pools account for it.
Several helpers visit the entire imported-character library. A `Material` or native `FindMaterial`
lookup can make an unused character resident before the helper discovers that it was never drawn.

## Decision

GMod's saved NPC/player-model registration precaches managed textures whose GPU backing is never
sampled. Keep that model-readiness behavior, and defer the backing in the runtime instead. Patch
0022 enables `d3d9.deferManagedTextures` by default for `gmod.exe` only (case insensitive). The
config key or `DXVK_DEFER_MANAGED_TEXTURES` overrides that default. Deferral applies to static
2D `D3DPOOL_MANAGED` textures with no usage flags, shadow semantics or format conversion, and
only while `evictManagedOnUnlock` is off. Default-pool, shared, dynamic, render/depth targets,
automatic mipmaps, cubes, volumes and conversion formats retain the existing allocation path.

The original CPU buffers, description, dimensions, format, mips and LOD stay intact. Construction,
metadata/surface queries, CPU locks and `SetLOD` allocate no Vulkan image. The first sampling/view,
GPU upload or explicit `PreLoad` creates it. The existing zero-initialization logic is shared with
the normal initializer, but a deferred image's clear is queued on the same main command stream
before its first upload/use, preserving order without another queue submission. The texture hash
still comes from exactly the same CPU data and hash path. A hash query on an unbacked managed
texture returns the original empty-hash success result without creating an image.

Do not evict images merely because the Source sampler has not rebound them recently: Remix can
still sample cached surfaces and anti-culled geometry. Used images retain the existing lifetime,
including the application's release marker and renderer references; process exit releases all
of them. Source model-cache/CPU-buffer retention is a separate problem.

The MMD alpha classifier first reads the existing draw tracker's hashes for the exact public or
soft-copy material name. Only valid nonzero hashes permit a subsequent VMT/material/texture lookup
or tracking call. Missing hashes remain retryable, with the existing bounded lookup budget,
revision refresh and exponential retry. Keep the base-texture namespace/fallback validation and
the NoSave category. Never change image bytes, dimensions, mip levels or texture hashes to save
memory; authored replacements and saved categories keep their identities.

Add two local measurement instruments:

- A manually loaded, PoC-only native QA module reads `DebugTextureInfo001`'s loaded-texture list.
  It temporarily enables debug collection, then disables it. It never creates/finds/tracks a
  material. Preserve the raw fields and validate the Win64 Source ABI in the game before using
  the measurements. It is neither shipped nor added to a native allowlist.
- Runtime patch 0021 extends the existing opt-in memory profiler with D3D9 pool/format/mip metadata
  on primary and resolve images. `rtx.profiler.memory.requestSnapshot` is a resettable NoSave
  request, read on present, emitting grouped allocation records only when the profiler was enabled
  at launch (`RTX_PROFILER_MEMORY_ENABLE=1`). Group by category, resource type, locality/demotion,
  dimensions, Vulkan format, D3D9 pool/format/mips. Sizes are actual allocation slices, not logical
  image estimates. Rows outlive an application's texture release until the Vulkan image itself
  goes, so renderer-held images remain visible. Synchronize profiler metadata updates with its
  registry lock; copy the registry before grouping/logging and never wait on the GPU.

An offline reader rejects incomplete/mixed snapshots and whole-frame profiling (which includes
already released resources). Keep Source logical texture estimates distinct from DXVK allocation
slices and from the driver's allocations. Unavailable evidence remains unavailable.

Every experiment uses the shared exclusive PoC lock, restores its snapshot and checks field
activity immediately before launching with `-multirun`. Unknown process paths block launches.
Only current-session console bytes may be collected. Field library/Workshop files are read only.

## Consequences

Cold libraries no longer load through the alpha classifier. Materials actually drawn retain the
same classification after the next bounded poll. Their first drawn frame may precede registration,
as with the previous tracker/hash readiness path. A library metadata record alone is never a
reason to instantiate a texture. Source and the native fixes may still retain a texture after
it was used; do not claim that Lua garbage collection frees those native caches.

The default profiler remains disabled. Diagnostic collection adds CPU work only when enabled or
requested, and may produce many log rows; it is a manual investigative tool, not periodic player
telemetry. The field's settings, high-tier visual quality, hashes, native trust policy and
`user.conf` remain unchanged. Eye-white preparation and the automatic game-PBR queue belong to
other R12 tasks; their exact findings/proposals and measured contributions go in the
[R12-C report](../handover/R12-C-report.md).

Allocation work moves to first use, so new-character first-use latency needs game QA. The isolated
GPU host verifies zero GPU bytes for metadata/CPU operations, `PreLoad`, first-draw upload, exact
sampled mip pixels, zero initialization, partial writes, unchanged original/new hashes and the
excluded resource classes. It compares the original binary, new eager control and deferred mode.
An existing common-device-object teardown warning appears in the original host control too;
successful assertions do not claim that unrelated runtime diagnostic is fixed.

## Alternatives considered

- Compress/downsample existing base VTFs: changes captured hashes and may break replacements;
  outside this change's visual/identity guarantees.
- Lower the default quality or texture detail: hides an eager loading problem and changes the
  player's rendering. Existing explicit performance tiers remain available.
- Guess attribution from `.gma` sizes: archives, resident textures and allocation slices have
  different sizes and lifetimes. Measure loaded names and allocations instead.
- Force a global material reload on each character removal: disrupts other content and creates
  reload stalls; native cache lifetime needs a separately reviewed fix.
