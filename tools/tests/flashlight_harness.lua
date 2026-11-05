-- R19 regression for the RTX fixes' flashlight Lua under a fake GMod API (no game):
--   luajit flashlight_harness.lua server <sv_remix_flashlight.lua>
--   luajit flashlight_harness.lua client <cl_remix_flashlight.lua>
local mode, path = arg[1], arg[2]
assert((mode == "server" or mode == "client") and path, "usage: flashlight_harness.lua server|client <file>")
BRANCH = "x86-64"
SERVER, CLIENT = mode == "server", mode == "client"

local now = 100
function SysTime() return now end
function CurTime() return now end
function RealTime() return now end
local timers = {}
timer = {Simple = function(delay, fn) timers[#timers + 1] = {at = now + delay, fn = fn} end}
local function advance(seconds)
    now = now + seconds
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
    end
    for i = #due, 1, -1 do due[i].fn() end
end

function print() end
function MsgC() end
function istable(v) return type(v) == "table" end
function IsValid(v) return type(v) == "table" and v.valid ~= false end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
function tobool(v) return v == true or v == 1 or v == "1" end
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
local hooks, receivers, commands = {}, {}, {}
hook = {Add = function(event, name, fn) hooks[event] = fn end}
concommand = {Add = function(name, fn) commands[name] = fn end}
cvars = {AddChangeCallback = function() end}
util = {AddNetworkString = function() end, CRC = function(text) return tostring(#text) end}
file = {Exists = function() return false end}
function include() end

local function convar(default)
    local cv = {value = default}
    function cv:GetBool() return tobool(self.value) end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    return cv
end
function CreateConVar(name, default) return convar(default) end
function CreateClientConVar(name, default) return convar(default) end

-- net: what a handler reads is queued by the test; what the code sends is recorded.
local incoming, sent, building = {}, {}, nil
local function take() return table.remove(incoming, 1) end
net = {
    Receive = function(name, fn) receivers[name] = fn end,
    Start = function(name) building = {name = name, data = {}} end,
    WriteEntity = function(v) table.insert(building.data, v) end,
    WriteBool = function(v) table.insert(building.data, v) end,
    WriteUInt = function(v) table.insert(building.data, v) end,
    Broadcast = function() building.to = "all" sent[#sent + 1] = building end,
    Send = function(target) building.to = target sent[#sent + 1] = building end,
    SendToServer = function() building.to = "server" sent[#sent + 1] = building end,
    ReadEntity = take, ReadBool = take, ReadUInt = take,
}
local function receive(name, from, ...)
    -- A refused message is left unread, as GMod discards what a receiver does not read.
    incoming = {...}
    receivers[name](0, from)
end
local function count(name)
    local n = 0
    for _, message in ipairs(sent) do if message.name == name then n = n + 1 end end
    return n
end
local function last(name)
    for i = #sent, 1, -1 do if sent[i].name == name then return sent[i] end end
end

local vector = {}
vector.__index = vector
local function Vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vector) end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__mul = function(a, s) return Vector(a.x * s, a.y * s, a.z * s) end
local angles = {Forward = function() return Vector(1, 0, 0) end, Right = function() return Vector(0, 1, 0) end,
                Up = function() return Vector(0, 0, 1) end}
local entities = 0
local function Player(team)
    entities = entities + 1
    local p = {valid = true, alive = true, can = true, team = team or "player", index = entities}
    function p:Alive() return self.alive end
    function p:CanUseFlashlight() return self.can end
    function p:EntIndex() return self.index end
    function p:Nick() return "player" .. self.index end
    function p:EyePos() return Vector(0, 0, 64) end
    function p:EyeAngles() return angles end
    function p:ShouldDrawLocalPlayer() return false end
    function p:EmitSound() end
    return p
end
-- The base gamemode's rule: spectators may only switch off, others as CanUseFlashlight says.
gmod = {GetGamemode = function()
    return {PlayerSwitchFlashlight = function(_, ply, on)
        if ply.team == "spectator" then return not on end
        return ply:CanUseFlashlight()
    end}
end}

if mode == "server" then
    dofile(path)
    local switch = hooks.PlayerSwitchFlashlight
    local ply = Player()
    -- F-04: a burst of toggles costs one broadcast; the next one after the cooldown counts.
    for _ = 1, 10 do receive("rtx_flashlight_toggle", ply, 1, 2, 3) advance(0.01) end
    assert(count("rtx_flashlight_state") == 1 and last("rtx_flashlight_state").data[2] == true, "one toggle in the burst")
    advance(0.3)
    receive("rtx_flashlight_toggle", ply, 1, 2, 3)
    assert(count("rtx_flashlight_state") == 2 and last("rtx_flashlight_state").data[2] == false, "the next toggle after it")
    -- The miss: no flashlight for the dead, spectators or a player the gamemode denies; off always.
    ply.alive = false
    advance(1)
    receive("rtx_flashlight_toggle", ply, 1, 2, 3)
    assert(count("rtx_flashlight_state") == 2, "a dead player's toggle does not switch on")
    assert(switch(ply, true) == false, "nor does the flashlight key")
    ply.alive, ply.can = true, false
    advance(1)
    assert(switch(ply, true) == false, "CanUseFlashlight decides")
    local spectator = Player("spectator")
    assert(switch(spectator, true) == false and switch(spectator, false) == true, "spectators may only switch off")
    ply.can = true
    advance(1)
    assert(switch(ply, true) == true and last("rtx_flashlight_state").data[2] == true, "an allowed player switches on")
    assert(switch(ply, true) == false, "a second switch on within the cooldown is refused")
    assert(switch(ply, false) == true and last("rtx_flashlight_state").data[2] == false, "switching off is never refused")
    -- F-04: colours are coalesced: the first goes out at once, the newest when the interval ends.
    advance(1)
    assert(switch(ply, true) == true)
    local colours = count("rtx_flashlight_update_color")
    for i = 1, 10 do receive("rtx_flashlight_update_color", ply, i, i, i) advance(0.005) end
    assert(count("rtx_flashlight_update_color") == colours + 1, "one colour at once")
    advance(0.2)
    local newest = last("rtx_flashlight_update_color")
    assert(count("rtx_flashlight_update_color") == colours + 2 and newest.data[2] == 10 and newest.data[4] == 10,
        "then the newest colour")
    -- A switched-off flashlight broadcasts no colour.
    advance(1)
    assert(switch(ply, false) == true)
    receive("rtx_flashlight_update_color", ply, 5, 5, 5)
    advance(1)
    assert(count("rtx_flashlight_update_color") == colours + 2, "no colour while off")
    hooks.PlayerDisconnected(ply)
    assert(last("rtx_flashlight_state").data[1] == ply and last("rtx_flashlight_state").data[2] == false)
    io.write("PASS flashlight server: toggle cooldown, gamemode and CanUseFlashlight rule, coalesced colours\n")
else
    local localPlayer = Player()
    function LocalPlayer() return localPlayer end
    local nextId, live, destroyed = 0, {}, 0
    RemixLight = {
        CreateSphere = function() nextId = nextId + 1 live[nextId] = true return nextId end,
        DestroyLight = function(id) assert(live[id], "a live light") live[id] = nil destroyed = destroyed + 1 end,
        UpdateSphere = function(_, _, id) assert(live[id], "updates go to a live light") end,
    }
    local function lights() local n = 0 for _ in pairs(live) do n = n + 1 end return n end
    dofile(path)
    local other = Player()
    -- F-03: the join-time sync repeats an "on" the broadcast already gave: the first light goes.
    receive("rtx_flashlight_state", nil, other, true, 10, 20, 30)
    receive("rtx_flashlight_state", nil, other, true, 10, 20, 30)
    assert(lights() == 1 and destroyed == 1, "a repeated on replaces the light")
    hooks.PreRender(Vector(0, 0, 0), angles, 90)
    receive("rtx_flashlight_state", nil, other, false, 0, 0, 0)
    assert(lights() == 0, "off removes it")
    receive("rtx_flashlight_state", nil, localPlayer, true, 1, 2, 3)
    receive("rtx_flashlight_state", nil, localPlayer, true, 1, 2, 3)
    assert(lights() == 1, "the local player's light too")
    commands.rtx_flashlight_reload()
    advance(0.2)
    assert(lights() == 1, "reload keeps one light")
    io.write("PASS flashlight client: a repeated on replaces the light, off and reload keep the count\n")
end
