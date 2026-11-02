-- QA probe (C-16): spawn a Model Hotloader character where the player is looking, pin a camera
-- straight down onto its face and take one screenshot per sky condition (NL_SHOT, answered by the
-- session driver with nl_shot_taken <n>), so the eye whites can be measured against the skin as the
-- light changes (eye_white_patches.py). Removes the character it spawned and puts the player's sky
-- settings back. Prints NL_EYE lines. No cheats needed.
local ASSET = NL_EYE_ASSET or "f9c3e4b461c6b6ba3272493a96b00bd6d400e17a5730b5aa1417628d1d7ad32b"  -- Robin
local CONDITIONS = NL_EYE_CONDITIONS or {{"noon", 12}, {"golden", 17.25}, {"dusk", 19.0}, {"night", 0}}
local SETTINGS = NL_EYE_SETTINGS or {{"", nil, nil}} -- label, automatic feature, brightness percent
local SETTLE = NL_EYE_SETTLE or 10 -- seconds after a change: exposure and denoisers
local ent, current
local extras = {}

local KEPT = {"nativeloader_weather_seconds", "nativeloader_weather", "nativeloader_sky_follow_map", "nativeloader_sky_hour",
    "nativeloader_eye_whites", "nativeloader_eye_white_brightness"}
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
    hook.Remove("Think", "nl_eye_white_timing")
    for _, name in ipairs(KEPT) do
        if kept[name] then RunConsoleCommand(name, kept[name]) end
    end
    -- Client Lua may not run lua_run; the hotloader's own action removes what this probe spawned.
    if IsValid(ent) then mmdhl.Action("remove", nil, ent) end
    for _, extra in ipairs(extras) do if IsValid(extra) then mmdhl.Action("remove", nil, extra) end end
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
    if NL_EYE_FRONT then
        -- A frozen Source ragdoll's root angles can disagree with its posed head. Spawn faces the
        -- placed player, whose horizontal position is stable for both outdoor and room captures.
        local direction = LocalPlayer():GetPos() - pos
        direction.z = 0
        direction:Normalize()
        local origin = pos + direction * (NL_EYE_DISTANCE or 22) + Vector(0, 0, 1)
        return {origin = origin, angles = (pos - origin):Angle(), fov = NL_EYE_FOV or 38, drawviewer = true}
    end
    -- straight down onto a face-up character; a tiny horizontal offset fixes which way is up
    return {origin = pos + Vector(0.01, 0, 22), angles = Angle(90, 0, 0), fov = 38, drawviewer = true}
end)
hook.Add("HUDShouldDraw", "nl_eye_white_probe", function() if current then return false end end)
hook.Add("PreDrawViewModel", "nl_eye_white_probe", function() if current then return true end end)

local step, frames = 0, {}
hook.Add("Think", "nl_eye_white_timing", function()
    if current then frames[#frames + 1] = RealFrameTime() * 1000 end
end)
local function nextStep()
    step = step + 1
    local condition = CONDITIONS[math.floor((step - 1) / #SETTINGS) + 1]
    if not condition then finish() return end
    local setting = SETTINGS[(step - 1) % #SETTINGS + 1]
    current = condition
    frames = {}
    if setting[2] ~= nil then RunConsoleCommand("nativeloader_eye_whites", tostring(setting[2])) end
    if setting[3] ~= nil then RunConsoleCommand("nativeloader_eye_white_brightness", tostring(setting[3])) end
    RunConsoleCommand("nativeloader_sky_time", tostring(condition[2]))
    timer.Simple(SETTLE, function()
        local label = condition[1] .. (setting[1] ~= "" and "-" .. setting[1] or "")
        table.sort(frames)
        local median = frames[math.max(1, math.floor(#frames / 2))] or 0
        local p95 = frames[math.max(1, math.ceil(#frames * .95))] or 0
        print(string.format("NL_EYE %s hour %.2f head %s frame_ms_median %.3f frame_ms_p95 %.3f frames %d",
            label, condition[2], tostring(head()), median, p95, #frames))
        local info = istable(mmdhl.assets) and mmdhl.assets[ASSET]
        local bindings = {}
        for index, part in ipairs(info and info.materials or {}) do
            local mat = part.path and Material(part.path)
            local texture = mat and not mat:IsError() and mat:GetTexture("$basetexture")
            local copies = istable(mmdhl.softMaterials) and mmdhl.softMaterials[ASSET]
            local copyName = istable(copies) and istable(copies.soft) and copies.soft[index]
            local copy = isstring(copyName) and copyName ~= "" and Material(copyName)
            local copyTexture = copy and not copy:IsError() and copy:GetTexture("$basetexture")
            bindings[#bindings + 1] = {name = part.name, path = part.path, texture = texture and texture:GetName() or "pending",
                soft_path = copyName or nil, soft_texture = copyTexture and copyTexture:GetName() or nil}
        end
        -- Source truncates long console lines. One material per line also covers large PBR actors.
        for _, binding in ipairs(bindings) do
            print("NL_EYE_BINDING " .. label .. " " .. util.TableToJSON(binding))
        end
        RunConsoleCommand("nativeloader_eye_whites_status")
        print("NL_SHOT " .. label)
    end)
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.3, nextStep) end)

local function spawnExtras(remaining)
    if remaining <= 0 then nextStep() return end
    local ok = mmdhl.RequestSpawn(ASSET, {frozen = NL_EYE_FROZEN == true}, function(state, _, index)
        if state == "ready" then
            timer.Simple(1, function()
                extras[#extras + 1] = Entity(index)
                spawnExtras(remaining - 1)
            end)
        elseif state == "error" then finish() end
    end)
    if not ok then finish() end
end

RunConsoleCommand("nativeloader_weather_seconds", "0")
RunConsoleCommand("nativeloader_weather", "clear")
local ply = LocalPlayer()
print(string.format("NL_EYE start pos %s ang %s", tostring(ply:GetPos()), tostring(ply:EyeAngles())))
if not mmdhl or not mmdhl.RequestSpawn then
    print("NL_EYE spawn error nil Model Hotloader is not loaded")
    finish()
    return
end
local ok, err = mmdhl.RequestSpawn(ASSET, {frozen = NL_EYE_FROZEN == true}, function(state, message, index)
    print("NL_EYE spawn " .. tostring(state) .. " " .. tostring(index) .. " " .. tostring(message))
    if state == "ready" then
        timer.Simple(3, function()
            ent = Entity(index)
            print("NL_EYE entity " .. tostring(ent) .. " valid " .. tostring(IsValid(ent)))
            -- A ragdoll that fell out of the world, or that this client does not see, has nothing to frame.
            if IsValid(ent) then spawnExtras(math.max(0, math.min(tonumber(NL_EYE_EXTRA_COUNT) or 0, 4))) else finish() end
        end)
    elseif state == "error" then
        finish()
    end
end)
print("NL_EYE request " .. tostring(ok) .. " " .. tostring(err))
if not ok then finish() end
