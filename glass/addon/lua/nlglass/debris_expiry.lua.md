# debris_expiry.lua

MIT client helper included by `debris.lua`. Indexed min heap for descendants whose original birth
time predates their new insertion order. `Add(piece)`/`Remove(piece)` are O(log live descendants);
`PopBefore(birth)` returns the earliest piece if due, otherwise nil. `Clear` resets all indices.

Input pieces have `id` and `ageBorn`; the helper owns `expiryIndex` and its bounded `items` array.
The manager feeds the existing final-second shrink cohort and rebuilds deadlines on lifetime changes.
Expiry keeps the parent's original lifetime across every split; ordinary G1 pieces keep their existing
birth-order cursor. Removed pieces leave no stale heap entries. No engine, network or file calls;
no process exit code.
