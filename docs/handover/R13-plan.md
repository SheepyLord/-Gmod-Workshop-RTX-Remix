# R13 plan: less RAM and VRAM, with budgets that scale with the computer

Status: **approved** by the user (2026-11-03), with the answers below. Claude does the work itself:
the main session plus Claude subagents running in parallel. Codex is not used in R13.

## The user's words (2026-11-03, verbatim)

The request:

> Yes, plan both the RAM the VRAM ideas. Optimize the RAM and VRAM use of the games to enhance its
> accessibility on lower end computers.

The approval, after reading the draft (kept in the main checkout's `out/r13/R13-plan-draft.md`):

> Combine the unfinished optimization for Smaller maps and Reuse across versions to R13. In R13, don't
> use Codex, do everything yourself. You may run Claude subagent in parallel.
>
> For the R13 plan:
> Visible quality on the low tier. Follow recommended path. For First spawn, a short delay is accepted
> for low end computer, keep five most recently used characters if plenty of resource available.
>
> The budget should scale with the user's available compute, down to 8GB VRAM and 16GB RAM as the
> minimum hardware, we don't support anything lower than this. The 16GB VRAM and 32 GB RAM as the
> recommended and everything should run smooth. Don't enforce 8GB budget on a 16GB card. For users
> with more advanced hardware, more could be kept in memory.
>
> Additionally: there is a related bug out\r12\lag\lag-report.md
> Please proceed with R13. Push to GitHub and Workshop when you finished.

What the answers mean here:

- **Visible quality:** R13 changes memory only (budgets, caches, copies, what is loaded when). It
  changes no rendering setting that can be seen, on any tier.
- **First spawn:** on a minimum computer a character loads when it is first used, which may take a
  moment. Where memory is plentiful, the five most recently used characters stay ready.
- **Budgets scale** with the computer's VRAM and RAM (below). Nothing is sized for 8 GB on a larger
  card; larger computers keep more.

## Hardware profiles and budgets (R13-C, ADR 0101)

The loader reads the largest NVIDIA adapter's dedicated VRAM (as the R6 tier does) and the total
physical RAM, and picks a **memory profile**. Windows reports slightly less than the installed size,
so the thresholds leave a margin.

| Profile | VRAM | RAM | Meaning |
|---|---|---|---|
| below minimum | under 7.5 GiB, or | under 14 GiB | Unsupported. Runs with the minimum budgets; the RTX status line says the computer is below the minimum |
| minimum | 7.5 GiB or more | 14 GiB or more | 8 GB / 16 GB |
| recommended | 15 GiB or more | 28 GiB or more | 16 GB / 32 GB: everything should run smoothly |
| high | 23 GiB or more | 56 GiB or more | 24-32 GB / 64 GB: keeps more in memory |

Budgets per profile:

| Budget | minimum | recommended | high | Who applies it |
|---|---|---|---|---|
| Characters kept ready (most recently used) | 0 | 5 | 10 | hotloader (R13-A) |
| Their material archives, at most | - | RAM / 10 | RAM / 10 | hotloader (R13-A) |
| GPU memory for idle game textures before release | VRAM / 4 | VRAM / 4 | VRAM / 4 | runtime (R13-B) |
| CPU copy of a game texture once it is on the GPU | released | kept | kept | runtime (R13-B) |
| Replacement textures | Remix's own budget, made to follow the live VRAM budget (R13-B) | | | runtime (R13-B) |

- The profile is independent of the R6 performance tier, which stays as it is.
- `remix.memory_profile` in `native-loader\config.json` overrides the choice: `auto` (the default),
  `minimum`, `recommended` or `high`. This is also how tests run the minimum budgets on this machine.
- The loader records its choice in `garrysmod/data/native-loader/status.json` as
  `activation.memory`:

  ```json
  {"profile": "recommended", "source": "auto", "reason": "...", "vram_mib": 16376, "ram_mib": 32605,
   "warm_characters": 5, "warm_mib": 3260, "managed_texture_budget_mib": 4094,
   "release_host_copies": false}
  ```

- It passes the runtime's two settings in a DXVK layer it writes, as it does for the low tier:
  `d3d9.managedTextureBudgetMiB` and `d3d9.releaseManagedHostCopies`.
- The companion's RTX menu shows the profile beside the performance tier.

## The lag report

`out/r12/lag/lag-report.md` in the main checkout (git-ignored). In the
field game on 2026-11-03 at 09:41 UTC, 14.35 GB of game textures became GPU-resident within
30 seconds, while a manhack was spawned. The driver went 2.5 GB over its budget and the game
stuttered until it was restarted. Replacement textures held 10.4 GB, and system commit was at 97.5 %.
Its four fixes map to R13 as follows:

1. Find what touched every registered character's textures: R13-A (it reproduces the trigger first).
2. Release idle GPU images of game textures: R13-B.
3. Do not load unspawned characters: R13-A.
4. Bound replacement textures: R13-B.

## Tasks

| Task | What | Who | Worktree / branch | ADR |
|---|---|---|---|---|
| R13-M | Compact imported game maps; reuse across versions (R12-B3's items 2 and 3) | Claude subagent | `out/worktrees/r13-maps` / `r13-maps`; fixes `out/worktrees/r12-fixes` / `claude/r13-maps` | 0098 |
| R13-A | Load a saved character when it is first used; keep the most recently used ready; the lag trigger | Claude subagent | `out/worktrees/r13-hotloader` / `r13-hotloader` | 0099 |
| R13-B | Runtime: one copy of each game texture, release of idle GPU images, a host-memory account, replacement textures within the live budget | Claude subagent | `out/worktrees/r13-runtime` / `r13-runtime`; runtime source `out/worktrees/r12-vram/out/runtime-src` / `claude/r13-runtime` | 0100 |
| R13-C | Loader: hardware profiles and budgets; the memory measurement tool; the lower-end guide | Claude (main) | `out/worktrees/r13-int` / `r13-int` | 0101 |

The three subagents run at once. Claude reviews each, merges them into `r13-int`, measures,
publishes and checks the field game. Each task ends with `docs/handover/R13-<X>-report.md`.

**The copied library.** `out/r13/field-cache` in the main checkout is one read-only copy of the
field's character library (57 approved characters, 218 rigs, 3,113 files, 21.2 GB; every file's
SHA-256 matched; index `out/r13/field-cache-files.json`). Copy what you need from it into the PoC
under the lock and restore the PoC afterwards. R12-C's
`out/worktrees/r12-vram/out/r12-vram/lab.py` shows one way.

### R13-M: compact imported game maps, reuse across versions (fixes)

The brief is [R12-B3](R12-B3-game-maps-budget-formats-reuse.md), items 2 and 3, with its acceptance.

- **Item 1 shipped** in the hotfix. Game maps no longer count toward the 1 GiB, and a refusal logs
  one clear warning: fixes `26aec12` on `codex/r12-hotfix`, in `main` at `8489b88`. What remains of
  item 1:
  - The Imported game PBR panel shows the refusal line instead of "DDS publication failed".
  - A family stopped halfway completes on its next pass.
- **Start** from a new fixes branch `claude/r13-maps` at `codex/r12-hotfix` in
  `out/worktrees/r12-fixes`.
- **Codex's unfinished R12-B3 work** is on `codex/r12-b3-wip` (`44559f4`). It is based on the shipped
  `026708a`, not on the hotfix, and was never built or tested. Read it critically: keep what is right
  and rewrite the rest.
- **Build** with a full rebuild, as the hotfix did. The project file is
  `out/worktrees/r12-pbr/out/r12-b/build/gmcl_RTXFixesBinary.vcxproj` (MSBuild
  `/t:Rebuild /p:Configuration=ReleaseWithSymbols /p:Platform=x64 /p:VCToolsVersion=14.44.35207 /p:WindowsTargetPlatformVersion=10.0.26100.0`).
  Check that it compiles your branch's sources.
- **Deliver** one import of the DLL into `packages/fixes`, then refresh the GPL source copy in
  `packages/fixes/licenses/oversized-skinning/autopbr`. The main checkout's
  `out/r12/hotfix/refresh_source.py` shows how.
- **Measure** for the round: replacement-texture VRAM before and after for the same characters, and
  bytes per family.

### R13-A: load a saved character when it is first used (hotloader)

Today `ReadyActor` (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/actors.lua:88-103`) mounts and
precaches every saved NPC and player-model character when a map starts. Source then loads every
library character's model and textures. R12-C measured 12.4 GB of their textures with nothing
spawned, and patch 0022 keeps only their CPU copies.

1. **The lag trigger first.** Reproduce it on the PoC with the copied library and the current
   package:
   - Record game textures with the runtime's telemetry before and after each action: spawn a
     manhack from the NPC tab, open the NPC tab, open the hotloader menu, approve or import a
     character.
   - The field wrote the hotloader's `names/assets` and `approved.json` just before the jump, then
     two bullet-break-simulator mesh caches.
   - Find what made Source give every registered character's textures GPU memory, and fix that path
     wherever it is (hotloader, another add-on, or the runtime: then tell Claude).
2. **Load on first use.**
   - Publish NPC-tab and player-model entries from validated metadata (carrier on disk, identity
     matches).
   - Prepare a character (mount, precache, metadata checks) immediately before its first real use:
     a spawn from the hotloader menu or the NPC tab, `SetModel` from tools, saves and dupes, and the
     player's own model when they spawn. Clients must have the carrier before the entity needs it:
     no error model and no "missing model" error, in single player and multiplayer.
3. **The ready set.**
   - Keep the most recently used characters ready at map start, as today: by spawn or use time,
     persisted in the hotloader's data.
   - Read the count and the archive cap from `native-loader/status.json`
     (`activation.memory.warm_characters`, `warm_mib`, above). With no such file, keep none.
   - A ConVar overrides both for tests.
4. **Menu icons** must not load the 3D model of characters that are not ready. Use a cached 2D
   image, or the metadata.
5. **After removal.** Source keeps a model and its textures until the map changes. Find out whether
   anything safe can release them earlier, and report what holds them. R13-B releases their GPU
   memory.
6. **Keep:** R10-H's NPC entries after a map change
   ([ADR 0090](../decisions/0090-ready-carriers-before-actor-publication.md)), R12-A's delete and
   re-import ([ADR 0094](../decisions/0094-reimported-carrier-metadata-and-state.md)), saves and
   dupes, player models, multiplayer clients, R12-D's eye-white choices.
7. **Measure** on the PoC with the copied library, against the current package:
   - RAM (private and working set) and game textures with nothing spawned.
   - The first-spawn delay for a cold and a ready character.
   - Every role and route: NPC tab and hotloader menu; NPC, ragdoll, player model; after a map
     change; from a save.

Lua changes reach `packages/model-hotloader` through `tools/inputs.py import`, as R12-A did. Tests
go in `tools/tests` (LuaJIT harnesses, as `test_mmd_reimport.py`).

### R13-B: the runtime's memory (one copy, release, account, replacement budget)

Read [runtime/README.md](../../runtime/README.md) and patches 0021 and 0022 (R12-C,
[ADR 0096](../decisions/0096-demand-loaded-character-classification-and-memory-census.md)).

- **Source and build.** R12-C's runtime source with a built tree is
  `out/worktrees/r12-vram/out/runtime-src` (fork commit `fc62f44f` = patch 0022;
  `_CompRelease_x64`). Its setup and test commands are `setup_runtime.ps1` and `test_runtime.ps1`
  beside R12-C's evidence in `out/worktrees/r12-vram/out/r12-vram`. Work on a branch
  `claude/r13-runtime` there.

1. **Account.** Extend the opt-in census (patch 0021) to the runtime's host memory, by memory type
   (device-local, host-visible, cached, coherent) and purpose: texture CPU copies, buffers, staging
   and upload, Remix's own. Identify the field's idle census, `out/r13/field/vm-idle.json`: 17.3 GB
   read-write and 11.0 GB write-combined committed memory, mostly in 128 and 256 MiB blocks.
2. **One copy.** `d3d9.releaseManagedHostCopies` (and `DXVK_RELEASE_MANAGED_HOST_COPIES`): once a
   static managed texture's data is on the GPU, free its CPU copy. A later lock reads it back from
   the GPU, as DXVK's `evictManagedOnUnlock` path does.
3. **Release idle GPU images.** `d3d9.managedTextureBudgetMiB` (and
   `DXVK_MANAGED_TEXTURE_BUDGET_MIB`; 0 = off). When static managed textures hold more GPU memory
   than the budget, release the least recently used images not used for a while (choose and
   justify the idle time). Keep their data, reading it back first if the copy was released, so the
   next use uploads them again through patch 0022's path.
   - Remix may still hold a released image; its memory goes when Remix lets go. Verify that.
4. **Both options default off.** The loader turns them on (R13-C).
5. **Replacement textures.** Find how Remix's texture manager sets its budget
   (`rtx.texturemanager.budgetPercentageOfAvailableVram` and the fixed budget) and whether it
   follows the driver's live budget when other memory grows. In the lag report it kept 10.3 GB
   while game textures rose 14 GB and the driver went over budget. Make replacement textures give
   way under real pressure (demote streamed mips, release unused ones) without changing what a
   computer with free memory shows.
6. **Other large consumers** the account finds: bound them only where measured and safe.
7. **Must keep:**
   - Texture hashes, including `rtx.recomputeTextureHashOnWrite` after a later write.
   - Device reset, Remix captures, and the fixes' texture tracking.
   - Patch 0022's behaviour.
   - Visuals.
8. **Tests and delivery.**
   - The GPU test host `tools/qa/managed_texture_probe.cpp` proves exact pixels and hashes through
     upload, the copy released, a read-back lock, a rewrite, release and re-upload, against the
     original runtime.
   - Runtime unit tests and PoC sessions with the copied library: memory before and after, and no
     hash or visual change.
   - New patches `0023-...` in `runtime/patches`, `runtime/README.md` and `base.json` as their
     conventions say, and one runtime import through `runtime/build_runtime.ps1`.

### R13-C: hardware profiles, measurement, guide (loader; Claude)

- The profile and budgets above, in the loader core with unit tests, status.json, the layer and
  the companion's line.
- **A memory measurement tool** in `tools/qa`, made from `out/r13/ram_sampler.ps1` and
  `vm_census.py`. It records RAM and the runtime's VRAM statistics for one session.
- **The standard lower-end run:** the PoC at 1920x1080, the low tier, `remix.memory_profile =
  minimum`, the copied library, with and without Workshop add-ons. Plus a recommended run at
  2560x1440. Measured before R13 and after integration.
- **Goals** with the copied library (targets; the report says what was reached and why):

  | | Field before R13 (4K) | minimum run | recommended run |
  |---|---:|---:|---:|
  | Committed at idle | 28.6 GB | under 12 GB | under 20 GB |
  | Working set at idle | 18.0 GB | under 8 GB | under 14 GB |
  | GPU memory in use, two characters spawned | 8.4 GB | under 6.5 GB | under 13 GB |

- **A lower-end guide** in the player README: what costs memory (library size, Workshop
  subscriptions, resolution, tier), the profiles, and the overrides.

## Rules for every task

As in [R12-plan.md](R12-plan.md#rules-for-every-task), with these changes:

- **No Codex.** Commit with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Subagents
  never push, merge or publish; Claude merges and publishes at the end.
- **The PoC lock.** Create `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock`
  exclusively before changing or launching the PoC. Wait and retry if it exists, and never remove a
  lock you did not create. Restore the PoC exactly and release the lock after each hold.
- **The field game is a test session**: end it when a test needs the GPU. Many field games are
  automated validation sessions.
- `E:\G\Upload` is read-only. Never read the user's console logs, only your own session's part.
- **Shared docs** take additive edits only: CHANGELOG under a new `### R13` heading, ROADMAP,
  RESEARCH, TESTING, `docs/decisions/README.md`, `docs/handover/README.md`.
- One import per binary. `tools\test.ps1 -Config Release` passes before your last commit.

## After R13

When R13 is merged, pushed and published and the field check is done, its report says
`Status: **done**`. The scheduled task `r14-after-r13` waits for that line on `origin/main`, then
starts R14: the user's items 41 and 5, kept verbatim in the task.
