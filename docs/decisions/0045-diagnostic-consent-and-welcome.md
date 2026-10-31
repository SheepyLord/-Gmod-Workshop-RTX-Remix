# 0045: Explicit diagnostic consent and a dismissible welcome window

- Status: Accepted 2026-10-30
- Decided by: the user's request 21

## Context

The welcome window previously treated missing preferences as permission to send diagnostics.
Legacy preferences cannot distinguish an explicit choice from those checked defaults. The window
also held input until it was closed manually.

## Decision

New and legacy profiles decline usage and crash reporting until an explicit, successfully saved
choice under the new consent policy. Before initializing the diagnostic SDK, archive an unconfirmed
legacy SDK database, including queued reports, to a unique sibling directory. Preserve unrelated
local preferences. Confirmed choices persist. A failed preference save rolls back the in-memory
choice and shows an error; it never grants consent.

The welcome window closes after twelve visible seconds. Interaction with it cancels that countdown
for this opening. Never Show This Again persists independently of diagnostics. The Permissions tab
can restore startup visibility. Merely opening, timing out or dismissing the window grants nothing.
The crash dialog defaults to No. The public UI state exposes the welcome window to GMod's cursor
bridge. API changes to nonpersistent options use their proper derived layer, allowing close and
timeout to work after the API opens the window.

## Consequences

An old implicit opt-in is intentionally not retained. Archived SDK data is kept on disk and is not
submitted automatically. A player can explicitly choose diagnostics later. Runtime policy tests
cover migration, restart, failed writes, stale SDK consent and timer interaction. No manual edits
to game user.conf are required.
