# ADR 0090: make carriers ready before publishing actor entries

Date: 2026-11-02. Status: accepted for R10-H, the user's item 33.

## Context

Model Hotloader restores saved NPC/player registrations on every map, but its
old restoration path ignored mount failures and did not explicitly precache
the model on the new server. Mount memoization also trusted a lifetime boolean,
even if the engine removed the underlying mount. Archive visibility and a map's
modelprecache string table have different lifetimes. Publishing the entry alone
does not establish
that this server can spawn it. The controlled baseline did spawn successfully
after map changes; this is a verified readiness gap, not proof of the exact
field error's cause ([report](../handover/R10-H-report.md)).

## Decision

Use one shared `ReadyActor` gate for saved registrations, publication and the
hotloader's own actor factory before creating an NPC. Mount the rig's material
archive and carrier (arms too when present), checking both results. On the
server explicitly precache each model and require `util.IsValidModel` before
adding the NPC/player-model list entry or announcing it to clients. Clients
also require successful mounts before registering an entry.

Reuse mount memoization only while a file supplied by that archive remains
visible. A carrier's caller can additionally require its exact model path,
so another MDL in the same folder cannot satisfy readiness. Re-mount a stale
entry; do not re-mount a still-visible one, which can reload live models on a
listen server. This adds per-map readiness, without per-frame remounts or disk
changes to stock models. Keep approval, NPC classes, limits, undo ownership,
equipment and attachment hooks unchanged.

## Consequences

An unavailable carrier is not advertised as a usable NPC. The hotloader's own
spawn returns its existing mount error before creating an entity. Repeated map
restoration establishes the new server's precache even when package bytes are
already mounted. A Lua regression resets just that table, retains mounted
bytes, and verifies mounting/precache precede publication; failed mounts publish
nothing. Another regression removes visibility after success and checks remount,
failure/retry, the exact requested model and no reload while visible. PoC results
and any unreproduced field behavior remain explicit in
the handover.

## Alternatives considered

- Attach only in `PlayerSpawnedNPC`: too late for the engine's model selection.
- Clear every mount cache/remount everything: can invalidate live ragdolls and
  addresses a different lifetime.
- Advertise stale entries and let Sandbox fail: repeats an avoidable missing
  model path without exposing whether the carrier was available.
