-- The Motion importer creation tab beside External Models: the bundled Character Motion
-- Importer's in-game importer and its Motion Manager, built into the tab with the add-on's own
-- builders, in the look of External Models. Documented in nativeloader_motion_tab.lua.md.
local i18n = include("nativeloader/i18n.lua")
local L = i18n.L
if not spawnmenu or not isfunction(spawnmenu.AddCreationTab) then return end
local key = "#nativeloader.motion_importer"
local function phrases()
    language.Add("nativeloader.motion_importer", L("Motion importer"))
    local entry = spawnmenu.GetCreationTabs()[key]
    if entry then entry.Tooltip = L("Import VMD files and manage your motion library and playback.") end
end

-- The sections: the add-on's builder that fills the tab, the window it also fills, and the
-- add-on's own phrase for its title (its catalogs, in the game's language).
local SECTIONS = {
    { id = "import", title = "mmd_vmd_npc.import.title", fallback = "Import MMD Motion",
      build = "BuildMotionImporter", open = "OpenMotionImporter" },
    { id = "manager", title = "mmd_vmd_npc.manager.title", fallback = "Motion Manager",
      build = "BuildMotionManager", open = "OpenMotionManager" },
}
local REMEMBERED = "nativeloader_motion_section"
-- External Models' page colour and text.
local BACKGROUND, MUTED = Color(246, 248, 251), Color(93, 109, 127)

local function addon()
    return istable(MMDVMDNPC) and MMDVMDNPC or nil
end

local function title(api, section)
    if isfunction(api.L) then return api.L(section.title, section.fallback) end
    return section.fallback
end

local function open_window(api, section)
    local open = section and api[section.open]
    if not isfunction(open) then return end
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    open()
end

