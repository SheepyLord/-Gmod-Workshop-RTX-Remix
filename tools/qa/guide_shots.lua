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
local function add(sets, label, prepare, settle)
    for set in sets:gmatch("%S+") do
        if set == SET or SET == "all" and set ~= "guide_lang" then
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

local function tool_panel()
    local menu = IsValid(g_SpawnMenu) and g_SpawnMenu:GetToolMenu()
    return menu and menu:GetToolPanel("RTX Remix")
end

-- The spawn menu open on the RTX Remix tab, every group of its sidebar open, the tool half TOOL_WIDTH wide.
local function spawn_menu()
    close_windows()
    remix("0")
    if not g_SpawnMenu:IsVisible() then g_SpawnMenu:Open() end
    local divider = g_SpawnMenu.HorizontalDivider
    if divider and not saved.divider then saved.divider = divider:GetLeftWidth() end
    if divider then divider:SetLeftWidth(math.max(divider:GetLeftMin() or 0, divider:GetWide() - TOOL_WIDTH - divider:GetDividerWidth())) end
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

-- The character for the Imported game PBR and eye-white pictures: an imported Wuthering Waves character
-- when the library has one (game maps), else the first one. Spawned in front of the player, who looks at it.
local character
local function pick_character()
    local entries = istable(mmdhl) and istable(mmdhl.library) and mmdhl.library.entries or {}
    local first, game
    for id, entry in pairs(entries) do
        local name = istable(entry) and (entry.name or entry.info and entry.info.name) or ""
        if isstring(id) and #id == 64 then
            first = first or id
            if isstring(name) and name:find("鳴潮", 1, true) then game = game or id end
        end
    end
    return game or first
end

local function aim_at(entity)
    local player = LocalPlayer()
    if not (IsValid(player) and IsValid(entity)) then return end
    local target = entity:WorldSpaceCenter() + Vector(0, 0, 12)
    player:SetEyeAngles((target - player:EyePos()):Angle())
end

local function spawn_character(done)
    close_windows()
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    local id = pick_character()
    if not id or not isfunction(mmdhl.RequestSpawn) then say("no character to spawn") return done() end
    local player = LocalPlayer()
    player:SetEyeAngles(Angle(12, player:EyeAngles().y, 0))
    local options = isfunction(mmdhl.GetGlobalSettings) and mmdhl.GetGlobalSettings() or {}
    options.role, options.frozen, options.weapon = "citizen", true, "none"
    local started = SysTime()
    local ok, why = mmdhl.RequestSpawn(id, options, function(state, message, entityIndex)
        say("spawn " .. tostring(state) .. " " .. tostring(message))
        if state ~= "ready" then if state == "error" then done() end return end
        hook.Add("Think", "NLGuideShots.Presented", function()
            local entity = Entity(entityIndex)
            if IsValid(entity) and entity.MMDHLClientInstance or SysTime() - started > 90 then
                hook.Remove("Think", "NLGuideShots.Presented")
                character = entity
                aim_at(entity)
                say("presented " .. tostring(IsValid(entity) and entity:GetModel()))
                timer.Simple(4, done)
            end
        end)
    end)
    if not ok then say("spawn refused " .. tostring(why)) done() end
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
-- Remix's own menu (Alt+X): rtx.showUI 1 is the simple menu, 2 the developer menu (not saved).
add("remix", "remix_simple", function() close_windows() if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end remix("1") end, 3)
add("remix", "remix_developer", function() remix("2") end, 3)
-- A character: the hotloader's library, Imported game PBR and the eye-white chooser.
add("character", "hotloader_tab", creation_tab(istable(mmdhl) and isfunction(mmdhl.L) and mmdhl.L("common.external_models") or "External Models"), 3)
add("character", "hotloader_window", function() close_windows() if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end mmdhl.Open() end, 3)
add("character", "character_spawned", nil, 1)
add("character", "imported_pbr", tool("RTX_ImportedGamePBR"), 3)
add("character", "imported_pbr_window", function() close_windows() if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end RunConsoleCommand("rtx_topbr_game_editor") end, 3)
add("character", "model_outlines_character", tool("nativeloader_model_layers"))
add("character", "eye_whites", function() close_windows() if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end aim_at(character) RunConsoleCommand("nativeloader_eye_white_materials") end, 4)
-- The guide: every page, and every section of every page.
local function add_guide(set, prefix)
    for _, page in ipairs(NATIVELOADER_GUIDE and NATIVELOADER_GUIDE.pages or {}) do
        add(set, prefix .. page.id, guide(page.id), 2)
        for _, item in ipairs(page.items) do
            if item[1] == "h" and item.id then add(set, prefix .. page.id .. "." .. item.id, guide(page.id, item.id), 2) end
        end
    end
end
add_guide("guide", "guide_")
add_guide("guide_lang", "guide_" .. LANGUAGE .. "_")

local function restore()
    close_windows()
    remix("0")
    if IsValid(g_SpawnMenu) then
        if saved.divider and g_SpawnMenu.HorizontalDivider then g_SpawnMenu.HorizontalDivider:SetLeftWidth(saved.divider) end
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
        timer.Simple(step.settle, function() print("NL_SHOT " .. step.label) end)
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
if SET == "guide_lang" then
    saved.language = GetConVar("nativeloader_language"):GetString()
    RunConsoleCommand("nativeloader_language", LANGUAGE)
end
say("steps " .. #steps .. " set " .. SET)
timer.Simple(SET == "guide_lang" and 3 or 1, next_step)
