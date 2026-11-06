-- Run the actual R20-B autoruns against persisted DATA/ConVars, real timer ordering and fresh Lua
-- locals per map. No runtime settings file can stand in for a live snapshot. See the adjacent .md.
local root, scenario, arg1, arg2 = ...
CLIENT, SERVER = true, false
local lua = root .. "/companion/nativeloader/lua/"
local archive, callbacks, hooks, jobs, data = {}, {}, {}, {}, {}
local now, serial, reads, hints, sounds = 0, 0, 0, {}, {}
local fault, writeFailed
local marker = "nativeloader_companion/upscaling_hint_start.txt"
local skyMarker = "nativeloader_companion/sky_defaults_client_v1.txt"
local status = { schema = 1, process_id = 1234, utc = "2026-11-06T12:00:00Z", activation = {
    outcome = "active", non_nvidia = false, gpu_vendors = { 4318, 4098 },
    performance_tier = { adapter = "NVIDIA GeForce RTX 5090" },
} }
local state = { ready = true, upscaler = 0, frame_generation = 0, dlss_supported = true,
    dlss_frame_generation_supported = true, fsr_frame_generation_supported = true }
local convars = {}
function CreateClientConVar(name, default)
    if archive[name] == nil then archive[name] = default end
    local c = { default = default }
    function c:GetString() return archive[name] end
    function c:GetDefault() return self.default end
    function c:GetBool() return (tonumber(archive[name]) or 0) ~= 0 end
    function c:SetString(value)
        local old = archive[name]
        archive[name] = value
        for _, fn in pairs(callbacks[name] or {}) do fn(name, old, value) end
    end
    convars[name] = c
    return c
end
function GetConVar(name) return convars[name] end
function RunConsoleCommand() error("No queued console writes in the synchronous migration") end
function AddCSLuaFile() end
function include(path)
    if path == "nativeloader/i18n.lua" then return { L = function(s) return s end } end
    return dofile(lua .. path)
end
hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
    Run = function(event) for _, fn in pairs(hooks[event] or {}) do fn() end end,
}
cvars = { AddChangeCallback = function(name, fn, id)
    callbacks[name] = callbacks[name] or {} callbacks[name][id] = fn
end }
timer = {
    Simple = function(delay, fn) serial = serial + 1 jobs[serial] = { at = now + delay, fn = fn } end,
    Create = function(id, delay, reps, fn) jobs[id] = { at = now + delay, fn = fn, delay = delay, reps = reps } end,
    Remove = function(id) jobs[id] = nil end,
}
local function advance(seconds)
    local target = now + seconds
    while true do
        local id, due
        for key, job in pairs(jobs) do if job.at <= target and (not due or job.at < due.at) then id, due = key, job end end
        if not due then break end
        now = due.at
        jobs[id] = nil
        if due.reps and due.reps > 1 then jobs[id] = {
            at = now + due.delay, fn = due.fn, delay = due.delay, reps = due.reps - 1 } end
        due.fn()
    end
    now = target
