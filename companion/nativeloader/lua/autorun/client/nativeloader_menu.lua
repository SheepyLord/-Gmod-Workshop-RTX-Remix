-- One "RTX Remix" tab in the spawn menu (ADR 0022). The RTX add-ons put their panels under four
-- Utilities categories ("RTX", "RTX Remix", "RTX Remix - API Lights", "Glass Rewrite Remixed"); they
-- are moved into this tab as they register, untouched. The tab adds:
--   * Start here: status, the guide, the classic settings, the guard, the language;
--   * Remix settings: common Remix options. A value set here is kept in a saved client setting
--     (nativeloader_remix_<name>) and given to Remix at every session start through the RTX fixes'
--     RemixConfig API. Empty means "leave it to Remix's own files".
-- The tab's text is translated (nativeloader/i18n.lua). Documented in nativeloader_menu.lua.md beside this file.
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N

local TAB = "RTX Remix"
-- The add-ons' categories, and the tab's category each goes to (category names stay English; the
-- labels shown are translated).
local MOVED = {
    ["RTX Remix"] = N("Rendering"),
    ["RTX Remix - API Lights"] = N("Lights"),
    ["RTX"] = N("Water and glass"),
    ["Glass Rewrite Remixed"] = N("Water and glass"),
}
local CATEGORIES = { N("Start here"), N("Remix settings"), N("Rendering"), N("Lights"), N("Water and glass") }

-- Remix options with a short name, a label and the control kind. Keys are the runtime's option names
-- (they appear in the classic install's rtx.conf/user.conf and the runtime log). Product names
-- (DLSS, XeSS, FSR, ...) are not translated.
local OPTIONS = {
    { "graphics_preset", "rtx.graphicsPreset", N("Graphics preset"), "choice",
        { { N("Ultra"), "0" }, { N("High"), "1" }, { N("Medium"), "2" }, { N("Low"), "3" },
          { N("Custom (keeps your own settings)"), "4" }, { N("Automatic (by GPU)"), "5" } } },
    { "upscaler", "rtx.upscalerType", N("Upscaler"), "choice",
        { { N("None"), "0" }, { "DLSS", "1" }, { "NIS", "2" }, { "TAA-U", "3" }, { "XeSS", "4" }, { "FSR", "5" } } },
    { "dlss_quality", "rtx.qualityDLSS", N("DLSS quality"), "choice",
        { { N("Ultra performance"), "0" }, { N("Performance"), "1" }, { N("Balanced"), "2" }, { N("Quality"), "3" },
          { N("Auto"), "4" }, { N("Full resolution (DLAA)"), "5" } } },
    { "frame_generation", "rtx.frameGenerationType", N("Frame generation"), "choice",
        { { N("Off"), "0" }, { "DLSS-G", "1" }, { "FSR 3", "2" } } },
    { "indirect_mode", "rtx.integrateIndirectMode", N("Indirect lighting"), "choice",
        { { N("Importance sampled"), "0" }, { "ReSTIR GI", "1" }, { N("Neural Radiance Cache"), "2" },
          { N("Hashed radiance cache"), "3" } } },
    { "max_bounces", "rtx.pathMaxBounces", N("Most light bounces"), "number", { 1, 16, 0 } },
    { "fog_distance", "rtx.volumetrics.transmittanceMeasurementDistanceMeters", N("Fog distance (m)"), "number", { 1, 2000, 0 },
        N("Larger is clearer.") },
    { "fog_anisotropy", "rtx.volumetrics.anisotropy", N("Fog scattering"), "number", { -1, 1, 2 },
        N("How much the fog scatters light forward (-1 to 1).") },
    { "sky_brightness", "rtx.skyBrightness", N("Sky brightness"), "number", { 0, 10, 2 } },
    { "sun_elevation", "rtx.atmosphere.sunElevation", N("Sun height (degrees)"), "number", { -10, 90, 0 } },
    { "sun_rotation", "rtx.atmosphere.sunRotation", N("Sun direction (degrees)"), "number", { 0, 360, 0 } },
    { "clouds", "rtx.atmosphere.cloudEnabled", N("Clouds"), "bool" },
    { "post_effects", "rtx.postfx.enable", N("Post effects"), "bool", nil, N("Bloom, motion blur and film grain.") },
    { "colour_purity", "rtx.tonemap.psycho17.purityScale", N("Tone map colour purity"), "number", { 0, 3, 2 } },
}

local convars = {}
for _, option in ipairs(OPTIONS) do
    convars[option[1]] = CreateClientConVar("nativeloader_remix_" .. option[1], "", true, false,
        "Remix " .. option[2] .. " set from the RTX Remix tab (empty: leave it to Remix's files)")
end

local function remix_ready()
    return istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable)
