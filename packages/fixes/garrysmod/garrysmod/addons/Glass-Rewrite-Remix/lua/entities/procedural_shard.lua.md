# procedural_shard.lua

Shared procedural glass entity: convex VPhysics, networked mesh, crack drawing and damage/impact
splitting. Its original spawn/tool glass behavior remains. Native-map debris sets RTX_MAP_DEBRIS
before Spawn. Client mesh removal tolerates a not-yet-created mesh. No configuration files are written;
existing glass convars are used. GPL-2.0.
The client draws a shard's mesh itself in ENT:Draw (the entity's material override and colour apply). DrawModel with GetRenderMesh rendered it through studiorender, which crashed on the material system's render thread with mat_queue_mode 2 as soon as a shard was drawn in an RTX session (review R4, 2026-10-31). Meshes that may still be queued for drawing (replaced render meshes, crack meshes, those of removed shards) are retired through networking.lua and destroyed eight frames later.

## Loose pieces (ADR 0061, 2026-10-31)

A loose piece broke off a pane: map debris, or any shard with an original shard. Split hands every
fragment to `glass_debris.lua` (collision group, motion, the 256-piece budget, the lifetime).

- **Physics damage.** `ENT:OnTakeDamage` replaces base_anim's, so it calls `TakePhysicsDamage`
  first: bullets, explosions and melee push a piece (a frozen pane does not move).
- **Breaking again.** Map debris breaks like any shard (0.25 s after it was made). A loose piece
  splits with fewer planes (depth `max(2, ceil(rtx_glass_shard_count / 4))` instead of the shard count
  itself; a pane's first break keeps the count plus 2-4), and from impacts above 500 units/s instead
  of 300, so falling out of a window does not shatter it. Fragments below a bounding radius of 20 are dust: Split creates no entity for them
  and shows at most 3 GlassImpact effects per split, 24 per tick (BuildCollision still turns a
  fragment that ends up smaller into dust). Fragments of a loose piece are not welded; a pane's first
  break still welds its shards. Two loose pieces never break each other: the pieces of a pile collide.
  That check reads `HitEntity`; the add-on's own shard check reads `HitObject`, a physics object
  without `GetClass`, never matches and is left as it is, so a pane still breaks when a piece hits it.
- **Placeholders.** A piece that broke is frozen, made non-solid and hidden, as before. A fragment
  that broke is removed after 5 s (its fragments count towards the original); the original stays
  until its last fragment is gone, and then removes what is left of it (only when it broke).
  `GLASS_BREAKING` takes a piece out of the budget while its fragments are added; `GLASS_SPLIT` keeps
  OnRemove from counting a placeholder out of its original twice.
- **Fading.** `ENT:FadeOut` (called by the registry) sets the networked `FadeStart`, stops the piece
  breaking and drops it from players' hands; it keeps moving, and is removed after `FADE_TIME` (1 s).
  The client's Draw shrinks it to nothing over that second by scaling the model matrix: no mesh is
  built or freed, so queued rendering and Remix see only a moving transform.
- Settings created here: `rtx_glass_debris_lifetime` (seconds, default 120, 0-600, archived, notify,
  replicated) and the reworded help of `rtx_glass_expensive_shards`.
- Unchanged: unbroken panes (spawn menu, tool, `func_breakable_surf` replacement) stay frozen and
  solid. The client's Think still freezes and pins a client-side physics copy to the networked pose;
  clients build none today (BuildCollision runs on the server), so it never moves anything.
