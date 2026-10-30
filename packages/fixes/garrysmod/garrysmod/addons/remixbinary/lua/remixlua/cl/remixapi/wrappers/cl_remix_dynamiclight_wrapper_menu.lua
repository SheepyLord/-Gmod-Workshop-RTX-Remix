-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Tool Menu for RTX DynamicLight Wrapper
if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

hook.Add("PopulateToolMenu", "RTXDynamicLightWrapper_Menu", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix - API Lights", "RTX_DynamicLight_Wrapper", NL("Wrapper - Dynamic"), "", "", function(panel)
        panel:ClearControls()
        
        panel:Help(NL("Convert DynamicLight() calls to Remix API lights"))
        panel:Help(NL("Works with SWEPs like lanterns, and other addons that use dynamic lights"))
        
        -- Enable/Disable
        local enableCheckbox = panel:CheckBox(NL("Enable Dynamic Light Wrapper"), "rtx_dynamiclight_wrapper_enabled")
        
        local brightnessSlider = panel:NumSlider(NL("Brightness Scale"), "rtx_dynamiclight_wrapper_brightness_scale", 1, 200, 0)
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