end
file = {
    Read = function(path)
        if fault == "read" then error("unreadable DATA") end
        return path == "native-loader/status.json" and "status" or data[path]
    end,
    Write = function(path, value) if not writeFailed then data[path] = value end end,
    CreateDir = function() end,
    Exists = function(path) return data[path] ~= nil end,
}
util = { JSONToTable = function()
    if fault == "json" then error("malformed JSON") end
    return status
end }
RemixConfig = {
    GetConfigVariable = function() error("File-only getter must never be used") end,
    SetConfigVariable = function() error("The hint must not change settings") end,
    GetUpscalingState = function() reads = reads + 1 if fault == "native" then error("not ready") end return state end,
}
NOTIFY_HINT = 3
notification = { AddLegacy = function(text, kind, length)
    assert(kind == NOTIFY_HINT and length >= 15)
    hints[#hints + 1] = text
end }
surface = { PlaySound = function(sound) sounds[#sounds + 1] = sound end }
concommand = { Add = function() end }
SortedPairs = pairs
MsgN = function() end
CreateClientConVar("cl_showhints", "1")

local function boot(draw)
    dofile(lua .. "autorun/client/nativeloader_upscaling_hint.lua")
    hook.Run("InitPostEntity")
    if draw ~= false then hook.Run("PostRender") end
end
local function checkHint(count, fragment)
    assert(#hints == count, "hint count " .. #hints .. " expected " .. count)
    assert(#sounds == count, "one sandbox sound per hint")
    if fragment and fragment ~= "" then assert(hints[count]:find(fragment, 1, true), hints[count]) end
end
if scenario == "matrix" then
    state.upscaler, state.frame_generation = tonumber(arg1), tonumber(arg2)
    boot() advance(11.99) checkHint(0) advance(0.02)
    local count = (state.upscaler == 0 or state.frame_generation == 0) and 1 or 0
    checkHint(count, count == 1 and (state.upscaler == 0 and (state.frame_generation == 0
        and "Upscaling and frame generation are off." or "Upscaling is off.") or "Frame generation is off."))
    if count == 1 then assert(hints[1]:find("RTX Remix > Remix settings, or Alt+X:", 1, true)) end
    local before = reads
    boot() advance(70) checkHint(count) assert(reads == before, "map change must not query again")
elseif scenario == "gpu" then
    status.activation.performance_tier.adapter = arg1
    if arg2 == "amd" then status.activation.non_nvidia = true status.activation.gpu_vendors = {4098} end
    if arg2 == "mixed" then status.activation.performance_tier.adapter = "AMD Radeon RX 7900 XTX" end
    boot() advance(70)
    if arg2 == "silent" or arg2 == "amd" or arg2 == "mixed" then checkHint(0)
    else checkHint(1, arg2) end
elseif scenario == "capabilities" then
    if arg1 == "no-dlfg" then state.dlss_frame_generation_supported = false end
    if arg1 == "no-fg" then state.dlss_frame_generation_supported = false state.fsr_frame_generation_supported = false end
    if arg1 == "no-dlss" then state.dlss_supported = false end
    if arg1 == "none" then state.dlss_supported = false state.dlss_frame_generation_supported = false state.fsr_frame_generation_supported = false end
    boot() advance(70)
    checkHint(arg1 == "none" and 0 or 1, arg2)
elseif scenario == "suppressed" then
    if arg1 == "hints" then archive.cl_showhints = "0" end
    if arg1 == "opt-out" then archive.nativeloader_upscaling_hint = "0" end
    if arg1 == "inactive" then status.activation.outcome = "disabled" end
    if arg1 == "schema" then status.schema = 2 end
    if arg1 == "pid" then status.process_id = nil end
    if arg1 == "utc" then status.utc = "old" end
    if arg1 == "gpu" then status.activation.performance_tier = nil end
    if arg1 == "vendor" then status.activation.gpu_vendors = nil end
    if arg1 == "non-nvidia" then status.activation.non_nvidia = nil end
    boot() advance(70) checkHint(0) assert(reads == 0)
elseif scenario == "unreadable" then
    if arg1 == "no-api" then RemixConfig = nil
    elseif arg1 == "file-getter-only" then RemixConfig.GetUpscalingState = nil
    elseif arg1 == "not-ready" then state.ready = false
    elseif arg1 == "nil" then state = nil
    elseif arg1 == "not-table" then state = "0"
    elseif arg1 == "bad-up" then state.upscaler = 6
    elseif arg1 == "bad-fg" then state.frame_generation = -1
    elseif arg1 == "string" then state.upscaler = "0"
    elseif arg1 == "fraction" then state.upscaler = 0.5
    elseif arg1 == "nan" then state.upscaler = 0/0
    elseif arg1 == "inf" then state.frame_generation = math.huge
    elseif arg1 == "no-marker" then writeFailed = true
    else fault = arg1 end
    boot() advance(120) checkHint(0)
    local before = reads
    advance(120) assert(reads == before, "bounded retries")
elseif scenario == "ready-later" then
    state.ready = false boot() advance(18) checkHint(0)
    state.ready = true advance(2) checkHint(1)
elseif scenario == "drawn" then
    boot(false) advance(60) checkHint(0) assert(reads == 0)
    hook.Run("PostRender") advance(11.99) checkHint(0) advance(0.02) checkHint(1)
elseif scenario == "next-start" then
    boot() advance(15) checkHint(1)
    status.utc = "2026-11-06T12:10:00Z" -- same recycled PID, different process start
    boot() advance(15) checkHint(2)
elseif scenario == "both-on-then-off" then
    state.upscaler, state.frame_generation = 1, 1
    boot() advance(15) checkHint(0)
    state.upscaler, state.frame_generation = 0, 0
    boot() advance(15) checkHint(0)
elseif scenario == "migration" then
    dofile(lua .. "autorun/nativeloader_defaults.lua")
    CreateClientConVar("nativeloader_sky_time_passes", "1")
    CreateClientConVar("nativeloader_sky_day_minutes", "20")
    archive.nativeloader_sky_time_passes, archive.nativeloader_sky_day_minutes = arg1, arg2
    hook.Run("NativeLoaderSkyDefaults")
    local old = tonumber(arg1) == 0 and tonumber(arg2) == 30
    assert(archive.nativeloader_sky_time_passes == (old and "1" or arg1))
    assert(archive.nativeloader_sky_day_minutes == (old and "20" or arg2))
    assert(data[skyMarker])
    archive.nativeloader_sky_time_passes, archive.nativeloader_sky_day_minutes = "0", "30"
    dofile(lua .. "autorun/nativeloader_defaults.lua") -- another map/restart, preserved DATA
    hook.Run("NativeLoaderSkyDefaults")
    assert(archive.nativeloader_sky_time_passes == "0" and archive.nativeloader_sky_day_minutes == "30")
elseif scenario == "migration-missing" then
    dofile(lua .. "autorun/nativeloader_defaults.lua")
    hook.Run("NativeLoaderSkyDefaults") assert(not data[skyMarker])
    CreateClientConVar("nativeloader_sky_time_passes", "0")
    CreateClientConVar("nativeloader_sky_day_minutes", "30")
    hook.Run("NativeLoaderSkyDefaults")
    assert(archive.nativeloader_sky_time_passes == "1" and archive.nativeloader_sky_day_minutes == "20")
else error("Unknown scenario " .. scenario) end
print("PASS " .. scenario .. " " .. (arg1 or "") .. " " .. (arg2 or ""))
