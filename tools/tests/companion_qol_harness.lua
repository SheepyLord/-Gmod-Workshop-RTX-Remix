-- Run the actual R20-B autoruns against persisted DATA/ConVars, real timer ordering and fresh Lua
-- locals per map. No runtime settings file can stand in for a live snapshot. See the adjacent .md.
local root, scenario, arg1, arg2 = ...
CLIENT, SERVER = true, false
local lua = root .. "/companion/nativeloader/lua/"
local archive, callbacks, hooks, jobs, data = {}, {}, {}, {}, {}
local now, serial, reads, hints, sounds = 0, 0, 0, {}, {}
local fileReads, settingsWrites = 0, 0
local fault, writeFailed
local cursorBusy, gameMenuBusy, remixMenuBusy = false, false, false
gui = { IsGameUIVisible = function() return gameMenuBusy end }
vgui = { CursorVisible = function() return cursorBusy end }
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
        if due.reps and (due.reps == 0 or due.reps > 1) then jobs[id] = {
            at = now + due.delay, fn = due.fn, delay = due.delay, reps = due.reps == 0 and 0 or due.reps - 1 } end
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
    GetConfigVariable = function() fileReads = fileReads + 1 error("File-only getter must never be used") end,
    SetConfigVariable = function() settingsWrites = settingsWrites + 1 error("The hint must not change settings") end,
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
    -- cl_showhints 0 still decides, for the top-right notice (R22, ADR 0129); the rest never read.
    boot() advance(70) checkHint(0) assert(reads == (arg1 == "hints" and 1 or 0))
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
elseif scenario == "ui" then
    if arg1 == "cursor" or arg1 == "changed" then cursorBusy = true end
    if arg1 == "game-menu" then gameMenuBusy = true end
    if arg1 == "remix-menu" then
        remixMenuBusy = true
        RemixConfig.GetUIState = function() return remixMenuBusy and 1 or 0 end
    end
    boot() advance(80) checkHint(0)
    assert(reads == 0 and data[marker] == nil, "an obscured map must not consume the decision")
    if arg1 == "changed" then state.upscaler, state.frame_generation = 1, 1 end
    cursorBusy, gameMenuBusy, remixMenuBusy = false, false, false
    advance(2)
    checkHint(arg1 == "changed" and 0 or 1)
    assert(reads == 1 and data[marker], "read current settings once after closing the menu")
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
elseif scenario == "notice" or scenario == "notice-hints-off" or scenario == "notice-opt-out" then
    -- R22: the hint's top-right notice. A recording VGUI: every panel method works, a few are kept.
    local width, height = tonumber(arg1) or 1920, tonumber(arg2) or 1080
    state.upscaler = 1 -- DLSS on, frame generation off: the user's case
    if scenario == "notice-hints-off" then archive.cl_showhints = "0" end -- as in the user's own game
    if scenario == "notice-opt-out" then archive.nativeloader_upscaling_hint = "0" end
    local panels, world = {}, {}
    local function panel(kind)
        local p = { kind = kind, x = 0, y = 0, w = 64, h = 24, visible = true, alpha = 255, children = {} }
        panels[#panels + 1] = p
        return setmetatable(p, { __index = function(_, name)
            if name == "SetSize" then return function(self, w, h) self.w, self.h = w, h end end
            if name == "SetTall" then return function(self, h) self.h = h end end
            if name == "GetTall" then return function(self) return self.h end end
            if name == "GetSize" then return function(self) return self.w, self.h end end
            if name == "SetPos" then return function(self, x, y) self.x, self.y = x, y end end
            if name == "GetPos" then return function(self) return self.x, self.y end end
            if name == "SetText" then return function(self, text) self.text = text end end
            if name == "SetAlpha" then return function(self, a) self.alpha = a end end
            if name == "IsVisible" then return function(self) return self.visible end end
            if name == "Remove" then return function(self) self.removed = true end end
            if name == "Add" then return function(self, child)
                local c = panel(child) self.children[#self.children + 1] = c return c end end
            -- Methods are no-ops; plain fields are nil, as on a real panel.
            if type(name) == "string" and name:match("^%u") then return function() end end
        end })
    end
    -- The Hotloader's notice, already at the top right (540 x 92 at y = 40), and a hidden full-screen menu.
    local hotloader = panel("DPanel") hotloader.x, hotloader.y, hotloader.w, hotloader.h = width - 560, 40, 540, 92
    local menu = panel("EditablePanel") menu.w, menu.h, menu.visible = width, height, false
    world[1], world[2] = hotloader, menu
    vgui.Create = function(kind) local p = panel(kind) world[#world + 1] = p return p end
    vgui.GetWorldPanel = function() return { GetChildren = function() return world end } end
    ScrW, ScrH = function() return width end, function() return height end
    IsValid = function(p) return p ~= nil and not p.removed end
    SysTime = function() return now end
    Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    draw = { RoundedBox = function() end }
    surface.CreateFont = function(name, data) surface.fonts = surface.fonts or {} surface.fonts[name] = data end
    surface.SetDrawColor, surface.DrawRect = function() end, function() end
    math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    boot() advance(12.01)
    local notice
    for _, p in ipairs(panels) do if p.nativeloaderHintNotice then notice = p end end
    if scenario == "notice-opt-out" then
        checkHint(0)
        assert(not notice, "the RTX tab's checkbox turns the notice off too")
        assert(reads == 0)
    else
        local sandbox = scenario == "notice" and 1 or 0 -- cl_showhints 0 hides the sandbox hint only
        checkHint(sandbox, sandbox == 1 and "Frame generation is off." or nil)
        assert(notice, "a top-right notice")
        local expected = "Frame generation is off.\nRTX Remix > Remix settings, or Alt+X:\nChoose Frame generation: DLSS-G."
        local body
        for _, c in ipairs(notice.children) do if c.text == expected then body = c end end
        assert(body, "the notice says what the hint says")
        local scale = math.max(0.65, height / 1080)
        assert(notice.x + notice.w == width - math.floor(20 * scale + 0.5), "at the right edge")
        assert(notice.y >= hotloader.y + hotloader.h, "below the Hotloader's notice, not over it")
        assert(notice.w == math.min(math.floor(500 * scale + 0.5), width - math.floor(40 * scale + 0.5)), "scaled with the screen")
        assert(surface.fonts.NativeLoaderHintNotice.size == math.floor(17 * scale + 0.5))
        advance(14.9) assert(not notice.removed, "still there before fifteen seconds")
        advance(0.2) assert(notice.removed, "gone after fifteen seconds")
        checkHint(sandbox) -- the sandbox hint, if any, is unchanged and shown once
    end
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
-- Assert outside the consumer's protected calls: swallowing a forbidden API error cannot pass.
assert(fileReads == 0 and settingsWrites == 0, "Forbidden file-only read or runtime settings write")
print("PASS " .. scenario .. " " .. (arg1 or "") .. " " .. (arg2 or ""))
