# host_memory_census.py

Turns the runtime's host memory census (R13-B, runtime patch 0023,
[ADR 0100](../../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) into an account of
where a session's committed memory went.

```powershell
python tools\qa\host_memory_census.py <session>\remix-dxvk.log --out account.json
```

**Input:** one session's `remix-dxvk.log`. A census is requested in game with
`rtx.profiler.memory.requestSnapshot = True` (NoSave; the QA Lua sets it through
`RemixConfig.SetConfigVariable`). The runtime then writes `[RTX Host Memory]` rows on the next present,
with or without the memory profiler:

- `memory_type`: each Vulkan memory type's heap and flags, its chunks (bytes and bytes in use) and its
  dedicated allocations;
- `host_mapping`: the address range of every host-visible memory object;
- `process`: private bytes (commit) and working set;
- `address_space`: the process's committed address space by kind (private, mapped, image) and
  protection, with the bytes DXVK's own mappings cover, per memory type;
- `end`.

With `RTX_PROFILER_MEMORY_ENABLE=1` set at launch, the `[RTX Allocation]` groups follow, now with the
memory flags each allocation received, whether the application released the image while the renderer
still holds it (`released`), and the allocation's name (its purpose; texture CPU copies are
`d3d9 texture copy`).

**Output:** JSON with one entry per census: the memory types, the private address space split into
read-write (`rw`) and write-combined (`wc`) with the DXVK-mapped part, the largest purposes in
host-visible and in device-local memory, and an `account`: texture CPU copies, staging and upload
buffers, Remix's own host memory, other DXVK host memory, images released by the application but still
held by the renderer, read-write memory DXVK did not map (the game's own heaps, the driver), and
write-combined memory DXVK did not map (the driver's mappings of device-local memory). The
`[RTX Managed Textures]` lines (R13 one-copy/release counters) and `[RTX Texture Budget]` lines
(replacement texture budget under pressure) are listed as they appear.

**Exit:** 0; 1 when a census is incomplete (no `end` row). Reads only the given log; writes only
`--out`. Never reads the game's console log.
