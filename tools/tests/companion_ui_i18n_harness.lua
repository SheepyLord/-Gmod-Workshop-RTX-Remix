-- Exercise the built catalogs, metadata phrases, language changes and server-to-client notices.
local dataPath, modulePath, autorunPath = ...
local values = {gmod_language = "zh-CN", nativeloader_language = ""}
local callbacks, phrases, queued = {}, {}, nil
local data = dofile(dataPath)
local function convar(name) return {GetString = function() return values[name] end} end
file = {Exists = function() return true end}
include = function() return data end
istable = function(v) return type(v) == "table" end
isstring = function(v) return type(v) == "string" end
CreateClientConVar = function(name) return convar(name) end
GetConVar = function(name) return convar(name) end
language = {Add = function(key, text) phrases[key] = text end}
util = {CRC = function(text) return tostring(#text) end, AddNetworkString = function() end}
cvars = {AddChangeCallback = function(name, fn) callbacks[name] = fn end}
timer = {Create = function(_, _, _, fn) queued = fn end}
RunConsoleCommand = function(command) assert(command == "spawnmenu_reload") end
surface = {SetFont = function() end, GetTextSize = function(text) return #text * 10 end}
local i18n = dofile(modulePath)
for _, code in ipairs({"zh-CN", "zh-TW", "ja", "ko", "fr", "ru"}) do
    values.nativeloader_language = code
    assert(i18n.L("Sky") ~= "Sky", code .. " companion lookup")
    assert(i18n.A("Settings") ~= "Settings", code .. " add-on lookup")
    assert(i18n.A("player-model.mdl") == "player-model.mdl", "user data fallback")
end
assert(i18n.A("Settings", "zh-tw") == "設定", "add-on language alias")
values.nativeloader_language = "zh-CN"
local token = i18n.P("Settings")
assert(phrases[token:sub(2)] == "设置", "initial metadata translation")
values.nativeloader_language = "fr"
callbacks.nativeloader_language()
queued()
assert(phrases[token:sub(2)] == "Paramètres", "metadata language switch")
values.nativeloader_language = ""
values.gmod_language = "zh-TW"
callbacks.gmod_language()
queued()
assert(phrases[token:sub(2)] == "設定", "follow game language")
local panel = {labels = {}}
panel.Help = function(self, text) self.labels[#self.labels + 1] = text end
panel.NumSlider = function(_, text, name, minimum, maximum)
    assert(text == "" and name == "example" and minimum == 0 and maximum == 1)
    return "slider"
end
i18n.PreparePanel(panel)
i18n.PreparePanel(panel)
assert(panel:NumSlider("A long translated label", "example", 0, 1) == "slider")
assert(#panel.labels == 1, "long labels are shown once without changing control values")

local sent, receive, displayed = {}, nil, nil
AddCSLuaFile = function() end
net = {
    Start = function(name) sent.name = name end,
    WriteString = function(text) sent.text = text end,
    WriteTable = function(arguments) sent.arguments = arguments end,
    Send = function(player) sent.player = player end,
    Receive = function(_, fn) receive = fn end,
    ReadString = function() return sent.text end,
    ReadTable = function() return sent.arguments end,
}
SERVER = true
dofile(autorunPath)
NATIVELOADER_LOCALIZED_CHAT("recipient", "Glass damage: %d / %d", {12, 30})
assert(sent.player == "recipient" and sent.text == "Glass damage: %d / %d")
SERVER = false
include = function() return i18n end
chat = {AddText = function(text) displayed = text end}
dofile(autorunPath)
receive()
assert(displayed == "玻璃損傷：12 / 30", displayed)
print("Companion catalog, metadata, layout and localized notice checks passed")
