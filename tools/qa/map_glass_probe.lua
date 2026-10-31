-- QA probe: shoot a map glass pane on modern_house the way a player does (real +attack with the 357),
-- then shoot the broken window again. Needs sv_cheats 1 (setpos/setang). Prints NL_GLASS lines and
-- paces screenshots with NL_SHOT (answered by the session driver with nl_shot_taken <n>).
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
local function shards() return #ents.FindByClass("procedural_shard") end

local panes = {}
for _, ent in ipairs(ents.FindByClass("func_breakable")) do if isGlass(ent) then panes[#panes + 1] = ent end end
out("panes", #panes, "func_breakable", #ents.FindByClass("func_breakable"), "shards", shards())
local me = LocalPlayer()
table.sort(panes, function(a, b) return a:WorldSpaceCenter():DistToSqr(me:GetPos()) < b:WorldSpaceCenter():DistToSqr(me:GetPos()) end)
local pane = panes[1]
local center, normal
if IsValid(pane) then
    local mins, maxs = pane:OBBMins(), pane:OBBMaxs()
    local size = maxs - mins
    local axis = size.x <= size.y and size.x <= size.z and Vector(1, 0, 0) or (size.y <= size.z and Vector(0, 1, 0) or Vector(0, 0, 1))
    center = pane:WorldSpaceCenter()
    normal = (pane:LocalToWorld(axis) - pane:GetPos()):GetNormalized()
    out("target", pane:EntIndex(), "center", tostring(center), "size", tostring(size), "normal", tostring(normal))
end

local function aim(from)
    local eye = from + Vector(0, 0, 64)
    local ang = (center - eye):Angle()
    RunConsoleCommand("setpos", tostring(from.x), tostring(from.y), tostring(from.z))
    RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
end
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

local steps = {
    function()
        if not center then out("no glass pane found") print("NL_SHOT_DONE") return end
        -- Stand 90 units in front of the pane (on the side the player is), eye level with its centre.
        local side = (me:GetPos() - center):Dot(normal) >= 0 and 1 or -1
        local stand = center + normal * (90 * side) - Vector(0, 0, 64)
        aim(stand)
        RunConsoleCommand("use", "weapon_357")
        timer.Simple(2, function() out("before", "shards", shards()) print("NL_SHOT before_shot") end)
    end,
    function()
        fire(1, function()
            out("after_first", "pane_valid", tostring(IsValid(pane)), "shards", shards())
            print("NL_SHOT after_first_shot")
        end)
    end,
    function()
        -- Shoot the broken window again: through where the pane was, into the debris.
        fire(3, function()
            out("after_more", "shards", shards())
            print("NL_SHOT after_more_shots")
        end)
    end,
    function()
        -- And the debris on the floor below the window.
        local eye = me:EyePos()
        local ang = (center - Vector(0, 0, 60) - eye):Angle()
        RunConsoleCommand("setang", tostring(ang.p), tostring(ang.y), "0")
        timer.Simple(0.5, function()
            fire(3, function() out("after_floor", "shards", shards()) print("NL_SHOT after_floor_shots") end)
        end)
    end,
    function() out("done") print("NL_SHOT_DONE") end,
}
local index = 0
local function nextStep() index = index + 1 if steps[index] then steps[index]() end end
concommand.Add("nl_shot_taken", function() timer.Simple(0.5, nextStep) end)
timer.Simple(1, nextStep)
