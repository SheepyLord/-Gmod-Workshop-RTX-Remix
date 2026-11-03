# 0100: One copy of each game texture, idle image release and replacement textures under pressure

- Status: accepted within the user's R13 plan (approved 2026-11-03); defaults changed by the main session
  during R13-B (automatic for gmod.exe, below)
- Decided by: the user's R13 answers ([R13-plan.md](../handover/R13-plan.md)), the lag report of
  2026-11-03, and the measurements in the [R13-B report](../handover/R13-B-report.md)

## Context

The field game at idle committed 28.4 GB of private memory: 17.3 GB read-write and 11.0 GB
write-combined, mostly in 128 and 256 MiB blocks (`out/r13/field/vm-idle.json`). In the lag report,
14.35 GB of game textures became GPU-resident within 30 seconds and stayed until the game restarted;
the driver held the process 2.5 GB over its budget while replacement textures kept 10.3 GB.

Patch 0022 ([ADR 0096](0096-demand-loaded-character-classification-and-memory-census.md)) gives a static
managed texture GPU memory only on first use, but keeps two copies of every used texture (the CPU copy
DXVK's managed pool keeps, and the image), and never gives the image back.

The R13-B census (runtime patch 0023) accounts for that memory on this machine:

- **Read-write committed memory** is DXVK's host-cached memory type (`HOST_VISIBLE|COHERENT|CACHED`,
  128 MiB chunks and dedicated allocations for mips of 128 MiB and more), whose largest purpose is the
  CPU copies of managed textures (`d3d9 texture copy`), plus the game's own heaps.
- **Write-combined committed memory** is mostly not DXVK's mappings at all: the NVIDIA driver maps the
  process's device-local allocations into its address space as write-combined private memory, and they
  count in the process's private bytes (commit). Releasing 358 MB of images in the GPU probe lowered
  write-combined commit and private bytes by 358 MB. DXVK's own write-combined mappings are its
  host-visible uncached type (staging) and the device-local host-visible type (ReBAR).

So VRAM the game holds also holds system commit, and the two copies of a texture cost RAM twice.

The lag report's 10.3 GB of replacement textures that never gave way were nearly all **preloaded**
textures. A USD material with `preload_textures = 1` pins its textures at every mip from the moment the
mod loads, drawn or not: `requestMips` forces every mip while `m_canDemote` is false, and the budget pass
and `manageBudgetWithPriority` skip such textures (`rtx_texture_manager.cpp`, `rtx_texture.cpp:189-198`).
rpai writes the flag on every material (`skills/mmd-remix-pbr/tool/rpai/usda.py:61`), as do the fixes'
ToPBR for game maps and the material editor's default. The field's mods preload 889 files, 11.05 GB
(10,537 MiB; `ai_pbr` alone 8.50 GB in 219 materials, and three standalone character mods with the same
files as `ai_pbr` under another path, 2.22 GB, which Remix loads twice because it keys replacement
textures by path), against the lag report's 10,320 MiB. No budget could make them give way.

## Decision

Runtime patches 0023-0028 (R13-B):

### 0023: the host memory census

`rtx.profiler.memory.requestSnapshot` also writes `[RTX Host Memory]` rows, with or without the memory
profiler: every memory type's chunks and dedicated allocations, the address range of each host-visible
memory object, the process counters, and the committed address space by protection with the part DXVK's
mappings cover. Allocation groups gain the memory flags they received, whether the application released
the image while the renderer holds it, and the allocation's name.
[host_memory_census.py](../../tools/qa/host_memory_census.py.md) turns a session's log into an account.

### 0024: one copy, and idle images released over a budget

