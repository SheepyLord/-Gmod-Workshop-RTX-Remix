# debris_settings.lua

Client helper included by `debris.lua`. Creates the archived `rtx_glass_debris_collide_with` mask
(0–15, default 3: objects and ragdolls; living players/NPCs/NextBots off) and returns its ConVar.
Map and piece collisions remain enabled. On the first load, queues console commands setting the
obsolete `rtx_glass_debris_collide` to 1 and `rtx_glass_debris_collision_version` to 1. Later loads
keep choices. The master interaction switch, lifetime, budget and explicit new mask are preserved.
No server request, file access or gameplay mutation. No exit code; runtime errors use the Lua console.
