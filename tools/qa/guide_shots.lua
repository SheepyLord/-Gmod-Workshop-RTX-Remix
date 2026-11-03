-- R14: opens the views the RTX Remix guide shows (the spawn menu's RTX Remix tab, its categories, the
-- guide's pages) and prints one NL_SHOT <label> per view; tools/poc_session.py answers each with
-- nl_shot_taken <n> after the screenshot. tools/guide_annotate.py draws the arrows on the captures.
local steps, index = {}, 0
local function add(label, fn) steps[#steps + 1] = { label, fn } end

local function open_tab()
    g_SpawnMenu:Open()
    timer.Simple(0.4, function()
        local sheet = g_SpawnMenu.ToolMenu
        if sheet and sheet.GetItems then
            for _, item in ipairs(sheet:GetItems()) do
                if item.Name == "RTX Remix" or (item.Tab and item.Tab:GetText() == "RTX Remix") then
                    sheet:SetActiveTab(item.Tab)
                end
            end
        end
        print("NL_TABS " .. tostring(sheet) .. " " .. tostring(sheet and sheet.GetItems and #sheet:GetItems()))
    end)
end

add("spawnmenu_tab", open_tab)

local function click_label(root, text)
    for _, child in ipairs(root:GetChildren()) do
        if child.GetText and child.DoClick and child:GetText() == text then child:DoClick() return true end
        if click_label(child, text) then return true end
    end
end
for _, entry in ipairs({
    { "start_here", "Start here" }, { "remix_settings", "Common Remix settings" },
    { "sky_weather", "Sky and weather" }, { "base_options", "Base Options" },
    { "flashlight", "Flashlight" }, { "glass_settings", "Glass settings" },
    { "imported_pbr", "Imported game PBR" }, { "performance", "Performance" },
    { "player_models", "Player models" },
}) do
    add("tab_" .. entry[1], function() click_label(g_SpawnMenu.ToolMenu, entry[2]) end)
end

local function guide_page(title)
    return function()
        RunConsoleCommand("nativeloader_guide")
        timer.Simple(0.5, function()
            for _, pnl in ipairs(vgui.GetWorldPanel():GetChildren()) do
                if pnl.GetTitle and pnl:GetTitle() == "RTX Remix guide" then
                    for _, child in ipairs(pnl:GetChildren()) do
                        if child.GetItems then
                            for _, item in ipairs(child:GetItems()) do
                                if item.Tab and item.Tab:GetText() == title then child:SetActiveTab(item.Tab) end
                            end
                        end
                    end
                end
            end
        end)
    end
end
add("guide_welcome", guide_page("Welcome"))

local function nextStep()
    index = index + 1
    local step = steps[index]
    if not step then return print("NL_SHOT_DONE") end
    step[2]()
    timer.Simple(2.5, function() print("NL_SHOT " .. step[1]) end)
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.3, nextStep) end)
timer.Simple(1, nextStep)
