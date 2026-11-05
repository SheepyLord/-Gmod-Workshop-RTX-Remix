# 0111: Content packages come only from subscribed Workshop items

- Status: Accepted 2026-11-05 (amends [ADR 0027](0027-content-packages-from-any-subscription.md)
  decision 1: "every other installed Workshop item" becomes every other installed item that an account
  on this computer subscribed to)
- Decided by: the user, after the pre-release review's H2 ([R19-review.md](../handover/R19-review.md)):
  "All real findings, then test and publish a new release on Github and workshop" (2026-11-05), with the
  fix the [R19 plan](../handover/R19-plan.md) set out; Claude choosing how
- Builds on: [0027](0027-content-packages-from-any-subscription.md) (content packages without the
  allowlist), [0025](0025-unsubscribe-removes-the-package.md) (an unsubscribe removes the package),
  [0009](0009-startup-deployment-last-good.md) (keep-last-good). It narrows what deploys without the
  allowlist; it loosens nothing ([AGENTS.md](../../AGENTS.md) rule 4).

## Context

- **What ADR 0027 meant and what the code did.** ADR 0027 opened content packages to every *subscribed*
  Workshop item. Discovery took every item *installed* in the library's `workshop\content\4000` whose one
  `.gma` lists `native/manifest.json`, and never read whether anyone subscribed.
- **Installed is not subscribed.** GMod's client Lua `steamworks.DownloadUGC(id, callback)` installs an
  item there without a subscription (measured in M6: [RESEARCH.md](../RESEARCH.md) section 14,
  [ADR 0015](0015-workshop-route-for-native-packages.md) step 3). Any server's client Lua may call it, and
  servers do, to stream their content. On this machine Steam's record listed 817 installed items on
  2026-11-05; 40 of them had no subscriber.
- **What a server could do with that.** At the player's next start the loader deployed such an item's
  Lua add-on into `garrysmod/addons`, where it runs in every later single-player or hosted game, and its
  Remix mod into `rtx-remix/mods`, which every RTX session loads. Together with the runtime's DDS reader
  (the review's H1), joining a server led to memory corruption at every later start.
- **What Steam records.** `appworkshop_4000.acf` keeps, under `AppWorkshop`, `WorkshopItemsInstalled` and
  `WorkshopItemDetails` (RESEARCH.md section 22). A subscribed item's details carry `subscribedby`: the
  accounts on this computer that subscribed, decimal account ids separated by commas (this machine's
  record holds one to four per item). An item downloaded without a subscription is in both sections,
  and its details have no `subscribedby`. The Steam API, which could say the same, is not initialised
  when the bootstrap runs ([ADR 0025](0025-unsubscribe-removes-the-package.md)).

## Decision

1. **New content needs a subscription.** A content-only candidate (an item not in `allow.workshop`) is
   taken only when Steam's record has a `WorkshopItemDetails` entry for it whose `subscribedby` names at
   least one non-zero account id. An installed item without one is not a candidate at all, and is not
   listed as skipped: a server's download was never the player's choice.
2. **A deployed one without a subscription is removed** like an unsubscribed item (ADR 0025): no
   keep-last-good hold, no rollback copy, its files deleted, what it had taken over put back. Its reason
   reads "not subscribed: Steam has it only because the game or a server downloaded it (or it was
   unsubscribed); content packages come only from subscriptions, so a package it deployed is removed".
   This covers a package an older loader deployed from a downloaded item, and the minutes after a real
   unsubscribe in which Steam has dropped the item's details but not yet its files.
3. **No record, no verdict.** When `appworkshop_4000.acf` is missing or unreadable, has no `AppWorkshop`
   or no `WorkshopItemDetails` section, or gives an item a details entry or a `subscribedby` value that is
   not what Steam writes, that item cannot be shown to be subscribed or not: no installed item becomes new
   content on its strength, and every deployed content package keeps its candidate as before. One bad read
   must not remove packages and deploy them again. ADR 0025's rule (an item the record lists nowhere, its
   folder gone) is unchanged.
4. **Unchanged:**
   - allowlisted items (`allow.workshop`) need no subscription;
   - `"subscribed_content": false` still turns content packages off;
   - content packages still hold content only (ADR 0027 decision 2);
   - a subscription by any account of this computer counts. Without the Steam API the loader cannot tell
     which account is signed in, and either way it is a person's choice, not a server's.

## Consequences

- A server can no longer choose content that the loader deploys on a player's machine. A player who
  wants a server's PBR package subscribes to it.
- Packages an older loader deployed from downloaded items go at the first start of loader 0.14.0.
- The change is in `winmm.dll`: players get it with the release zip, not with the Workshop item.
- An unsubscribed content package goes when Steam drops the item's details, minutes after the
  unsubscribe, rather than when Steam deletes its files at the next launch from Steam.
- Tested in `loader/tests/test_discovery.cpp` (the value's rules; subscribed, downloaded, `"0"`, no
  details, a value Steam does not write, still downloading; deployed and no longer subscribed; a missing,
  broken and detail-less record), `test_deploy.cpp` through `nl::startup::prepare` (the bootstrap's own
  entry point), and `loader/proxy/tests/activation_integration.py` through the real `winmm.dll`.

## Alternatives considered

- **Keep "installed" and rely on the content-only rules.** A Lua add-on and Remix mods count as content,
  and the review showed both reach code execution (the add-on's Lua; the runtime's DDS reader).
- **Ask the Steam API** (`ISteamUGC::GetItemState`): it is not initialised when the bootstrap runs, and
  starting it early as app 4000 would change how Steam sees the game (ADR 0025).
- **Require only a `WorkshopItemDetails` entry.** A downloaded item has one too, without `subscribedby`.
- **Treat a missing or broken record as "nothing is subscribed".** A read that failed for a moment (Steam
  rewriting the file) would remove every content package and deploy it again at the next start.
