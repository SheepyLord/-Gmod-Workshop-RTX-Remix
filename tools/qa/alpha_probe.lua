-- QA probe (R7-A): client-side plates with alpha-tested and translucent material variants of one
-- texture, laid flat above open ground in daylight, so the surface and its shadow can be compared under
-- RTX. The materials come from the session's QA add-on (nlqa_alpha, made by the session driver). Takes
-- one screenshot (NL_SHOT plates), then removes the plates. Prints NL_ALPHA lines.
local VARIANTS = NL_ALPHA_VARIANTS or {"a_hotloader", "b_no_atoc", "c_ref02", "d_translucent",
    "e_plain_alphatest", "f_no_vertexcolor", "g_unlit_alphatest", "h_opaque"}
local CENTER = NL_ALPHA_CENTER or Vector(700, 576, -143)
local HEIGHT, SPACING = 30, 60
local plates, camera = {}, nil

local function finish()
    camera = nil
    hook.Remove("CalcView", "nl_alpha_probe")
    hook.Remove("HUDShouldDraw", "nl_alpha_probe")
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
    print(string.format("NL_ALPHA material %s error %s shader %s", name, tostring(mat:IsError()), mat:GetShader()))
    p.RenderOverride = function(self) render.MaterialOverride(mat) self:DrawModel() render.MaterialOverride() end
    plates[#plates + 1] = p
    print(string.format("NL_ALPHA plate %d %s row %d column %d at %s", i, name, row, column, tostring(pos)))
end
local look = CENTER + Vector(SPACING * 0.5, 0, HEIGHT * 0.5)
local eye = look + Vector(-150, 0, 170)
camera = {eye, (look - eye):Angle()}
timer.Simple(10, function() print("NL_SHOT plates") end)
