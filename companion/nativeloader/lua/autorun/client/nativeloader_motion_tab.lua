local i18n = include("nativeloader/i18n.lua")
local L = i18n.L
if not spawnmenu or not isfunction(spawnmenu.AddCreationTab) then return end
local key = "#nativeloader.motion_importer"
local function phrases()
    language.Add("nativeloader.motion_importer", L("Motion importer"))
    local entry = spawnmenu.GetCreationTabs()[key]
    if entry then entry.Tooltip = L("Open the VMD motion importer and motion library.") end
end
spawnmenu.AddCreationTab(key, function()
    local panel = vgui.Create("DPanel")
    panel:DockPadding(12, 12, 12, 12)
    local help = panel:Add("DLabel")
    help:Dock(TOP)
    help:SetWrap(true)
    help:SetAutoStretchVertical(true)
    help:SetDark(true)
    help:SetText(L("Import VMD files and manage your motion library and playback."))
    local button = panel:Add("DButton")
    button:Dock(TOP)
    button:DockMargin(0, 12, 0, 0)
    button:SetTall(36)
    button:SetText(L("Open motion importer"))
    local function available()
        return MMDVMDNPC and isfunction(MMDVMDNPC.OpenMotionManager)
    end
    button.Think = function(self) self:SetEnabled(available() == true) end
    button.DoClick = function()
        if available() then
            if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
            MMDVMDNPC.OpenMotionManager()
        end
    end
    return panel
end, "icon16/film.png", 26, L("Open the VMD motion importer and motion library."))
cvars.AddChangeCallback("nativeloader_language", phrases, "nativeloader_motion_tab")
cvars.AddChangeCallback("gmod_language", phrases, "nativeloader_motion_tab")
phrases()
