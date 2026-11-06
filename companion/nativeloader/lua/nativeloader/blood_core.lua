-- Owned Blood Overhaul RTX patterns, colour schemes and mixer. No stock material is changed.
local BO = BloodOverhaul
local cv = {
    enable = CreateClientConVar("bloodoverhaul_enable", "1", true, false),
    scheme = CreateClientConVar("bloodoverhaul_scheme", "realistic", true, false),
    variety = CreateClientConVar("bloodoverhaul_variety", "1", true, false),
    size = CreateClientConVar("bloodoverhaul_size", "1", true, false, "Splat size", 0.25, 3),
    droplets = CreateClientConVar("bloodoverhaul_droplets", "1", true, false),
}
for family, defaults in pairs({ red = {150, 16, 14}, alien = {199, 179, 61} }) do
    for i, channel in ipairs({ "r", "g", "b" }) do
        local name = family .. "_" .. channel
        cv[name] = CreateClientConVar("bloodoverhaul_" .. name, tostring(defaults[i]), true, false, "Blood colour", 0, 255)
    end
end
BO.ConVars = cv
local STOCK = { [0] = Color(150, 16, 14), [1] = Color(199, 179, 61), [2] = Color(110, 140, 30),
    [4] = Color(199, 179, 61), [5] = Color(110, 140, 30), [6] = Color(170, 210, 35) }
local FAMILIES = { [0] = "red", [1] = "alien", [2] = "green", [4] = "alien", [5] = "green", [6] = "worker" }
local CODES = { red = 0, alien = 1, green = 2, worker = 6 }
local function custom(family)
    return Color(cv[family .. "_r"]:GetInt(), cv[family .. "_g"]:GetInt(), cv[family .. "_b"]:GetInt())
end
function BO.Colour(code, index)
    if not STOCK[code] then return end
    local scheme = BO.GetScheme(cv.scheme:GetString())
    local mode = code == 0 and scheme.red or scheme.alien
    if not cv.enable:GetBool() or cv.scheme:GetString() == "realistic" then return STOCK[code] end
    if mode == "rainbow" then return HSVToColor(((index or 1) * 0.6180339887 * 360) % 360, 0.78, 0.95) end
    if mode == "custom" then return custom(code == 0 and "red" or "alien") end
    return IsColor(mode) and mode or STOCK[code]
end
BO.Family = function(code) return FAMILIES[code] end
BO.StockColour = function(code) return STOCK[code] end
local cached = {}
local function paint(name, texture, col, model)
    local mat = Material(name)
    if not mat or mat:IsError() then return end
    mat:SetTexture("$basetexture", texture)
    mat:SetVector(model and "$color2" or "$color", Vector(col.r / 255, col.g / 255, col.b / 255))
    return mat
end
function BO.Pattern(code, index)
    local family, shape = FAMILIES[code], BO.Shapes[index]
    if not family or not shape then return end
    local name = "decals/bloodoverhaul/" .. family .. "/" .. shape.key
    if not cached[name] then
        local col = BO.Colour(code, index)
        local natural = code == 0 and cv.scheme:GetString() == "realistic"
        local tex = "decals/bloodoverhaul/tex/" .. shape.key .. (natural and "" or "_n")
        cached[name] = paint(name, tex, natural and color_white or col)
        paint(name .. "_model", tex, natural and color_white or col, true)
    end
    return cached[name]
end
function BO.Apply()
    local previous = cached
    cached = {}
    -- Only already-used materials need retinting. Do not load every shape/PBR map at startup.
    for family, code in pairs(CODES) do
        for i, s in ipairs(BO.Shapes) do
            if previous["decals/bloodoverhaul/" .. family .. "/" .. s.key] then BO.Pattern(code, i) end
        end
    end
    hook.Run("NativeLoaderBloodColoursChanged")
end
for name in pairs(cv) do
    cvars.AddChangeCallback("bloodoverhaul_" .. name, BO.Apply, "nativeloader_blood")
end

local incoming = {}
for code, count in pairs({ [0] = 8, [1] = 6 }) do
    for i = 1, count do
        local prefix = code == 0 and "decals/blood" or "decals/yblood"
        incoming[prefix .. i], incoming[prefix .. i .. "_subrect"] = { code, i }, { code, i }
    end
end
local original_decal = util.DecalEx
BO.OrigDecalEx = original_decal
function util.DecalEx(mat, ent, pos, normal, colour, w, h)
    local entry = mat and incoming[string.lower(mat:GetName())]
    if cv.enable:GetBool() and entry then
        local index = cv.variety:GetBool() and math.random(#BO.Shapes) or ((entry[2] - 1) % #BO.Shapes + 1)
        local replacement = BO.Pattern(entry[1], index)
        if replacement then
            mat = replacement
            local scale = math.Clamp(cv.size:GetFloat(), 0.25, 3)
            w, h = (w or 1) * scale, (h or 1) * scale
        end
    end
    return original_decal(mat, ent, pos, normal, colour, w, h)
end
local emitter_meta = FindMetaTable("CLuaEmitter")
if emitter_meta and emitter_meta.Add then
    local original_add = emitter_meta.Add
    BO.OrigEmitterAdd = original_add
    emitter_meta.Add = function(self, mat, pos, ...)
        local name = type(mat) == "string" and mat or (mat and mat:GetName())
        local entry = name and incoming[string.lower(name)]
        if entry and cv.enable:GetBool() and cv.droplets:GetBool() and BO.ParticleMaterial then
            local index = cv.variety:GetBool() and math.random(#BO.Shapes) or 1
            mat = BO.ParticleMaterial(entry[1], index, false)
        end
        return original_add(self, mat, pos, ...)
    end
end
concommand.Add("bloodoverhaul_apply", BO.Apply)
concommand.Add("bloodoverhaul_reset", function()
    for _, c in pairs(cv) do RunConsoleCommand(c:GetName(), c:GetDefault()) end
    RunConsoleCommand("nativeloader_blood_impacts", "1")
    RunConsoleCommand("nativeloader_blood_amount", "1")
end)
concommand.Add("bloodoverhaul_test", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    if not tr.Hit or tr.HitSky then return end
    local side = tr.HitNormal:Cross(Vector(0, 0, 1))
    if side:LengthSqr() < 0.01 then side = Vector(1, 0, 0) end
    for i, code in ipairs({ 0, 1 }) do
        local m = BO.Pattern(code, math.random(#BO.Shapes))
        if m then util.DecalEx(m, tr.Entity, tr.HitPos + side * (i * 32 - 48), tr.HitNormal, color_white, 1, 1) end
    end
end)
