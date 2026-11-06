-- Settings shared by the RTX package and the standalone owned-pattern part.
local BO = BloodOverhaul
if not BO or not BO.Packaged or BO.MenuRegistered then return end
BO.MenuRegistered = true
local i18n = file.Exists("nativeloader/i18n.lua", "LUA") and include("nativeloader/i18n.lua")
local function identity(text) return text end
local L, N = i18n and i18n.L or identity, identity
local SCHEMES = {
    realistic = N("Realistic"), arterial = N("Fresh arterial"), dark = N("Dark venous"),
    aged = N("Aged, dried"), ink = N("Black ink"), toxic = N("Toxic green"), blue = N("Blue blood"),
    violet = N("Violet"), gold = N("Golden ichor"), synthetic = N("Synthetic white"),
    rainbow = N("Rainbow"), custom = N("Custom colours"),
}
local function colour_picker(panel, label, prefix)
    panel:Help(label)
    local picker = vgui.Create("DColorMixer")
    picker:SetPalette(true) picker:SetAlphaBar(false) picker:SetWangs(true) picker:SetTall(170)
    picker:SetConVarR(prefix .. "_r") picker:SetConVarG(prefix .. "_g") picker:SetConVarB(prefix .. "_b")
    panel:AddItem(picker)
end
local function build(panel)
    if i18n then i18n.PreparePanel(panel) end
    panel:CheckBox(L("Enable Blood Overhaul RTX"), "bloodoverhaul_enable")
    panel:ControlHelp(L("Eighteen new patterns and twelve colour schemes, with wet PBR surfaces under RTX. Crunchy's Blood Overhaul is optional."))
    panel:CheckBox(L("Realistic bullet impacts"), "nativeloader_blood_impacts")
    panel:ControlHelp(L("Directional spray, brief mist and falling droplets that leave small stains. Off restores the engine's blood impact effect."))
    panel:NumSlider(L("Impact amount"), "nativeloader_blood_amount", 0, 2, 2)
    panel:ControlHelp(L("Zero uses the stock impact. Detail reduces with viewing distance; the particle and stain limits always apply."))
    local combo = panel:ComboBox(L("Colour scheme"), "bloodoverhaul_scheme")
    for _, scheme in ipairs(BO.Schemes) do combo:AddChoice(L(SCHEMES[scheme.id]), scheme.id) end
    panel:CheckBox(L("Mix all blood patterns"), "bloodoverhaul_variety")
    panel:NumSlider(L("Splat size"), "bloodoverhaul_size", 0.25, 3, 2)
    panel:CheckBox(L("Recolour flying droplets"), "bloodoverhaul_droplets")
    panel:ControlHelp(L("Custom colours apply when the Custom colours scheme is selected."))
    colour_picker(panel, L("Red blood"), "bloodoverhaul_red")
    colour_picker(panel, L("Alien blood"), "bloodoverhaul_alien")
    panel:Help(L("Limits: 640 particles per second, 512 alive; 48 new stains per second, 384 until map cleanup or Clear all decals. Existing stains stay when impacts are turned off."))
    panel:Button(L("Test splats where you look"), "bloodoverhaul_test")
    panel:Button(L("Clear all decals"), "bloodoverhaul_clear")
    panel:Button(L("Reset blood settings"), "bloodoverhaul_reset")
    panel:Help(L("New patterns made with an AI image model. Base and style credit: Crunchy's 2022 Blood Overhaul (2683396098); its original textures and derived maps are not bundled."))
end
BO.BuildMenu = build
-- The complete companion owns the tab/categories. A part tested alone has the same usable panel.
if not file.Exists("autorun/client/nativeloader_menu.lua", "LUA") then
    hook.Add("AddToolMenuTabs", "nlblood", function() spawnmenu.AddToolTab("RTX Remix", "RTX Remix", "icon16/lightbulb.png") end)
    hook.Add("AddToolMenuCategories", "nlblood", function() spawnmenu.AddToolCategory("RTX Remix", "Blood", L("Blood")) end)
end
hook.Add("PopulateToolMenu", "bloodoverhaul_menu", function()
    spawnmenu.AddToolMenuOption("RTX Remix", "Blood", "bloodoverhaul_settings", L("Blood and impacts"), "", "", build)
end)
