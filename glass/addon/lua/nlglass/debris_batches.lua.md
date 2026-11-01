# debris_batches.lua

Client-only helper included by `debris.lua`. Owns immutable settled meshes by 256-unit area,
material and color. `Add`, `Remove`, `Tick`, `Draw`, `Count`, `Clear` are manager-internal calls.
Additions keep the old valid meshes visible while a snapshot is transformed at no more than
1,800 vertices/frame. A GPU upload contains at most 6,000 vertices; at most one upload occurs
per frame. Replacement is published only after all its meshes exist. New arrivals queue a later
revision; removal cancels stale staged geometry. A removed/woken/shrinking member hides only its
old small chunk; other chunks stay drawn, and that chunk's survivors draw individually until
replacement. Old/staged meshes are destroyed on replacement, failure cancellation or cleanup.
Build failures retain valid old meshes and retry after one second. No files, server or network
operations. No process exit code; mesh exceptions are caught and retried.

Only dirty/in-progress areas enter the rebuild work set. An unchanged settled area is never
visited by Think; drawing still visits its visible batches.
