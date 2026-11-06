-- One "RTX Remix" tab in the spawn menu (ADR 0022). The RTX add-ons put their panels under four
-- Utilities categories ("RTX", "RTX Remix", "RTX Remix - API Lights", "Glass Rewrite Remixed"); they
-- are moved into this tab as they register, untouched. The tab adds:
--   * Start here: status, the guide, the classic settings, the guard, the language;
--   * Remix settings: common Remix options. A value set here is kept in a saved client setting
--     (nativeloader_remix_<name>) and applied when edited. Replaying them at startup is opt-in;
--     otherwise Remix's own saved files remain authoritative.
--   * Sky and weather: the physical sky, its time of day and the weather (nativeloader_sky.lua).
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
local CATEGORIES = { N("Start here"), N("Remix settings"), N("Sky and weather"), N("Rendering"), N("Lights"),
    N("Water and glass"), N("Blood") }

local function remix_ready()
    return istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable)
end

-- The local body proxy's switch, rtx_pseudoplayer, belongs to the RTX fixes: cl_rtx_misc.lua creates it
-- (default 1) before this file loads. Turning it on asks Remix for the player's primary shadows
-- (ADR 0043). Only that toggle writes the option, or the opt-in startup replay below: at map start
-- Remix's saved setting wins (ADR 0044), so a shadow turned off in Alt+X and saved stays off.
CreateClientConVar("rtx_pseudoplayer_offset_z", "0", true, false)
local function player_shadow()
    local body = GetConVar("rtx_pseudoplayer")
    if body and body:GetBool() and remix_ready() then
        RemixConfig.SetConfigVariable("rtx.playerModel.enablePrimaryShadows", "True")
    end
end
cvars.AddChangeCallback("rtx_pseudoplayer", player_shadow, "nativeloader_player_shadow")

-- Remix's own volumetric fog presets ("Volumetric Visual Presets" in its menu,
-- rtx_global_volumetrics.cpp), applied as its Apply button does: the four fog values, the game's
-- fog no longer remapped. Volumetrics are switched on too, or the preset shows nothing. The sky's
-- weather leaves the fog alone while one is chosen (nativeloader_sky.lua).
local FOG_OPTIONS = { "rtx.volumetrics.transmittanceColor", "rtx.volumetrics.transmittanceMeasurementDistanceMeters",
    "rtx.volumetrics.singleScatteringAlbedo", "rtx.volumetrics.anisotropy" }
local FOG = {
    default = { "0.999, 0.999, 0.999", "200", "0.999, 0.999, 0.999", "0" },
    heavyFog = { "0.85, 0.85, 0.85", "5", "0.9, 0.9, 0.9", "-0.2" },
    lightFog = { "0.93, 0.93, 0.93", "15", "0.95, 0.95, 0.95", "-0.1" },
    mist = { "0.96, 0.96, 0.96", "50", "0.98, 0.98, 0.98", "0.1" },
    haze = { "0.9, 0.85, 0.75", "70", "0.8, 0.8, 0.8", "0.2" },
    dust = { "0.87, 0.73, 0.5", "60", "0.85, 0.75, 0.65", "0.4" },
    smoke = { "0.87, 0.73, 0.5", "20", "0.85, 0.75, 0.65", "0.6" },
}
local fog_active = false
hook.Add("NativeLoaderRemixFogOverride", "nativeloader_menu", function() return fog_active end)
local function apply_fog(name)
    local values = FOG[name]
    if not values then return end
    RemixConfig.SetConfigVariable("rtx.volumetrics.enable", "True")
    RemixConfig.SetConfigVariable("rtx.volumetrics.enableFogRemap", "False")
    for i, option in ipairs(FOG_OPTIONS) do RemixConfig.SetConfigVariable(option, values[i]) end
    fog_active = true
end

