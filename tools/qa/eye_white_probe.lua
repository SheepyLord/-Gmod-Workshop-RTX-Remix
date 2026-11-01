-- QA probe (C-16): spawn a Model Hotloader character where the player is looking, pin a camera
-- straight down onto its face and take one screenshot per sky condition (NL_SHOT, answered by the
-- session driver with nl_shot_taken <n>), so the eye whites can be measured against the skin as the
-- light changes (eye_white_patches.py). Removes the character it spawned and puts the player's sky
-- settings back. Prints NL_EYE lines. No cheats needed.
local ASSET = NL_EYE_ASSET or "f9c3e4b461c6b6ba3272493a96b00bd6d400e17a5730b5aa1417628d1d7ad32b"  -- Robin
local CONDITIONS = NL_EYE_CONDITIONS or {{"noon", 12}, {"golden", 17.25}, {"dusk", 19.0}, {"night", 0}}
local SETTLE = 10  -- seconds after a sky change: auto exposure (tau 0.15-0.75 s) and the denoisers
local ent, current

local KEPT = {"nativeloader_weather_seconds", "nativeloader_weather", "nativeloader_sky_follow_map", "nativeloader_sky_hour"}
local kept = {}
for _, name in ipairs(KEPT) do
    local cv = GetConVar(name)
    kept[name] = cv and cv:GetString() or nil
end

local function finish()
    current = nil
    hook.Remove("CalcView", "nl_eye_white_probe")
    hook.Remove("HUDShouldDraw", "nl_eye_white_probe")
    hook.Remove("PreDrawViewModel", "nl_eye_white_probe")
    for _, name in ipairs(KEPT) do
        if kept[name] then RunConsoleCommand(name, kept[name]) end
    end
    -- Client Lua may not run lua_run; the hotloader's own action removes what this probe spawned.
    if IsValid(ent) then mmdhl.Action("remove", nil, ent) end
    timer.Simple(1, function() print("NL_SHOT_DONE") end)
end

local function head()
    if not IsValid(ent) then return nil end
    local bone = ent:LookupBone("ValveBiped.Bip01_Head1")
    return bone and ent:GetBonePosition(bone) or ent:WorldSpaceCenter()
end

hook.Add("CalcView", "nl_eye_white_probe", function()
    if not current then return end
    local pos = head()
    if not pos then return end
    -- straight down onto a face-up character; a tiny horizontal offset fixes which way is up
    return {origin = pos + Vector(0.01, 0, 22), angles = Angle(90, 0, 0), fov = 38, drawviewer = true}
end)
hook.Add("HUDShouldDraw", "nl_eye_white_probe", function() if current then return false end end)
hook.Add("PreDrawViewModel", "nl_eye_white_probe", function() if current then return true end end)

local step = 0
local function nextStep()
    step = step + 1
    local condition = CONDITIONS[step]
    if not condition then finish() return end
    current = condition
    RunConsoleCommand("nativeloader_sky_time", tostring(condition[2]))
    timer.Simple(SETTLE, function()
        print(string.format("NL_EYE %s hour %.2f head %s", condition[1], condition[2], tostring(head())))
        print("NL_SHOT " .. condition[1])
    end)
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.3, nextStep) end)

RunConsoleCommand("nativeloader_weather_seconds", "0")
RunConsoleCommand("nativeloader_weather", "clear")
local ply = LocalPlayer()
print(string.format("NL_EYE start pos %s ang %s", tostring(ply:GetPos()), tostring(ply:EyeAngles())))
if not mmdhl or not mmdhl.RequestSpawn then
    print("NL_EYE spawn error nil Model Hotloader is not loaded")
    finish()
    return
end
local ok, err = mmdhl.RequestSpawn(ASSET, {}, function(state, message, index)
    print("NL_EYE spawn " .. tostring(state) .. " " .. tostring(index) .. " " .. tostring(message))
    if state == "ready" then
        timer.Simple(3, function()
            ent = Entity(index)
            print("NL_EYE entity " .. tostring(ent) .. " valid " .. tostring(IsValid(ent)))
            -- A ragdoll that fell out of the world, or that this client does not see, has nothing to frame.
            if IsValid(ent) then nextStep() else finish() end
        end)
    elseif state == "error" then
        finish()
    end
end)
print("NL_EYE request " .. tostring(ok) .. " " .. tostring(err))
if not ok then finish() end
