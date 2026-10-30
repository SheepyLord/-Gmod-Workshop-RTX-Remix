-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Dedicated Tool Menu for Remix API Lights runtime controls
-- Loaded automatically by autorun/cl_rtx.lua which includes all files under remixlua/cl/remixapi/

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

hook.Add("PopulateToolMenu", "RemixAPILights", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix - API Lights", "RTX_Remix_API_Lights", NL("Map"), "", "", function(panel)
        panel:ClearControls()

        -- Section: Actions
        panel:Help(NL("Actions"))
        panel:Button(NL("Process Map Lights"), "rtx_api_map_lights_process")
        panel:Button(NL("Clear All Map Lights"), "rtx_api_map_lights_clear")

        -- Section: Runtime Modifiers
        panel:Help("")
        panel:Help(NL("Point Lights (light)"))
        panel:NumSlider(NL("Point Brightness"), "rtx_api_map_lights_point_brightness_mult", 0, 10, 1)
        panel:NumSlider(NL("Point Radius"), "rtx_api_map_lights_point_radius_mult", 0, 10, 1)
        panel:NumSlider(NL("Point Size"), "rtx_api_map_lights_point_size_mult", 0, 25, 1)
        panel:NumSlider(NL("Point Volumetrics"), "rtx_api_map_lights_point_volumetric_mult", 0, 10, 1)
        local btnPointReset = panel:Button(NL("Reset"), "")
        btnPointReset.DoClick = function()
            RunConsoleCommand("rtx_api_map_lights_point_brightness_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_point_radius_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_point_size_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_point_volumetric_mult", "1")
        end

        panel:Help("")
        panel:Help(NL("Spot Lights (light_spot)"))
        panel:NumSlider(NL("Spot Brightness"), "rtx_api_map_lights_spot_brightness_mult", 0, 10, 1)
        panel:NumSlider(NL("Spot Radius"), "rtx_api_map_lights_spot_radius_mult", 0, 10, 1)
        panel:NumSlider(NL("Spot Size"), "rtx_api_map_lights_spot_size_mult", 0, 25, 1)
        panel:NumSlider(NL("Spot Volumetrics"), "rtx_api_map_lights_spot_volumetric_mult", 0, 10, 1)
        local btnSpotReset = panel:Button(NL("Reset"), "")
        btnSpotReset.DoClick = function()
            RunConsoleCommand("rtx_api_map_lights_spot_brightness_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_spot_radius_mult", "1.5")
            RunConsoleCommand("rtx_api_map_lights_spot_size_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_spot_volumetric_mult", "1")
        end

        panel:Help("")
        panel:Help(NL("Directional (light_environment)"))
        panel:NumSlider(NL("Brightness"), "rtx_api_map_lights_env_brightness_mult", 0, 10, 1)
        panel:NumSlider(NL("VRAD Scale"), "rtx_api_map_lights_env_vrad_scale", 0.0001, 0.01, 4)
        panel:NumSlider(NL("Angular Multiplier"), "rtx_api_map_lights_env_angular_mult", 0, 5, 1)
        panel:NumSlider(NL("Env Size"), "rtx_api_map_lights_env_size_mult", 0, 25, 1)
        panel:NumSlider(NL("Env Volumetrics"), "rtx_api_map_lights_env_volumetric_mult", 0, 10, 1)
        local btnEnvReset = panel:Button(NL("Reset"), "")
        btnEnvReset.DoClick = function()
            RunConsoleCommand("rtx_api_map_lights_env_brightness_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_env_vrad_scale", "0.003")
            RunConsoleCommand("rtx_api_map_lights_env_angular_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_env_size_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_env_volumetric_mult", "1")
            RunConsoleCommand("rtx_api_map_lights_env_dir_flip", "0")
            RunConsoleCommand("rtx_api_map_lights_env_max_brightness", "10")
            RunConsoleCommand("rtx_api_map_lights_env_ambient_to_sky", "1")
            RunConsoleCommand("rtx_api_map_lights_env_ambient_scale", "0.005")
        end

        -- Section: Debug
        panel:Help(NL("Debug"))
        panel:CheckBox(NL("Draw Debug Directions"), "rtx_api_map_lights_debug_vis")
        panel:CheckBox(NL("Show HUD Overlay"), "rtx_api_map_lights_debug_hud")
        panel:CheckBox(NL("Show Disabled Lights"), "rtx_api_map_lights_debug_hud_show_disabled")
        panel:NumSlider(NL("HUD Max Distance"), "rtx_api_map_lights_debug_hud_max_distance", 512, 8192, 0)
    end)
end)
