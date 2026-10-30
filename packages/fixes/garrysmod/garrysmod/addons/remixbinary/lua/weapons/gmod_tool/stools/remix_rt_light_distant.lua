-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
local function NLP(key, text)
    if bundle_i18n then bundle_i18n.RegisterPhrase(key, text)
    elseif CLIENT then language.Add(key, text) end
end
TOOL.Category		= "RTX Remix"
TOOL.Name			= "#tool.remix_rt_light_distant.name"
TOOL.Command		= nil
TOOL.ConfigName		= ""

-- Client ConVars
TOOL.ClientConVar["radius"]			= "20"
TOOL.ClientConVar["brightness"]		= "1"
TOOL.ClientConVar["volumetric"]		= "1"
TOOL.ClientConVar["color_r"]		= "255"
TOOL.ClientConVar["color_g"]		= "220"
TOOL.ClientConVar["color_b"]		= "180"
TOOL.ClientConVar["freeze"]			= "1"
TOOL.ClientConVar["distantang"]		= "0.5"
TOOL.ClientConVar["yaw"]			= "0"
TOOL.ClientConVar["pitch"]			= "-90"

if CLIENT then
    NLP("tool.remix_rt_light_distant.name", NN("API Light - Distant"))
    NLP("tool.remix_rt_light_distant.desc", NN("Spawn and edit Distant/Directional Lights"))
    NLP("tool.remix_rt_light_distant.0", NN("Left-click: Spawn | Right-click: Update"))
end

local function computeRadianceVector(r, g, b, brightness)
    local scale = math.max(0, brightness or 1)
    return Vector((r/12)*scale, (g/12)*scale, (b/12)*scale)
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    if not trace.HitPos then return false end

    local pos = trace.HitPos + (trace.HitNormal or Vector(0,0,1)) * 16
    local ang = Angle(0, ply:EyeAngles().y, 0)

    local ent = ents.Create("remix_rt_light")
    if not IsValid(ent) then return false end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()

    ent:SetNWString("rtx_light_type", "distant")
    ent:SetNWFloat("rtx_light_radius", self:GetClientNumber("radius") or 20)
    ent:SetNWFloat("rtx_light_brightness", self:GetClientNumber("brightness") or 1)
    ent:SetNWFloat("rtx_light_volumetric", self:GetClientNumber("volumetric") or 1)
    ent:SetNWFloat("rtx_light_distant_angle", self:GetClientNumber("distantang") or 0.5)

    local r = self:GetClientNumber("color_r") or 255
    local g = self:GetClientNumber("color_g") or 220
    local b = self:GetClientNumber("color_b") or 180
    ent:SetNWFloat("rtx_light_color_r", r)
    ent:SetNWFloat("rtx_light_color_g", g)
    ent:SetNWFloat("rtx_light_color_b", b)

    if self:GetClientNumber("freeze") ~= 0 then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    undo.Create("Remix Distant Light")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
    undo.Finish()

    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    if not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    if ent:GetClass() ~= "remix_rt_light" then return false end

    ent:SetNWString("rtx_light_type", "distant")
    ent:SetNWFloat("rtx_light_radius", self:GetClientNumber("radius") or 20)
    ent:SetNWFloat("rtx_light_brightness", self:GetClientNumber("brightness") or 1)
    ent:SetNWFloat("rtx_light_volumetric", self:GetClientNumber("volumetric") or 1)
    ent:SetNWFloat("rtx_light_distant_angle", self:GetClientNumber("distantang") or 0.5)

    local r = self:GetClientNumber("color_r") or 255
    local g = self:GetClientNumber("color_g") or 220
    local b = self:GetClientNumber("color_b") or 180
    ent:SetNWFloat("rtx_light_color_r", r)
    ent:SetNWFloat("rtx_light_color_g", g)
    ent:SetNWFloat("rtx_light_color_b", b)

    return true
end

function TOOL:Reload(trace)
    return false
end

function TOOL:Think()
end

function TOOL.BuildCPanel(panel)
    panel:Help(NL("Spawn and edit Distant/Directional Lights"))

    panel:NumSlider(NL("Brightness"), "remix_rt_light_distant_brightness", 0, 10000, 2)
    panel:NumSlider(NL("Volumetrics"), "remix_rt_light_distant_volumetric", 0, 5, 2)
    panel:NumSlider(NL("Angular Diameter (degrees)"), "remix_rt_light_distant_distantang", 0, 10, 2)
    
    panel:AddControl("Color", {
        Label = NL("Color"),
        Red = "remix_rt_light_distant_color_r",
        Green = "remix_rt_light_distant_color_g",
        Blue = "remix_rt_light_distant_color_b",
        ShowAlpha = 0,
        ShowHSV = 1,
        ShowRGB = 1,
        Multiplier = 1
    })
    
    panel:CheckBox(NL("Freeze on Spawn"), "remix_rt_light_distant_freeze")
end


if bundle_i18n then
    bundle_i18n.RegisterPhrase("Remix Distant Light", NN("Remix Distant Light"))
end
