# vram_census.py

Validates and summarizes logs produced by the R12-C QA probe and runtime patch 0021:

```
python tools/vram_census.py --console out/qa/console.log --runtime out/qa/remix-dxvk.log --out out/qa/census.json
```

Either input may be omitted. Only give it console bytes written by the owned QA session, never a
user's previous console history. It does not open an install, game process or texture. Output JSON
keeps every raw Source texture row and Remix sample, groups allocation bytes by device-local
category, sorts app-texture groups by size and retains all other groups for inspection. Integers
remain integers; no MB/GB rounding is used. `d3d9_pool=-1` means no D3D9 metadata, not default pool.

`--telemetry PATH --since 2026-11-03T01:35:00Z` reads an existing companion `vram.csv` without
launching or sending input to a game. It validates complete rows and integer counters, keeps
missing counters as null, filters by an explicit time zone and reports an omitted in-progress
trailing row. This can inspect the active field session read-only while the activity gate is
closed. Only the named CSV is opened; it does not read the user's console history.

Rejects interrupted/truncated allocation snapshots, missing groups, mismatched frame IDs, invalid
bytes/counts and whole-frame sampling (which includes resources already released in that frame).
Also checks Source's reported texture count against received rows. It never substitutes zeros for
unavailable measurements. Source's `Size` units must be established from the game records before
adding or comparing them with DXVK allocations; Source estimates and Vulkan allocation sizes are
different measurements. Driver allocation, DXVK used bytes and retained allocator bytes likewise
must not be added to one another.

Source summaries group byte estimates by engine texture group, format and a few explicit path
families. `mmd_base_textures` includes every `mmd/t/` texture, including textures supplied by an
authored character pack; the namespace alone does not identify the current library or its loader.
Raw rows and the thirty largest estimates remain available for inspection.

Side effects: creates/replaces only `--out` and its parent. Exit 0 on success, nonzero on malformed
or inaccessible evidence. Standard-library Python only; offline tests use generated logs.
