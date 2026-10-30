# 0042: Archive an older Remix installation before deploying our shipment

- Status: accepted
- Date: 2026-10-30
- Decision maker: the user, asking to back up and replace a previous Remix installation without
  assistance; use a new Xenthio installation for testing because RTX_c has already been replaced.

## Context

RTXLauncher puts Remix directly in bin/win64, edits four engine DLLs, and installs a custom shader,
loose modules, addons, configs and five replacements of stock Lua/image files. Ordinary package
deployment only displaces overlapping root targets. It would leave an old D3D proxy, obsolete Lua
and disk patches active. Its normal uninstall-original restoration would also reactivate them.

## Decision

Loader 0.8.0 plans migration only alongside an active, allowlisted RTX runtime. Detect the legacy
runtime by a validated PE export named remixapi_InitializeLibrary, using bounded sparse reads and
never loading old code. Plain DXVK, strings in files and our versioned runtime are not triggers.
The path catalog describes the pinned Xenthio layout; no arbitrary engine paths become package
targets and the native allowlist stays unchanged.

Archive recognized runtime files, the five legacy addon roots, base_mod, loose fixes modules and
startup utilities, root rtx.conf/dxvk.conf, and exact factory launcher configs. Include obsolete or
edited files inside those known roots. Exclude current loader-owned paths, every user.conf,
unrelated addons, other mods, generated ~gmod_topbr, data and custom configs. Report retained
custom configs because their RTX commands may still affect play.

The ten replaced depot files are identified by exact legacy hashes. Restore only exact known stock
hashes from Steam's registered install, launcher backup_patches directories, verified sibling .bak
files, or an explicit nlctl --legacy-source root. No game bytes are committed or downloaded by the
loader. Unknown depot edits, links or missing recovery sources stop before migration mutates files.
Unmodified gmod.exe/client.dll/server.dll hashes confirm the target build before any stock recovery.
An explicit recovery root replaces automatic Steam-source discovery; local backups remain checked.
This narrowly supersedes rule 2's prohibition on disk writes for already modified legacy targets;
an intact depot file is never patched or replaced.

Stage and verify the complete incoming shipment and stock recovery first. Then archive originals
and install replacements in the existing durable deployment transaction. Keep a SHA-256/size
manifest at native-loader/backup/legacy/<transaction>/manifest.json. A crash before commit restores
the original installation. A committed archive is permanent recovery material, outside the two
package generations; normal rollback, RTX-off, unsubscribe and uninstall do not reactivate it.
If uninstall reset the journal's transaction counter, a numeric suffix selects a new archive;
an earlier archive is never overwritten.
If an earlier RTX-off deployment already kept old addon files as ordinary uninstall originals,
move those verified copies into the permanent archive and remove their automatic restore records.
Their manifest entry includes restore_target, naming their original game-relative location.
An interrupted rollback also never retires an irreplaceable legacy backup when another file has
taken its old path. Source hashes and links are checked again immediately before transaction moves.

## Consequences

Fresh supported legacy copies migrate automatically at first startup. CLI apply --dry-run shows
the archive and stock-restore operations. Offline installs whose six overwritten files have no
vanilla originals cannot be fully recovered from launcher backups alone; migration fails safely
with the exact missing file and recovery-source option. Other GMod builds or unknown native edits
need Steam verification before this bounded migration can proceed. The backup is kept for manual
recovery: with the game closed and this loader uninstalled, verify its manifest and copy the
archived files to their original relative paths. Never overwrite user.conf or newer personal files.
For a saved uninstall original, use its manifest restore_target rather than its backup-container path.

## Alternatives considered

- Overwrite only package targets: leaves old DLLs, patches and Lua active.
- Keep the old files as normal uninstall originals: silently reactivates the old installation.
- Guess stock bytes, reverse arbitrary native patches or trust a build-number string: risks mixing
  engine versions or destroying edits. Hash-verified restoration is reproducible and bounded.
- Bundle Steam game files: unnecessary redistribution and cannot cover every future build.