-- Section buttons on the left of the top bar, Open in window on its right, the shown section
-- below. A section is built the first time it is shown; both keep their state when hidden.
local function build_workspace(panel, api)
    local theme = api.UITheme("light")
    local scale = isfunction(api.MenuScale) and api.MenuScale() or 1
    local function S(value) return math.floor(value * scale + 0.5) end
    local sections = {}
    for _, section in ipairs(SECTIONS) do
        if isfunction(api[section.build]) then sections[#sections + 1] = section end
    end

    local workspace = vgui.Create("DPanel", panel)
    workspace:Dock(FILL)
    workspace:SetPaintBackground(false)
    local header = vgui.Create("DPanel", workspace)
    header:Dock(TOP)
    header:SetTall(S(36))
    header:DockMargin(0, 0, 0, S(10))
    header:SetPaintBackground(false)
    local body = vgui.Create("DPanel", workspace)
    body:Dock(FILL)
    body:SetZPos(100)
    body:SetPaintBackground(false)
    workspace.Header, workspace.Body, workspace.Buttons, workspace.Pages = header, body, {}, {}

    local function width_for(button, font, least, extra)
        surface.SetFont(font)
        button:SetWide(math.max(S(least), surface.GetTextSize(button:GetText() or "") + S(extra or 36)))
    end
    local openWindow = vgui.Create("DButton", header)
    openWindow:Dock(RIGHT)
    openWindow:SetFont("MMDVMDNPCManagerText")
    openWindow:SetText(L("Open in window"))
    openWindow:SetImage("icon16/application_double.png")
    -- Room for the icon in front of the text.
    width_for(openWindow, "MMDVMDNPCManagerText", 150, 60)
    api.StyleButton(openWindow, theme)
    workspace.OpenWindow = openWindow

    local function show(id)
        for _, section in ipairs(sections) do
            local active = section.id == id
            local page = workspace.Pages[section.id]
            if active and not IsValid(page) then
                page = api[section.build](body, { theme = "light", columns = true })
                workspace.Pages[section.id] = page
            end
            if IsValid(page) then page:SetVisible(active) end
            workspace.Buttons[section.id].Selected = active
            if active then
                workspace.Shown = section
                openWindow:SetEnabled(isfunction(api[section.open]))
            end
        end
        if cookie and isfunction(cookie.Set) then cookie.Set(REMEMBERED, id) end
        body:InvalidateLayout()
    end
    workspace.Show = show

    for _, section in ipairs(sections) do
        local button = vgui.Create("DButton", header)
        button:Dock(LEFT)
        button:DockMargin(0, 0, S(6), 0)
        button:SetFont("MMDVMDNPCManagerTextBold")
        button:SetText(title(api, section))
        width_for(button, "MMDVMDNPCManagerTextBold", 170)
        api.StyleButton(button, theme)
        button.DoClick = function()
            if workspace.Shown ~= section then show(section.id) end
        end
        workspace.Buttons[section.id] = button
    end
    openWindow.DoClick = function() open_window(api, workspace.Shown) end

    local remembered = cookie and isfunction(cookie.GetString) and cookie.GetString(REMEMBERED, "") or ""
    local first = sections[1].id
    for _, section in ipairs(sections) do
        if section.id == remembered then first = remembered end
    end
    show(first)
    return workspace
end

-- An add-on without the builders (an older copy): buttons that open its windows.
local function build_launchers(panel, api)
    local row = vgui.Create("DPanel", panel)
    row:Dock(TOP)
    row:DockMargin(0, 12, 0, 0)
    row:SetTall(36)
    row:SetPaintBackground(false)
    for _, section in ipairs(SECTIONS) do
        if isfunction(api[section.open]) then
            local button = vgui.Create("DButton", row)
            button:Dock(LEFT)
            button:DockMargin(0, 0, 8, 0)
            button:SetWide(220)
            button:SetText(title(api, section))
            button.DoClick = function() open_window(api, section) end
        end
    end
    return row
end

spawnmenu.AddCreationTab(key, function()
    local panel = vgui.Create("DPanel")
    local buildFailed = false
    panel:DockPadding(10, 8, 10, 8)
    panel.Paint = function(_, w, h)
        surface.SetDrawColor(BACKGROUND)
        surface.DrawRect(0, 0, w, h)
    end
    local summary = panel:Add("DLabel")
    summary:Dock(TOP)
    summary:SetWrap(true)
    summary:SetAutoStretchVertical(true)
    summary:SetTextColor(MUTED)
    summary:SetText(L("Import VMD files and manage your motion library and playback."))
    panel.Summary = summary
    -- Built when first shown; the add-on may load after this file, so wait for its builders.
    panel.Think = function(self)
        if IsValid(self.Workspace) or buildFailed then return end
        local api = addon()
        if not api then return end
        if isfunction(api.BuildMotionManager) and isfunction(api.UITheme) and isfunction(api.StyleButton) then
            if IsValid(self.Summary) then self.Summary:Remove() end
            if IsValid(self.Launchers) then self.Launchers:Remove() end
            local ok, result = pcall(build_workspace, self, api)
            if ok then
                self.Workspace = result
                return
            end
            -- A failing builder would otherwise run again, and leave another half-built page, every
            -- frame: report it once and offer the windows instead (review R4).
            buildFailed = true
            for _, child in ipairs(self:GetChildren()) do child:Remove() end
            ErrorNoHalt("[nativeloader] Motion importer tab: " .. tostring(result) .. "\n")
            self.Launchers = build_launchers(self, api)
        elseif not IsValid(self.Launchers) and (isfunction(api.OpenMotionManager) or isfunction(api.OpenMotionImporter)) then
            self.Launchers = build_launchers(self, api)
        end
    end
    return panel
end, "icon16/film.png", 26, L("Import VMD files and manage your motion library and playback."))
cvars.AddChangeCallback("nativeloader_language", phrases, "nativeloader_motion_tab")
cvars.AddChangeCallback("gmod_language", phrases, "nativeloader_motion_tab")
phrases()
