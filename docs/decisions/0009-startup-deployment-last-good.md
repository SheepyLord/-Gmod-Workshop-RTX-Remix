# 0009: Startup deployment preserves the last good generation when a source fails

- Status: Accepted 2026-10-27. Revised before merge on 2026-10-28 (Claude's review): a failed
  deployment that M3 has undone activates the committed generation (point 7)
- Decided by: Codex, implementing the startup rules the user assigned in the M4 handover
- Builds on: [0003](0003-native-trust-allowlist.md), [0007](0007-transactional-deployment.md),
  [0008](0008-activation-at-startup.md)

## Context

Workshop downloads and development rebuilds can leave an allowlisted source temporarily missing,
invalid or only partly readable. M3's explicit CLI apply may re-plan past a bad source. Doing that
automatically at game startup could remove or replace a working deployed runtime without a user
decision. The game also needs to exclude itself, but no other instance, from M3's running-game check.

## Decision

1. After the M1 log setup, startup reads config, discovers only allowlisted sources, considers and
   plans them, applies one deployment transaction, activates the committed generation, then reports.
   Missing config, disabled config, invalid config or an invalid journal never reaches deployment
   or activation. Nothing deployed is removed for those conditions.
2. Startup supplies its process ID as the sole running-game exclusion. A second GMod from the same
   root defers deployment; the current committed generation may still activate if it has no pending
   transaction. M3's explicit skip-all override remains a separate option for its existing tests.
3. If the deployer lock is held elsewhere, startup deploys nothing. It may activate only a valid
   current generation whose journal has no pending transaction. Normal activation preconditions
   and file-size checks still apply.
4. Startup opts into keep-last-good; the default CLI apply policy is unchanged. If a planned change
   would remove/replace a current package because its still-allowlisted source is unusable, defer
   the whole deployment and keep the committed generation. Check again after staging failures have
   caused a package to be re-planned as broken. No active-file change or new generation is committed;
   own staging is discarded. Normal pending-transaction recovery and retired-file cleanup still run.
5. A source absent from the allowlist is an intentional removal. A Workshop item explicitly disabled
   by addonnomount.txt is also intentional, represented separately from missing/invalid data in the
   discovery candidate. Match Workshop sources by item ID and local/dev sources by normalized paths.
   A healthy source providing the identical package identity does not require deferring other work.
6. M3's rollback hold is checked against the original plan before staging failures are re-planned.
   Startup respects it; it does not immediately redeploy the version the user rolled back from.
7. A caught exception or SEH fault leaves activation undone and the game vanilla. A pending journal
   transaction is recovered by M3 on the next eligible run. A deployment that *reports* failure has
   been undone in process by M3; with no pending transaction left, the committed generation is intact
   and activates as the last good one (`startup::after_deployment`). Report the outcome, generation, change
   count, elapsed time, skipped sources and reasons in the startup log and status file.

## Consequences

- A temporary source failure retains the last working installed version while reporting the fault.
- User opt-outs still remove packages; native trust and all three bootstrap off switches are unchanged.
- A second launch or busy CLI deployer cannot cause a competing deployment in the same game folder.
- With an off switch, the bootstrap is still pure pass-through and writes no new status; readers must
  compare status time/PID with the current game to recognize the previous launch's stale report.
- The keep-last-good checks are tested as pure decisions and against a late archive SHA-256 failure;
  M3 CLI/fault tests continue to exercise their original behavior.
