-- Actual menu, guide and i18n code over mocked controls, status data and the generated catalogs.
local menu, guide, i18n_path, catalog, scenario, code = ...
CLIENT = true
local values = {nativeloader_language = code, gmod_language = "en"}
local hooks, panels, commands = {}, {}, {}
local data = dofile(catalog)
local tier_name, source_name = scenario:match("^(%a+)_(%a+)$")
if tier_name ~= "high" and tier_name ~= "medium" then tier_name = "low" end
if source_name ~= "config" and source_name ~= "fallback" then source_name = "auto" end
local tier = {tier = tier_name, source = source_name, adapter = "NVIDIA GeForce RTX 4060 Laptop GPU",
    dedicated_vram_mib = 8192, reason = "VRAM and model class", layer = "native-loader/remix/tier.conf"}
local status = {schema = 1, activation = {performance_tier = tier}}
if scenario == "absent" then status.activation.performance_tier = nil end
if scenario == "no_activation" then status.activation = nil end
if scenario == "bad_field" then status.activation.performance_tier = "invalid" end
if scenario == "bad_schema" then status.schema = 2 end
if scenario == "invalid_tier" then tier.tier = "ultra" end
if scenario == "unknown_hardware" then
    tier.adapter, tier.dedicated_vram_mib, tier.source = nil, math.huge, "future_source"
end
local function cv(name)
    return {GetString = function() return values[name] end,
        GetBool = function() return values[name] == "1" end}
end
function CreateClientConVar(name, default)
    if values[name] == nil then values[name] = default end
    return cv(name)
