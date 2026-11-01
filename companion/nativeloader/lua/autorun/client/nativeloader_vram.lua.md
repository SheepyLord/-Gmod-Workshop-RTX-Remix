# nativeloader_vram.lua

Client-only local VRAM telemetry for R6. Runs with the RTX companion and samples
`RemixResource.GetVramStats()` every 30 seconds when the RTX fixes expose it. The archived client
setting `nativeloader_vram_telemetry` defaults to `1`; set it to `0` to stop sampling immediately.
Missing functions produce no files, calls or messages; availability is checked each tick so a
module loaded later is supported. Three consecutive failed calls (nil, error, non-table or no
valid fields) stop calls for this map, because the native binding can warn on each failure. A valid
sample resets that counter. Toggle the client setting off and on, change maps or restart to retry.
The sampler itself adds no warnings; file errors are caught and retried.

Writes in GMod's `DATA` realm only:

- `garrysmod/data/native-loader/vram.csv`: current segment, at most 120 samples (one hour).
- `garrysmod/data/native-loader/vram.previous.csv`: preceding segment, normally at most 120 samples.

At sample 121 the completed segment replaces the previous one and a new current segment begins.
Together they retain between one and two hours of samples after the first hour, at most 240 rows.
The count is recovered from the current file after a map change or restart; gaps between sessions
do not count as sampled time. Only these telemetry segments rotate; no source crash files change.
An unexpected header, unfinished/invalid row, NUL or CRLF data, excess rows or a file over 128 KiB
is renamed intact to `vram.previous.csv`, replacing that earlier telemetry segment, and a fresh
current segment starts. An oversized file is renamed without reading it; the saved invalid segment
may exceed normal bounds until the next rotation replaces it. If renaming fails, the source stays
in place and a later tick retries. Only the companion's two owned CSV files change. No upload or
settings changes occur.

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
