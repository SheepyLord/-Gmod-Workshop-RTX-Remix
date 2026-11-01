# 0082: Map commit headroom and a compact content summary

- Status: Accepted 2026-11-01
- Decided by: R7-B implementation under the user's diagnostics request
- Supersedes: the warning thresholds in 0063

## Context

R6's 70 percent commit warning flags 64.0 / 90.6 GiB despite 26.6 GiB remaining.
The saved R6 runs add about 11.1-16.2 GiB of system commit from bootstrap through map
load, across all three tiers. See [the measurements and limitations](../RESEARCH.md#r7-b-commit-headroom-from-the-saved-r6-runs-2026-11-01).
The runtime's VRAM snapshots cannot substitute for system commit measurements.

## Decision

Warn strictly below 18 GiB free commit, with a 24 GiB total-limit floor. Exact equality
is sufficient. A zero limit means unavailable; saturate used values above the limit.
Use one threshold across tiers because their main savings are GPU memory. Describe the
headroom and remedies in all seven languages. This is a cautious estimate, not a guarantee
for arbitrary maps, add-ons or concurrent programs.

Keep the RTX package's full version/hash identity and summarize other deployed packages
as one enabled-content count, including zero, in the panel and copied diagnostics.

## Consequences

Large healthy commit limits no longer cause percentage false alarms. Small limits still
warn. More demanding maps can exceed the reserve; more representative measurements can
justify a later change. The diagnostic payload retains package identities for internal use;
only their presentation becomes compact.

## Alternatives considered

- Raising the percentage still ties the warning to unrelated machine size.
- Using tier VRAM savings as CPU savings conflates different memory budgets.
- Listing every content package obscures the runtime identity the user asked to retain.
