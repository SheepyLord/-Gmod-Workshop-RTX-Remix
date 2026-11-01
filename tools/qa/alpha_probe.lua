-- QA probe (R7-A): client-side plates with alpha-tested and translucent material variants of one
-- texture, laid flat above open ground in daylight, so the surface and its shadow can be compared under
-- RTX. The materials come from the session's QA add-on (nlqa_alpha, made by the session driver). Takes
-- one screenshot (NL_SHOT plates), then removes the plates. Prints NL_ALPHA lines.
local VARIANTS = NL_ALPHA_VARIANTS or {"a_hotloader", "b_no_atoc", "c_ref02", "d_translucent",
    "e_plain_alphatest", "f_no_vertexcolor", "g_unlit_alphatest", "h_opaque"}
local CENTER = NL_ALPHA_CENTER or Vector(700, 576, -143)
local HEIGHT, SPACING = 30, 60
local plates, camera = {}, nil
local mmdOption = "rtx.gmod.mmdAlphaTexturesForSession"
local oldMmd, sentMmd, nextHashes = nil, nil, 0
local probeMaterials = {}
if NL_ALPHA_MMD then
    if RemixConfig and RemixConfig.GetConfigVariable and RemixConfig.SetConfigVariable and
        RemixMaterial and RemixMaterial.GetAllTextureHashes then
        oldMmd = RemixConfig.GetConfigVariable(mmdOption)
        print("NL_ALPHA mmd enabled; cutoff " .. tostring(RemixConfig.GetConfigVariable("rtx.mmdAlphaCutoff")))
    else
        print("NL_ALPHA mmd ERROR: missing Remix config/material API; no category write")
    end
end

-- Optional scoped fixture tagging; wait for the plates' real texture hashes, preserving the old set.
hook.Add("Think", "nl_alpha_probe_hashes", function()
    if oldMmd == nil or RealTime() < nextHashes then return end
    nextHashes = RealTime() + 0.25
    local hashes, values = {}, {}
    for _, name in ipairs(probeMaterials) do
        for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(name) or {}) do
            if isstring(hash) and hash:match("^0[xX]%x+$") and not hash:match("^0[xX]0+$") then hashes[hash:lower()] = true end
        end
    end
    for hash in pairs(hashes) do values[#values + 1] = hash end
    table.sort(values)
    local joined = table.concat(values, ", ")
    if tostring(oldMmd) ~= "" then joined = tostring(oldMmd) .. (joined ~= "" and ", " .. joined or "") end
    if sentMmd ~= joined and RemixConfig.SetConfigVariable(mmdOption, joined) then
        sentMmd = joined
        print("NL_ALPHA mmd textures " .. joined)
    end
end)

local function finish()
    camera = nil
    hook.Remove("CalcView", "nl_alpha_probe")
    hook.Remove("HUDShouldDraw", "nl_alpha_probe")
    hook.Remove("Think", "nl_alpha_probe_hashes")
    if oldMmd ~= nil then
        print("NL_ALPHA mmd restored " .. tostring(RemixConfig.SetConfigVariable(mmdOption, tostring(oldMmd))))
    end
    for _, p in ipairs(plates) do if IsValid(p) then p:Remove() end end
    timer.Simple(1, function() print("NL_SHOT_DONE") end)
end

hook.Add("CalcView", "nl_alpha_probe", function()
    if camera then return {origin = camera[1], angles = camera[2], fov = 60, drawviewer = false} end
end)
hook.Add("HUDShouldDraw", "nl_alpha_probe", function() if camera then return false end end)
concommand.Add("nl_shot_taken", function() timer.Simple(0.3, finish) end)

RunConsoleCommand("nativeloader_weather_seconds", "0")
RunConsoleCommand("nativeloader_weather", "clear")
RunConsoleCommand("nativeloader_sky_time", "12")
-- two rows of four, flat (normal up), the variant order left to right, then the second row
for i, name in ipairs(VARIANTS) do
    local column, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local pos = CENTER + Vector(row * SPACING, (column - 1.5) * SPACING, HEIGHT)
    local p = ClientsideModel("models/hunter/plates/plate1x1.mdl", RENDERGROUP_OPAQUE)
    p:SetPos(pos) p:SetAngles(Angle(0, 0, 0)) p:Spawn()
    -- SetMaterial on a client-side model did not take in this setup; override every draw instead.
    local mat = Material("nlqa_alpha/" .. name)
    probeMaterials[#probeMaterials + 1] = "nlqa_alpha/" .. name
    if NL_ALPHA_MMD and RemixMaterial and RemixMaterial.TrackMaterial then
        RemixMaterial.TrackMaterial("nlqa_alpha/" .. name)
    end
    print(string.format("NL_ALPHA material %s error %s shader %s", name, tostring(mat:IsError()), mat:GetShader()))
    p.RenderOverride = function(self) render.MaterialOverride(mat) self:DrawModel() render.MaterialOverride() end
    plates[#plates + 1] = p
    print(string.format("NL_ALPHA plate %d %s row %d column %d at %s", i, name, row, column, tostring(pos)))
end
local look = CENTER + Vector(SPACING * 0.5, 0, HEIGHT * 0.5)
local eye = look + Vector(-150, 0, 170)
camera = {eye, (look - eye):Angle()}
timer.Simple(10, function() print("NL_SHOT plates") end)
