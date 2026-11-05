# R19-G: glass and the companion's eye whites (report)

Status: **done** (Claude, 2026-11-05). Brief: [R19-plan.md](R19-plan.md), section "R19-G"; findings in
[R19-review.md](R19-review.md) and, git-ignored in the main checkout, `out/review-final/`
(`task-mw40hbhb-wibgei.md`: GL-01; `task-mw40h5pg-g30nzx.md`: glass F-01, F-02, companion F-03, F-04;
`verdicts.md`: the `sprp` and leaf-walk misses). Branch `r19-glass`, worktree
`out/worktrees/r19-glass`, from `r19-int` (`1e4cb10`):

- `baba026`: the sources, tests and the `.md` files beside them;
- `a03462b`: the rebuilt `gmcl_nlglass_win64.dll` imported into `packages/glass`;
- this report.

Evidence (git-ignored, in the worktree): `out/r19-glass/` (the read-only leaf-range check, commit
messages), `out/logs/` (build and test logs).

## In short

| Finding | Verdict | Outcome | Files |
|---|---|---|---|
| GL-01 | partly right, low | **Fixed**: a lump's declared expansion is checked against the rest of the 256 MiB budget *before* its buffer exists; an inflated `sprp` lump counts too | `glass/native/bsp.cpp` |
| `sprp` total (verifier's miss) | low | **Fixed**: the 32,768 static-prop records count across every `sprp` entry together | `glass/native/bsp.cpp` |
| Leaf walk (verifier's miss) | low | **Fixed**: a work budget of 8,388,608 leaf-brush references; and destroying a world now cancels its import, so `Shutdown` never waits for the rest of a map | `glass/native/bsp.cpp`, `bsp.h`, `world.cpp`, `world.h` |
| Glass F-01 | partly right, low | **Fixed**: a claimed interest region gets a shot only if the path is in that player's PVS or within 1,024 units of its eyes | `glass/addon/lua/nlglass/debris_bullets.lua` |
| Glass F-02 | partly right, low | **Fixed**: late-join snapshots paced at 16,000 bytes per player per tick; one full initial sync per connection | `glass/addon/lua/nlglass/server.lua` |
| Companion F-03 | partly right, none | **Fixed as the plan asks**: eviction counts and deletes only the companion's own `<sha256>.vtf` entries | `companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua` |
| Companion F-04 | partly right, none | **By design, no change** (documented retention of the companion's own telemetry) | none |

The wire protocol, the module's Lua functions and every shipped setting are unchanged. The new
glass module's SHA-256 is `10cefd574ff470a7b456d29e48d9a07325b89810529285b9df7518af35ef56cc`
(was `327ddf26...e4`).

## 1. Glass native (`gmcl_nlglass_win64.dll`)

### GL-01: the expansion budget is checked before inflating

- **Before:** the reader inflated a compressed collision lump (up to 128 MiB) and only then added it
  to the 256 MiB total (`bsp.cpp:39-42`, `:73`). A third 128 MiB lump was allocated while 256 MiB were
  already held. A compressed static-prop game lump (`bsp.cpp:198`) was not counted at all.
- **Now:** `Reader` keeps `charged`, the bytes counted against `kMaxMapBytes`. Every collision lump is
  charged: a slice of the file at its size (`charge`), a compressed one through `inflate`, which passes
  what is left of the budget to `decompress`. `decompress` checks the declared size against it after
  the header checks and **before** `std::vector out(size)`. `read_props` inflates a compressed `sprp`
  entry through the same `inflate`, so it is charged too. The error is the existing
  "expanded BSP collision data limit".
- **Peak:** at most 256 MiB of expanded data, plus the decoder's probability tables (at most 6 MiB at
  the largest accepted `lc+lp`); never a buffer over the budget.

### The `sprp` total

- **Before:** the 32,768 cap applied to each `sprp` entry, and the directory may hold 128 entries that
  all name one payload: 4.2 million props, about 12.6 million Lua tables in one `PollLoadMap` call on
  the game thread.
- **Now:** `read_props` keeps `records` across entries; each entry's count must fit in what is left of
  32,768 ("static-prop count"). A real map has one entry, so nothing changes for it. The brief allowed
  either this or reading only the engine's entry; I took the total, which does not depend on which
  entry the engine uses.

### The leaf walk, and a `Shutdown` that no longer waits

- **Before:** the walk over the world's leaves had no work budget. Leaves sharing one crafted range of
  the leaf-brush lump multiplied the visits: 1,048,576 leaves of 65,535 references is 2^36 visits
  (about 45 s at the measured rate) on the import worker, and `Shutdown` (`world.lua:111` ->
  `module.cpp:291` -> `World::~World`) joined that worker on quit and map change.
- **The budget:** at most `kMaxLeafBrushVisits` = 4 x 2,097,152 = 8,388,608 references, four times
  the largest leaf-brush lump the reader accepts ("BSP leaf brush reference work limit"). Compiled maps
  give each leaf its own range: on gm_construct the leaves' 5,002 ranges sum to exactly its 6,386
  references, on gm_flatgrass 3,610 ranges to its 2,855, none shared. 8,388,480 visits take 5.5 ms.
- **Cancellation, because the walk was not the only long unit:** under the other, unchanged limits a
  crafted map of 7,000 brushes sharing one 64-sided prism (a 99 KiB file) takes 3.1 s to parse and
  6.0 s to parse and cook, all of which `Shutdown` waited for. `World` now owns a `std::stop_source`;
  the destructor (`Shutdown`, `Init`, module close) requests a stop before joining. `begin_load` hands
  the worker a token taken on the caller's thread. `read_bsp(bytes, stop)` checks it at the start, per
  collision lump, per node or leaf popped in the walk, per brush, per displacement and per `sprp`
  entry; `load_impl` per cooked hull and per mesh batch. A stop throws "BSP import cancelled", which
  `load_impl` turns into its existing clean-up; nobody reads that result. Measured: the 7,000-brush
  import, 100 ms after `begin_load`, ended 0.75 ms after the destructor's request.
- **What still runs to its end:** one LZMA lump decodes in a single `LzmaDecode` call (at most
  128 MiB); `BeginFinishWorld` and a step, both short.
- **Real maps:** the import probe gives gm_construct's counts as before (2,095 considered, 2,092
  clipped, 3 skipped, 1 refused, 20,992 triangles, 4 props, 2,094 statics): parse 13.8 ms,
  parse-cook-finish 44.4 ms, asynchronous total 64.8 ms. gm_flatgrass: 112 brushes, 8,192 triangles,
  1 prop, total 33.6 ms. Read-only, from the PoC install.

## 2. Glass Lua

### F-01: forwarded shots need the player's PVS or its surroundings

- **Before:** `B.Forward` sent a shot's start, hit and damage to every client whose own *claimed*
  interest regions the path crossed. A modified client could claim regions around a remote fight.
- **Now** (`reaches` in `debris_bullets.lua`): the region still chooses which shots could touch the
  client's pieces, and the server decides whether the player may learn of the shot. It is forwarded to
  that player only when:
  - the path passes within `B.NEAR` = 1,024 units of the player's eyes (`EyePos`); or
  - its start, its hit, or the point where it passes the matching region is in the PVS (`TestPVS`) of
    the player or of its view entity (a camera: the engine computes that player's PVS from it).
- These are the places whose gunfire the engine already sends that player. With no recipient left the
  shot is not sent at all, so the shooter does not get a copy either. The tests run only for clients
  whose region overlaps, after the existing rate checks; the server-placed recent-break bridge keeps
  its `AddPVS` filter. `TestPVS` is the server API Seamless Portals' Lua already uses.
- **Cosmetic effect:** pieces a player cannot see or hear no longer react to other players' shots
  there. ADR 0070 already accepts pieces that differ between players.

### F-02: paced late-join snapshots, one full sync per connection

- **Before:** pane 0 made the request handler write every pane's snapshot in one callback, counted as
  one of 16 requests per two seconds, so a client could ask again every two seconds. The verifier
  estimated that 16-45 cracked panes could overflow a joiner's reliable buffer.
- **Now** (`server.lua`):
  - **One full initial sync per connection**: `ply.NLGlassFullSync`. The player entity lives exactly
    one connection; a later 0 is ignored. The full sync queues every current pane ID, sorted.
  - **Targeted requests** keep their limit (16 different IDs in two seconds, each once) and go to the
    front of the same per-player queue (`S.syncQueues`).
  - **Pacing**: a `timer.Simple(0)` chain, alive only while a queue holds something (still no Think or
    Tick hook), sends each waiting player at least one pane per tick, then more while that tick's bytes
    for the player stay under `S.SYNC_BYTES` = 16,000 (R4 paced the old add-on's late join at the same
    16,000 bytes per tick). The bytes come from `net.BytesWritten` (`S.Snapshot` now returns them);
    without it, one pane per tick.
  - A pane gone by its turn is sent as `nlglass_remove`; a player who left is dropped;
    `PreCleanupMap` clears every queue (every pane registered after cleanup is broadcast anyway).
- **Unchanged:** the client (it already requests 0 once per Lua state and accepts a snapshot whose
  revision is not older), the message formats and the targeted repair path.

## 3. Companion

### F-03: eviction touches only the companion's own entries

`makeRoom` now counts and deletes only names of 64 lowercase hex digits plus `.vtf`, the SHA-256 the
companion names each proxy by (`CACHE .. digest .. ".vtf"` since R10-E). Any other file a player puts
in `data/nativeloader/eye_whites/` stays and does not count toward the 1 GiB, so it cannot push the
companion into deleting its own entries either.

Not added: a content check before deleting a digest-named entry. Such a file is the companion's by
construction (its name is the hash of the bytes the companion wrote); if it changes, the companion
already refuses to bind or overwrite it ("cache differs"). Checking it would mean reading and hashing
cache files during a prepare. The verifier rated F-03 "none"; this is the plan's change. It can be
added if wanted (open issue 4).

### F-04: by design

The VRAM telemetry rotation (`nativeloader_vram.lua`) moves the companion's own
`native-loader/vram.csv` to `vram.previous.csv`, replacing the older segment: the two-segment retention
its documentation states for files only the companion writes. The verifier rated it "none". No change.

## 4. Tests

| What | Result |
|---|---|
| `tools\build.ps1 -Config Release` (build and CTest) | **26/26** CTests passed; `nl_glass_tests` 25.7 s |
| `nl_glass_tests.exe R19` (new `glass/native/tests/test_r19.cpp`) | 6/6: leaf budget at 128 leaves and refused at 129 (x 65,535); collision LZMA at exactly the budget, one byte over and 128 MiB over (the refusal comes *before* the decoder runs: the message differs); `sprp` LZMA over and within the budget; aliased `sprp` 1 x 32,768 and 2 x 16,384 accepted, 2 x 16,385 and 128 x 32,768 refused; a requested stop; the destructor 100 ms into the 7,000-brush import |
| Glass and eye-white Python modules (`test_eye_whites`, `test_nlglass`, `test_glass_interaction`, `test_nlglass_r9`, `test_glass_debris`, `test_glass_map`, `test_eye_white_*`, `test_companion`) | 153 tests OK, none skipped |
| `tools\test.ps1 -SkipNative` | all checks passed (conventions; 28, 25 and 580 Python tests) |
| `tools\test.ps1 -Config Release` and `tools\test.ps1` (Debug) | see section 4.1 |
| `python -I tools\inputs.py verify` and `verify --deep` | 11 parts checked, 0 problems |

New and changed Lua cases, each run against the pre-R19 files too:

- `nlglass_engine_harness.lua sync_pacing` (twelve near-cap panes, about 5.7 KB each in the harness):
  nothing written in the handler; several ticks; a tick adds a pane only while under budget; each pane
  once; a targeted resync goes first; a second full request is ignored; two joiners progress in the
  same tick; a pane removed while queued goes out as a removal; a leaver is dropped; cleanup clears.
  **Fails on the old server** ("the full sync writes nothing inside the request handler").
- `initial_sync` now flushes the timers and checks a repeat a minute later sends nothing; `network`
  and `target_sync` flush before reading a reply. **`initial_sync` fails on the old server.**
- `glass_interaction_harness.lua bullets_visibility`: a far client claiming a region around the fight
  gets nothing; the hit, the start, the passing point, the 1,024-unit radius and a camera view entity
  each make it a recipient; the bridge is unchanged. **Fails on the old add-on.**
- `eye_whites_harness.lua cache_cap`: digest-named proxies, plus older and larger files named
  `my_edit`, 64 uppercase hex, 63 and 65 hex digits; only the oldest proxy goes. **Fails on the old
  controller** (it deleted `my_edit`).

### 4.1 The full gate

- **`tools\test.ps1 -Config Release`** (what CI runs): **all checks passed**. Conventions; the
  Release build with **26/26** CTests; Python 28 (gmapack, one skip), 25 (steam, one skip) and 580
  (tools) tests.
- **`tools\test.ps1`** (its Debug default): everything passes except `nl_glass_tests`, which stops
  in two glass cases that only a Release build can pass, as the R16 report records. One deliberately
  overfills Jolt's contact tables and Jolt's Debug build asserts on it (`0x80000003`); the other is the
  4,000-piece benchmark's CPU limit (201 CPU s in Debug against 120). Both are untouched by this part.
  Every other glass case passes when run alone in Debug, the six R19 cases among them (the cancelled
  heavy import waited 4.9 ms there).

## 5. Proposed shared-doc lines

**CHANGELOG.md**, under `## [Unreleased]`:

- Glass: a joining player's pane snapshots are paced (at most 16,000 bytes per player per tick, one
  full initial sync per connection), so a map with many cracked panes can no longer overflow a
  joiner's reliable stream (R19, glass F-02).
- Glass: another player's shot moves your broken glass only when it is in your view (PVS) or within
  1,024 units of you; a client's claimed debris region no longer reveals gunfire it cannot see (R19,
  glass F-01).