-- Remix options with a short name, a label and the control kind, and for a choice that sets several
-- options the function that does it. Keys are the runtime's option names (they appear in the classic
-- install's rtx.conf/user.conf and the runtime log). Product names (DLSS, XeSS, FSR, ...) are not
-- translated.
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
    { "max_bounces", "rtx.pathMaxBounces", N("Max light bounces"), "number", { 1, 15, 0, 12 } },
    -- The sun and the clouds are the "Sky and weather" panel's (nativeloader_sky.lua), and so is the
    -- fog, unless a fog preset is chosen here.
    { "sky_brightness", "rtx.skyBrightness", N("Sky brightness"), "number", { 0, 10, 2, 1 },
        N("The map's own skybox only.") },
    { "fog", "rtx.volumetrics", N("Fog"), "choice",
        { { N("Remix default"), "default" }, { N("Heavy fog"), "heavyFog" }, { N("Light fog"), "lightFog" },
          { N("Mist"), "mist" }, { N("Haze"), "haze" }, { N("Dust"), "dust" }, { N("Smoke"), "smoke" } },
        N("Remix's volumetric fog presets. One chosen here replaces the weather's fog. Dense fog stays dark where no light reaches it."),
        apply_fog },
    { "post_effects", "rtx.postfx.enable", N("Post effects"), "bool", nil, N("Bloom, motion blur and film grain.") },
    { "colour_purity", "rtx.tonemap.psycho17.purityScale", N("Tone map colour purity"), "number", { 0, 5, 2, 1 } },
}

local replay = CreateClientConVar("nativeloader_remix_reapply", "0", true, false,
    "Explicitly reapply RTX tab overrides at map start, instead of using only Remix's saved settings")
local convars, enabled = {}, {}
for _, option in ipairs(OPTIONS) do
    convars[option[1]] = CreateClientConVar("nativeloader_remix_" .. option[1], "", true, false,
        "Remix " .. option[2] .. " set from the RTX Remix tab (empty: leave it to Remix's files)")
    if option[4] == "number" then
        -- Old sliders could archive zero just by opening the panel. Retain the value, but require
        -- a new explicit selection before using it; zero itself can be an intentional setting.
        enabled[option[1]] = CreateClientConVar("nativeloader_remix_" .. option[1] .. "_enabled", "0", true, false)
    end
end

local function number_value(option)
    local value = tonumber(convars[option[1]]:GetString())
    local range = option[5]
    if value and value == value and value >= range[1] and value <= range[2] then return value end
end

local started = false
local function push(option)
    local value = convars[option[1]]:GetString()
    if not started or value == "" or not remix_ready() then return end
    if option[4] == "number" then
        if not enabled[option[1]]:GetBool() or number_value(option) == nil then return end
    elseif option[4] == "choice" then
        local valid = false
        for _, choice in ipairs(option[5]) do if choice[2] == value then valid = true end end
        if not valid then return end
    elseif value ~= "0" and value ~= "1" then
        return
    end
    if option[7] then return option[7](value) end
    if option[4] == "bool" then value = tobool(value) and "True" or "False" end
    RemixConfig.SetConfigVariable(option[2], value)
end

for _, option in ipairs(OPTIONS) do
    cvars.AddChangeCallback("nativeloader_remix_" .. option[1], function()
        if option[1] == "fog" and convars.fog:GetString() == "" then fog_active = false end
        push(option)
    end, "nativeloader_menu")
    if enabled[option[1]] then
        cvars.AddChangeCallback("nativeloader_remix_" .. option[1] .. "_enabled", function()
            if enabled[option[1]]:GetBool() and number_value(option) == nil then
                RunConsoleCommand("nativeloader_remix_" .. option[1], tostring(option[5][4]))
            else
                push(option)
            end
        end, "nativeloader_menu")
    end
end
hook.Add("InitPostEntity", "nativeloader_remix_options", function()
    timer.Simple(4, function()
        started = true
        if replay:GetBool() then
            for _, option in ipairs(OPTIONS) do push(option) end
            player_shadow()
        end
    end)
end)

