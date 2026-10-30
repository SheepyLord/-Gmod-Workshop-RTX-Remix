-- Exercise the menu's persistence boundary without needing the game or a GPU.
local menu, scenario = ...
local archive, callbacks, commands, hooks, delayed = {}, {}, {}, {}, {}
local writes, pending, panels = {}, {}, {}
local runtime = { ["rtx.tonemap.psycho17.purityScale"] = "1.37" }
local prefix = "nativeloader_remix_"
if scenario == "legacy" then
    archive[prefix .. "colour_purity"] = "0.000000"
    archive[prefix .. "sky_brightness"] = "0.000000"
    archive[prefix .. "max_bounces"] = "0"
    archive[prefix .. "graphics_preset"] = "3"
    archive[prefix .. "fog"] = "heavyFog"
end
if scenario == "replay" then
    archive[prefix .. "reapply"] = "1"
    archive[prefix .. "colour_purity_enabled"] = "1"
    archive[prefix .. "colour_purity"] = "0"
    archive[prefix .. "sky_brightness_enabled"] = "1"
    archive[prefix .. "sky_brightness"] = "0"
    archive[prefix .. "max_bounces_enabled"] = "1"
    archive[prefix .. "max_bounces"] = "6"
end
local function cv(name)
    return {
        GetString = function() return archive[name] end,
        GetBool = function() return (tonumber(archive[name]) or 0) ~= 0 end,
    }
end
function CreateClientConVar(name, default)
    if archive[name] == nil then archive[name] = default end
    return cv(name)
end
GetConVar = cv
function RunConsoleCommand(name, value) pending[#pending + 1] = {name, value} end
local function flush()
    while #pending > 0 do
        local next = table.remove(pending, 1)
        if commands[next[1]] then commands[next[1]]() else
            local old = archive[next[1]]
            archive[next[1]] = tostring(next[2])
            if old ~= archive[next[1]] then
                for _, callback in pairs(callbacks[next[1]] or {}) do callback(next[1], old, archive[next[1]]) end
            end
        end
    end
end
cvars = {AddChangeCallback = function(name, fn, id)
    callbacks[name] = callbacks[name] or {} callbacks[name][id] = fn
end}
concommand = {Add = function(name, fn) commands[name] = fn end}
hook = {Add = function(event, name, fn)
    hooks[event] = hooks[event] or {} hooks[event][name] = fn
end}
timer = {Simple = function(_, fn) delayed[#delayed + 1] = fn end}
spawnmenu = {
    AddToolMenuOption = function(_, _, id, _, _, _, build) panels[id] = build end,
    AddToolTab = function() end, AddToolCategory = function() end,
}
istable = function(value) return type(value) == "table" end
isfunction = function(value) return type(value) == "function" end
tobool = function(value) return value == "1" end
math.Clamp = function(value, lo, hi) return math.max(lo, math.min(hi, value)) end
math.Round = function(value, decimals) local scale = 10 ^ decimals return math.floor(value * scale + 0.5) / scale end
local i18n = {L = function(s) return s end, N = function(s) return s end, PreparePanel = function() end}
include = function() return i18n end
RemixConfig = {SetConfigVariable = function(key, value)
    writes[#writes + 1] = {key, value} runtime[key] = value return true
end, GetConfigVariable = function() error("The file-only getter is not a live readout") end}
local function boot()
    dofile(menu)
    for _, fn in pairs(hooks.PopulateToolMenu) do fn() end
    for _, fn in pairs(hooks.InitPostEntity) do fn() end
    local timers = delayed delayed = {}
    for _, fn in ipairs(timers) do fn() end
end
local function panel()
    local result = {sliders = {}, boxes = {}}
    function result:Help() end
    result.ControlHelp, result.Button = result.Help, result.Help
    function result:CheckBox(_, name) self.boxes[name] = true return {} end
    function result:ComboBox() return {AddChoice = function() end} end
    function result:NumSlider(label, name)
        assert(name == nil, "Numeric controls must not bind to an empty ConVar")
        local widget = {}
        function widget:SetValue(value)
            self.value = value
            if self.OnValueChanged then self:OnValueChanged(value) end
        end
        function widget:SetEnabled(active) self.active = active end
        self.sliders[label] = widget
        return widget
    end
    panels.nativeloader_remix(result)
    flush()
    return result
end
local function command(key, value) RunConsoleCommand(prefix .. key, value) flush() end
boot()
if scenario == "replay" then
    assert(runtime["rtx.tonemap.psycho17.purityScale"] == "0", "Intentional zero was not replayed")
    assert(runtime["rtx.skyBrightness"] == "0" and runtime["rtx.pathMaxBounces"] == "6")
else
    assert(#writes == 0, "Startup overwrote Remix's saved values")
end
local before = #writes
local ui = panel()
for i = 1, 20 do
    for _, widget in pairs(ui.sliders) do widget:Think() end
    panel()
end
assert(#writes == before, "Opening or synchronizing the panel changed Remix")
if scenario == "legacy" then
    assert(archive[prefix .. "colour_purity"] == "0.000000", "Legacy value was destroyed")
    assert(hooks.NativeLoaderRemixFogOverride.nativeloader_menu() == false, "Dormant fog override suppressed weather")
elseif scenario == "edit" or scenario == "restart" then
    command("colour_purity_enabled", "1")
    assert(runtime["rtx.tonemap.psycho17.purityScale"] == "1", "Explicit selection did not apply draft default")
    ui.sliders["Tone map colour purity"]:OnValueChanged(0)
    flush()
    assert(runtime["rtx.tonemap.psycho17.purityScale"] == "0", "Intentional slider zero lost")
    if scenario == "restart" then
        -- Model an Alt+X edit and Save after the GMod edit, then a new session.
        runtime["rtx.tonemap.psycho17.purityScale"] = "1.61"
        before = #writes
        boot()
        panel()
        assert(#writes == before and runtime["rtx.tonemap.psycho17.purityScale"] == "1.61", "Stale panel value beat native Save")
    end
elseif scenario == "invalid" then
    command("colour_purity_enabled", "1")
    for _, value in ipairs({"nan", "inf", "-1", "6", "not a number", ""}) do
        before = #writes command("colour_purity", value) panel()
        assert(#writes == before, "Invalid number reached Remix: " .. value)
    end
    before = #writes command("graphics_preset", "not a preset") command("post_effects", "banana")
    assert(#writes == before, "Invalid choice reached Remix")
elseif scenario == "reset" then
    command("colour_purity_enabled", "1") command("colour_purity", "0") command("reapply", "1")
    before = #writes
    commands.nativeloader_remix_reset() flush()
    assert(archive[prefix .. "colour_purity"] == "" and archive[prefix .. "colour_purity_enabled"] == "0")
    assert(archive[prefix .. "reapply"] == "0" and #writes == before, "Reset sent a synthetic default")
end
print("PASS " .. scenario)