- Glass module: compressed collision and static-prop lumps are checked against the map's 256 MiB
  expansion budget before they are inflated; static props are capped at 32,768 across all game-lump
  entries; the world-leaf walk has a work budget; quitting or changing map cancels a map import still
  in progress instead of waiting for it (R19, GL-01 and the review's two map findings).
- Companion: eye-white cache eviction deletes only its own SHA-256-named proxies; other files in
  `data/nativeloader/eye_whites` are kept (R19, companion F-03).

**RESEARCH.md** (a short "R19-G: glass map import limits" section):

- vbsp gives each leaf its own range of the leaf-brush lump: gm_construct (v20) 5,002 leaves whose
  ranges sum to exactly its 6,386 references, gm_flatgrass 3,610 leaves and 2,855 references, none
  shared (read-only, `out/r19-glass/leafbrush_ranges.py` in the r19-glass worktree). A world walk
  therefore visits each reference at most once.
- The walk costs 5.5 ms for 8,388,480 references (Release, this machine), so the unbounded 2^36
  would be about 45 s on the import worker.
- A crafted 99 KiB map of 7,000 brushes sharing one 64-sided prism parses in 3.1 s and parses and
  cooks in 6.0 s within the reader's other limits; with R19's cancellation the destructor, 100 ms into
  an asynchronous import, returned 0.75 ms after its stop request.
- gm_construct with the R19 reader: counts unchanged; parse 13.8 ms, parse-cook-finish 44.4 ms,
  asynchronous total 64.8 ms. gm_flatgrass: 112 brushes, 8,192 triangles, 1 prop, 33.6 ms in all.
- A near-cap pane snapshot is 5,686 bytes in the engine harness's accounting (the protocol's in-game
  estimate is about 10 KiB); at 16,000 bytes per tick a joiner gets two or three such panes a tick.

