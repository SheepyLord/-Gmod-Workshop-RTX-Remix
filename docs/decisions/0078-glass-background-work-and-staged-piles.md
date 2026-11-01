# 0078: Prepare and step glass off the client thread; stage settled pile replacements

- Status: Accepted 2026-11-01 (G1-B fix pass, implementation delegated by the user).
- Amends the stepping, memory and batching choices in [0072](0072-glass-debris-world-and-batching.md).
  Collision corrections are recorded in [0073](0073-glass-native-fix-pass.md).

## Context

The fix brief requires background map preparation, less per-frame work, retained pile meshes and
nonfatal Jolt cache saturation. The old world reserved 144 MiB of scratch at Init(8192); active
physics blocked the caller, and the manager walked every piece even when the native changed list
was empty. Measurements and limits are in [RESEARCH](../RESEARCH.md).

## Decision

- A module worker exclusively owns BSP parsing/cooking, final broadphase optimization and each
  physics dispatch. Begin/Poll pairs publish complete results or errors. No worker accesses Lua or
  engine APIs; engine VFS reads, the bounded owned byte copy and prop collision extraction remain
  on the client thread. Busy mutations fail immediately; Lua queues removals, impulses and spawns
  until polling completes. Cleanup/shutdown joins before releasing resources. Synchronous native
  methods remain for core tests and compatibility.
- Capture Jolt's old/new active body sets with exclusive NoLock access, including final sleeps
  and newly woken pieces. Publish through a dense pose queue; Lua consumes only changed IDs and
  draws only individual/unbatched pieces. Entirely sleeping worlds need no worker dispatch.
  Expiry visits the birth-ordered final-second cohort; setting changes reset that cursor.
- Run fixed 1/60 steps, at most four/dispatch, with a measured 4 ms catch-up allowance. One step
  always runs even when it costs more than that allowance. Count/discard excess whole steps.
  A saturated manifold/pair/contact table increments per-kind counters and continues Jolt's safe
  partial-contact update. Other actual worker failures can still select fallback.
- Init/map preparation reserves no simulation scratch. Allocate from live demand on the first
  active step, then grow to measured peak, retaining the non-aborting heap fallback. Pair and
  contact table limits are max(1024, budget*8) and max(1024, budget*4), bounding the solver's demand.
- Build settled replacements from snapshots at up to 1800 transformed vertices/frame and at most
  one 6000-vertex GPU upload/frame. Keep valid old chunks until replacements exist. Wake/removal/
  shrink hides only its affected immutable chunk; its survivors draw individually. Cancel stale
  staging on removal, queue additions for the next revision, and retain old meshes after failures.

## Consequences

Worker dispatch adds one-frame pose latency, and a busy frame renders the previous published poses.
Cosmetic simulation can lose catch-up time under heavy load; overflow may omit some contacts, with
counts visible in the QA probe. Smaller chunks use more settled draws but bound replacement bursts
and limit the pieces redrawn after a wake. Actual engine/Remix timing and visible pile behavior
still require Claude's game acceptance. Native policy and package trust are unchanged.

## Alternatives considered

Synchronous stepping retains multi-millisecond client stalls. Waiting on a worker before every
mutation merely moves that stall. Keeping every old mesh visible after a removal duplicates glass;
destroying all of them redraws the entire pile individually. Retiring only the affected small chunk
avoids both failures while other chunks and replacement jobs remain intact.
