# debris_fallback.lua

Client helper included by `debris.lua`; at most 64 pieces are admitted by the manager. `Spawn`
uses `ents.CreateClientProp` and `PhysicsInitConvex`, hides the entity's stock model and simulates
only its convex hull. `COLLISION_GROUP_WORLD` conservatively restricts contact to the static world;
inter-piece contact is unavailable in this fallback, so the collide convar applies to Jolt only.
`Update` reads pose/sleeping state; `Impulse` wakes and applies a radial velocity kick; `Remove`
destroys only this helper's client entity. Initialization failure returns false. No files, server
entities or networking, and no process exit code. The manager draws the same glass meshes on both
backends. Requires the stock hunter plate model for the temporary client prop.

R8-G runtime-failure migration can retain grouped geometry via PhysicsInitMultiConvex when available. If unavailable/refused, that cosmetic piece is dropped safely. The ordinary missing-module path plans no groups; the shared budget still caps at 64 original fragments. No nil hull is passed to PhysicsInitConvex.
