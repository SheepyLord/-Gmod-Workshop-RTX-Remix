-- The two independently testable parts also keep one RTX tab without the complete companion.
-- In the combined package nativeloader_menu.lua owns the wrapper and translated categories.
if not NativeLoaderBundledDTS or NativeLoaderBundledPanels then return end
if file.Exists("autorun/client/nativeloader_menu.lua", "LUA") then return end
NativeLoaderBundledPanels = true
local i18n = file.Exists("nativeloader/i18n.lua", "LUA") and include("nativeloader/i18n.lua")
local function L(text) return i18n and i18n.L(text) or text end
local original = spawnmenu.AddToolMenuOption
function spawnmenu.AddToolMenuOption(tab, category, id, label, command, config, build, ...)
    if id == "dts_settings" then return end
    if id == "dynamic_toolgun_screen" then
        local title = i18n and L("Dynamic toolgun screen") or "#tool.dynamic_toolgun_screen.name"
        return original("RTX Remix", "Rendering", id, title, command, config, build, ...)
    end
    return original(tab, category, id, label, command, config, build, ...)
end
hook.Add("AddToolMenuTabs", "nativeloader_bundled_panels", function()
    spawnmenu.AddToolTab("RTX Remix", "RTX Remix", "icon16/lightbulb.png")
end)
hook.Add("AddToolMenuCategories", "nativeloader_bundled_panels", function()
    spawnmenu.AddToolCategory("RTX Remix", "Rendering", L("Rendering"))
end)
