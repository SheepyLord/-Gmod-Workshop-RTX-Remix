# 0007: Deployment is one journaled transaction per run, rolled back on failure

- Status: Accepted 2026-10-27; revised the same day, before it was merged, after an independent
  review (per-file payload moves, clean-up that never stops a command, links, ASCII paths, the hold)
- **Superseded in part by [0035](0035-restore-automatically.md)** (2026-10-29, the user): decision 5's
  rules for a changed `replace-owned` file (now put back, the changed copy kept) and for someone else's
  file at a `replace-owned` target (now taken over and put back later). The rest of this record stands.
- Decided by: Claude, implementing M3 within the plan the user approved on 2026-10-27
- Refines: [ADR 0004](0004-runtime-in-versioned-folder.md) (the payload folder's name, below)

## Context

The deployer writes into a game folder that is mostly Steam's and partly the user's. It must never
change a Steam file (AGENTS.md rule 2) or a file the user edited (rule 3). It must also leave a
consistent install whenever it stops: killed, crashed, or out of power. From M4 it runs at every
start-up inside `gmod.exe`, so a run with nothing to do must cost nearly nothing. M4 needs runtime
versions it can switch and roll back. M7 needs an uninstall that leaves the install verifying as
vanilla.

On one NTFS volume a rename is atomic, and `MoveFileEx` with `MOVEFILE_WRITE_THROUGH` returns only
once the rename is on disk. Ending a process closes its handles but keeps what it wrote in the
cache. Antivirus scanners open newly written DLLs for a moment, so a rename or delete right after a
write can fail briefly. Measurements are in [RESEARCH.md](../RESEARCH.md) section 9.

## Decision

1. **One transaction per run** produces a new *generation*. The order is: lock → undo an unfinished
   transaction → clean-up → plan → **stage** → write the intent (`pending`) to the journal → **move**
   into place → **commit** the new journal → clean-up.
2. **Staging** is `native-loader\staging\<transaction>\`, on the same volume as every target, so
   placing a file is a rename. Each file, payload files included, is moved on its own, and the
   journal records its hash. Every check happens while staging: each file's size, its GMA CRC-32 and
   the manifest's SHA-256 (Windows CNG). A package that fails a check, or whose target belongs to
   someone else, is re-planned as broken (ADR 0006), so a working lower-precedence copy takes over.
   Nothing in place has changed at that point.
3. **The journal** `native-loader\state.json` (schema 1, [ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md))
   records every file the loader placed, with its SHA-256, size and time. It is written atomically
   (temporary file, flush, rename). A journal that does not parse stops the deployer.
4. **Recovery rolls back.** The next run undoes a `pending` transaction step by step in reverse.
   - Each undo first checks whether its step happened, and checks the hash before moving a file
     back, so recovery can itself be interrupted and run again.
   - What it cannot put back is not forgotten. A copy it had moved into the loader's own folders,
     whose old place is now taken, is retired. A folder it made that now holds someone else's file
     stays listed.
   - A transaction that fails while running is undone the same way, at once.
5. **Ownership** (rule 3):
   - The loader replaces or removes only files the journal records, and only after a full SHA-256
     shows they are unchanged.
   - A changed file is left in place, reported, and no longer touched.
   - A file at a target that the loader did not place blocks its package. If it already has the
     right content it is *adopted* instead: recorded, never moved or deleted.
   - `create-only` files are never replaced, not even by a new version.
   - Folders the loader created are removed once empty; it never deletes a folder that holds files
     it did not place.
   - Nothing is placed, moved or deleted through a link (junction, symbolic link) anywhere below the
     game folder; a file whose path leads through one is left alone and no longer tracked.
   - The package paths it deploys are ASCII ([PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md)), so its
     case-insensitive comparisons agree with NTFS.
   - A file adopted earlier that the loader later had to put back itself (the user had deleted it)
     is the loader's from then on, also after a rollback.
6. **Payload folders** are `native-loader\packages\<id>\<version>_<generation>\` and are never
   modified once placed.
   - A package version keeps its folder for as long as the folder is intact.
   - A changed package (or a damaged folder) gets a new folder.
   - This refines ADR 0004's `<id>\<version>\`. The plan named folders by a manifest-hash prefix; the
     generation number makes every name unique, so a damaged copy can be replaced without a name
     clash. The journal records which manifest each folder holds.
7. **Two generations are kept.** The previous generation's payload folders stay, and the root files
   the current generation replaced or removed are kept in `native-loader\backup\<generation>\`.
   Anything older is retired, and its files are deleted only while still unchanged. `rollback` is a
   transaction back to the previous generation. Afterwards apply *holds* it: while the plan names
   exactly the packages it rolled back from, nothing is deployed. That comparison uses the plan
   before any package is re-planned as broken, so a package that cannot be deployed cannot lift the
   hold. The hold ends as soon as the plan names anything else. Rolling back twice returns to where
   it started.
   - A file that was missing when a new version was placed has no kept copy, so the previous
     generation leaves it out rather than claim one.
   - **Clean-up never stops a command.** What it cannot delete now (open in another program,
     read-only) stays listed with a note, and the next run tries again. `uninstall` keeps the journal
     until everything it lists is gone.
8. **One deployer at a time.** An exclusive handle on `native-loader\lock` excludes a second
   deployer; Windows closes it however the process ends. Outside the game (`nlctl`), the deployer
   refuses while this folder's `gmod.exe` runs, or while a `gmod.exe` runs whose folder cannot be read.
9. **No-op runs write nothing.** An unchanged plan, with unchanged files (size and time), makes no
   change at all, not even to the journal. The one exception is the run that ends a hold, which
   records that.
10. **Durability:**
    - staged files are flushed before the intent is written;
    - renames are write-through;
    - the journal is flushed before its rename;
    - renames and deletes retry for about two seconds while another process has the file open;
    - the journal accepts the loader's own paths up to 4,096 bytes, so a package path of up to
      1,024 bytes with a folder of the loader's in front always fits.

## Consequences

- An interrupted or failed run leaves the old state, or (once committed) the new state after the
  next run's clean-up. The tests interrupt every single change of a first deployment, an upgrade, a
  rollback and an uninstall, both in process and by killing a real process
  ([TESTING.md](../TESTING.md)).
- **Disk space:**
  - Keeping a rollback target costs a second runtime folder: about 1.9 GB for two versions of the
    930 MB runtime.
  - During an update, up to a third copy is staged, about 2.8 GB in total.
  - Free space is checked before staging.
- **Plan and disk stay in step.** The deployed state follows the plan: a package that stops being
  planned is removed (kept for rollback). M4 must decide what to do when a Workshop item is missing
  only for a moment, for example while Steam updates it during start-up.
- **Rollback can refuse.** It needs the previous generation's payload folders and backups intact, and
  refuses (changing nothing) if they are not, or if a file it must restore is in the way.
- **Status files.** `nlctl status` compares the disk with the journal; changed files show up there and
  in every report.

## Alternatives considered

- **Swap one whole folder per generation:** impossible for root files, which live among Steam's
  and the user's files, not in a folder of their own.
- **Recovery by rolling forward:** finishing an interrupted transaction needs its staged data to
  survive and be trusted; undoing it needs nothing but the journal and is simpler to make
  idempotent.
- **Hard links instead of moves:** NTFS only, and the journal and recovery would still be needed.
- **Back up and replace files that belong to someone else:** loosens rule 3; it would need a
  decision the user agrees to (M7 may bring one up for hand-installed RTX fixes).
- **Hash every deployed file on every run:** about 1-3 s for a runtime at each start-up; size and
  time first, with a full hash before any file is moved or deleted, gives the same safety.