For static managed 2D textures (patch 0022's class), two options in the DXVK configuration:

| Option | Environment | gmod.exe default | Other games | Values |
|---|---|---|---|---|
| `d3d9.releaseManagedHostCopies` | `DXVK_RELEASE_MANAGED_HOST_COPIES` | Auto | False | Auto: on below 28 GiB of RAM or 15 GiB of VRAM (the plan's minimum profile and below); True; False |
| `d3d9.managedTextureBudgetMiB` | `DXVK_MANAGED_TEXTURE_BUDGET_MIB` | -1 | 0 | -1: a quarter of the VRAM (the largest device-local heap); 0: off; else MiB |

Explicit values (the loader's memory layer, R13-C) win over the automatic choice; the environment wins
over configuration files. The runtime logs the resolved values once at startup
(`[RTX Managed Textures] budget: 8046 MiB (auto: VRAM/4)`, `release host copies: off (auto: RAM ..., VRAM ...)`).

*The defaults were first planned as off with the loader turning them on. The main session changed them
during R13-B to automatic for gmod.exe: the bootstrap reaches players only when they reinstall it by
hand, so testers with an older loader get the new runtime from the Workshop without the loader's memory
layer, and should still get the savings.*

- **One copy.** Once a texture's image holds its data and the texture has not been locked for
  `d3d9.managedHostCopyIdleSeconds` (10 presented seconds), its CPU copy is freed. A later lock reads the
  subresource back from the GPU first, exactly as DXVK's `evictManagedOnUnlock` path does. Textures that
  use `AddDirtyRect` keep their copy (games that write through an old lock pointer), and so do textures
  locked writable with `D3DLOCK_NO_DIRTY_UPDATE` (0028): such a write reaches the image only with a later
  `AddDirtyRect`, so until then it exists only in the copy.
- **Idle images.** Once a second, while these textures' images hold more than the budget, images not
  drawn for `d3d9.managedTextureIdleSeconds` (60 presented seconds) are released, least recently used
  first, at most 2 GiB of plain releases and 256 MiB of read-backs per pass. Bound, locked and pending
  textures are never chosen. The data stays: a texture whose CPU copy was released is read back
  asynchronously first, and released in a later pass if nothing used it meanwhile. Every subresource is
  marked for upload, so the next use creates the image again through patch 0022's path, with the hash it
  had.
- **Identity.** The texture keeps its Remix hash while the image is released: `dxvk_GetTextureHash`, the
  hash-on-write rule (`rtx.recomputeTextureHashOnWrite`, including its configured-category exceptions) and
  the re-created image all use it. A rewrite while released clears it, so the re-upload hashes the new
  data, as before. The hash lives in an atomic on the texture (0028): the API is called from other
  threads (ToPBR from Lua) while the device's pass may release the image, so for these textures it never
  reads the image.
- **Remix's references.** The released image is marked application-released, so Remix's texture cache
  frees it once no instance samples it (the existing `rtx.texturemanager.releaseReplacedGameTextures`
  path); instances still drawn are rebound on their next draw. Until then the image stays alive and
  correct, and its memory goes when Remix lets go. ImGui's texture list drops only its own entry for that
  image.
- **Ticks** are presented seconds: at most one per pass, so time minimized or loading without presenting
  never makes everything look idle.

Why 60 seconds: images go only while the class holds more than a quarter of the VRAM, and a minute
without a draw covers turning around, menus and short trips, so ordinary play does not re-upload; a
burst still returns quickly: R13-A's trigger (17.08 GB of game textures) was back at the 8 GB automatic
budget 75 seconds later in the PoC, and at the minimum profile's 2 GiB about two minutes later.

### 0025: replacement textures give way under real pressure

The texture manager's budget is a percentage (50 % by default) of the free VRAM plus what textures hold,
or a fixed size; it follows the driver's live budget every frame. A fixed or high budget can still hold
more than the driver lets the process keep. Under real pressure the budget is now capped from the
largest device-local heap's live numbers: within a margin below the driver's budget (2 %, at least
256 MiB) replacement textures stop growing, and over the budget they give back the overflow plus the
margin. While the margin is free nothing changes. A rate-limited `[RTX Texture Budget]` line reports the
regime and the numbers.

### 0026: undrawn preloaded textures give way under the same pressure

A texture a USD material preloads gives up its pin while 0025's limit applies (within the margin or over
the budget) and no instance has drawn it for 10 seconds: it streams like any texture and drops to its
smallest mip. Remix drops an instance one frame after its last draw (`rtx.numFramesToKeepInstances`
is 1), so the wait keeps a character the camera turned away from for a moment whole; textures never
drawn go at once. As soon as an instance draws it again it is pinned and loaded whole again, in the
background. While memory is free nothing changes, and a released preload stays released until it is
drawn, so a pressure episode does not end in reloading gigabytes nobody draws. Only a material's own
preload yields: dome lights, textures too large for the streaming staging buffer and
`rtx.texturemanager.neverDowngradeTextures` keep their pin.

0025's limit is for all replacement textures, but the budget pass can shrink only those that stream.
Under pressure they now get the limit less what pinned textures hold, so the overflow is taken from
them rather than left to the driver. `[RTX Texture Budget]` lines report what pinned textures hold and
count the releases and restores.

For tests, `DXVK_TEXTURE_PRESSURE_TEST_BUDGET_MIB` caps the budget these rules see; the driver's own
budget is unchanged and the log warns while it is set. A VRAM hog in another process does not make
real pressure on this computer: with 25.8 GB held beside the game, WDDM lowered the game's budget only
to its own usage (26.15 GB, 26.14 GB used) and paged the hog instead.

"Undrawn" means no instance's material retains the texture (Remix's instance reference count,
`retainSurfaceMaterial`) and nothing tracked it in the texture cache in the last frames (0028: the
terrain baker samples its sources through the cache every frame it bakes without retaining them, while
the baked instance binds the baker's own material). A texture that no material references any more
after a USD reload is never drawn, so it is among the first to go under pressure; so are the preloads of
every character that is not spawned, and of duplicate mods that lose to another for the same material.

### 0027: what creates the images

The `[RTX Managed Textures]` line counts the deferred images, and their bytes, created by each path of
patch 0022: sampling, a view, a flushed upload, `PreLoad` and a draw's upload. A burst such as the first
`item_ammo_ar2_altfire` precache of a session (R13-A: every loaded texture made resident in one frame)
then names the call. Diagnostics only.

### 0028: the review's fixes

An independent review of 0024-0027 found three defects and a nit, fixed in 0028:

- **The hash API raced the image release** (0024). `dxvk_GetTextureHash` and `GetStableHash` read the
  image and the released hash without a lock while the device's pass moved the image out first and wrote
  the hash after, so a caller on another thread could get hash 0 with success (ToPBR then drops the
  variant), a null image or a freed one. The texture now keeps its hash in an atomic, written with every
  hash change (`SetupForRtxFrom`, `ClearHash`, the release, kept across re-creation); the API and
  `GetStableHash` read only that for these textures.
- **Terrain-bake sources could stay at their smallest mip** (0026), because the baker does not retain
  what it samples. `addTexture`, which every consumer goes through, now stamps the frame, and a texture
  tracked in this frame or the two before counts as in use.
- **Writes without a dirty region could be lost** with copies released (0024): a writable
  `D3DLOCK_NO_DIRTY_UPDATE` lock now keeps the texture's copy for good.
- **Other games ran the once-a-second pass and its log:** with neither option on, it returns at once.

The GPU probe's `r13` sequence gained a second thread reading hashes through the release and an unmarked
write that must survive it; on the runtime before 0028 both fail (wrong hash reads with a budget, the
write lost with copies released), on 0028 every variant matches the original runtime.

### Per profile (R13-C's loader layer)

| | minimum | recommended | high |
|---|---|---|---|
| `d3d9.releaseManagedHostCopies` | True | False | False |
| `d3d9.managedTextureBudgetMiB` | VRAM / 4 (or -1) | VRAM / 4 (or -1) | VRAM / 4 (or -1) |
| `rtx.texturemanager.budgetPercentageOfAvailableVram` | 50 (default) | 50 (default) | 50 (default) |
| `rtx.texturemanager.fixedBudgetEnable` | False (default) | False (default) | False (default) |

The runtime's automatic values match this table, so the loader may also write -1/Auto. No `rtx.*`
texture setting needs to change per profile: the percentage already scales with the free VRAM, and
0025 and 0026 act only under the driver's own pressure. A lower percentage on small cards would change
what a computer with free memory shows. The loader should not write the texture budget at all, so a
player's own choice in the Remix menu (saved in `user.conf`) stays theirs.

## Consequences

- RAM and commit fall by the CPU copies of every texture in use on the minimum profile, and by idle
  images over the budget on every profile; the account and the savings are in the R13-B report.
- A lock of a texture whose CPU copy went waits for a GPU read-back (minimum profile only). The fixes do
  not lock game textures; Source does not read them back.
- An image released and used again is uploaded again: a short hitch for a large texture, after at least
  a minute without a draw and only while the class is over its budget.
- Nothing visible changes: the same data, mips and hashes; the probe compares exact pixels and hashes
  against the original runtime.
- A game that writes through an old lock pointer without `AddDirtyRect` would write into freed memory if
  its texture's copy were released; Source does not do this, and only gmod.exe has the option on.
- Under pressure, a character whose preloads were released shows its smallest mips for the moment its
  maps take to load again when it next appears. With free memory nothing changes.
- Preloads still cost their full size from the start of every session while memory is free: every
  character's maps, spawned or not. That is a content choice (rpai, ToPBR, the material editor) that
  0026 does not change; see the R13-B report.

## Alternatives considered

- **Release the CPU copy right after each upload:** a texture the game keeps writing would pay a GPU
  read-back on every lock. The copy goes only after ten seconds without a lock.
- **Release images by Source's last bind alone, without a budget:** re-uploads during ordinary play.
  Only the part over the budget goes.
- **Synchronous read-backs at release:** a stall of tens of milliseconds per batch; read-backs run
  asynchronously and are capped per pass.
- **Lower the replacement texture percentage per profile:** changes what a computer with free memory
  shows. The pressure cap only acts when the driver says memory is short.
- **Unpin a preload only once no material references it (after a USD reload):** needs the textures'
  reference counts checked against the asynchronous USD rebuild, which creates and reuses textures on
  its own thread, and covers only orphans, not the unspawned characters that hold most of the memory.
  The pressure rule covers orphans too, since they are never drawn.
- **Ignore `preload_textures`:** the fixes' ToPBR sets it so its generated maps do not stay at their
  smallest mip (R13-M, the fixes' `usda.cpp:350-357`); streaming them would bring that back. 0026 keeps
  every drawn preload whole.
- **Pin a released preload again when the pressure ends:** reloads gigabytes nobody draws and brings
  the pressure back. It is pinned again when drawn.
