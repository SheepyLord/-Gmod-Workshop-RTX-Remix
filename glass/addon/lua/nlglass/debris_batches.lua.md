# debris_batches.lua

Client-only helper included by `debris.lua`. Owns immutable settled meshes in 1024-unit XYZ areas,
offset half a cell around zero and grouped by material. Tint/alpha stay in vertex colors and do
not split draws. `Add`, `Remove`, `Tick`, `Draw`, `Count`, `Clear` are manager-internal calls.
Additions retain old valid meshes. A trailing 200 ms debounce, with a 750 ms maximum delay during
continuous arrivals, schedules a snapshot. One job shares a bounded pool of 24,000 vertex records
across all areas. Transforms stop at 1,800 vertices or a measured 0.6 ms allowance per frame,
checking time after each whole piece; at least one piece can progress. One upload/frame holds at
most 24,000 vertices. Native uploads cannot be preempted; game timings remain required.

Replacement publishes only after every mesh exists. New arrivals request a later revision;
removal cancels staging. Wake/removal/shrink immediately hides its affected immutable chunk;
other chunks remain drawn, and survivors draw individually until replacement. Failed builds
retain old valid geometry and retry after one second. Superseded/canceled GPU meshes retire at
most two/frame instead of all at publication; cleanup frees all outstanding meshes immediately.
The vertex pool survives `Clear` for reuse and is released with the helper on shutdown/reload.
`Count` uses maintained counters. `tick_ms`, `upload_ms`, `pool`, and the retirement queue feed
manager QA metrics. No file, server or network operations; exceptions are caught, no exit code.

Only dirty/in-progress areas enter the rebuild work set. An unchanged settled area is never
visited by Think; drawing still visits its visible batches.