end
GetConVar = cv
istable = function(v) return type(v) == "table" end
isstring = function(v) return type(v) == "string" end
isfunction = function(v) return type(v) == "function" end
local function refuse() error("UI must not write settings, files or Remix options") end
file = {
    Exists = function(path, realm) return realm == "LUA" and path == "nativeloader/i18n_data.lua" end,
    Read = function(path, realm)
        assert(path == "native-loader/status.json" and realm == "DATA")
        if scenario == "unreadable" then error("unreadable") end
        if scenario == "missing" then return nil end
        return "status"
    end,
    Write = refuse, Append = refuse, CreateDir = refuse,
}
util = {JSONToTable = function(body)
    assert(body == "status")
    if scenario ~= "malformed" then return status end
end}
language = {Add = function() end}
surface = {SetFont = function() end, GetTextSize = function(text) return #text * 10 end}
cvars = {AddChangeCallback = function() end}
timer = {Simple = function() end, Create = function() end}
hook = {Add = function(event, id, fn)
    hooks[event] = hooks[event] or {} hooks[event][id] = fn
end}
concommand = {Add = function(name, fn) commands[name] = fn end}
spawnmenu = {AddToolMenuOption = function(_, _, id, _, _, _, fn) panels[id] = fn end,
    AddToolTab = function() end, AddToolCategory = function() end}
RemixConfig = {SetConfigVariable = refuse}
RunConsoleCommand = refuse
local i18n
include = function(path)
    if path == "nativeloader/i18n_data.lua" then return data end
    assert(path == "nativeloader/i18n.lua")
    if not i18n then i18n = dofile(i18n_path) end
    return i18n
end
dofile(menu)
for _, fn in pairs(hooks.PopulateToolMenu) do fn() end
local function start_panel()
    local panel = {lines = {}, buttons = {}}
    function panel:Help(text) self.lines[#self.lines + 1] = text end
    panel.ControlHelp = panel.Help
    function panel:Button(label, command) self.buttons[command] = label return {} end
    function panel:CheckBox() return {} end
    function panel:ComboBox() return {AddChoice = function() end} end
    panels.nativeloader_start(panel)
    return panel
end
local panel = start_panel()
assert(panel.buttons.nativeloader_stability_guide == i18n.L("Memory and stability guide"))
local function find_tier(p)
    local found
    for _, line in ipairs(p.lines) do
        if line:find("remix.performance_tier", 1, true) then
            assert(not found, "more than one tier line") found = line
        end
    end
    return found
end
local hidden = {absent = true, no_activation = true, bad_field = true, missing = true,
    malformed = true, unreadable = true, bad_schema = true, invalid_tier = true}
local line = find_tier(panel)
if hidden[scenario] then
    assert(not line, "an absent or invalid tier must show no line")
else
    assert(line and line:find("native-loader\\config.json", 1, true))
    assert(line:find("auto, high, medium", 1, true) or line:find("auto", 1, true))
    assert(not line:find("%s", 1, true), "unexpanded translated placeholder")
    local level = ({high = "High", medium = "Medium", low = "Low"})[tier.tier]
    assert(line:find(i18n.L(level), 1, true), "missing translated tier")
    if scenario == "unknown_hardware" then
        assert(line:find(i18n.L("Unknown GPU"), 1, true) and line:find("?", 1, true))
        assert(line:find(i18n.L("Unknown source"), 1, true))
    else
        local source_label = ({auto = "Automatic selection", config = "Configuration override",
            fallback = "Compatibility fallback"})[tier.source]
        assert(line:find(i18n.L(source_label), 1, true), "missing translated source")
        assert(line:find(tier.adapter, 1, true) and line:find("8192", 1, true))
    end
    if code ~= "en" then
        assert(data[code]["Memory and stability guide"] ~= "Memory and stability guide")
        assert(data[code][level] ~= level, "tier label fell back to English")
    end
end
if scenario == "refresh" then
    tier.tier, tier.source, tier.adapter, tier.dedicated_vram_mib = "high", "config", "Second GPU", 32768
    local refreshed = find_tier(start_panel())
    assert(refreshed ~= line and refreshed:find("Second GPU", 1, true) and refreshed:find("32768", 1, true))
    assert(refreshed:find(i18n.L("Configuration override"), 1, true))
end
if scenario == "guide" then
    TOP, FILL = 1, 2
    Color = function() return {} end
    ScrW, ScrH = function() return 1920 end, function() return 1080 end
    local sheet
    local function widget(class, parent)
        local result = {class = class, parent = parent, labels = {}, tabs = {}}
        setmetatable(result, {__index = function() return function() end end})
        function result:Add(kind) return vgui.Create(kind, self) end
        function result:SetText(text)
            if self.class == "DLabel" then self.parent.labels[#self.parent.labels + 1] = text end
        end
        function result:SetWrap(wrap) assert(wrap, "guide text must wrap") end
        function result:SetAutoStretchVertical(stretch) assert(stretch, "guide text must stretch") end
        function result:AddSheet(title, content)
            local tab = {title = title, content = content}
            self.tabs[#self.tabs + 1] = tab
            if not rawget(self, "active") then self.active = tab end
            return {Tab = tab}
        end
        function result:SetActiveTab(tab) self.active = tab end
        if class == "DPropertySheet" then sheet = result end
        return result
    end
    vgui = {Create = widget}
    dofile(guide)
    commands.nativeloader_stability_guide(nil, "nativeloader_stability_guide", {})
    assert(#sheet.tabs == 6 and sheet.active.title == i18n.L("Memory and stability"))
    local body = table.concat(sheet.active.content.labels, "\n")
    for _, token in ipairs({"30", "OBS", "Committed", "Alt+X", "performance_tier", "next_start",
        "rtx_vram_stats", "memory.csv", "vram.previous.csv", "native-loader\\logs\\sessions\\",
        "200", "nvlddmkm", "WATCHDOG", "nativeloader_vram_telemetry 0"}) do
        assert(body:find(token, 1, true), "missing stability guidance: " .. token)
    end
    commands.nativeloader_guide(nil, "nativeloader_guide", {})
    assert(sheet.active.title == i18n.L("Welcome"), "default guide navigation changed")
end
print("PASS " .. scenario .. " " .. code)
