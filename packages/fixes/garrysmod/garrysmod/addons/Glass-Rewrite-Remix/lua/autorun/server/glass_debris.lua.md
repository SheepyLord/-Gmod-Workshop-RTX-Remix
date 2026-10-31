# glass_debris.lua

Server autorun: the registry of loose broken glass (the native loader repository's ADR 0061).
Every piece that broke off a pane is added as it is made, oldest first: map window debris
(`rtx_map_glass.lua`) and the fragments of any shard (`ENT:Split` in `procedural_shard.lua`). The
global `GlassRewriteDebris` has `Add(ent)`, `Count()` and `MAX_PIECES` (256).

- **Loose physics.** `Add` sets the collision group and turns motion on: `COLLISION_GROUP_WEAPON`
  with `rtx_glass_expensive_shards 1` (the world, props and the other pieces collide with it),
  `COLLISION_GROUP_DEBRIS` with 0 (the world and props only, cheaper). Players, NPCs and vehicles
  pass through either; traces still hit, so bullets, explosions, the physgun, the gravity gun and
  `+use` reach every piece. Clients have no physics copy of a shard, so a piece solid to players
  would stop them where the client lets them walk.
- **Budget.** At most 256 pieces; adding one more removes the oldest. A piece that breaks again
  (`GLASS_BREAKING`, its fragments take its place) or is fading out (`GLASS_FADING`) no longer counts.
- **Lifetime.** One timer (`glass_rewrite_debris_lifetime`, every second) reads only the oldest
  entries: a piece older than `rtx_glass_debris_lifetime` seconds gets `ENT:FadeOut` (it shrinks away
  over a second on the clients, then it is removed). 0 keeps pieces until map cleanup or the budget.
  A changed setting applies to the pieces already lying around.
- **Cleanup.** `PreCleanupMap` removes every piece and empties the list.

No networking of its own (the entity carries its fade time), no configuration or file writes. GPL-2.0.
