# 0075: Incremental glass subdivision and bounded topology snapshots

- Status: Accepted 2026-11-01 as G1-A fix-pass implementation under [0070](0070-glass-overhaul.md).
- Decided by: Codex implementing the user's fix-pass brief. Supersedes the bounded-history,
  crack-floor and fracture-replay details of [0071](0071-glass-impact-model.md).

## Decision

Keep live convex cells and a subdivision tree rather than reconstructing all cuts from the impact
list at each hit. Refine only cells in the new contact neighbourhood. When 512 cells would be
exceeded, restore complete distant groups to their original convex parent, preserving the recent
impact region. A group missing any released descendant cannot coarsen and is pruned. Groups are
bounded by live cells minus one. Retain eight recent spatial impact centres; reclaim a distant
slot for a new location and clear that slot's old cell/group tags. Never move damage to an old centre.

Accumulate all positive hit energy into damage and a pending crack pool. Start cracks once the pool
reaches min(8% of breaking threshold, 36,000). Break thresholds remain unchanged. This lets weak
hits add up and pistol shots crack ordinary large/thick panes. Tempered starts as one intact convex,
shows only a small local spiderweb and generates its uniform pieces at whole-pane shatter.

Cells/impacts/groups are immutable across Apply. Snapshots share them without a rebuild. Cache
remaining polygons/crack lines and run support connectivity only once on a break, using a bounds
sweep for adjacency. Merge clipped vertices closer than 1/256 before either renderer sees them.
Do not draw cracks on the original frame perimeter.

Snapshots encode the definition, eight centres, pending energy, live pane polygons and complete
subdivision groups, with shared vertex coordinates. That bounded topology is necessary for exact
continuation after old cuts coarsen: impacts alone no longer describe the pane. Hit events stay
compact; breaks still carry their pre-state to survive missing initial transmission/removal. There
is no networking for moving pieces, poses or per-piece server entities. A pathological perforated
pane whose boundaries prevent any sufficient coarsening releases its remaining bounded glass at
the current hit instead of assigning damage elsewhere or leaving invisible collision.

## Evidence and tradeoffs

The initial regression loses a new centre on its fourth spatial impact. The new 100-impact probe
reaches 512 cells, conserves a 32,768-unit² unbroken pane to 0.0142 unit² and restores its topology
without replay. A second probe checks that coarsening never covers any previously released piece's
centre. A 501-cell snapshot is 16,721 bytes: larger than the old centre-only state, but bounded and
needed only for registration/resync/break recovery. See [testing](../TESTING.md) for final timings.

Old distant cracks can simplify under sustained impacts. Exact continuation across clients and
late join, actual hit location, preserved holes and bounded CPU/memory take precedence over keeping
every distant ring forever. Game tuning and 40/50-pane frame-time acceptance remain with Claude.
