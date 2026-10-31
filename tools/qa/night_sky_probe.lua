-- QA probe: a clear midnight, then a tour of the sky (eight bearings 50 degrees up, two near the
-- zenith), one screenshot each (NL_SHOT, answered by the session driver with nl_shot_taken <n>).
-- The view is turned by a CalcView hook, so no cheats are needed; HUD and view model are hidden.
-- Prints NL_SKY lines with the sky state. Changes the time and weather of this session only.
local views = {}
for yaw = 0, 315, 45 do views[#views + 1] = {-50, yaw} end
views[#views + 1] = {-85, 0}
views[#views + 1] = {-85, 90}
local current
-- A place under open sky near the spawn (the spawn may be indoors): on the ground, with sky above
-- and in at least six of eight directions 50 degrees up.
local function openSky()
    local base = LocalPlayer():GetPos()
    for radius = 0, 6000, 200 do
        for bearing = 0, 345, radius == 0 and 360 or 15 do
            local p = base + Vector(math.cos(math.rad(bearing)) * radius, math.sin(math.rad(bearing)) * radius, 0)
            local down = util.TraceLine({start = p + Vector(0, 0, 300), endpos = p - Vector(0, 0, 3000), mask = MASK_SOLID_BRUSHONLY})
            if down.Hit and not down.StartSolid and not down.HitSky then
                local eye = down.HitPos + Vector(0, 0, 72)
                local open = 0
                for yaw = 0, 315, 45 do
                    local dir = Angle(-50, yaw, 0):Forward()
                    if util.TraceLine({start = eye, endpos = eye + dir * 30000, mask = MASK_SOLID_BRUSHONLY}).HitSky then open = open + 1 end
                end
                local up = util.TraceLine({start = eye, endpos = eye + Vector(0, 0, 30000), mask = MASK_SOLID_BRUSHONLY})
                if up.HitSky and open >= 6 then return eye, open end
            end
        end
    end
end
local place, open = openSky()
print("NL_SKY place " .. tostring(place) .. " open " .. tostring(open))
hook.Add("CalcView", "nl_night_sky_probe", function(_, origin, _, fov)
    if not current then return end
    return {origin = place or origin, angles = Angle(current[1], current[2], 0), fov = 90, drawviewer = false}
end)
hook.Add("HUDShouldDraw", "nl_night_sky_probe", function() if current then return false end end)
hook.Add("PreDrawViewModel", "nl_night_sky_probe", function() if current then return true end end)

-- The player's sky settings, put back before the probe ends (they are archived).
local KEPT = {"nativeloader_weather_seconds", "nativeloader_weather", "nativeloader_sky_follow_map", "nativeloader_sky_hour"}
local kept = {}
for _, name in ipairs(KEPT) do
    local cv = GetConVar(name)
    kept[name] = cv and cv:GetString() or nil
end
print("NL_SKY kept " .. util.TableToJSON(kept))
RunConsoleCommand("nativeloader_weather_seconds", "0")
RunConsoleCommand("nativeloader_weather", "clear")
RunConsoleCommand("nativeloader_sky_time", "0")
local index = 0
local function nextStep()
    index = index + 1
    local view = views[index]
    if not view then
        current = nil
        for _, name in ipairs(KEPT) do
            if kept[name] then RunConsoleCommand(name, kept[name]) end
        end
        timer.Simple(1, function() print("NL_SHOT_DONE") end)
        return
    end
    current = view
    timer.Simple(1.5, function() print(string.format("NL_SHOT sky_p%d_y%d", -view[1], view[2])) end)
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.3, nextStep) end)
timer.Simple(8, function()
    RunConsoleCommand("nativeloader_sky_status")
    nextStep()
end)