-- Move the RTX add-ons' panels into the tab as they register (they do so in PopulateToolMenu).
local add_tool_menu_option = spawnmenu.AddToolMenuOption
local function readable_panel(build)
    if not isfunction(build) then return build end
    return function(panel)
        i18n.PreparePanel(panel)
        return build(panel)
    end
end
function spawnmenu.AddToolMenuOption(tab, category, id, label, command, config, build, ...)
    -- R20-C: retain the actual tracking tool, with its full thirteen-language settings panel.
    -- Its extra Utilities shortcut would be a second panel; the tool itself is moved instead.
    if NativeLoaderBundledDTS and id == "dts_settings" then return end
    if NativeLoaderBundledDTS and id == "dynamic_toolgun_screen" then
        return add_tool_menu_option(TAB, N("Rendering"), id, L("Dynamic toolgun screen"), command, config, readable_panel(build), ...)
    end
    if tab == "Utilities" and MOVED[category] then
        return add_tool_menu_option(TAB, MOVED[category], id, label, command, config, readable_panel(build), ...)
    end
    if tab == TAB then build = readable_panel(build) end
    return add_tool_menu_option(tab, category, id, label, command, config, build, ...)
end

hook.Add("AddToolMenuTabs", "nativeloader_menu", function()
    spawnmenu.AddToolTab(TAB, "#" .. TAB, "icon16/lightbulb.png")
end)

hook.Add("AddToolMenuCategories", "nativeloader_menu", function()
    for _, category in ipairs(CATEGORIES) do
        spawnmenu.AddToolCategory(TAB, category, L(category))
    end
end)

local function loader_status()
    local ok, status = pcall(function()
        local body = file.Read("native-loader/status.json", "DATA")
        return body and util.JSONToTable(body)
    end)
    if ok and type(status) == "table" and status.schema == 1 then return status end
end

-- I2 is optional: older loaders report no performance tier. Read the local report when the panel
-- opens, and describe the loader's choice without writing any Remix options or configuration.
local function performance_tier_line(status)
    if not status then return end
    local activation = status.activation
    local tier = type(activation) == "table" and activation.performance_tier
    if type(tier) ~= "table" then return end
    if activation.non_nvidia or type(tier.adapter) ~= "string" or tier.adapter == "" then return end
    local levels = { high = N("High"), medium = N("Medium"), low = N("Low") }
    if not levels[tier.tier] then return end
    if tier.tier ~= "high" and (type(tier.layer) ~= "string" or tier.layer == "") then
        local reason = type(tier.reason) == "string" and tier.reason ~= "" and tier.reason or
            L("No tier layer is available.")
        return string.format(L("Performance tier %s is not applied: %s. See Performance and memory in the guide."),
            L(levels[tier.tier]), reason)
    end
    local sources = { auto = N("Automatic selection"), config = N("Configuration override"),
        fallback = N("Compatibility fallback") }
    local adapter = tier.adapter
    local memory = tier.dedicated_vram_mib
    memory = type(memory) == "number" and memory >= 0 and memory < math.huge and
        string.format("%.0f", memory) or "?"
    return string.format(L("Performance tier: %s (%s; %s, %s MiB VRAM). To change it, set remix.performance_tier in native-loader\\config.json to auto, high, medium or low, then restart Garry's Mod."),
        L(levels[tier.tier]), L(sources[tier.source] or N("Unknown source")), adapter, memory)
end

-- R13 (ADR 0101): loaders from 0.13.0 report a memory profile; older ones report none.
local function memory_profile_line(status)
    local memory = status and type(status.activation) == "table" and status.activation.memory
    if type(memory) ~= "table" then return end
    local profiles = { below_minimum = N("Below the minimum"), minimum = N("Minimum"),
        recommended = N("Recommended"), high = N("High") }
    if not profiles[memory.profile] then return end
    local function count(value)
        return type(value) == "number" and value >= 0 and value < math.huge and string.format("%.0f", value) or "?"
    end
    return string.format(L("Memory profile: %s (%s MiB VRAM, %s MiB RAM). Characters kept ready for an instant spawn: %s; the others load when first used. To change it, set remix.memory_profile in native-loader\\config.json to auto, minimum, recommended or high, then restart Garry's Mod."),
        L(profiles[memory.profile]), count(memory.vram_mib), count(memory.ram_mib), count(memory.warm_characters))
