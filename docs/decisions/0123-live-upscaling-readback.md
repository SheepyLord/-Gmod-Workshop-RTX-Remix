# 0123: read effective upscaling state from the runtime

Date: 2026-11-06. Status: accepted for R20-E (item 45).

## Context

R20-B's startup hint needs effective settings and selected-device capabilities after graphics/DLSS
presets and option callbacks. The fixes' `GetConfigVariable` reads `rtx.conf` from disk; startup option
logs also precede device-dependent presets. R20-B already consumes an optional live snapshot and
stays silent without one.

## Decision

Runtime patch 0040 publishes one atomic game value, `rtx.runtime.upscalingState`, through the existing
`remixapi_GetGameValue`. Its wire format is exactly thirteen ASCII bytes plus NUL: `1 R U F D G A`,
with single spaces. `1` is the schema version, `R` readiness, `U` effective `rtx.upscalerType` (0-5),
`F` effective `rtx.frameGenerationType` (0-2), `D` DLSS support, `G` DLSS frame-generation support,
and `A` FSR 3 frame-generation support. Boolean fields are `0` or `1`. One key prevents reads spanning
two publications. This adds no API function or option.

`GameStateStore` reserves the entire `rtx.runtime.` prefix. Plugin `SetGameValue` writes return
`REMIXAPI_ERROR_CODE_INVALID_ARGUMENTS` there; only the typed internal publisher writes the snapshot.
Existing plugin keys retain their behavior and lifetime.

The device's `RtxInitializer` owns publication. Construction publishes unready state. Completion of
initialization permits readiness after startup presets and the option resolver. Every dirty option
immediately invalidates readiness under the option update mutex, covering indirect preset
dependencies. The resolver records whether callbacks converged. An exhausted callback cycle
suppresses readiness until device recreation, because the existing resolver abandons those remaining
changes. Publication refreshes after initialization and at every present. It holds the option update
mutex while copying both effective enums, then the store mutex. Readers take only the store mutex.
The enum copy uses `getValueNoLock` under the existing lock, including option debug-logging builds.

Capabilities use actual selected-device probes: DLSS extensions and `metaDLSS().supportsDLSS`, DLFG
support excluding `hasDLFGFailed`, and `metaFSRFrameGen().supportsFSRFrameGen` (runtime DLL and the
required presentation/acquire queues). They describe usability independently of the selected feature.
Destruction removes the snapshot; a new initializer replaces its owner and old initializers cannot
publish or erase its state. Two startup log lines record pending/resolved publication.

The fixes' sixth GPL patch adds `RemixConfig.GetUpscalingState()`. It looks up the existing export
without reading an optional SDK interface tail. One bounded read strictly checks the API result,
length, terminator, version, enums and booleans. Missing/older runtime, missing key or invalid data
returns `nil`. Success allocates a fresh Lua table:

| Field | Type |
|---|---|
| `ready` | boolean |
| `upscaler` | integer 0-5 |
| `frame_generation` | integer 0-2 |
| `dlss_supported` | boolean |
| `dlss_frame_generation_supported` | boolean |
| `fsr_frame_generation_supported` | boolean |

R20-B's consumer and contract stay unchanged. The getter saves nothing, reads no config file and
performs no GPU-name inference.

## Source and shipped provenance during integration

The brief requires a tested runtime patch and a passing repository gate without importing its DLL:
the reviewer imports one combined R20 runtime. The previous checker rejects every new patch until
import. To satisfy both requirements honestly, `runtime/base.json` may declare
`pending_patches: {why, files}` with a reason and exact hashes. Only new numbered patches ordered
after every packaged patch may be pending. Existing packaged patches, base/submodule/clone inputs
and the stored DLL retain all previous checks. Changed/missing/undeclared additions fail. Every
patch still participates in source verification and builds. Import clears the pending record;
`-NoImport` retains it and the unchanged packaged provenance. The small supporting change to
`tools/check_repo.py` exceeds the brief's original source paths solely to resolve this contradictory
gate requirement; it does not claim the packaged DLL contains 0040.

## Validation

The runtime's SDK-free test checks readiness, reservation, failed convergence, enums, lifecycle and
concurrent readers. The GPL reader test checks every enum/capability combination and malformed,
absent, oversized and failed API results. The aggregate Release gate builds both from the committed
patch/source without a runtime clone. PoC acceptance uses both new binaries and in-memory setting
changes, records real capabilities, then restores the snapshot under the shared lock. The combined
runtime build/import remains integration work.
