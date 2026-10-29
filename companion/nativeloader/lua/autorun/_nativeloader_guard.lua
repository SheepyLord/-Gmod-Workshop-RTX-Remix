-- RTX-session guard (ADR 0022). The companion ships in the RTX-only package (ADR 0013), so this runs
-- only in sessions with RTX. It keeps other add-ons' Lua from undoing what the session needs:
--   * the session console variables the loader sets (cfg/nativeloader_session.cfg) and motion blur
--     stay as set: a Lua write that would change them is dropped and logged once per caller;
--   * the stock post-process functions and halo.Render do nothing: their shaders cannot run at
--     shader model 0, and the screen copy and quad they leave paint the raster image over the
--     path-traced one.
-- The RTX fixes (remixbinary) and this companion are exempt. nativeloader_guard 0 turns it all off.
-- The file name sorts first so it is in place before other add-ons' autorun files set variables.
if SERVER then
    AddCSLuaFile()
    return
end

local enabled = CreateClientConVar("nativeloader_guard", "1", true, false,
    "Keep add-ons from undoing the RTX session's settings and drawing post-processing over the path-traced image")

local EXTRA = { mat_motion_blur_enabled = "0" }
local POSTPROCESS = { "DrawBloom", "DrawColorModify", "DrawSharpen", "DrawMotionBlur", "DrawToyTown",
    "DrawMaterialOverlay", "DrawSobel", "DrawSunbeams", "DrawTexturize", "DrawBokehDOF" }

-- name -> value the session pins, from the loader's session cfg (`name "value"` lines).
local pinned = {}
for line in string.gmatch(file.Read("cfg/nativeloader_session.cfg", "MOD") or "", "[^\r\n]+") do
    local name, value = string.match(line, "^%s*([%w_%.]+)%s+\"?([^\"]*)\"?")
    if name and not string.StartWith(name, "//") then pinned[string.lower(name)] = value end
end
for name, value in pairs(EXTRA) do pinned[name] = pinned[name] or value end

local function exempt(source)
    return string.find(source, "remixbinary", 1, true) or string.find(source, "remixlua", 1, true)
        or string.find(source, "nativeloader", 1, true)
end

local told = {}
local function allow(name, value, level)
    if not enabled:GetBool() then return true end
    local want = pinned[string.lower(tostring(name or ""))]
    if want == nil or tostring(value) == want or tonumber(value) == tonumber(want) then return true end
    local info = debug.getinfo(level, "S")
    local source = info and info.short_src or "?"
    if exempt(source) then return true end
    local key = source .. "|" .. name
    if not told[key] then
        told[key] = true
        MsgN(string.format("[nativeloader] kept %s at %s for RTX: %s tried %s (nativeloader_guard 0 allows it)",
            name, want, source, tostring(value)))
    end
    return false
end

local run_console_command = RunConsoleCommand
function RunConsoleCommand(name, ...)
    if allow(name, select(1, ...), 3) then return run_console_command(name, ...) end
end

local player_meta = FindMetaTable("Player")
local con_command = player_meta.ConCommand
function player_meta:ConCommand(command, ...)
    local name, value = string.match(tostring(command), "^%s*([%w_%.]+)%s*\"?([^\";]*)")
    if not name or allow(name, value, 3) then return con_command(self, command, ...) end
end

-- The post-process functions and halos are defined while the client loads; replace them once it has.
hook.Add("Initialize", "nativeloader_guard", function()
    local originals = {}
    for _, name in ipairs(POSTPROCESS) do
        if isfunction(_G[name]) then
            originals[name] = _G[name]
            _G[name] = function(...) if not enabled:GetBool() then return originals[name](...) end end
        end
    end
    if halo and isfunction(halo.Render) then
        local render_halo = halo.Render
        halo.Render = function(...) if not enabled:GetBool() then return render_halo(...) end end
    end
end)