end

local function start_here(panel)
    panel:Help(L("RTX Remix is running in this session. Every setting of the RTX package is in this tab, in the groups on the left."))
    local status = loader_status()
    local tier = performance_tier_line(status)
    if tier then panel:Help(tier) end
    local memory = memory_profile_line(status)
    if memory then panel:Help(memory) end
    panel:Button(L("Open the RTX Remix guide"), "nativeloader_guide")
    panel:Button(L("Performance and memory guide"), "nativeloader_stability_guide")
    panel:Button(L("Print the loader's status to the console"), "nativeloader_status")
    panel:Help(L("When RTX first ran, the RTX add-ons took the settings of the original RTX install, except for settings you had already changed. This button applies all of them again, also over your own changes."))
    panel:Button(L("Use the classic RTX settings"), "nativeloader_rtx_defaults")
    panel:CheckBox(L("RTX session guard"), "nativeloader_guard")
    panel:ControlHelp(L("Stops other add-ons from undoing RTX settings or drawing post-processing over the picture. Turn it off only to test an add-on that misbehaves."))
    panel:Help(L("Remix's own menu: press Alt+X, and save your changes there to keep them. Before you change single settings, set Graphics Preset, or DLSS Preset for the DLSS settings, to Custom; the guide shows how."))
    local box = panel:ComboBox(L("Language"), "nativeloader_language")
    box:AddChoice(L("Same as Garry's Mod"), "")
    for _, language in ipairs(i18n.languages) do box:AddChoice(language[2], language[1]) end
    panel:ControlHelp(L("Language of this tab and the guide"))
end

local function remix_settings(panel)
    if not remix_ready() then
        panel:Help(L("The Remix API is not available in this session, so these settings cannot be applied. Run nativeloader_status for details."))
    end
    panel:Help(L("Changes here apply at once, for this session. To keep them, press Alt+X and save them there. The values shown are this panel's own choices, not a live reading of Remix."))
    panel:CheckBox(L("Reapply these overrides at every launch"), "nativeloader_remix_reapply")
    panel:ControlHelp(L("Off (the default), Remix starts with its own saved settings. On, this panel applies its choices at every start, over those settings."))
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
            panel:CheckBox(string.format(L("Set %s here"), L(option[3])), name .. "_enabled")
            -- Never bind a numeric widget to the empty-string sentinel. Set up its range and
            -- initial value before installing the edit handler, and guard later read-only syncs.
            local slider = panel:NumSlider(L(option[3]), nil, range[1], range[2], range[3])
            local syncing = false
            local last_value, last_enabled
            local function sync()
                local value = number_value(option) or range[4]
                local active = enabled[option[1]]:GetBool()
                if value == last_value and active == last_enabled then return end
                last_value, last_enabled = value, active
                syncing = true
                slider:SetValue(value)
                slider:SetEnabled(active)
                syncing = false
            end
            sync()
            slider.OnValueChanged = function(_, value)
                if syncing or not enabled[option[1]]:GetBool() then return end
                RunConsoleCommand(name, tostring(math.Round(math.Clamp(value, range[1], range[2]), range[3])))
            end
            slider.Think = sync
        end
        -- A label holds about 100 pixels; what does not fit goes below the control.
        if option[6] then panel:ControlHelp(L(option[6])) end
    end
    panel:ControlHelp(L("A number is used only while the box above it, Set ... here, is ticked. Zero is a valid value for sky brightness and colour purity."))
    panel:Button(L("Clear this panel's overrides"), "nativeloader_remix_reset")
end

