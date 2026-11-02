# 0087: Irregular shards, immediate break visibility and bounded local environment effects

- Status: Implemented for R9-G, 2026-11-02; Claude reviews and accepts game performance.
- Requested by: the user ([brief](../handover/R9-G-glass.md)).
- Supersedes the rectangular secondary fracture/four-unit floor in [0084](0084-glass-one-way-interaction.md),
  tempered grid in [0076](0076-glass-bounded-break-density.md), and breaking-hole delay in
  [0077](0077-glass-client-build-queue.md). Their authority, cell/wire/budget limits remain.

## Decision

1. Annealed cracks keep seeded radial rays and growing rings, with a small crushed core and
   alternating diagonal branches through ring cells. Tempered glass uses seeded recursive oblique
   convex cuts, with a smaller target area by the impact. Both use the same integer Lua generator,
   shared snapped intersections and stable ordering in both realms. Keep 200 annealed/300 tempered
   live cells and the 512-cell wire ceiling. Coarsening cannot reset a perforated pane to its outline.
2. Fallen individual convexes split near the actual local hit along seeded oblique crack lines,
   making two to six children. The minimum area is one square Source unit, independent of the
   pane's initial spacing. Preserve exact covered area, thickness, parent point velocities and
   original expiry. Six private native staging slots permit rollback; completed bodies and original
   represented fragments stay within their respective budgets. Fragments below four square units
   omit mutual glass contact but still meet map/Source mirrors. Distant R8 groups retain exact
   sub-hulls and move rigidly; they still do not split.
3. Build a breaking pane's remaining surface/prediction collision in the receipt callback. Weak
   crack refreshes retain the coalescing queue. Prioritize body construction by impact distance,
   then camera distance; retain the twelve-body/8192-vertex/0.75-ms soft construction allowance.
   Queued fragments draw in shared transient meshes immediately. Each chunk follows one ballistic
   trajectory until bodies start at its exact pose; queued geometry is not silently absent.
   During a long map import the preview clock stops at 0.5 seconds. The native handoff then begins
   physical collision. This deliberately approximates pre-body individual spin and contact.
4. A fixed 128-entry native sound buffer receives contact, split and water-entry events; worker
   callbacks allocate nothing and never call Lua/Source. No piece-piece damage cascade. Sound is
   independent of the interaction master. Drain only at an idle worker boundary. The client uses
   stock positional glass sounds, rejects distance over 1536 units and limits four/frame, 24/s
   (burst 24) and one/0.12 s/piece. Archive the local sound switch and translate it in seven languages.
5. Import solid world water/slime brushes as convex halfspaces, separate from solid collision.
   A bounded BVH (4096 volumes maximum) finds the containing volume; only active pieces are tested.
   Apply Jolt's submerged-volume buoyancy/drag on actual hulls, including compounds, at water/glass
   density ratio 0.4, linear drag 1.4 and angular drag 0.08. Sleeping bottom piles stay asleep.
   Use the upward surface plane; near side walls the test is by body centre rather than an exact
   clipped fluid intersection. Moving brush water is outside this static world import.
6. Observe exact `util.BlastDamage`/`BlastDamageInfo` calls and native explosion signals without
   changing arguments, return values or gameplay. Grenades emit `BaseGrenade.Explode`. The PoC confirms that GMod routes the native
   RPG/barrel env_explosion through AcceptInput as well, even with no damage victim. This needs
   no entity polling; explicit explosion inputs use the same observer. The damage fallback uses the inflictor: grenade ReportedPosition is the thrower.
   Coalesce nearby signals within 32 units/0.1 s; cap pending at 32, delivery at 32/s (burst 16),
   radius at 2048 and speed at 1800. Retain two-turn OnBreak ordering and queued-body blast history.
7. Suppress initial/pose-correction mirror overlaps until separation, including a piece's next
   swept extent after a teleport. Fast sweeps transfer motion along sampled travel when starting
   overlapped, then suppress the second penetration solve for that pair. Ordinary separated contacts
   and real bounces remain physical. No global velocity sign clamp and no Source response.
8. Local Clear removes only the caller's fallen/queued/preview glass. A validated, rate-limited
   listen-server admin route clears debris for everyone without erasing pane state. Dedicated-server
   clients have local Clear. Reset remains usable by non-admins and includes sound defaults.

## Evidence and limits

Generated native and LuaJIT fixtures verify deterministic fracture/area, one-unit descendants,
capacity and worker boundaries, event bounds, water sinking/drag, explosion observation, unchanged
Source transforms, receiving-frame drawing and clear permissions. The [report](../handover/R9-G-report.md)
records paired CPU costs and actual PoC evidence. Offline measurements do not establish RTX frame
costs. Dense nearby full-detail crowds, indivisible mesh/cooking calls, ballistic preview contacts,
rigid distant groups, missing custom explosion signals and finite observation caps remain limits.
