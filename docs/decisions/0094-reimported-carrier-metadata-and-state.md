# ADR 0094: restore prepared carrier metadata and forget deleted entry state

Date: 2026-11-03. Status: accepted for R12-A, the user's item 36.

## Context

The hotloader's native deletion can remove `rig.json` and name records while Windows keeps a
mounted `carrier.gma` open. Native `PrepareCarrier` reuses that archive, recreates the short-name
record and returns the fitted manifest, but its cached branch does not recreate `rig.json`.
The persistence `Entity:SetModel` wrapper resolves the model before `AttachNative` publishes that
manifest. A missing sidecar can reject a carrier whose model bytes are already mounted.
The client also needs the sidecar for presentation. ADR [0090](0090-ready-carriers-before-actor-publication.md)
checks mount/precache readiness, which has a different lifetime from the metadata lookup.

Deletion previously cleared the client's rig table and menu registrations but left server rig
lookups and the persistence wrapper's ragdoll-to-actor conversion memo. Clearing mounted archives
would reload models used by live entities and is unnecessary.

## Decision

Remember a native prepared rig before `SetModel` for every factory, attachment, actor readiness
and persistence conversion. Require loadable version/generator and matching asset/key/model
identities. If its sidecar is absent, require the carrier archive, stage the native manifest,
verify its bytes and rename it before using it. A short write never becomes the final sidecar;
the next attempt uses a new staging name. Existing metadata files are never overwritten. Cache the exact
model identity alongside the full rig key, so the wrapper does not depend on a short-name sidecar
that was removed in this session. Clients subsequently read the restored full manifest.

On entry deletion or catalog withdrawal, evict only that asset's reusable rig/model and conversion
lookups in each realm. The conversion memo is shared across Lua refreshes so the guarded wrapper
and the current withdrawal callback reference the same table. A cached conversion must also have
its metadata sidecar and pass current availability before reuse; otherwise native prepares it again.
Live entities retain their already bound immutable manifest; clearing reusable lookups does not
replace or remount their carrier. Morph geometry memoization follows the same deletion event.
Mount visibility memoization remains governed by ADR 0090 and persistence requires the exact
requested model. Approval and the native trust/path policy stay in force.

## Consequences

An identical reimport can recover a retained archive without rebuilding native binaries, remounting
live models or asking the player to restart. A new fit uses its own key and never redirects an old
entity to that fit. A failed metadata write fails readiness and can be retried. No source model,
Steam depot file or Remix setting is changed. The regression executes the shipped deletion,
spawn, lookup and persistence functions with separate cache lifetimes; PoC observations and their
limits are recorded in the [R12-A report](../handover/R12-A-report.md).
