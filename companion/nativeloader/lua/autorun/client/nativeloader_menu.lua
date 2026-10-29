-- One "RTX Remix" tab in the spawn menu (ADR 0022). The RTX add-ons put their panels under four
-- Utilities categories ("RTX", "RTX Remix", "RTX Remix - API Lights", "Glass Rewrite Remixed"); they
-- are moved into this tab as they register, untouched. The tab adds:
--   * Start here: status, the guide, the classic settings, the guard;
--   * Remix settings: common Remix options. A value set here is kept in a saved client setting
--     (nativeloader_remix_<name>) and given to Remix at every session start through the RTX fixes'
--     RemixConfig API. Empty means "leave it to Remix's own files".
-- Documented in nativeloader_menu.lua.md beside this file.
local TAB = "RTX Remix"
local MOVED = {
    ["RTX Remix"] = "Rendering",
    ["RTX Remix - API Lights"] = "Lights",
    ["RTX"] = "Water and glass",
    ["Glass Rewrite Remixed"] = "Water and glass",
}

-- Remix options with a short name, a label and the control kind. Keys are the runtime's option names
-- (they appear in the classic install's rtx.conf/user.conf and the runtime log).
local OPTIONS = {
    { "graphics_preset", "rtx.graphicsPreset", "Graphics preset", "choice",
        { { "Ultra", "0" }, { "High", "1" }, { "Medium", "2" }, { "Low", "3" }, { "Custom (keeps your own settings)", "4" },
          { "Automatic (by GPU)", "5" } } },
    { "upscaler", "rtx.upscalerType", "Upscaler", "choice",
        { { "None", "0" }, { "DLSS", "1" }, { "NIS", "2" }, { "TAA-U", "3" }, { "XeSS", "4" }, { "FSR", "5" } } },
    { "dlss_quality", "rtx.qualityDLSS", "DLSS quality", "choice",
        { { "Ultra performance", "0" }, { "Performance", "1" }, { "Balanced", "2" }, { "Quality", "3" }, { "Auto", "4" }, { "Full resolution (DLAA)", "5" } } },
    { "frame_generation", "rtx.frameGenerationType", "Frame generation", "choice", { { "Off", "0" }, { "DLSS-G", "1" }, { "FSR 3", "2" } } },
    { "indirect_mode", "rtx.integrateIndirectMode", "Indirect lighting", "choice",
        { { "Importance sampled", "0" }, { "ReSTIR GI", "1" }, { "Neural Radiance Cache", "2" }, { "Hashed radiance cache", "3" } } },
    { "max_bounces", "rtx.pathMaxBounces", "Most light bounces", "number", { 1, 16, 0 } },
    { "fog_distance", "rtx.volumetrics.transmittanceMeasurementDistanceMeters", "Fog distance (m, larger is clearer)", "number", { 1, 2000, 0 } },
    { "fog_anisotropy", "rtx.volumetrics.anisotropy", "Fog light scattering forward", "number", { -1, 1, 2 } },
    { "sky_brightness", "rtx.skyBrightness", "Sky brightness", "number", { 0, 10, 2 } },
    { "sun_elevation", "rtx.atmosphere.sunElevation", "Sun height (degrees)", "number", { -10, 90, 0 } },
    { "sun_rotation", "rtx.atmosphere.sunRotation", "Sun direction (degrees)", "number", { 0, 360, 0 } },
    { "clouds", "rtx.atmosphere.cloudEnabled", "Clouds", "bool" },
    { "post_effects", "rtx.postfx.enable", "Post effects (bloom, motion blur, film grain)", "bool" },
    { "colour_purity", "rtx.tonemap.psycho17.purityScale", "Tone map colour purity", "number", { 0, 3, 2 } },
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
    for _, category in ipairs({ "Start here", "Remix settings", "Rendering", "Lights", "Water and glass" }) do
        spawnmenu.AddToolCategory(TAB, category, category)
    end
end)

local function start_here(panel)
    panel:Help("RTX Remix runs in this session through the native loader. Everything RTX lives in this tab.")
    panel:Button("Open the RTX Remix guide", "nativeloader_guide")
    panel:Button("Print the loader's status to the console", "nativeloader_status")
    panel:Help("Classic settings: the values of the original RTX install. They were applied once, only where a setting was still at its default. This button applies all of them again.")
    panel:Button("Use the classic RTX settings", "nativeloader_rtx_defaults")
    panel:CheckBox("Keep add-ons from undoing RTX settings or drawing post-processing over the image", "nativeloader_guard")
    panel:ControlHelp("Turn this off only to test an add-on that misbehaves.")
    panel:Help("Remix's own menu: press Alt+X. Choose Custom as the graphics preset before changing single settings, then use Save, or they come back at the next start.")
end

local function remix_settings(panel)
    if not remix_ready() then
        panel:Help("The Remix API is not available in this session, so these settings cannot be applied. Run nativeloader_status for details.")
    end
    panel:Help("A setting chosen here is kept and applied at every start. Clear it (the empty choice, or the reset button) to leave it to Remix's own files.")
    for _, option in ipairs(OPTIONS) do
        local name = "nativeloader_remix_" .. option[1]
        if option[4] == "choice" then
            local box = panel:ComboBox(option[3], name)
            box:AddChoice("(leave to Remix)", "")
            for _, choice in ipairs(option[5]) do box:AddChoice(choice[1], choice[2]) end
        elseif option[4] == "bool" then
            local box = panel:ComboBox(option[3], name)
            box:AddChoice("(leave to Remix)", "")
            box:AddChoice("On", "1")
            box:AddChoice("Off", "0")
        else
            local range = option[5]
            panel:NumSlider(option[3], name, range[1], range[2], range[3])
        end
    end
    panel:Button("Reset these to Remix's own values", "nativeloader_remix_reset")
end

concommand.Add("nativeloader_remix_reset", function()
    for _, option in ipairs(OPTIONS) do RunConsoleCommand("nativeloader_remix_" .. option[1], "") end
    print("[nativeloader] Remix settings from the RTX Remix tab cleared; they apply from Remix's files at the next start.")
end)

hook.Add("PopulateToolMenu", "nativeloader_menu", function()
    add_tool_menu_option(TAB, "Start here", "nativeloader_start", "Start here", "", "", start_here)
    add_tool_menu_option(TAB, "Remix settings", "nativeloader_remix", "Common Remix settings", "", "", remix_settings)
end)
