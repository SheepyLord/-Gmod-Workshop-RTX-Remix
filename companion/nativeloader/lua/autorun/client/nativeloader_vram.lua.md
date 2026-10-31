# nativeloader_vram.lua

Client-only local VRAM telemetry for R6. Runs with the RTX companion and samples
`RemixResource.GetVramStats()` every 30 seconds when the RTX fixes expose it. The archived client
setting `nativeloader_vram_telemetry` defaults to `1`; set it to `0` to stop sampling immediately.
Missing functions, nil results, API errors and file errors produce no messages or new samples.
Availability is checked each tick so a module loaded later is supported.

Writes in GMod's `DATA` realm only:

- `garrysmod/data/native-loader/vram.csv`: current segment, at most 120 samples (one hour).
- `garrysmod/data/native-loader/vram.previous.csv`: preceding completed segment, at most 120 samples.

At sample 121 the completed segment replaces the previous one and a new current segment begins.
Together they retain between one and two hours of samples after the first hour, at most 240 rows.
The count is recovered from the current file after a map change or restart; gaps between sessions
do not count as sampled time. Only these telemetry segments rotate; no source crash files change.
An unexpected header, unfinished line, more than 120 existing rows or a file over 128 KiB stops
writing that segment without changing it. No upload or settings changes occur.

The CSV starts with `time_utc` (ISO 8601 UTC), then the fixes' exact field names:
`driverBudgetBytes`, `driverAllocatedBytes`, `totalAllocatedBytes`, `totalUsedBytes`,
`poolRetainedBytes`, `usedReplacementGeometryBytes`, `usedBufferBytes`,
`usedAccelerationStructureBytes`, `usedOpacityMicromapBytes`, `usedMaterialTextureBytes`,
`usedRenderTargetBytes`, `forkTextureCacheCount`, `usedAppTextureBytes`, `usedAppBufferBytes`.
Every numeric column is bytes except `forkTextureCacheCount`, which counts cache entries. Missing
or invalid fields are blank, so an older binding does not report false zeros. A table with no valid
fields is skipped. Driver allocation includes memory outside DXVK's allocator; do not sum it with
DXVK's totals or sum totals with their categories.

No exit code (game Lua). Offline checks:
[`test_companion_vram.py`](../../../../../tools/tests/test_companion_vram.py.md).
