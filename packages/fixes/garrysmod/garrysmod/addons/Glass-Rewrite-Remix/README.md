# Remix Stuff
- More shards
- Better impact physics
- Shatter effects
- Native `func_breakable` glass windows retain their map behavior and leave networked physics
  shards when broken. This covers Modern House's ordinary breakable panes.
- Convex fracture works on vertical, horizontal and rotated panes.
- Broken glass, from map windows and from the add-on's own panes, is loose physics: players walk
  through it, props push it, bullets and explosions knock it about, and the physgun, the gravity gun
  and +use pick it up. Shooting a piece, an explosion or a hard impact (500 units/s) breaks it again,
  until its fragments are small enough to turn into dust.
- Settings: `rtx_glass_debris_lifetime` (seconds broken pieces stay before they shrink away; default
  120, 0 keeps them until map cleanup) and `rtx_glass_expensive_shards` (1: the pieces of a pile also
  collide with each other; 0: cheaper). At most 256 broken pieces exist; the oldest go first.
- Late-join shard data is split into bounded network packets, and visual bounds match each mesh.

# Glass-Rewrite
A Rewrite of a Garrys Mod Addon created a year ago

## Currently Features:
- Networked shards
- Custom collision
- Ability to set color/material of shards
- Completely procedural
- (Mostly) lag friendly, unfortunately can't do much about laggy source vphysics

## Features needed to be added:
- Hopefully some vphysics hackery I can do to improve performance with large shard piles
- Different break patterns
- Tool to turn things to glass
- Cool refractive glass material
- (Dupe support?)
