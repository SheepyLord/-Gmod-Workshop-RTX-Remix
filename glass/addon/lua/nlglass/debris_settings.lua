-- MIT. Archived client collision choices; map and piece contacts are always enabled.
local flags = CreateClientConVar("rtx_glass_debris_collide_with", "3", true, false,
    "Source collision targets: 1 objects, 2 ragdolls, 4 living players, 8 living NPCs/NextBots", 0, 15)
CreateClientConVar("rtx_glass_debris_collide", "1", true, false, "Obsolete piece collision switch", 0, 1)
local version = CreateClientConVar("rtx_glass_debris_collision_version", "0", true, false, "Glass collision settings migration", 0, 1)
if version:GetInt() < 1 then
    -- The old checkbox controlled piece/piece contacts, not Source categories. Retire it once.
    -- Keep the master interaction choice, lifetime and budget, including an archived master off.
    RunConsoleCommand("rtx_glass_debris_collide", "1")
    RunConsoleCommand("rtx_glass_debris_collision_version", "1")
end
return flags
