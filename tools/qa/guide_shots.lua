-- R14-H: opens every place the RTX Remix guide pictures, one at a time, and prints NL_SHOT <label> once
-- each view is ready; tools/poc_session.py takes the screenshot and answers nl_shot_taken <n>, and the
-- next view opens. tools/guide_annotate.py then crops the captures and draws the numbered badges.
-- Documented in guide_shots.lua.md beside this file.
--
-- Panels open through spawnmenu.ActivateTool(<item>), as a click on the item does: the RTX Remix
-- tab, its panel built, and the item highlighted, whatever the sidebar showed before. NL_GUIDE_SET
-- (a global set before this file runs) chooses the views: "all" (default), "tab", "remix", "character",
-- "guide" or "guide_lang" (the guide again in NL_GUIDE_LANGUAGE, default fr). The spawn menu's divider
-- and the RTX Remix groups' open state are put back at the end, and nativeloader_language too.
local SET = NL_GUIDE_SET or "all"
local LANGUAGE = NL_GUIDE_LANGUAGE or "fr"
local TOOL_WIDTH = NL_GUIDE_TOOL_WIDTH or 640
local steps, index = {}, 0
local saved = {}

local function say(text) print("NL_GUIDE " .. text) end
-- Sets that stand for several: everything but the second language, and the views the pictures need.
local GROUPS = { all = { tab = true, remix = true, character = true, guide = true },
    pictures = { tab = true, remix = true, character = true }, panels = { tab = true, character = true },
    check = { guide = true, guide_lang = true } }
local function add(sets, label, prepare, settle)
    for set in sets:gmatch("%S+") do
        if set == SET or GROUPS[SET] and GROUPS[SET][set] then
            steps[#steps + 1] = { label = label, prepare = prepare, settle = settle or 1.5 }
            return
        end
    end
end

local function close_windows()
    for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if IsValid(panel) and panel:IsVisible() and panel.GetTitle and panel.Close and panel ~= g_SpawnMenu and panel ~= g_ContextMenu then
            panel:Close()
        end
    end
end

local function remix(value)
    if istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable) then
        RemixConfig.SetConfigVariable("rtx.showUI", value)
    else
        say("no RemixConfig")
    end
end

-- The tool menu keys its panels by the tab's place in spawnmenu.GetTools() (sorted by name), not by name.
local function tool_panel()
    local menu = IsValid(g_SpawnMenu) and g_SpawnMenu:GetToolMenu()
    if not menu then return end
    for place, tab in ipairs(spawnmenu.GetTools()) do
        if tab.Name == "RTX Remix" then return menu:GetToolPanel(place) end
    end
end

