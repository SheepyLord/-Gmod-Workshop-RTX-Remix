-- QA probe: opens the spawn menu and shows the creation tabs the RTX package adds or changes, one
-- screenshot each (NL_SHOT, answered by the session driver with nl_shot_taken <n>): Model Hotloader's
-- External Models and the Motion importer. Prints NL_QA_TABS with every creation tab's name.
local function out(part, value) print("NL_QA_" .. part .. " " .. util.TableToJSON(value)) end
local names = {}
for name in pairs(spawnmenu.GetCreationTabs() or {}) do names[#names + 1] = name end
table.sort(names)
out("TABS", names)
local function find(pattern)
    for _, name in ipairs(names) do
        local shown = language.GetPhrase((string.gsub(name, "^#", ""))) or name
        if string.find(string.lower(name), pattern, 1, true) or string.find(string.lower(shown), pattern, 1, true) then
            return name
        end
    end
end
local wanted = {{"external_models", find("external") or find("mmdhl")}, {"motion_importer", find("motion")}}
local index = 0
local function nextStep()
    index = index + 1
    local step = wanted[index]
    if not step then
        RunConsoleCommand("-menu")
        print("NL_SHOT_DONE")
        return
    end
    if not step[2] then print("NL_QA_TAB_MISSING " .. step[1]) nextStep() return end
    if index == 1 then RunConsoleCommand("+menu") end
    timer.Simple(1, function()
        spawnmenu.SwitchCreationTab(step[2])
        timer.Simple(1.5, function() print("NL_SHOT " .. step[1]) end)
    end)
end
concommand.Add("nl_shot_taken", function() timer.Simple(0.5, nextStep) end)
timer.Simple(1, nextStep)
