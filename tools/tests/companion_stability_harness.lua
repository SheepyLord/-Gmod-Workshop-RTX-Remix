-- Actual menu, guide and i18n code over mocked controls, status data and the generated catalogs.
local menu, guide, i18n_path, catalog, scenario, code, status_path, decoder = ...
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
local report_scenario = scenario:gsub("^guide_", ""):gsub("^json_", "")
if report_scenario == "absent" then status.activation.performance_tier = nil end
if report_scenario == "no_activation" then status.activation = nil end
if report_scenario == "bad_field" then status.activation.performance_tier = "invalid" end
if report_scenario == "bad_schema" then status.schema = 2 end
if report_scenario == "invalid_tier" then tier.tier = "ultra" end
if report_scenario == "unknown_hardware" then tier.adapter = nil end
if report_scenario == "unknown_source" then
    tier.dedicated_vram_mib, tier.source = math.huge, "future_source"
end
if tier.tier == "high" then tier.layer = "" end
if report_scenario == "non_nvidia" or report_scenario == "query_failed" then
    tier.tier, tier.source, tier.adapter, tier.dedicated_vram_mib, tier.layer = "high", "auto", "", 0, ""
    status.activation.non_nvidia = report_scenario == "non_nvidia"
end
if report_scenario == "non_nvidia_with_adapter" then status.activation.non_nvidia = true end
if report_scenario == "no_layer_medium" or report_scenario == "no_layer_low" then
    tier.tier = report_scenario == "no_layer_medium" and "medium" or "low"
    tier.layer, tier.reason = "", "package has no " .. tier.tier .. " tier file, retaining classic defaults"
end
if report_scenario == "no_layer_reason_missing" then tier.layer, tier.reason = "", nil end
local json_body, json_reads
if status_path then
    local input = assert(io.open(status_path, "rb"))
    json_body = input:read("*a") input:close()
    json_reads = 0
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
        if report_scenario == "unreadable" then error("unreadable") end
        if report_scenario == "missing" then return nil end
        return json_body or "status"
    end,
    Write = refuse, Append = refuse, CreateDir = refuse,
}
util = {JSONToTable = function(body)
    if json_body then
        assert(body == json_body)
        -- GMod's JSON parser is native. In this integration case decode the real JSON document
        -- with Python instead of returning the hand-built Lua status stub above.
        local pipe = assert(io.popen('python "' .. decoder .. '" --decode-status "' .. status_path .. '"', "r"))
        local parsed = pipe:read("*a") assert(pipe:close())
        status = assert(loadstring(parsed))()
        tier = status.activation and status.activation.performance_tier
        json_reads = json_reads + 1
        return status
    end
    assert(body == "status")
    if report_scenario ~= "malformed" then return status end
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
if code == "ru" then
    assert(i18n.L("High") == "Высокий" and i18n.L("Medium") == "Средний" and i18n.L("Low") == "Низкий",
        "Russian tier adjectives must agree with masculine Уровень")
end
local normal_format = "Performance tier: %s (%s; %s, %s MiB VRAM). To change it, set remix.performance_tier in native-loader\\config.json to auto, high, medium or low, then restart Garry's Mod."
local unapplied_format = "Performance tier %s is not applied: %s. See the Memory and stability guide."
local function find_tier(p)
    local found
    for _, line in ipairs(p.lines) do
        if line:find(i18n.L(normal_format):match("^(.-)%%s"), 1, true) or
            line:find(i18n.L(unapplied_format):match("^(.-)%%s"), 1, true) then
            assert(not found, "more than one tier line") found = line
        end
    end
    return found
end
local hidden = {absent = true, no_activation = true, bad_field = true, missing = true,
    malformed = true, unreadable = true, bad_schema = true, invalid_tier = true,
    unknown_hardware = true, non_nvidia = true, query_failed = true, non_nvidia_with_adapter = true}
local line = find_tier(panel)
if hidden[report_scenario] then
    assert(not line, "an absent or invalid tier must show no line")
else
    assert(line)
    assert(not line:find("%s", 1, true), "unexpanded translated placeholder")
    local level = ({high = "High", medium = "Medium", low = "Low"})[tier.tier]
    assert(line:find(i18n.L(level), 1, true), "missing translated tier")
    if report_scenario:find("^no_layer_") then
        assert(line == string.format(i18n.L(unapplied_format), i18n.L(level),
            tier.reason or i18n.L("No tier layer is available.")), "missing loader reason for unapplied tier")
        assert(not line:find("remix.performance_tier", 1, true), "unapplied tier must not claim active defaults")
    elseif report_scenario == "unknown_source" then
        assert(line:find(tier.adapter, 1, true) and line:find("?", 1, true))
        assert(line:find(i18n.L("Unknown source"), 1, true))
    else
        local source_label = ({auto = "Automatic selection", config = "Configuration override",
            fallback = "Compatibility fallback"})[tier.source]
        assert(line:find(i18n.L(source_label), 1, true), "missing translated source")
        assert(line:find(tier.adapter, 1, true) and line:find("8192", 1, true))
    end
    if not report_scenario:find("^no_layer_") then
        assert(line:find("native-loader\\config.json", 1, true) and line:find("auto", 1, true))
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
if scenario:find("^guide") or json_body then
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
    for _, token in ipairs({"30", "OBS", "Committed", "Alt+X", "User Settings (user.conf): Save",
        "rtx_vram_stats", "vram.previous.csv", "status.json", "session.json", "rtx-remix\\logs\\",
        "nvlddmkm", "WATCHDOG", "nativeloader_vram_telemetry"}) do
        assert(body:find(token, 1, true), "missing stability guidance: " .. token)
    end
    local r6 = type(status) == "table" and status.schema == 1 and
        type(status.activation) == "table" and type(status.activation.performance_tier) == "table" and
        report_scenario ~= "missing" and report_scenario ~= "malformed" and report_scenario ~= "unreadable"
    for _, token in ipairs({"remix.performance_tier", "diagnostics.gpu_crash_dumps", "next_start",
        "memory.csv", "native-loader\\logs\\sessions\\", "gpu-crash-dumps.used"}) do
        assert(not not body:find(token, 1, true) == not not r6, "wrong loader-version guidance: " .. token)
    end
    if r6 then
        if code == "ru" then
            assert(body:find(i18n.L("Start here"), 1, true), "Russian guide must use the tab's navigation label")
        end
        local example
        for _, label in ipairs(sheet.active.content.labels) do
            if label:sub(1, 1) == "{" then example = label end
        end
        assert(example, "missing complete JSON example")
        print("CONFIG_BEGIN\n" .. example .. "\nCONFIG_END")
    else
        assert(body:find("bin\\win64\\winmm.dll", 1, true), "older loader needs bootstrap update guidance")
    end
    if scenario == "guide_refresh" then
        status.activation.performance_tier = nil
        commands.nativeloader_stability_guide()
        local refreshed = table.concat(sheet.active.content.labels, "\n")
        assert(not refreshed:find("diagnostics.gpu_crash_dumps", 1, true), "guide reused stale R6 capability")
        assert(refreshed:find("bin\\win64\\winmm.dll", 1, true))
    end
    commands.nativeloader_guide(nil, "nativeloader_guide", {})
    assert(sheet.active.title == i18n.L("Welcome"), "default guide navigation changed")
end
if json_body then assert(json_reads >= 2, "menu and guide must actually parse the JSON report") end
print("PASS " .. scenario .. " " .. code)