**TESTING.md** (an "R19-G" paragraph): `test_r19.cpp`'s six cases as in section 4; the Lua cases
`sync_pacing`, `bullets_visibility` and the extended `initial_sync` and `cache_cap`; and the in-game
checks of section 6.

COMPONENTS.md, ROADMAP.md, AGENTS.md: nothing from this part (no new folder; R19's status is the
integrator's).

## 6. What the integrator must do

- **Merge** `r19-glass` (three commits). `packages/glass/bin/gmcl_nlglass_win64.dll.xz` is a new Git
  LFS object (oid prefix `e008145092`); push it with `main`.
- **Pins:** none. `tools/ci/pins.json` builds the glass module from this repository's source
  (`repository_builds`), so the package workflow's module comes from the merged `glass/native`.
- **Translations:** none. No new user-visible string; the two new native refusal reasons ("BSP leaf
  brush reference work limit", "BSP import cancelled") can only appear in the existing English
  "[NLGlass] Jolt unavailable" console line, and only on a crafted map.
- **In-game checks** (PoC, RTX session):
  1. **Late join, many cracked panes (F-02).** Host a listen server with `-multirun` on gm_construct.
     Spawn about 40 spawn-menu panes (or use a map with many windows) and crack each several times
     without breaking it out (pistol shots spread over the pane). Join from a second PoC instance
     (`connect localhost`). Expect every pane's cracks on the joiner within about a second, the joiner
     staying connected, no "overflowed reliable buffer" or Lua error on either console. On the host,
     `lua_run print(next(NLGlass.Server.syncQueues))` prints `nil` once the joiner has everything.
  2. **Debris near and far (F-01).** Same two instances. Break a window; both players see its pieces.
     Host shoots the pieces from beside them: they react on both clients while the guest stands
     nearby or in sight of them (also from more than 1,024 units away with a clear view). Then put
     the guest in another room, out of sight of those pieces, and shoot them again from the host: they
     react on the host, not on the guest; when the guest returns its pieces lie where they were. NPC
     gunfire near pieces still moves them for a player close by. No Lua errors; `lua_run
     print(NLGlass.Bullets.sent, NLGlass.Bullets.limited)` grows as before.
  3. **Import and shutdown (native), a regression check.** Load gm_construct, then gm_flatgrass, then
     quit: on each map the client's `NLGlassDebris.Backend()` is `jolt` once a window was seen or
     broken, there is no "[NLGlass] Jolt unavailable" line, and the map change and the quit take no
     longer than with R18. (A real map imports in about 65 ms, too fast to interrupt by hand; the
     cancellation itself is proven by `test_r19.cpp`.)
  4. **Eye whites (F-03).** Put any file at `garrysmod/data/nativeloader/eye_whites/notes.vtf` in the
     PoC; spawn an imported character: its eye whites stay steady as before and the file is still
     there after the session. (Eviction itself starts only above 1 GiB; the harness covers it.)

## 7. Open issues

1. **One LZMA lump is still uninterruptible.** `LzmaDecode` decodes a lump in one call, so a crafted
   map with two 128 MiB lumps can still hold `Shutdown` for the time to decode them (about 1-2 s,
   estimated, not measured). Decoding in chunks with `LzmaDec_DecodeToDic` and the stop token between
   them would close this.
2. **Several `sprp` entries.** The reader takes all of them, within the total; the engine uses one
   of them. Only a crafted or unusual map has more than one, and only the glass world's static props
   differ.
3. **The 16,000-byte pace is not measured in game.** It is R4's pace for the old add-on; in-game
   check 1 is the measurement.
4. **Edited digest-named eye-white proxies** can still be evicted (section 3). A SHA-256 check
   before deleting would close it at the cost of reading the files being evicted.
5. **A developer's Lua refresh** of the glass add-on on a client asks for pane 0 again, which is now
   refused for that connection; its panes come back one by one on their next hit or targeted repair.
   Ordinary play never refreshes the add-on's Lua.
