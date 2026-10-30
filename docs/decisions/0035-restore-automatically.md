# 0035: Restore automatically: a package's files are put back, and what was in their place is kept

- Status: Accepted 2026-10-29. **Supersedes in part** [0007](0007-transactional-deployment.md)
  (decision 5: a changed file left in place; someone else's file blocking its package; an adopted file
  never moved), [0011](0011-lua-addon-folders.md) and [0023](0023-content-packages-and-modern-house-item.md)
  (an add-on folder or a mod the player already has blocking the package). Amends AGENTS.md rule 3.
- Decided by: the user, on R3-001 ([R3-triage.md](../handover/R3-triage.md)): "Proceed to Restore
  automatically: put the package's copy back at the next start. Everything should respect this
  package. Note, if a loader dll already exist before we start the installation or replacement, back it
  up and restore it when RTX is uninstalled." Claude choosing how. Loader 0.6.0.

## Context

R3-001 ([R3-report.md](../handover/R3-report.md)): a module's `load_first` files (Model Hotloader's
`garrysmod/lua/bin/mmdhl_runtime_win64.dll`) were loaded by path with no check, while the deployer left
a file it had placed and that changed since in place for good (`keep_edited`, also over a new version).
So the loader could itself load native code it never deployed. The runtime's own files were already
checked by size and time before every activation (R1-008, [ADR 0014](0014-r1-hardening.md)).

Until now ([ADR 0007](0007-transactional-deployment.md) decision 5):

- a `replace-owned` file the loader placed and that changed stayed as it was, reported, and was not
  updated again, not even by a new version;
- a file someone else placed at a `replace-owned` target blocked its package, unless it had the right
  content, which was adopted and never moved; a new version at an adopted path blocked the package too;
- `install-loader.ps1` refused to install over a `winmm.dll` that is not the loader.

No Steam depot file is in the four areas packages place files in (`rtx-remix/mods`,
`garrysmod/lua/bin`, `garrysmod/addons`, `garrysmod/data`; [RESEARCH.md](../RESEARCH.md) section 16),
and `bin/`, the game root (`user.conf`) and `garrysmod/cfg` are no area. So a file the loader finds at a
package path is the player's or another mod's, never Steam's.

## Decision

1. **A `replace-owned` path holds the package's file.** At every deployment (every start):
   - **put back:** the loader's copy changed (edited, replaced, also when the package has a new
     version): the package's copy goes in, and the changed one is moved to
     `native-loader/backup/edits/<transaction>/<path>`;
   - **take over:** a file the loader did not place, with other content, or a file it adopted that the
     package now differs from: moved to `native-loader/backup/originals/<path>`, recorded in the
     journal's `originals`, and the package's copy goes in. A file with the right content is still
     adopted.
   - Only the first file the loader takes from a path is its original; another one found there later
     goes to `backup/edits` like a changed copy.
   - The report's changes say `put-back` and `take-over`, and a note says where the file went.
2. **Originals go back** in clean-up once no generation names their path (neither the current one nor
   the rollback target) and the path is free: when a package stops placing the file (two deployments
   later, or at once for an unsubscribed item, which keeps no rollback copy:
   [ADR 0025](0025-unsubscribe-removes-the-package.md)) and at `nlctl uninstall`. The change says
   `restore-original`. One whose kept copy changed or is gone is dropped, with a note. One whose path
   another file has taken stays kept, with a note; after an uninstall the note says to put it back by
   hand.
3. **The loader never deletes** `backup/originals` or `backup/edits`. An interrupted transaction whose
   undo cannot move such a file back leaves it there, noted, instead of retiring it as its own copy.
4. **`create-only` is unchanged:** a create-only file the player changed is theirs, and someone else's
   file at a create-only target is kept.
5. **Dependencies are loaded only as deployed** (`session::deployed_files`, R3-001): a `load_first`
   file is loaded before its module only when the current generation records it and its size and time
   are what the deployer wrote, in RTX sessions and without RTX alike. Otherwise it is left out with a
   session note, and the module loads (or fails) on its own. Size and time, as for the runtime's files:
   the deployment that ran just before has put back any changed copy, and hashing at every start is what
   ADR 0007 rejected.
6. **The bootstrap installer** (`tools/install-loader.ps1`) moves a foreign `winmm.dll`, with the
   `winmm.pdb` beside it unless that is the loader's, to `native-loader/original/` and records their
   SHA-256 in the receipt's `original`; `-Uninstall` puts them back when they still match and their
   place is free. One is kept at a time: a second foreign DLL while one is kept is refused, and so is
   `-Uninstall` while a foreign DLL is in place (the loader is not installed there).
7. **Loader 0.6.0.** The journal gains `originals`, written only when there are some, so an older
   loader reads a journal without them as before (and refuses one with them).

AGENTS.md rule 3 now reads: never touch Remix `user.conf`, and never destroy a file the user edited
(compare hashes first). A package's `replace-owned` file is put back when it changed, and what was in
its place is kept; a `create-only` file the user changed stays theirs.

## Consequences

- What runs is what the package says: a changed or replaced package file, a DLL included, is replaced
  at the next start. A player's change is never lost, but it no longer stays in effect: to keep one,
  they make a package of their own (or the file is `create-only`).
- A player's copy of a bundled add-on, or a mod folder of the same name, no longer stops the RTX
  package: its files at the package's paths are kept aside and come back when the package goes. Only
  those files move; other files in the same folder stay, beside the package's.
- `backup/edits` grows with every put-back and only the player deletes it: `nlctl uninstall` keeps its
  folders and says so, and `install-loader.ps1 -RemoveState` lists the files it leaves. Something that
  rewrites a package file every session would add a copy at each start: such a file should be
  `create-only`.
- A rollback over a take-over brings back the rollback target's files, but not the original: the
  generation rolled back from is the rollback target now and still names the path, so the path stays
  empty until a later deployment drops that generation and clean-up puts the original back.
- The player README no longer asks players to move their copies of the bundled add-ons out first.

## Alternatives considered

- **Keep changed files and refuse to load them** (the triage's other option): the package would stay
  broken until the player found and fixed the file. The user chose the package's copy.
- **Overwrite without keeping:** breaks rule 3; a player's work or another mod's file would be lost.
- **Check dependencies by SHA-256 at every start:** the deployment just before already compares by
  hash before replacing; the extra cost buys nothing against a writer of the folder, who can replace
  `winmm.dll` itself.
- **Move a player's whole folder on take-over:** the journal tracks files, not folders; moving files the
  package does not name would take more from the player than the package needs.