end

local function push(option)
    local value = convars[option[1]]:GetString()
    if value == "" or not remix_ready() then return end
    if option[4] == "bool" then value = tobool(value) and "True" or "False" end
    RemixConfig.SetConfigVariable(option[2], value)
end

for _, option in ipairs(OPTIONS) do
    cvars.AddChangeCallback("nativeloader_remix_" .. option[1], function() push(option) end, "nativeloader_menu")
end
hook.Add("InitPostEntity", "nativeloader_remix_options", function()
    timer.Simple(4, function() for _, option in ipairs(OPTIONS) do push(option) end end)
end)

-- Move the RTX add-ons' panels into the tab as they register (they do so in PopulateToolMenu).
local add_tool_menu_option = spawnmenu.AddToolMenuOption
function spawnmenu.AddToolMenuOption(tab, category, ...)
    if tab == "Utilities" and MOVED[category] then
        return add_tool_menu_option(TAB, MOVED[category], ...)
    end
    return add_tool_menu_option(tab, category, ...)
end

hook.Add("AddToolMenuTabs", "nativeloader_menu", function()
    spawnmenu.AddToolTab(TAB, "#" .. TAB, "icon16/lightbulb.png")
end)

hook.Add("AddToolMenuCategories", "nativeloader_menu", function()
    for _, category in ipairs(CATEGORIES) do
        spawnmenu.AddToolCategory(TAB, category, L(category))
    end
end)

local function start_here(panel)
    panel:Help(L("RTX Remix runs in this session through the native loader. Everything RTX lives in this tab."))
    panel:Button(L("Open the RTX Remix guide"), "nativeloader_guide")
    panel:Button(L("Print the loader's status to the console"), "nativeloader_status")
    panel:Help(L("Classic settings: the values of the original RTX install. They were applied once, only where a setting was still at its default. This button applies all of them again."))
    panel:Button(L("Use the classic RTX settings"), "nativeloader_rtx_defaults")
    panel:Help(L("Keep add-ons from undoing RTX settings or drawing post-processing over the image"))
    panel:CheckBox(L("RTX session guard"), "nativeloader_guard")
    panel:ControlHelp(L("Turn this off only to test an add-on that misbehaves."))
    panel:Help(L("Remix's own menu: press Alt+X. Choose Custom as the graphics preset before changing single settings, then use Save, or they come back at the next start."))
    local box = panel:ComboBox(L("Language"), "nativeloader_language")
    box:AddChoice(L("Same as Garry's Mod"), "")
    for _, language in ipairs(i18n.languages) do box:AddChoice(language[2], language[1]) end
    panel:ControlHelp(L("Language of this tab and the guide"))
end

local function remix_settings(panel)
    if not remix_ready() then
        panel:Help(L("The Remix API is not available in this session, so these settings cannot be applied. Run nativeloader_status for details."))
    end
    panel:Help(L("A setting chosen here is kept and applied at every start. Clear it (the empty choice, or the reset button) to leave it to Remix's own files."))
    for _, option in ipairs(OPTIONS) do
        local name = "nativeloader_remix_" .. option[1]
        if option[4] == "choice" then
            local box = panel:ComboBox(L(option[3]), name)
            box:AddChoice(L("(leave to Remix)"), "")
            for _, choice in ipairs(option[5]) do box:AddChoice(L(choice[1]), choice[2]) end
        elseif option[4] == "bool" then
            local box = panel:ComboBox(L(option[3]), name)
            box:AddChoice(L("(leave to Remix)"), "")
            box:AddChoice(L("On"), "1")
            box:AddChoice(L("Off"), "0")
        else
            local range = option[5]
            panel:NumSlider(L(option[3]), name, range[1], range[2], range[3])
        end
        -- A label holds about 100 pixels; what does not fit goes below the control.
        if option[6] then panel:ControlHelp(L(option[6])) end
    end
    panel:Button(L("Reset these to Remix's own values"), "nativeloader_remix_reset")
end

concommand.Add("nativeloader_remix_reset", function()
    for _, option in ipairs(OPTIONS) do RunConsoleCommand("nativeloader_remix_" .. option[1], "") end
    print("[nativeloader] Remix settings from the RTX Remix tab cleared; they apply from Remix's files at the next start.")
end)

hook.Add("PopulateToolMenu", "nativeloader_menu", function()
    add_tool_menu_option(TAB, N("Start here"), "nativeloader_start", L("Start here"), "", "", start_here)
    add_tool_menu_option(TAB, N("Remix settings"), "nativeloader_remix", L("Common Remix settings"), "", "", remix_settings)
end)
