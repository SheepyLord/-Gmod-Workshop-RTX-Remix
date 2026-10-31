-- NATIVELOADER_RENDER_GUARD_V2
-- Verified early startup installs this after stock includes/init.lua. A local RTX start without
-- that view installs it from this autorun instead, and the separate verified multiplayer bootstrap
-- route may run after community/server autoruns. Self-contained and idempotent.
-- Lua containment is not native SEH/GPU fault recovery.
if SERVER or MENU_DLL then return end
local environment = getfenv(1)
local early = __NATIVELOADER_RTX_GUARD_EARLY == true
local verifiedMultiplayer = environment ~= _G and rawget(environment, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
if NativeLoaderRenderGuard and NativeLoaderRenderGuard.version == 2 then return end
-- A listen host serves this file and its generated initializer to remote clients too. Outside the
-- private multiplayer environment, install only where this machine's own loader reported an active
-- RTX start: it rewrites status.json at every start, before any Lua runs.
local function localRTXStart()
    if not (file and file.Read) then return false end
    local ok, text = pcall(file.Read, "native-loader/status.json", "DATA")
    return ok and type(text) == "string" and text:find('\n"activation":{"outcome":"active"', 1, true) ~= nil
end
local installation
if verifiedMultiplayer then installation = "verified multiplayer bootstrap"
elseif localRTXStart() then installation = early and "early" or "autorun"
else return end
local late = installation == "verified multiplayer bootstrap"
-- Verified multiplayer chunks receive a scoped hook proxy. Change the real
-- hook table, not a field written only into that chunk's private proxy.
local hook = _G.hook

local enabled = CreateClientConVar("nativeloader_guard", "1", true, false,
    "Keep incompatible add-on rendering from undoing the RTX session")
local playerMeta, convarMeta = FindMetaTable("Player"), FindMetaTable("ConVar")
-- The native getter: the motion-blur read compatibility below wraps ConVar:GetBool.
local getBool = convarMeta and convarMeta.GetBool
local state = {version = 2, installation = installation,
    blocked = {}, errors = {}, cleanup_errors = {}, limitations = {
    "Lua errors only: native faults, GPU failures and infinite loops are not caught",
    "Unknown native state and partially built meshes cannot be universally restored",
    "Later API replacements or unwrapped native aliases can bypass these guards"}}
NativeLoaderRenderGuard = state
local function active()
    local on
    if getBool then on = getBool(enabled) else on = enabled:GetBool() end
    state.enabled = on
    return on
end
state.enabled_at_install = active()
local function pack(...) return {n = select("#", ...), ...} end
local getinfo, traceback, pcall, xpcall, unpack = debug.getinfo, debug.traceback, pcall, xpcall, unpack
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function integer(n) return finite(n) and n % 1 == 0 end
-- Native size arguments are truncated toward zero, so ScrW() / 3 and similar sizes are valid.
local function whole(n) if finite(n) then return n < 0 and math.ceil(n) or math.floor(n) end end
local function virtual(s)
    s = tostring(s or "?"):gsub("\\", "/"):gsub("^@", "")
    local pos = s:find("/lua/", 1, true)
    if pos then s = s:sub(pos + 1) end
    if s:sub(1, 4) == "lua/" then return s:sub(1, 180) end
    if s:find("^[%a]:") or s:sub(1, 1) == "/" then return "<external Lua>" end
    if s:sub(1, 1) == "[" or s:sub(1, 1) == "=" then return "<dynamic Lua>" end
    return s:sub(1, 180)
end
local function caller() local info = getinfo(3, "S") return virtual(info and info.source) end
local function functionSource(fn)
    local info = type(fn) == "function" and getinfo(fn, "S")
    return virtual(info and info.source)
end
local guardSource = getinfo(1, "S").source
-- The first caller outside this guard and native frames, resolved only when a call is refused.
local function externalCaller()
    for level = 3, 32 do
        local info = getinfo(level, "S")
        if not info then break end
        if info.what ~= "C" and info.source ~= guardSource then return virtual(info.source) end
    end
    return "<unknown>"
end
local told, reportCounts = {}, {}
local function report(kind, api, reason, source)
    source = virtual(source)
    local key = kind .. "|" .. api .. "|" .. source .. "|" .. reason
    local count = reportCounts[kind] or 0
    -- Each category has its own cap, so a flood of refusals cannot hide later error records.
    if told[key] or count >= 128 then return end
    told[key], reportCounts[kind] = true, count + 1
    local list = state[kind]
    list[#list + 1] = {api = api, reason = reason, source = source}
    if MsgN then MsgN("[nativeloader] RTX guard: " .. api .. ": " .. reason .. " (" .. source .. ")") end
end
local function reject(api, reason, source)
    report("blocked", api, reason, source or externalCaller())
    error("[nativeloader RTX guard] " .. api .. ": " .. reason, 3)
end
local function rejectNul(api, value, source)
    if type(value) == "string" and value:find("%z") then
        reject(api, "embedded NUL in native string", source)
    end
end

-- Keep the existing pin exemptions and motion-blur read compatibility.
local pinned = {}
local session = file and file.Read and file.Read("cfg/nativeloader_session.cfg", "MOD") or ""
for line in session:gmatch("[^\r\n]+") do
    local name, value = line:match('^%s*([%w_%.]+)%s+"([^"]*)"')
    if not name then name, value = line:match("^%s*([%w_%.]+)%s+([^%s;]+)") end
    if name then pinned[name:lower()] = value end
end
pinned.mat_motion_blur_enabled = pinned.mat_motion_blur_enabled or "0"
for _, name in ipairs({"mat_dxlevel", "mat_hdr_level"}) do
    local value = GetConVar(name)
    if value then pinned[name] = pinned[name] or value:GetString() end
end
local function exempt(s)
    return s:find("remixbinary", 1, true) or s:find("remixlua", 1, true) or s:find("nativeloader", 1, true)
end
local criticalPins = {mat_dxlevel = true, mat_hdr_level = true}
local function allowPin(name, value, source, query)
    if not active() then return true end
    local key = tostring(name or ""):lower()
    local want = pinned[key]
    if want == nil or (exempt(source) and not criticalPins[key]) or (query and value == nil) then return true end
    if type(value) == "boolean" then value = value and "1" or "0" end
    local a, b = tonumber(value), tonumber(want)
    if tostring(value) == want or (a ~= nil and b ~= nil and finite(a) and a == b) then return true end
    report("blocked", tostring(name), "kept session value " .. want, source)
    return false
end
local function tokens(text)
    local out, part, quoted = {}, {}, false
    local function finish() if #part > 0 then out[#out + 1] = table.concat(part) part = {} end end
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == '"' then quoted = not quoted
        elseif not quoted and ch:match("%s") then finish()
        else part[#part + 1] = ch end
    end
    finish()
    return out
end
local function segments(text)
    local out, part, quoted, comment = {}, {}, false, false
    for i = 1, #text do
        local ch = text:sub(i, i)
        if comment then
            if ch == "\n" or ch == "\r" then comment = false out[#out + 1] = table.concat(part) part = {} end
        elseif not quoted and ch == "/" and text:sub(i + 1, i + 1) == "/" then comment = true
        elseif ch == '"' then quoted = not quoted part[#part + 1] = ch
        elseif not quoted and (ch == ";" or ch == "\n" or ch == "\r") then out[#out + 1] = table.concat(part) part = {}
        else part[#part + 1] = ch end
    end
    out[#out + 1] = table.concat(part)
    return out
end
local indirect = {toggle = true, incrementvar = true, multvar = true, cycle = true}
local unsafeCommands = {mat_setvideomode = true, mat_restart = true, vid_restart = true}
local checkCommands
local function checkTokens(args, source, depth)
    local name = tostring(args[1] or ""):lower()
    if unsafeCommands[name] or name:match("^mat_reload") then
        report("blocked", name, "renderer reload/video transitions require an RTX restart", source) return false
    end
    local target = tostring(args[2] or ""):lower()
    if indirect[name] and pinned[target] and (criticalPins[target] or not exempt(source)) then
        report("blocked", name, "indirect write to a session setting", source) return false
    end
    if (name == "alias" or name == "bind") and args[3] then
        if depth >= 4 then report("blocked", name, "nested command limit", source) return false end
        if not checkCommands(table.concat(args, " ", 3), source, depth + 1) then return false end
    end
    return allowPin(name, args[2], source, true)
end
checkCommands = function(text, source, depth)
    for _, command in ipairs(segments(text)) do
        if not checkTokens(tokens(command), source, depth or 0) then return false end
    end
    return true
end
if RunConsoleCommand then
    local original = RunConsoleCommand
    RunConsoleCommand = function(name, ...)
        if not active() then return original(name, ...) end
        local source = caller()
        rejectNul("RunConsoleCommand", name, source)
        for i = 1, select("#", ...) do rejectNul("RunConsoleCommand", select(i, ...), source) end
        if checkTokens({name, ...}, source, 0) then return original(name, ...) end
    end
end
if playerMeta and playerMeta.ConCommand then
    local original = playerMeta.ConCommand
    playerMeta.ConCommand = function(self, command, ...)
        if not active() then return original(self, command, ...) end
        local source = caller()
        rejectNul("Player.ConCommand", command, source)
        if type(command) ~= "string" or checkCommands(command, source, 0) then return original(self, command, ...) end
    end
end
if game and game.ConsoleCommand then
    local original = game.ConsoleCommand
    game.ConsoleCommand = function(command, ...)
        if not active() then return original(command, ...) end
        local source = caller()
        rejectNul("game.ConsoleCommand", command, source)
        if type(command) ~= "string" or checkCommands(command, source, 0) then return original(command, ...) end
    end
end
if convarMeta then
    local getName = convarMeta.GetName
    for _, method in ipairs({"SetInt", "SetFloat", "SetBool", "SetString"}) do
        local original = convarMeta[method]
        if original and getName then
            convarMeta[method] = function(self, value, ...)
                if allowPin(getName(self), value, caller(), false) then return original(self, value, ...) end
            end
        end
    end
    if pinned.mat_motion_blur_enabled == "0" then
        local blur = GetConVar("mat_motion_blur_enabled")
        for method, on in pairs({GetInt = 1, GetFloat = 1, GetBool = true, GetString = "1"}) do
            local original = convarMeta[method]
            if original then
                convarMeta[method] = function(self, ...)
                    if rawequal(self, blur) and active() then return on end
                    return original(self, ...)
                end
            end
        end
    end
end

-- Early installation captures enums before add-ons can rewrite them. The verified
-- multiplayer bootstrap can run later, so its current globals are not guaranteed pristine.
-- R32F (27) is used by the shipped MMDHL shadow target and verified on this backend,
-- but is not exported as IMAGE_FORMAT_R32F by every supported GMod build.
local formats, sizes, depthModes, fullFrame = {[-1] = true, [27] = true}, {}, {}, {}
for name, value in pairs(_G) do
    if type(name) == "string" and integer(value) then
        if name:match("^IMAGE_FORMAT_") and not name:find("COUNT", 1, true)
            and not name:find("NUM_FORMATS", 1, true) then formats[value] = true end
        if name:match("^RT_SIZE_") then sizes[value] = true end
        if name:match("^MATERIAL_RT_DEPTH_") then depthModes[value] = true end
    end
end
for _, name in ipairs({"RT_SIZE_FULL_FRAME_BUFFER", "RT_SIZE_FULL_FRAME_BUFFER_ROUNDED_UP", "RT_SIZE_HDR"}) do
    if _G[name] ~= nil then fullFrame[_G[name]] = true end
end
local allocations, allocationCounts = {}, {}
state.allocations_by_source = allocationCounts
local function canonical(name) return name:gsub("\\", "/"):lower():gsub("%.[^./]*$", "") end
local function checkTarget(api, name, w, h, sizeMode, format, source)
    if type(name) ~= "string" or #name == 0 or #name > 256 or name:find("%z") then reject(api, "invalid target name", source) end
    local base = canonical(name):match("([^/]+)$") or ""
    if base:match("^_rt_shadowdepthtexture_") or base:match("^_rt_resolvedfullframedepth") then
        reject(api, "engine-owned shadow/depth target cannot be recreated by Lua in RTX", source)
    end
    w, h = whole(w), whole(h)
    if not w or not h then reject(api, "target dimensions must be finite numbers", source) end
    if sizeMode ~= nil and not sizes[sizeMode] then reject(api, "unknown render-target size mode", source) end
    local fw, fh = w, h
    if fullFrame[sizeMode] then
        if w < -1 or h < -1 or w == 0 or h == 0 then reject(api, "invalid full-frame dimensions", source) end
        fw, fh = ScrW(), ScrH()
    elseif w <= 0 or h <= 0 then reject(api, "target dimensions must be positive", source) end
    if not finite(fw) or not finite(fh) or fw > 16384 or fh > 16384 or fw * fh > 67108864 then
        reject(api, "render-target allocation exceeds the guard limit", source)
    end
    if format ~= nil and (not integer(format) or not formats[format]) then reject(api, "unknown image format", source) end
    local key = canonical(name)
    if not allocations[key] then
        if (allocationCounts[source] or 0) >= 128 then reject(api, "caller render-target name limit", source) end
        return key, source
    end
end
local function allocated(key, source)
    if key then allocations[key] = true allocationCounts[source] = (allocationCounts[source] or 0) + 1 end
end
if GetRenderTarget then
    local original = GetRenderTarget
    GetRenderTarget = function(name, w, h, ...)
        if not active() then return original(name, w, h, ...) end
        local key, bytes = checkTarget("GetRenderTarget", name, w, h, nil, nil, caller())
        local result = pack(original(name, w, h, ...))
        if result[1] then allocated(key, bytes) end
        return unpack(result, 1, result.n)
    end
end
if GetRenderTargetEx then
    local original = GetRenderTargetEx
    GetRenderTargetEx = function(name, w, h, size, depth, flags, rtFlags, format, ...)
        if not active() then return original(name, w, h, size, depth, flags, rtFlags, format, ...) end
        local source = caller()
        if not integer(size) or not sizes[size] then reject("GetRenderTargetEx", "unknown size mode", source) end
        if not integer(depth) or not depthModes[depth] then reject("GetRenderTargetEx", "unknown depth mode", source) end
        if not integer(format) or not formats[format] then reject("GetRenderTargetEx", "unknown image format", source) end
        if not integer(flags) or not integer(rtFlags) or flags < 0 or flags > 4294967295
            or rtFlags < 0 or rtFlags > 4294967295 then reject("GetRenderTargetEx", "flags must be finite unsigned integers", source) end
        local key, bytes = checkTarget("GetRenderTargetEx", name, w, h, size, format, source)
        local result = pack(original(name, w, h, size, depth, flags, rtFlags, format, ...))
        if result[1] then allocated(key, bytes) end
        return unpack(result, 1, result.n)
    end
end

local unsupported = {depthwrite = true, screenspace_general = true, screenspace_general_dx9 = true}
-- Shader names per material object: render.SetMaterial runs many times every frame.
local shaderNames = setmetatable({}, {__mode = "k"})
local function shaderMethod(mat) return mat.GetShader end
local function shaderName(mat)
    if mat == nil then return end
    local name = shaderNames[mat]
    if name ~= nil then return name or nil end
    name = false
    local ok, method = pcall(shaderMethod, mat)
    if ok and type(method) == "function" then
        local success, value = pcall(method, mat)
        if success and type(value) == "string" then name = value:lower() end
    end
    local kind = type(mat)
    if kind == "userdata" or kind == "table" then shaderNames[mat] = name end
    return name or nil
end
if CreateMaterial then
    local original = CreateMaterial
    CreateMaterial = function(name, shader, ...)
        if active() then
            local source = caller()
            rejectNul("CreateMaterial", name, source)
            rejectNul("CreateMaterial", shader, source)
            if type(shader) == "string" and unsupported[shader:lower()] then reject("CreateMaterial", "unsupported RTX shader", source) end
        end
        return original(name, shader, ...)
    end
end
if Material then
    local original = Material
    Material = function(path, ...)
        if active() then rejectNul("Material", path, caller()) end
        local result = pack(original(path, ...))
        if unsupported[shaderName(result[1])] and active() then reject("Material", "material requires an unsupported RTX shader", caller()) end
        return unpack(result, 1, result.n)
    end
end
local nativeRender = {}
for name, value in pairs(render or {}) do nativeRender[name] = value end
for _, name in ipairs({"SetMaterial", "MaterialOverride", "BrushMaterialOverride", "WorldMaterialOverride"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(mat, ...)
            if unsupported[shaderName(mat)] and active() then reject("render." .. name, "unsupported RTX shader draw", caller()) end
            return original(mat, ...)
        end
    end
end
for _, name in ipairs({"GetResolvedFullFrameDepth", "RedownloadAllLightmaps"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() then reject("render." .. name, "unsupported RTX depth/lightmap rebuild", caller()) end
            return original(...)
        end
    end
end

-- Track only observed Lua pushes. Never guess native contexts or use mesh.End as an abort.
local frame, busy = nil, 0
local stacks = {rt = {}, camera = {}, clip = {}, model = {}}
-- An entry is live while its owner, or one of the owner's callers, is a protected callback still running.
local function live(action)
    local owner = action.owner
    while owner do
        if owner.completed == nil then return true end
        owner = owner.parent
    end
    return false
end
-- A push left open by code that failed outside a protected callback (the stock toolgun screen around
-- a tool's DrawToolScreen, an ENT:Draw error between cam.Start3D2D and End3D2D) is never popped.
-- At each frame boundary (a new FrameNumber, or PreRender where that is unavailable), forget the
-- tracked entries no running callback owns. Native state is neither guessed nor popped: only the
-- guard's own bookkeeping is resynchronized.
local function resync()
    for _, stack in pairs(stacks) do
        local kept = 0
        for i = 1, #stack do
            local action = stack[i]
            if live(action) then kept = kept + 1 stack[kept] = action else action.active = false end
        end
        for i = #stack, kept + 1, -1 do stack[i] = nil end
    end
end
local frameNumber, seenFrame = FrameNumber, nil
local function sync()
    if not frameNumber then return end
    local ok, now = pcall(frameNumber)
    if ok and now ~= seenFrame then
        if seenFrame ~= nil then resync() end
        seenFrame = now
    end
end
-- Only the running callback chain's own scopes count toward its limit; unowned leftovers never do.
local function chainDepth(stack)
    if not frame then return 0 end
    local count = 0
    for i = 1, #stack do if live(stack[i]) then count = count + 1 end end
    return count
end
-- A protected callback's entry render target, recorded when it first changes render targets.
local function noteTarget()
    local f = frame
    while f and f.haveTarget == nil do
        if nativeRender.GetRenderTarget then f.haveTarget, f.target = pcall(nativeRender.GetRenderTarget)
        else f.haveTarget = false end
        f = f.parent
    end
end
local function log(f)
    local list = f.actions
    if not list then list = {} f.actions = list end
    return list
end
local function pushed(kind, undo, replay)
    local action = {stack = stacks[kind], owner = frame, undo = undo, replay = replay, active = true}
    action.stack[#action.stack + 1] = action
    if frame then local list = log(frame) list[#list + 1] = action end
end
local function descendant(owner, ancestor)
    while owner do
        if owner == ancestor then return true end
        owner = owner.parent
    end
    return false
end
local function popped(kind)
    local action = table.remove(stacks[kind])
    if not action then return end
    action.active = false
    -- A completed Pre hook may deliberately leave a scope for its Post hook.
    -- If that later callback fails, retain the exact known RT push for replay.
    -- A descendant's scope was created after our entry and is already gone.
    if frame and action.owner ~= frame and not descendant(action.owner, frame) then
        local list = log(frame)
        list[#list + 1] = {restore = action, previous = stacks[kind][#stacks[kind]], depth = #stacks[kind]}
    end
end
local function invokeBusy(fn, ...)
    busy = busy + 1
    local result = pack(pcall(fn, ...))
    busy = busy - 1
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end
local function pair(tbl, push, pop, kind, validate)
    local first, last = tbl and tbl[push], tbl and tbl[pop]
    if not first or not last then return end
    tbl[push] = function(...)
        if busy > 0 then return first(...) end
        sync()
        if active() then
            if chainDepth(stacks[kind]) >= 32 then reject(push, "tracked stack limit") end
            if validate then validate(nil, ...) end
        end
        if kind == "rt" and frame then noteTarget() end
        local replay
        if kind == "rt" then
            local args = pack(...)
            replay = function()
                if validate then validate("<tracked render-target push>", unpack(args, 1, args.n)) end
                return first(unpack(args, 1, args.n))
            end
        end
        local result = pack(invokeBusy(first, ...))
        pushed(kind, last, replay)
        return unpack(result, 1, result.n)
    end
    tbl[pop] = function(...)
        if busy > 0 then return last(...) end
        sync()
        if active() then
            local top = stacks[kind][#stacks[kind]]
            if not top then reject(pop, "no tracked Lua push to pop") end
            if frame and top.owner ~= frame and (not top.owner or not top.owner.completed) then
                reject(pop, "protected callback cannot consume caller-owned state")
            end
        end
        if kind == "rt" and frame then noteTarget() end
        local result = pack(invokeBusy(last, ...))
        popped(kind)
        return unpack(result, 1, result.n)
    end
end
local function viewValues(api, source, view)
    if view == nil then return end
    if type(view) ~= "table" then reject(api, "view must be a table", source) end
    for _, key in ipairs({"x", "y", "w", "h", "fov", "znear", "zfar", "zNear", "zFar", "aspect"}) do
        if view[key] ~= nil and not finite(view[key]) then reject(api, "non-finite view parameter " .. key, source) end
    end
    for _, key in ipairs({"w", "h"}) do
        if view[key] ~= nil and (view[key] <= 0 or view[key] > 16384) then reject(api, "invalid explicit viewport", source) end
    end
    for _, key in ipairs({"origin", "angles"}) do
        if view[key] ~= nil then
            local ok, a, b, c = pcall(function()
                if key == "origin" then return view[key].x, view[key].y, view[key].z end
                return view[key].p, view[key].y, view[key].r
            end)
            if not ok or not finite(a) or not finite(b) or not finite(c) then reject(api, "invalid " .. key, source) end
        end
    end
end
local function dimensions(texture) return texture:Width(), texture:Height() end
local validTextures = setmetatable({}, {__mode = "k"})
local function targetValues(source, texture, x, y, w, h)
    if texture ~= nil and not validTextures[texture] then
        local ok, width, height = pcall(dimensions, texture)
        if not ok or not finite(width) or not finite(height) or width <= 0 or height <= 0 then reject("PushRenderTarget", "invalid texture", source) end
        local kind = type(texture)
        if kind == "userdata" or kind == "table" then validTextures[texture] = true end
    end
    if (x ~= nil and not finite(x)) or (y ~= nil and not finite(y)) or (w ~= nil and not finite(w)) or (h ~= nil and not finite(h)) then
        reject("PushRenderTarget", "non-finite viewport", source)
    end
    if (w and w <= 0) or (h and h <= 0) then reject("PushRenderTarget", "invalid explicit viewport", source) end
end
pair(render, "PushRenderTarget", "PopRenderTarget", "rt", targetValues)
pair(render, "PushCustomClipPlane", "PopCustomClipPlane", "clip")
pair(cam, "PushModelMatrix", "PopModelMatrix", "model")
pair(cam, "Start", "End3D", "camera", function(s, view) viewValues("cam.Start", s, view) end)
pair(cam, "Start2D", "End2D", "camera")
pair(cam, "Start3D", "End3D", "camera", function(s, pos, angle, fov, x, y, w, h, near, far)
    viewValues("cam.Start3D", s, {origin = pos, angles = angle, fov = fov, x = x, y = y, w = w, h = h, znear = near, zfar = far})
end)
pair(cam, "Start3D2D", "End3D2D", "camera")
if nativeRender.SetRenderTarget then
    render.SetRenderTarget = function(texture, ...)
        if active() then targetValues(nil, texture) end
        if frame and busy == 0 then noteTarget() end
        local result = pack(nativeRender.SetRenderTarget(texture, ...))
        if frame and busy == 0 then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
if nativeRender.SetRenderTargetEx then
    render.SetRenderTargetEx = function(index, texture, ...)
        if active() then
            if not integer(index) or index < 0 or index > 3 then reject("render.SetRenderTargetEx", "unknown render-target slot")
            -- Clearing slots 1-3 with nil is how stock code ends MRT work; only binding them is refused.
            elseif index ~= 0 and texture ~= nil then reject("render.SetRenderTargetEx", "MRT is unsupported by the RTX path")
            else targetValues(nil, texture) end
        end
        local primary = index == 0 and frame ~= nil and busy == 0
        if primary then noteTarget() end
        local result = pack(nativeRender.SetRenderTargetEx(index, texture, ...))
        if primary then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
local viewDepth = 0
if nativeRender.RenderView then
    render.RenderView = function(view, ...)
        if not active() then return nativeRender.RenderView(view, ...) end
        viewValues("render.RenderView", caller(), view)
        if viewDepth >= 4 then reject("render.RenderView", "nested view limit", caller()) end
        viewDepth = viewDepth + 1
        local result = pack(pcall(nativeRender.RenderView, view, ...))
        viewDepth = viewDepth - 1
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
end
local function sourceOf(f)
    local source = f.source
    if not source then source = functionSource(f.fn) f.source = source end
    return source
end
local function cleanup(f)
    local actions = f.actions
    busy = busy + 1
    for i = actions and #actions or 0, 1, -1 do
        local action = actions[i]
        if action.restore then
            local prior = action.restore
            if #prior.stack ~= action.depth or prior.stack[#prior.stack] ~= action.previous then
                report("cleanup_errors", f.event, "tracked state changed before popped-scope restoration", sourceOf(f))
            elseif not prior.replay then
                -- Camera/clip/matrix defaults and mutable arguments are not
                -- enough to reconstruct an earlier native context safely.
                report("cleanup_errors", f.event, "completed camera/clip/matrix pop cannot be safely replayed", sourceOf(f))
            else
                local ok = pcall(prior.replay)
                if ok then prior.stack[#prior.stack + 1] = prior prior.active = true
                else report("cleanup_errors", f.event, "popped render-target restoration failed", sourceOf(f)) end
            end
        elseif action.active then
            if action.stack[#action.stack] == action then
                local ok = pcall(action.undo)
                if ok then table.remove(action.stack) action.active = false
                else report("cleanup_errors", f.event, "tracked stack restoration failed", sourceOf(f)) end
            else report("cleanup_errors", f.event, "untracked state prevents stack restoration", sourceOf(f)) end
        end
    end
    if f.targetChanged and f.haveTarget and nativeRender.SetRenderTarget then
        local ok = pcall(nativeRender.SetRenderTarget, f.target)
        if not ok then report("cleanup_errors", f.event, "target restoration failed", sourceOf(f)) end
    end
    busy = busy - 1
end
-- A failure prints the original error and its stack through the engine's own error output, at most
-- once per callback every ten seconds; the guard's records keep virtual sources only. Three
-- consecutive failures within ten seconds quarantine a hook, timer or cvar callback. Gamemode
-- methods are never quarantined: base GM:PostDrawViewModel draws the hands for every weapon.
local clock = SysTime or RealTime or os.clock
local reportInterval, quarantineWindow, quarantineFailures = 10, 10, 3
local failures = setmetatable({}, {__mode = "k"})
local function printError(text)
    if ErrorNoHaltWithStack then ErrorNoHaltWithStack(text)
    elseif ErrorNoHalt then ErrorNoHalt(traceback(text, 3) .. "\n")
    elseif MsgN then MsgN(traceback(text, 3)) end
end
local function failed(f, text)
    local now = clock()
    local record = failures[f.fn]
    if not record then record = {streak = 0, first = now, suppressed = 0} failures[f.fn] = record end
    if record.streak == 0 or now - record.first > quarantineWindow then record.streak, record.first = 1, now
    else record.streak = record.streak + 1 end
    if record.reported and now - record.reported < reportInterval then
        record.suppressed = record.suppressed + 1
        return
    end
    local suppressed = record.suppressed
    record.reported, record.suppressed = now, 0
    pcall(printError, text)
    report("errors", f.event, "Lua error contained; its message and stack are in the console", sourceOf(f))
    if suppressed > 0 and MsgN then
        MsgN("[nativeloader] RTX guard: " .. f.event .. ": " .. suppressed .. " further Lua errors from "
            .. sourceOf(f) .. " since the last report")
    end
end
-- The xpcall message handler runs where the error was raised, so the printed stack is the callback's.
local function handler(err)
    local text = tostring(err)
    if frame then pcall(failed, frame, text) end
    return text
end
local function quarantined(fn, event)
    local record = failures[fn]
    if not record or record.streak < quarantineFailures then return false end
    report("errors", event, "callback quarantined after " .. quarantineFailures .. " consecutive Lua errors", functionSource(fn))
    return true
end
local function settle(f, ok, ...)
    frame = f.parent
    f.completed = ok
    if not ok then cleanup(f) return false end
    local record = failures[f.fn]
    if record then record.streak = 0 end
    -- Successful nested work is part of its active caller's chronological
    -- undo log. Failed children already cleaned their own log and must not
    -- replay those restores a second time if an ancestor subsequently fails.
    local parent, actions = f.parent, f.actions
    if parent then
        if actions then
            local list = log(parent)
            for i = 1, #actions do list[#list + 1] = actions[i] end
        end
        if f.targetChanged then parent.targetChanged = true end
    end
    return true, ...
end
local function protectedCall(fn, event, ...)
    local f = {event = event, fn = fn, parent = frame}
    frame = f
    return settle(f, xpcall(fn, handler, ...))
end
local events = {Initialize = true, InitPostEntity = true, OnReloaded = true,
    PreRender = true, PostRender = true, RenderScene = true, RenderScreenspaceEffects = true,
    PreDrawEffects = true, PostDrawEffects = true, PreDrawOpaqueRenderables = true,
    PostDrawOpaqueRenderables = true, PreDrawTranslucentRenderables = true, PostDrawTranslucentRenderables = true,
    PreDrawViewModel = true, PostDrawViewModel = true, PostDrawPlayerHands = true,
    HUDPaint = true, PreDrawHUD = true, PostDrawHUD = true, PostRenderVGUI = true,
    SetupWorldFog = true, SetupSkyboxFog = true, NeedsDepthPass = true,
    InitPostShaderlib = true, InitPostReconstruction = true, PreDrawReconstruction = true, PostDrawReconstruction = true}
local getHooks, quarantine = hook.GetTable, {}
local function gamemodeResult(ok, ...) if ok then return ... end end
if not late then
    local originalCall = hook.Call
    hook.Call = function(name, gm, ...)
        if not events[name] or not active() then return originalCall(name, gm, ...) end
        if name == "PreRender" and not frameNumber and frame == nil and busy == 0 then resync() end
        local entries = getHooks()[name]
        local stopped = quarantine[name]
        if not stopped then stopped = setmetatable({}, {__mode = "k"}) quarantine[name] = stopped end
        if entries then
            for id, fn in pairs(entries) do
                if type(id) ~= "string" and not IsValid(id) then entries[id] = nil
                elseif stopped[id] ~= fn then
                    local ok, a, b, c, d, e, g
                    if type(id) == "string" then ok, a, b, c, d, e, g = protectedCall(fn, name, ...)
                    else ok, a, b, c, d, e, g = protectedCall(fn, name, id, ...) end
                    if not ok then
                        if quarantined(fn, name) then stopped[id] = fn end
                    elseif a ~= nil then return a, b, c, d, e, g end
                end
            end
        end
        local fn = gm and gm[name]
        if fn then return gamemodeResult(protectedCall(fn, name, gm, ...)) end
    end
end
local function callback(fn, event)
    local stopped = false
    local function finish(ok, ...)
        if ok then return ... end
        if quarantined(fn, event) then stopped = true end
    end
    return function(...)
        if not active() then return fn(...) end
        if stopped then return end
        return finish(protectedCall(fn, event, ...))
    end
end
-- In the verified multiplayer route the remote server's own Lua stays as it is (ADR 0052): only
-- callbacks defined in the owned, hash-verified environments are protected, recognized by the
-- private marker raw-set in their environment.
local function owned(fn)
    if type(fn) ~= "function" then return false end
    local ok, env = pcall(getfenv, fn)
    return ok and type(env) == "table" and env ~= _G and rawget(env, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
end
local function protects(fn) return type(fn) == "function" and (not late or owned(fn)) end
if late then
    -- The engine may already hold the original hook.Call. Protect owned render
    -- functions themselves in this late path. Loading-hook identity stays intact
    -- for the verified bootstrap's initialization replay.
    local loadingEvents = {Initialize = true, InitPostEntity = true, OnReloaded = true}
    local lateEvents, registrations = {}, {}
    for event in pairs(events) do
        if not loadingEvents[event] then lateEvents[event] = true end
    end
    local function renderCallback(event, id, fn)
        local entries = registrations[event]
        if not entries then
            entries = setmetatable({}, {__mode = "k"})
            registrations[event] = entries
        end
        local prior = entries[id]
        if prior and (prior.original == fn or prior.wrapper == fn) then return prior.wrapper end
        local wrapper = callback(fn, event)
        entries[id] = {original = fn, wrapper = wrapper}
        return wrapper
    end
    for event, entries in pairs(getHooks()) do
        if lateEvents[event] and type(entries) == "table" then
            for id, fn in pairs(entries) do
                if owned(fn) then entries[id] = renderCallback(event, id, fn) end
            end
        end
    end
    local originalAdd = hook.Add
    hook.Add = function(event, id, fn, ...)
        if lateEvents[event] and id ~= nil and owned(fn) then fn = renderCallback(event, id, fn) end
        return originalAdd(event, id, fn, ...)
    end
    state.late_render_wrappers = true
end
if timer and timer.Create then
    local original = timer.Create
    timer.Create = function(id, delay, count, fn, ...)
        if protects(fn) then fn = callback(fn, "timer.Create") end
        return original(id, delay, count, fn, ...)
    end
end
if timer and timer.Simple then
    local original = timer.Simple
    timer.Simple = function(delay, fn, ...)
        if protects(fn) then fn = callback(fn, "timer.Simple") end
        return original(delay, fn, ...)
    end
end
if cvars and cvars.AddChangeCallback then
    local original = cvars.AddChangeCallback
    cvars.AddChangeCallback = function(name, fn, id, ...)
        if protects(fn) then fn = callback(fn, "cvars.AddChangeCallback") end
        return original(name, fn, id, ...)
    end
end
local postprocess = {"DrawBloom", "DrawColorModify", "DrawSharpen", "DrawMotionBlur", "DrawToyTown",
    "DrawMaterialOverlay", "DrawSobel", "DrawSunbeams", "DrawTexturize", "DrawBokehDOF"}
local wrappedPost = {}
local function installPost()
    for _, name in ipairs(postprocess) do
        local original = _G[name]
        if type(original) == "function" and original ~= wrappedPost[name] then
            local wrapper = function(...) if not active() then return original(...) end end
            wrappedPost[name], _G[name] = wrapper, wrapper
        end
    end
    if halo and type(halo.Render) == "function" and halo.Render ~= wrappedPost.halo then
        local original = halo.Render
        local wrapper = function(...) if not active() then return original(...) end end
        wrappedPost.halo, halo.Render = wrapper, wrapper
    end
end
installPost()
hook.Add("Initialize", "nativeloader_guard", installPost)