-- The spawn menu open on the RTX Remix tab, every group of its sidebar open, the tool half TOOL_WIDTH wide.
local function spawn_menu()
    close_windows()
    remix("0")
    if not g_SpawnMenu:IsVisible() then g_SpawnMenu:Open() end
    local divider = g_SpawnMenu.HorizontalDivider
    if divider and not saved.divider then saved.divider = divider:GetLeftWidth() end
    -- SetLeftWidth applies at the next layout; ask for it at once, and again once the menu's first layout
    -- (which restores the cookie's share) has run. No cookie is written (dragging writes one).
    local function widen()
        if not IsValid(divider) then return end
        divider:SetLeftWidth(math.max(divider:GetLeftMin() or 0, divider:GetWide() - TOOL_WIDTH - divider:GetDividerWidth()))
        divider:InvalidateLayout(true)
    end
    widen()
    timer.Simple(0.3, widen)
    local panel = tool_panel()
    if panel and panel.List then
        for _, category in ipairs(panel.List.pnlCanvas:GetChildren()) do
            if category.SetExpanded then
                saved.expanded = saved.expanded or {}
                if saved.expanded[category] == nil then saved.expanded[category] = category:GetExpanded() end
                category:SetExpanded(true)
            end
        end
    else
        say("no RTX Remix tool panel")
    end
end

local function tool(item)
    return function()
        spawn_menu()
        spawnmenu.ActivateTool(item, true)
        local panel = tool_panel()
        say("tool " .. item .. " " .. tostring(panel and panel.ActiveCPName))
    end
end

local function creation_tab(name)
    return function()
        spawn_menu()
        g_SpawnMenu:OpenCreationMenuTab(name)
    end
end

-- The characters of the Imported game PBR and eye-white pictures: an imported Wuthering Waves character
-- (鳴潮: game maps) and one whose eye-white material the rules detect (Karin's 目白), when the library
-- has them, else the first one. Each spawned frozen in front of the player.
local character, eyes_character
local function pick_character(pattern)
    local entries = istable(mmdhl) and istable(mmdhl.library) and mmdhl.library.entries or {}
    local first, wanted
    for id, entry in pairs(entries) do
        local name = istable(entry) and (entry.name or entry.info and entry.info.name) or ""
        if isstring(id) and #id == 64 then
            first = first or id
            if pattern and isstring(name) and name:find(pattern, 1, true) then wanted = wanted or id end
        end
    end
    return wanted or first
end

local function aim_at(entity)
    local player = LocalPlayer()
    if not (IsValid(player) and IsValid(entity)) then return end
    local target = entity:WorldSpaceCenter() + Vector(0, 0, 12)
    player:SetEyeAngles((target - player:EyePos()):Angle())
end

local function spawn(pattern, yaw, done)
    local id = pick_character(pattern)
    if not id or not isfunction(mmdhl.RequestSpawn) then say("no character to spawn") return done() end
    local player = LocalPlayer()
    player:SetEyeAngles(Angle(12, player:EyeAngles().y + yaw, 0))
    local options = isfunction(mmdhl.GetGlobalSettings) and mmdhl.GetGlobalSettings() or {}
    options.role, options.frozen, options.weapon = "citizen", true, "none"
    local started = SysTime()
    local ok, why = mmdhl.RequestSpawn(id, options, function(state, message, entityIndex)
        say("spawn " .. pattern .. " " .. tostring(state) .. " " .. tostring(message))
        if state ~= "ready" then if state == "error" then done() end return end
        hook.Add("Think", "NLGuideShots.Presented", function()
            local entity = Entity(entityIndex)
            if IsValid(entity) and entity.MMDHLClientInstance or SysTime() - started > 90 then
                hook.Remove("Think", "NLGuideShots.Presented")
                say("presented " .. tostring(IsValid(entity) and entity:GetModel()))
                done(entity)
            end
        end)
    end)
    if not ok then say("spawn refused " .. tostring(why)) done() end
end

local function spawn_character(done)
    close_windows()
    remix("0")
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    spawn("鳴潮", 0, function(entity)
        character = entity
        timer.Simple(2, function()
            spawn("Karin", 40, function(other)
                eyes_character = other
                aim_at(character)
                timer.Simple(4, done)
            end)
        end)
    end)
end

local function guide(page, section)
    return function()
        close_windows()
        if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
        remix("0")
        RunConsoleCommand("nativeloader_guide", page, section)
    end
end

-- The RTX Remix tab and its panels.
add("tab", "spawnmenu_tab", tool("nativeloader_start"), 2.5)
add("tab", "remix_settings", tool("nativeloader_remix"))
add("tab", "sky_weather", tool("nativeloader_sky"))
add("tab", "base_options", tool("RTX_Client_BaseOptions"))
add("tab", "performance", tool("RTX_Client_Performance"))
add("tab", "model_outlines", tool("nativeloader_model_layers"))
add("tab", "player_models", tool("nativeloader_player"))
add("tab", "toolgun", tool("nativeloader_toolgun"))
add("tab", "topbr", tool("RTX_Client_ToPBR"))
add("tab", "autocat", tool("RTX_Client_AutoCategorization"))
add("tab", "flashlight", tool("Flashlight"))
add("tab", "map_lights", tool("RTX_Remix_API_Lights"))
add("tab", "glass_settings", tool("GlassSettings"))
add("tab", "rtx_water", tool("RTXWater"))
-- Remix's own menu (Alt+X): rtx.showUI 1 is the simple menu, 2 the developer menu (not saved). Clicks and
-- the wheel inside it go through tools/qa/guide_input.py (NL_INPUT lines); the points are where the
-- menu's tabs are at 1920x1080.
local inputs = 0
local function input(kind, x, y, extra)
    inputs = inputs + 1
    print(string.format("NL_INPUT %d %s %d %d%s", inputs, kind, x, y, extra and (" " .. extra) or ""))
end
-- Posted mouse input does not reach the menu (it reads the real cursor); its keyboard navigation does.
-- Keys reach the game's binds too: End is often bound to quit and the arrows turn the view, so only
-- Page Down is used, which pages the focused developer menu down to its Settings Management section.
local VK_NEXT = 34
add("remix", "remix_simple", function() close_windows() if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end remix("1") end, 3)
add("remix", "remix_developer", function() remix("2") end, 3)
add("remix", "remix_developer_paged", function() input("key", VK_NEXT, 6) end, 4)
add("remix", "remix_developer_bottom", function() input("key", VK_NEXT, 10) end, 5)
-- A character: the hotloader's library, Imported game PBR and the eye-white chooser.
local function find(root, test)
    if not IsValid(root) then return end
    if test(root) then return root end
    for _, child in ipairs(root:GetChildren()) do
        local found = find(child, test)
        if found then return found end
    end
end
local function label_text(panel) return isfunction(panel.GetText) and panel:GetText() or "" end
local function top_window(title)
    for _, top in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if IsValid(top) and top:IsVisible() and top.GetTitle and top:GetTitle() == title then return top end
    end
end
-- Imported game PBR: select the first material whose state is automatic or cached, so its maps show.
local function pick_material(root)
    local row = find(root, function(p)
        local text = label_text(p)
        return p.ClassName == "DLabel" and (text:find("\nautomatic$") or text:find("\ncached$"))
    end)
    local button = row and row:GetParent()
    if button and button.DoClick then
        button:DoClick()
        say("material " .. label_text(row):gsub("\n", " / "))
        -- Show the chosen row in the list too (the list scrolls; its canvas is the button's parent).
        local list = button:GetParent() and button:GetParent():GetParent()
        if IsValid(list) and list.ScrollToChild then list:ScrollToChild(button) end
    else
        say("no automatic material")
    end
end
local function library_select(library)
    local id = IsValid(character) and isfunction(mmdhl.GetAsset) and mmdhl.GetAsset(character) or pick_character()
    if IsValid(library) and isfunction(library.SelectAsset) and id then library:SelectAsset(id) end
end
add("character", "character_spawned", nil, 1)
add("character", "hotloader_window", function()
    close_windows()
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    mmdhl.Open()
    local window = mmdhl.window
    if IsValid(window) then
        -- The guide's pictures are at most 900 wide, with room for badges beside the window; the library
        -- lays itself out again for the window's size.
        window:SetSize(800, 1000)
        window:Center()
        timer.Simple(0.5, function() if IsValid(window) then library_select(window.Library) end end)
    end
end, 4)
add("character", "hotloader_tab", function()
    creation_tab(istable(mmdhl) and isfunction(mmdhl.L) and mmdhl.L("common.external_models") or "External Models")()
    timer.Simple(0.8, function() library_select(IsValid(mmdhl.spawnPanel) and mmdhl.spawnPanel.Library) end)
end, 4)
add("character", "imported_pbr", function()
    tool("RTX_ImportedGamePBR")()
    timer.Simple(3, function() pick_material(controlpanel.Get("RTX_ImportedGamePBR")) end)
end, 5)
add("character", "imported_pbr_window", function()
    close_windows()
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    RunConsoleCommand("rtx_topbr_game_editor")
    timer.Simple(3, function() pick_material(top_window("Imported game PBR")) end)
end, 5)
add("character", "model_outlines_character", tool("nativeloader_model_layers"))
-- The eye-white chooser, scrolled to the first material detected as an eye white.
add("character", "eye_whites", function()
    close_windows()
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    aim_at(IsValid(eyes_character) and eyes_character or character)
    RunConsoleCommand("nativeloader_eye_white_materials")
    timer.Simple(0.3, function()
        -- Narrower than its 860, so the picture has room for badges beside it (the rows follow the width).
        local window = top_window("Choose eye-white materials")
        if IsValid(window) then window:SetSize(780, 680) window:Center() end
    end)
    timer.Simple(3, function()
        local window = top_window("Choose eye-white materials")
        local status = find(window, function(p) return p.ClassName == "DLabel" and label_text(p) == "Automatic: eye white" end)
        local row = status and status:GetParent()
        local scroll = find(window, function(p) return p.ClassName == "DScrollPanel" end)
        if row and scroll then scroll:ScrollToChild(row) say("eye white row found") else say("no automatic eye white on this page") end
    end)
end, 5)
-- The guide: every page, and every section of every page.
local function add_guide(set, prefix)
    for _, page in ipairs(NATIVELOADER_GUIDE and NATIVELOADER_GUIDE.pages or {}) do
        if NL_GUIDE_PAGE == nil or NL_GUIDE_PAGE == page.id then -- NL_GUIDE_PAGE: only that page
            add(set, prefix .. page.id, guide(page.id), 2)
            for _, item in ipairs(page.items) do
                if item[1] == "h" and item.id then add(set, prefix .. page.id .. "." .. item.id, guide(page.id, item.id), 2) end
            end
        end
    end
end
add_guide("guide", "guide_")
-- The second language: nativeloader_language rebuilds the spawn menu (0.2 s later); the guide follows.
add("guide_lang", "language_" .. LANGUAGE, function()
    close_windows()
    if saved.language == nil then saved.language = GetConVar("nativeloader_language"):GetString() end
    RunConsoleCommand("nativeloader_language", LANGUAGE)
end, 3)
add_guide("guide_lang", "guide_" .. LANGUAGE .. "_")

-- Where each control of the view is on screen (= capture pixels): NL_RECT <label> <class> x y w h <text>,
-- so a picture's badges point at measured rectangles.
local function dump(label, root, depth)
    if not IsValid(root) or not root:IsVisible() or (depth or 0) > 14 then return end
    local text = isfunction(root.GetText) and root:GetText() or ""
    if not isstring(text) then text = "" end
    local class = root.ClassName or root:GetClassName() or "?"
    local interesting = text ~= "" or class:find("Button", 1, true) or class:find("CheckBox", 1, true) or
        class:find("ComboBox", 1, true) or class:find("Slider", 1, true) or class:find("TextEntry", 1, true) or
        class == "DImage" or class == "DCollapsibleCategory" or class == "DFrame"
    if interesting then
        local x, y = root:LocalToScreen(0, 0)
        local w, h = root:GetSize()
        print(string.format("NL_RECT\t%s\t%s\t%d\t%d\t%d\t%d\t%s", label, class, x, y, w, h, text:gsub("[\r\n\t]", " "):sub(1, 90)))
    end
    for _, child in ipairs(root:GetChildren()) do dump(label, child, (depth or 0) + 1) end
end

local function dump_view(label)
    local panel = tool_panel()
    if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then
        if panel and IsValid(panel.Content) then dump(label, panel.Content) end
        if panel and IsValid(panel.List) then dump(label, panel.List) end
        if panel and IsValid(panel.SearchBar) then dump(label, panel.SearchBar) end
        local menu = g_SpawnMenu:GetToolMenu()
        for _, item in ipairs(menu and menu.Items or {}) do if IsValid(item.Tab) then dump(label, item.Tab) end end
        local create = g_SpawnMenu:GetCreationMenu()
        for _, item in ipairs(create and create.Items or {}) do if IsValid(item.Tab) then dump(label, item.Tab) end end
        local library = IsValid(mmdhl and mmdhl.spawnPanel) and mmdhl.spawnPanel
        if library and library:IsVisible() then dump(label, library) end
    end
    for _, top in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if IsValid(top) and top:IsVisible() and top.GetTitle and top ~= g_SpawnMenu and top ~= g_ContextMenu then dump(label, top) end
    end
end

local function restore()
    close_windows()
    remix("0")
    if IsValid(g_SpawnMenu) then
        if saved.divider and g_SpawnMenu.HorizontalDivider then
            g_SpawnMenu.HorizontalDivider:SetLeftWidth(saved.divider)
            g_SpawnMenu.HorizontalDivider:InvalidateLayout(true)
        end
        for category, open in pairs(saved.expanded or {}) do
            if IsValid(category) then category:SetExpanded(open) end
        end
        g_SpawnMenu:Close()
    end
    if saved.language ~= nil then RunConsoleCommand("nativeloader_language", saved.language) end
end

local function next_step()
    index = index + 1
    local step = steps[index]
    if not step then
        restore()
        timer.Simple(1, function() print("NL_SHOT_DONE") end)
        return
    end
    local function ready()
        timer.Simple(step.settle, function()
            local ok, why = pcall(dump_view, step.label)
            if not ok then say("rects " .. step.label .. " failed: " .. tostring(why)) end
            print("NL_SHOT " .. step.label)
        end)
    end
    if step.label == "character_spawned" then
        spawn_character(ready)
        return
    end
    local ok, why = pcall(step.prepare)
    if not ok then say("step " .. step.label .. " failed: " .. tostring(why)) end
    ready()
end

concommand.Add("nl_shot_taken", function() timer.Simple(0.3, next_step) end)
say("steps " .. #steps .. " set " .. SET)
timer.Simple(1, next_step)
