# 0025: Unsubscribing from a Workshop item removes its package completely

- Status: Accepted 2026-10-29
- Decided by: the user ("Unsubscribing from [3829070317] does not uninstall RTX Remix: it keeps
  working, it just stops getting updates. Please also make sure if user unsubscribe, RTX-Remix and all
  relevant content in the package is uninstalled"), Claude choosing how
- Builds on: [0007](0007-transactional-deployment.md) (two generations kept),
  [0009](0009-startup-deployment-last-good.md) (keep-last-good at start-up)
- Amends 0009 point 5: an unsubscribed Workshop item is an intentional removal, like one disabled in
  `addonnomount.txt`. Amends 0007 point 7: a package removed this way keeps no rollback copy.

## Context

- **What the loader saw.** Unsubscribing leaves the package deployed. Once Steam deletes the item's
  folder, the item looks to discovery like a download in progress: an allowlisted source that is
  missing. Keep-last-good (0009) then keeps the deployed generation, so RTX Remix keeps running from
  `native-loader\packages\` and the root files stay in place, with no updates.
- **What Steam does** (measured with a hidden test item, [RESEARCH.md](../RESEARCH.md) section 22):
  - Subscribing adds the item to `WorkshopItemDetails` in `appworkshop_4000.acf` at once, then to
    `WorkshopItemsInstalled` with its folder once the download is done.
  - Unsubscribing changes nothing on disk for at least 90 s. Minutes later the item leaves
    `WorkshopItemDetails`, while `WorkshopItemsInstalled` and the folder stay.
  - When the game is next launched from Steam, Steam removes the item from both sections and deletes
    its folder before `gmod.exe` starts (1.2 s after the launch request; the game ran at 2.0 to 2.8 s),
    also when the launch comes seconds after the unsubscribe.
- **Telling the cases apart.** A first download lists the item in `WorkshopItemDetails`. An update
  keeps it in `WorkshopItemsInstalled`. Only after an unsubscribe is the item in neither section,
  with its folder gone.
- **The rollback copy.** The deployer keeps the previous generation (0007): a removed package's payload
  folder stays in `native-loader\packages\`, and its root files go to `native-loader\backup\<generation>\`.
  GMod loads neither, but for the RTX package that is over 1.5 GB left behind, and rolling back to an
  item the user unsubscribed from makes no sense.

## Decision

1. **Discovery marks an item unsubscribed** when all of these hold:
   - `appworkshop_4000.acf` was read and has an `AppWorkshop` section;
   - the item is in neither `WorkshopItemsInstalled` nor `WorkshopItemDetails`;
   - its folder is gone.

   The reason reads "not subscribed". Without a readable record nothing is marked: a missing or broken
   `appworkshop_4000.acf` still counts as a source that is only missing.
2. **Start-up removes the package.** An unsubscribed item is an intentional removal, so keep-last-good
   does not hold the package back, exactly as for an item disabled in `addonnomount.txt`.
3. **No rollback copy.** A package the plan removes because its item was unsubscribed is left out of
   the previous generation the journal keeps. Its payload folders, and the root files the removal moves
   aside, are therefore retired and deleted in the same run's clean-up, older generations' copies
   included. When it was the previous generation's only package, there is no previous generation, so
   `nlctl rollback` refuses. The report notes each such package.
4. **Unchanged rules:**
   - Files the user changed after the loader placed them stay where they are (AGENTS.md rule 3), as
     on every removal. `user.conf` is never the loader's.
   - Files GMod or Remix create while running (logs, caches, `config.cfg`) are not the loader's either.
   - Another source of the same package (a local archive, a development folder) is not affected.
   - Subscribing again deploys the package afresh.

## Consequences

- **When it happens.** The package goes at the first start after Steam has deleted the item, normally
  the next launch from Steam. Started any other way before that, the game keeps the package for that
  session, because the folder is still there.
- **Safe to interrupt.** The removal is an ordinary deployment transaction, followed by the clean-up
  that already deletes retired generations. It is tested with a kill or a failure at every single
  change (`nl_tests_faults_unsubscribe`, [TESTING.md](../TESTING.md)).
- A Workshop item that is gone from the allowlist, or disabled, is still kept for a rollback; only an
  unsubscribe deletes at once.

## Alternatives considered

- **Use the Steam API to ask whether the item is subscribed.** It is not initialised when the bootstrap
  runs, which is before the engine (0008), and starting it early as app 4000 would change how Steam
  sees the game.
- **Treat a missing folder as removed.** Steam deletes and re-creates folders while it updates items,
  so a running update would uninstall RTX: the case keep-last-good exists for (0009).
- **Remove on unsubscribe, but keep the rollback copy.** The files would stay on disk until some later
  deployment retired them, which is not the uninstall the user asked for.
