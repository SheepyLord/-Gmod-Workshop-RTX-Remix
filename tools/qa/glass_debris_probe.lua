-- QA probe (R5, ADR 0061): break a map glass pane on modern_house with the 357, then check that the
-- debris is loose physics: its collision group, that shooting the pile moves and breaks pieces, and
-- that pieces go after rtx_glass_debris_lifetime. Needs sv_cheats 1 (setpos/setang). Prints NL_GLASS
-- lines and paces screenshots with NL_SHOT (answered by the session driver with nl_shot_taken <n>).
local function out(...) print("NL_GLASS " .. table.concat({...}, " ")) end
local function isGlass(ent)
    if not IsValid(ent) or not ent.GetBrushSurfaces then return false end
    local ok, surfaces = pcall(ent.GetBrushSurfaces, ent)
    if not ok or not istable(surfaces) then return false end
    for _, surface in ipairs(surfaces) do
        local material = surface.GetMaterial and surface:GetMaterial()
        local name = material and material.GetName and material:GetName() or ""
        if string.find(string.lower(name), "glass", 1, true) then return true end
    end
    return false
end
local function shards()
    local list = {}
    for _, ent in ipairs(ents.FindByClass("procedural_shard")) do if not ent:GetNoDraw() then list[#list + 1] = ent end end
    return list
end
local function where(list)
    local positions = {}
    for _, ent in ipairs(list) do positions[ent] = ent:GetPos() end
    return positions
end
local function groups(list)
    local count = {}
    for _, ent in ipairs(list) do local g = ent:GetCollisionGroup() count[g] = (count[g] or 0) + 1 end
    local parts = {}
    for g, n in pairs(count) do parts[#parts + 1] = g .. "x" .. n end
    table.sort(parts)
    return table.concat(parts, ",")
end

local panes = {}
for _, ent in ipairs(ents.FindByClass("func_breakable")) do if isGlass(ent) then panes[#panes + 1] = ent end end
local me = LocalPlayer()
table.sort(panes, function(a, b) return a:WorldSpaceCenter():DistToSqr(me:GetPos()) < b:WorldSpaceCenter():DistToSqr(me:GetPos()) end)
local pane = panes[1]
local center, normal
if IsValid(pane) then
    local size = pane:OBBMaxs() - pane:OBBMins()
    local axis = size.x <= size.y and size.x <= size.z and Vector(1, 0, 0) or (size.y <= size.z and Vector(0, 1, 0) or Vector(0, 0, 1))
    center = pane:WorldSpaceCenter()
    normal = (pane:LocalToWorld(axis) - pane:GetPos()):GetNormalized()
end
out("panes", #panes, "target", tostring(IsValid(pane) and pane:EntIndex()))
local lifetime = GetConVar("rtx_glass_debris_lifetime")
local keptLifetime = lifetime and lifetime:GetString()
out("lifetime", tostring(keptLifetime))

local function fire(times, done)
    local n = 0
    local function one()
        n = n + 1
        RunConsoleCommand("+attack")
        timer.Simple(0.15, function()
            RunConsoleCommand("-attack")
            if n < times then timer.Simple(0.9, one) else timer.Simple(2.5, done) end
        end)
    end
    one()
end
local before
local steps = {
    function()
        if not center then out("no glass pane found") print("NL_SHOT_DONE") return end
        local side = (me:GetPos() - center):Dot(normal) >= 0 and 1 or -1
        local stand = center + normal * (110 * side) - Vector(0, 0, 64)
        local ang = (center - (stand + Vector(0, 0, 64))):Angle()
        RunConsoleCommand("setpos", tostring(stand.x), tostring(stand.y), tostring(stand.z))
        RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
        RunConsoleCommand("use", "weapon_357")
        timer.Simple(2, function() out("before", "shards", #shards()) print("NL_SHOT before") end)
    end,
    function()
        fire(1, function()
            timer.Simple(2, function()
                local list = shards()
                before = where(list)
                -- COLLISION_GROUP_WEAPON is 11, COLLISION_GROUP_DEBRIS 1, COLLISION_GROUP_WORLD 20.
                out("broken", "shards", #list, "groups", groups(list))
                print("NL_SHOT broken")
            end)
        end)
    end,
    function()
        -- The pile on the floor below the window.
        local eye = me:EyePos()
        local ang = (center - normal * 0 - Vector(0, 0, 70) - eye):Angle()
        RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
        timer.Simple(0.5, function()
            fire(4, function()
                local list, moved, gone = shards(), 0, 0
                for ent, pos in pairs(before or {}) do
                    if not IsValid(ent) or ent:GetNoDraw() then gone = gone + 1
                    elseif ent:GetPos():Distance(pos) > 2 then moved = moved + 1 end
                end
                out("shot_pile", "shards", #list, "moved", moved, "broke_or_gone", gone, "groups", groups(list))
                print("NL_SHOT shot_pile")
            end)
        end)
    end,
    function()
        -- Pieces go after the lifetime: 6 s here, the player's value put back afterwards.
        RunConsoleCommand("rtx_glass_debris_lifetime", "6")
        timer.Simple(9, function()
            out("after_lifetime", "shards", #shards())
            if keptLifetime then RunConsoleCommand("rtx_glass_debris_lifetime", keptLifetime) end
            print("NL_SHOT after_lifetime")
        end)
    end,
    function() out("done") print("NL_SHOT_DONE") end,
}
local index = 0
local function nextStep() index = index + 1 if steps[index] then steps[index]() end end
concommand.Add("nl_shot_taken", function() timer.Simple(0.5, nextStep) end)
timer.Simple(1, nextStep)
