# 0061: Broken glass is loose physics; it breaks again and expires

- Status: Accepted 2026-10-31. Supersedes in part [0040](0040-native-map-glass-debris.md): its
  persistent debris (no age-based disappearance), the exclusion of map debris from recursive splitting
  and the map-only budget. 0040's native brush behaviour, fracture geometry, networking and cleanup
  stand.
- Decided by: the user's report, "The glass on ground is not (physically) interactive, can not be
  further broken (and broke small enough to disappear) and has no option to remove them after some
  time."; implemented by Claude on `r5-glass` under the lead's brief (defaults and collision group
  chosen there).
- Scope: the bundled GPL-2.0 Glass-Rewrite-Remix input in `packages/fixes`, its translations in
  `companion/i18n/addons` and the LuaJIT harness. No loader, runtime or networking change.

## Context

Why broken glass lay inert (facts in [RESEARCH.md](../RESEARCH.md), section "Loose glass physics in
GMod"):

- `rtx_glass_expensive_shards` (default 1) put map debris and the add-on's small fragments into
  `COLLISION_GROUP_WORLD`, the group of the No Collide tool's right click: "no collisions with
  anything but the world". Props and players passed through them; only the floor held them.
- `ENT:OnTakeDamage` replaces base_anim's empty handler without calling `TakePhysicsDamage`, which
  GMod's own entities call to react to damage. Bullets and explosions never moved a shard.
- Map debris kept `CAN_BREAK = false` (ADR 0040). The add-on's own fragments could break, but a
  fragment's split took the shard count itself as its depth (21-26 planes at the default 12; a pane's
  first break adds 2-4 to it), and each fragment below the dust size was created as an entity only to
  be removed again in `BuildCollision`.
- Nothing removed broken glass but map cleanup and the 256-piece map budget.

Clients have no physics copy of a shard (`BuildCollision` runs on the server only), so a shard that is
solid to players makes the client predict walking through what the server blocks. Review R4's
rendering (each shard draws its own IMesh; replaced meshes are retired for eight frames) and the
paced per-player resync must stay as they are.

## Decision

**Loose pieces.** Every piece that broke off a pane, map debris or a fragment of any shard, is
registered as it is made in `lua/autorun/server/glass_debris.lua` (oldest first). The registry makes it
loose physics, counts it and expires it. Unbroken panes are not registered.

**Collision group.** `COLLISION_GROUP_WEAPON` with `rtx_glass_expensive_shards 1` (the default):
the world, props and the other pieces collide with it; players, NPCs and vehicles pass through, so
nobody is stopped or trapped by glass the client cannot predict. With 0, `COLLISION_GROUP_DEBRIS`:
world and props only, pieces pass through each other, cheaper. Traces hit both groups, so bullets
reach `OnTakeDamage`, and explosions, the physgun, the gravity gun and `+use` reach every piece. GMod
gives `COLLISION_GROUP_WEAPON` to props that must not collide with players (`gmod_cameraprop`,
`ragdoll_motion`), and TTT to corpses that are "nonsolid to players, but can be picked up and shot".
This holds for every broken piece, including the add-on's large fragments, which used to be solid.

**Physics damage.** `OnTakeDamage` calls `TakePhysicsDamage` first. A frozen pane does not move.

**Motion.** The registry turns motion on and wakes each piece. Frozen as before, for their reasons:
unbroken panes (spawn menu, tool, the `func_breakable_surf` replacement) stand like windows; the
placeholder of a piece that broke is frozen, non-solid and hidden; the client's `Think` pins a
client-side physics copy to the networked pose and never touches the server's simulation (no copy is
built today).

**Breaking again.**
- Map debris breaks like any shard, 0.25 s after it was made.
- A loose piece splits with `max(2, ceil(rtx_glass_shard_count / 4))` as its depth (3 at the default:
  3-8 planes, a handful of fragments), so a shot cracks it rather than pulverising it, and breaking
  can repeat. A pane's first break keeps its count and its welds; fragments of a loose piece are not
  welded.
- A loose piece breaks from impacts above 500 units/s (a pane: 300). At `sv_gravity 600` a fall reaches
  500 units/s after about 210 units, so pieces do not shatter by dropping out of a window, while a
  gravity-gun punt, a thrown prop or a blast that sends them flying does.
- A fragment below the existing dust size (bounding radius 20) becomes GlassImpact dust without an
  entity: at most 3 effects per split and 24 per tick, since an explosion over a pile breaks every
  piece in one tick and creating and dropping their dust as entities could exhaust edicts.
  `BuildCollision` keeps its own check for a fragment that ends up smaller.
