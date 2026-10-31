# 0055: The legacy migration never blocks the package

- Status: Accepted. Supersedes in part [0042](0042-legacy-remix-migration.md): "Unknown depot edits,
  links or missing recovery sources stop before migration mutates files"; "Other GMod builds or
  unknown native edits need Steam verification before this bounded migration can proceed"; "Exclude
  current loader-owned paths" (for adopted files); "Source hashes and links are checked again
  immediately before transaction moves" (now the migration's moves only).
- Date: 2026-10-31. Decided by Claude on the R4 review of loader 0.8.0, under the user's instruction
  to decide autonomously ([R4 review](../handover/R4-review.md)).

## Context

The review found that loader 0.8.0's migration could stop every deployment, not only itself: a link
inside a catalogued root (RTXLauncher's "Mount HL2 RTX" fills `garrysmod/addons/mount-hl2rtx` with
symbolic links) made `plan()` throw, and nothing caught it; a GMod update (new stock hashes) with a
leftover Remix runtime threw "Verify this install in Steam first" at every start, which verifying
could not clear; and a game folder reached through a junction failed the link check on its own path
even with no legacy Remix at all. Files an earlier RTX-off deployment had only adopted were treated as
the loader's, so they were neither archived nor replaced.

## Decision

1. A migration that cannot be planned (no verified stock copy, a linked archive folder, an unreadable
   file, a bad `--legacy-source`) is a note; the packages deploy as before 0.8.0, and the next start
   plans it again.
2. Links are never followed or moved: one inside a catalogued root (Mount HL2 RTX's) stays, with a
   note. Links count only below the game root, so a junctioned game folder migrates; a linked runtime
   entry is not Remix. External recovery roots are checked as given (`.` and `..` refused), with no
   link from their volume root.
3. Steam's files are restored all or none. If any differs from stock, the build anchors decide first;
   on another build, beside a change the catalog cannot account for, or with a linked depot path,
   every depot file stays as it is, a note says to verify in Steam, and the rest is archived. A
   missing stock copy skips the whole migration (1), so the old runtime stays detectable and Steam
   verification or `--legacy-source` can complete it.
4. A file the loader only adopted is not the loader's: a legacy one is archived, and the package's copy
   becomes loader-placed.
5. The SHA-256 check just before a move covers the migration's moves only. Package files were hashed
   while staged (a 1.5 GiB re-hash took 0.75 s on a SHA-capable CPU, more without).
6. The archive manifest names a stock copy inside the game folder relative to the game root.

## Alternatives considered

- Archive links as links: undo cannot move them back without new step semantics.
- Restore the recognized subset beside an unknown edit: risks mixing patched and stock engine DLLs.
- Archive the rest when a stock copy is missing: `--legacy-source` could never finish the depot files.

## Consequences

The migration guarantees of ADR 0042 hold where it runs; where it cannot, the user gets RTX as before
0.8.0 and a note, never a loader that stops deploying. Tests: `test_legacy_migrate.cpp`,
`test_legacy_detect.cpp`, `test_deploy.cpp` and the fault CTests `nl_tests_faults_legacy` and
`nl_tests_faults_legacy_stock` (a synthetic catalog, every filesystem operation interrupted and failed).