local function player_settings(panel)
    panel:CheckBox(L("Local player shadow"), "rtx_pseudoplayer")
    panel:ControlHelp(L("Shows the shadow and reflection of your own body while you play in first person. Other players and ragdolls are not affected."))
    panel:NumSlider(L("Body height offset (units)"), "rtx_pseudoplayer_offset_z", -32, 64, 1)
    panel:ControlHelp(L("Raises (positive) or lowers (negative) only that body. Your view and your collisions stay where they are."))
end

local function toolgun_settings(panel)
    panel:CheckBox(L("Keep toolgun text sharp"), "nativeloader_toolgun_screen")
    panel:ControlHelp(L("Draws the toolgun's screen at full resolution after DLSS or another upscaler, so its text stays readable. Animated and custom screens keep working."))
end

local function model_layers_settings(panel)
    panel:CheckBox(L("Hide outline meshes"), "nativeloader_ignore_outlines")
    panel:ControlHelp(L("Hides the outline shells that many anime models have: path tracing draws them as a dark layer over the model. The model's other materials are not changed."))
    panel:CheckBox(L("Imported game PBR"), "rtx_topbr_game_maps")
    panel:ControlHelp(L("Uses the game's own maps for characters imported from Wuthering Waves, Endfield and Silver Palace. Skin and faces stay as they are. Off restores the original materials."))
    panel:CheckBox(L("Steady eye whites for imported characters"), "nativeloader_eye_whites")
    panel:ControlHelp(L("Keeps the whites of imported characters' eyes clean and bright. It finds them by their material names; if it misses one, choose them yourself below. Characters with a PBR pack keep its materials."))
    panel:NumSlider(L("Eye-white brightness"), "nativeloader_eye_white_brightness", 0, 200, 0)
    panel:ControlHelp(L("In percent; 100 is the tuned default. A change applies at once, to steady eye whites and to the eye glow of PBR packs that follows the scene's light; 0 removes that glow."))
    panel:Button(L("Choose eye-white materials"), "nativeloader_eye_white_materials")
    panel:CheckBox(L("Hide painted shadows"), "nativeloader_hide_painted_shadows")
    panel:ControlHelp(L("Leaves out the shadows that imported characters have painted over their eyes, under their fringe and on their faces: path tracing casts real shadows there. Their bodygroups and saves do not change."))
    panel:CheckBox(L("Solid hair"), "nativeloader_solid_hair")
    panel:ControlHelp(L("Draws an imported character's hair solid when its texture is mostly opaque but the alpha test would cut holes into it, as in hair from Endfield. Hair cut out of its texture strand by strand keeps its cutouts."))
end

concommand.Add("nativeloader_remix_reset", function()
    for _, option in ipairs(OPTIONS) do
        RunConsoleCommand("nativeloader_remix_" .. option[1], "")
        if enabled[option[1]] then RunConsoleCommand("nativeloader_remix_" .. option[1] .. "_enabled", "0") end
    end
    RunConsoleCommand("nativeloader_remix_reapply", "0")
    print("[nativeloader] Remix settings from the RTX Remix tab cleared; they apply from Remix's files at the next start.")
end)

hook.Add("PopulateToolMenu", "nativeloader_menu", function()
    add_tool_menu_option(TAB, N("Start here"), "nativeloader_start", L("Start here"), "", "", readable_panel(start_here))
    add_tool_menu_option(TAB, N("Remix settings"), "nativeloader_remix", L("Common Remix settings"), "", "", readable_panel(remix_settings))
    add_tool_menu_option(TAB, N("Rendering"), "nativeloader_player", L("Player models"), "", "", readable_panel(player_settings))
    add_tool_menu_option(TAB, N("Rendering"), "nativeloader_toolgun", L("Toolgun screen"), "", "", readable_panel(toolgun_settings))
    add_tool_menu_option(TAB, N("Rendering"), "nativeloader_model_layers", L("Model outlines"), "", "", readable_panel(model_layers_settings))
end)