- Two loose pieces never break each other, since the pieces of a pile collide now. The check reads
  `HitEntity`. The add-on's own check for two breakable shards reads `HitObject`, a physics object
  without `GetClass`, so it never matched; it stays as it is, and a pane still breaks when a flying
  piece hits it.

**Budget.** At most 256 loose pieces of any origin; adding one more removes the oldest. A piece that
breaks again leaves the count and its fragments join it. A fragment that broke is removed 5 s later
(it used to stay hidden until its original went); an original stays hidden until its last fragment is
gone and then removes what is left. Entities stay bounded: 256 loose pieces, one hidden original per
lineage that still has pieces, and the placeholders of the last five seconds.

**Lifetime.** `rtx_glass_debris_lifetime`, seconds, archived, notify and replicated like the other glass
settings, 0-600, default **120**: long enough to see, push, shoot and pick up what a fight broke,
short enough that a long session or a busy server does not keep hundreds of physics pieces (and the
budget seldom has to cut a pile short); 0 restores 0040's keep-until-cleanup. One timer, once a second,
reads only the oldest entries, so a changed setting applies to the pieces already lying around. An
expired piece gets `ENT:FadeOut`: the networked `FadeStart` is set, it stops breaking and leaves
players' hands, and it is removed a second later; it keeps moving meanwhile. Clients shrink it to
nothing over that second by scaling the model matrix in `ENT:Draw`. Only the transform changes: no
mesh is built or freed under queued rendering, and no blend or alpha state is used, so Remix sees a
moving, shrinking instance like any other dynamic draw.

**Interface.** A "Debris lifetime (s)" slider in the settings panel's Visual Effects section and on the
spawn-menu settings page (with a help line), and in Reset to Defaults. The label and help are
translated in `companion/i18n/addons` for every shipped language; those translations are agent-written
and not yet reviewed.

## Consequences

- A broken window's debris stays two minutes by default instead of until map cleanup;
  `rtx_glass_debris_lifetime 0` brings the old behaviour back.
- Shooting debris cracks it a few times until it is dust; an explosion in a pile shatters most of it in
  one tick, at bounded cost.
- With `rtx_glass_expensive_shards 1` a pile's pieces collide with each other, which costs physics time
  that the old `COLLISION_GROUP_WORLD` did not; 0 is the cheap setting.
- Players walk through all broken glass, also the add-on's large fragments, which used to block them
  (with prediction errors on the client).
- The add-on's own fragments split into fewer pieces when shot again; its panes' first break is
  unchanged.
- `tools/tests/test_glass_map.py` runs the shipped entity, registry and map controller under LuaJIT:
  collision groups and motion, bullets pushing pieces, recursive fracture of map debris to dust and the
  placeholders' cleanup, the budget counting fragments, hard impacts, the lifetime with mocked time,
  lifetime 0, and the transform-only shrink. Each of these scenarios fails on the code before this
  decision.
- To check in the game: interaction with the physgun, gravity gun and `+use`; that players and NPCs
  pass through while props collide; the shrink under Remix; an explosion in a full pile; a listen
  server with a second player.

## Alternatives considered

- `COLLISION_GROUP_NONE`: players stand on pieces, get trapped by falling ones, and the client
  predicts against no physics.
- `COLLISION_GROUP_INTERACTIVE_DEBRIS`: whether it collides with players depends on the game's
  collision rules (Source's base rules exempt the player only outside HL2MP), and pieces would still
  pass through each other.
- `COLLISION_GROUP_PUSHAWAY`: relies on multiplayer push-away player code.
- Keeping `COLLISION_GROUP_WORLD`: inert glass, the report.
- A `timer.Simple` per piece: fixes the lifetime at creation, so a changed setting would not apply.
  A `Think` over every shard: per-frame work for what changes once a second.
- An alpha fade: per-tick colour updates over the network, or an untested translucency path in Remix.
  A GlassImpact burst at expiry: a window's 18 pieces would burst together; the shrink is quiet.
- Default 0: the report's third point would need every player to find the setting. 300 s: piles
  stay for most of a short session.
- Keeping 300 units/s for loose pieces: map debris would shatter on landing and vanish, the failure
  ADR 0040 fixed. Keeping the shard count as a loose piece's depth: one shot pulverises a piece, so
  breaking never repeats, and its dust would be created as entities.
