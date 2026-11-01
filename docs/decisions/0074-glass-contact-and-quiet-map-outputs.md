# 0074: Incoming body contact and map outputs without engine shatter

- Status: Accepted 2026-11-01 as G1-A fix-pass implementation under [0070](0070-glass-overhaul.md).
- Decided by: Codex implementing the user's fix-pass brief. Supersedes the body-contact and
  Shatter-bridge details of [0071](0071-glass-impact-model.md).

## Decision

Require inward normal motion from the body's side, the projected body centre inside remaining
glass, and a plane distance no greater than half the thickness plus the body's oriented half width
(1/32-unit trace tolerance). Keep Touch for NPCs/vehicles and add a player SetupMove hull sweep.
That hook sees the incoming velocity before the mover clips it against frozen pane collision.
It traces only moving players and does not scan idle panes. Defer pane mutation out of callbacks.

Never ask the hidden func_breakable_surf to Shatter or Break. Capture its repeated OnBreak map
keys via EntityKeyValue. At first breakout, copy their raw values with SetKeyValue to an unused
OnUser1–4 channel on that same original and fire FireUser once. Source retains target selection,
delay, fire count, original caller/!self and attacker/!activator. Existing user outputs are reserved.
Native func_breakable glass remains engine-owned.

## Limits and evidence

Source SDK func_breakablesurf.cpp:562–579 plays a break sound and fires inherited OnBreak;
InputShatter:668–715 calls Die and ShatterPane even on a NoDraw brush. Its datadesc:143–172 adds
no OnShatter output. Facepunch documents SetupMove before engine movement, EntityKeyValue for
capturing otherwise unexposed output keys, and TriggerOutput as a scripted-base helper.
See [research](../RESEARCH.md) for primary-source URLs.

If all four user channels are occupied, report that the bridge cannot run instead of invoking
engine fracture. A Lua refresh/save loaded without the original key callbacks, runtime output
changes outside those callbacks, engine cell/health logic and previously fired output history
cannot be reconstructed. Game validation must check real Hammer target/activator/caller/delays,
cleanup and the absence of duplicate sounds/shards; the mocked harness proves routing only.
