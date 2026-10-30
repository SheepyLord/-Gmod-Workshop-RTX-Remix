-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Tool Menu for RTX Light Wrapper
if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

hook.Add("PopulateToolMenu", "RTXLightWrapper_Menu", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix - API Lights", "RTX_Light_Wrapper", NL("Wrapper - Basic"), "", "", function(panel)
        panel:ClearControls()

        panel:Help(NL("Automatically converts Garry's Mod point and spot lights into Remix API Lights"))
        
        -- Enable/Disable
        local enableCheckbox = panel:CheckBox(NL("Enable Light Wrapper"), "rtx_light_wrapper_enabled")
        
        local brightnessSlider = panel:NumSlider(NL("Brightness Scale"), "rtx_light_wrapper_brightness_scale", 0, 500, 0)
        if brightnessSlider then brightnessSlider:SetDecimals(0) end
        
        -- Update controls based on lightupdater state
        local function UpdateControls()
            local lightupdaterEnabled = GetConVar("rtx_lightupdater"):GetBool()
            local enabled = not lightupdaterEnabled
            if enableCheckbox then enableCheckbox:SetEnabled(enabled) end
            if brightnessSlider then brightnessSlider:SetEnabled(enabled) end
        end
        
        UpdateControls()
    end)
end)
