# Remix Stuff
- More shards
- Better impact physics
- Shatter effects
- Native `func_breakable` glass windows retain their map behavior and leave persistent, networked
  physics shards when broken. This covers Modern House's ordinary breakable panes.
- Convex fracture works on vertical, horizontal and rotated panes. Native map debris stays until
  cleanup or the 256-piece oldest-first budget; it does not immediately become short-lived particles.
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
