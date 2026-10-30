-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Tool Menu for RTX ProjectedTexture Wrapper
if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

hook.Add("PopulateToolMenu", "RTXProjectedTextureWrapper_Menu", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix - API Lights", "RTX_ProjectedTexture_Wrapper", NL("Wrapper - Projected Texture"), "", "", function(panel)
        panel:ClearControls()
        
        panel:Help(NL("Automatically convert ProjectedTexture() calls into Remix API spotlights"))
        panel:Help(NL("Works with Glide base headlights, spotlight entities, and other addons that use ProjectedTexture()"))

        -- Enable/Disable
        local enableCheckbox = panel:CheckBox(NL("Enable Projected Texture Wrapper"), "rtx_projectedtexture_wrapper_enabled")
        
        local brightnessSlider = panel:NumSlider(NL("Brightness Scale"), "rtx_projectedtexture_wrapper_brightness_scale", 1, 10000, 0)
        if brightnessSlider then brightnessSlider:SetDecimals(0) end
        
        panel:Help(NL("Position Offsets"))
        local offsetXSlider = panel:NumSlider(NL("Offset X (Forward/Back)"), "rtx_projectedtexture_wrapper_offset_x", -200, 200, 0)
        if offsetXSlider then offsetXSlider:SetDecimals(0) end
        
        local offsetYSlider = panel:NumSlider(NL("Offset Y (Left/Right)"), "rtx_projectedtexture_wrapper_offset_y", -200, 200, 0)
        if offsetYSlider then offsetYSlider:SetDecimals(0) end
        
        local offsetZSlider = panel:NumSlider(NL("Offset Z (Up/Down)"), "rtx_projectedtexture_wrapper_offset_z", -200, 200, 0)
        if offsetZSlider then offsetZSlider:SetDecimals(0) end
        
        -- Update controls based on lightupdater state
        local function UpdateControls()
            local lightupdaterEnabled = GetConVar("rtx_lightupdater"):GetBool()
            local enabled = not lightupdaterEnabled
            if enableCheckbox then enableCheckbox:SetEnabled(enabled) end
            if brightnessSlider then brightnessSlider:SetEnabled(enabled) end
            if offsetXSlider then offsetXSlider:SetEnabled(enabled) end
            if offsetYSlider then offsetYSlider:SetEnabled(enabled) end
            if offsetZSlider then offsetZSlider:SetEnabled(enabled) end
        end
        
        UpdateControls()
    end)
end)
