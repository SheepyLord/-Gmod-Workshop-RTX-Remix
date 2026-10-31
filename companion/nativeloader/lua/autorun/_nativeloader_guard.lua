-- NATIVELOADER_RENDER_GUARD_V2
-- Verified early startup installs this after stock includes/init.lua; the separate
-- verified multiplayer bootstrap route may run after community/server autoruns.
-- Self-contained and idempotent. Lua containment is not native SEH/GPU fault recovery.
if SERVER then if AddCSLuaFile then AddCSLuaFile() end return end
if MENU_DLL then return end
local environment = getfenv(1)
local early = __NATIVELOADER_RTX_GUARD_EARLY == true
local verifiedMultiplayer = environment ~= _G and rawget(environment, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
if not early and not verifiedMultiplayer then return end
if NativeLoaderRenderGuard and NativeLoaderRenderGuard.version == 2 then return end
-- Verified multiplayer chunks receive a scoped hook proxy. Replace the real
-- dispatcher, not a field written only into that chunk's private proxy.
local hook = _G.hook

local enabled = CreateClientConVar("nativeloader_guard", "1", true, false,
    "Keep incompatible add-on rendering from undoing the RTX session")
local state = {version = 2, installation = early and "early" or "verified multiplayer bootstrap",
    blocked = {}, errors = {}, cleanup_errors = {}, limitations = {
    "Lua errors only: native faults, GPU failures and infinite loops are not caught",
    "Unknown native state and partially built meshes cannot be universally restored",
    "Later API replacements or unwrapped native aliases can bypass these guards"}}
NativeLoaderRenderGuard = state
local function active() local on = enabled:GetBool() state.enabled = on return on end
state.enabled_at_install = active()
local function pack(...) return {n = select("#", ...), ...} end
local getinfo, pcall, xpcall, unpack = debug.getinfo, pcall, xpcall, unpack
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function integer(n) return finite(n) and n % 1 == 0 end
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
local told, reportCount = {}, 0
local function report(kind, api, reason, source)
    source = virtual(source)
    local key = kind .. "|" .. api .. "|" .. source .. "|" .. reason
    if told[key] or reportCount >= 128 then return end
    told[key], reportCount = true, reportCount + 1
    local list = state[kind]
    list[#list + 1] = {api = api, reason = reason, source = source}
    if MsgN then MsgN("[nativeloader] RTX guard: " .. api .. ": " .. reason .. " (" .. source .. ")") end
end
local function reject(api, reason, source)
    report("blocked", api, reason, source)
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
local playerMeta, convarMeta = FindMetaTable("Player"), FindMetaTable("ConVar")
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
    if not integer(w) or not integer(h) then reject(api, "target dimensions must be finite integers", source) end
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
local function shaderName(mat)
    if mat == nil then return end
    local ok, method = pcall(function() return mat.GetShader end)
    if not ok or type(method) ~= "function" then return end
    local success, name = pcall(method, mat)
    if success and type(name) == "string" then return name:lower() end
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
        if active() and unsupported[shaderName(result[1])] then reject("Material", "material requires an unsupported RTX shader", caller()) end
        return unpack(result, 1, result.n)
    end
end
local nativeRender = {}
for name, value in pairs(render or {}) do nativeRender[name] = value end
for _, name in ipairs({"SetMaterial", "MaterialOverride", "BrushMaterialOverride", "WorldMaterialOverride"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(mat, ...)
            if active() and unsupported[shaderName(mat)] then reject("render." .. name, "unsupported RTX shader draw", caller()) end
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
local function pushed(kind, undo, replay)
    local action = {stack = stacks[kind], owner = frame, undo = undo, replay = replay, active = true}
    action.stack[#action.stack + 1] = action
    if frame then frame.actions[#frame.actions + 1] = action end
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
        frame.actions[#frame.actions + 1] = {restore = action,
            previous = stacks[kind][#stacks[kind]], depth = #stacks[kind]}
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
        if active() then
            if #stacks[kind] >= 32 then reject(push, "tracked stack limit", caller()) end
            if validate then validate(caller(), ...) end
        end
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
        if active() then
            local top = stacks[kind][#stacks[kind]]
            if not top then reject(pop, "no tracked Lua push to pop", caller()) end
            if frame and top.owner ~= frame and (not top.owner or not top.owner.completed) then
                reject(pop, "protected callback cannot consume caller-owned state", caller())
            end
        end
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
local function targetValues(source, texture, x, y, w, h)
    if texture ~= nil then
        local ok, width, height = pcall(function() return texture:Width(), texture:Height() end)
        if not ok or not finite(width) or not finite(height) or width <= 0 or height <= 0 then reject("PushRenderTarget", "invalid texture", source) end
    end
    for _, value in pairs({x = x, y = y, w = w, h = h}) do
        if not finite(value) then reject("PushRenderTarget", "non-finite viewport", source) end
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
        if active() then targetValues(caller(), texture) end
        local result = pack(nativeRender.SetRenderTarget(texture, ...))
        if frame and busy == 0 then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
if nativeRender.SetRenderTargetEx then
    render.SetRenderTargetEx = function(index, texture, ...)
        if active() and (not integer(index) or index ~= 0) then reject("render.SetRenderTargetEx", "MRT is unsupported by the RTX path", caller()) end
        if active() then targetValues(caller(), texture) end
        local result = pack(nativeRender.SetRenderTargetEx(index, texture, ...))
        if frame and busy == 0 and index == 0 then frame.targetChanged = true end
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
local function cleanup(f)
    busy = busy + 1
    for i = #f.actions, 1, -1 do
        local action = f.actions[i]
        if action.restore then
            local prior = action.restore
            if #prior.stack ~= action.depth or prior.stack[#prior.stack] ~= action.previous then
                report("cleanup_errors", f.event, "tracked state changed before popped-scope restoration", f.source)
            elseif not prior.replay then
                -- Camera/clip/matrix defaults and mutable arguments are not
                -- enough to reconstruct an earlier native context safely.
                report("cleanup_errors", f.event, "completed camera/clip/matrix pop cannot be safely replayed", f.source)
            else
                local ok = pcall(prior.replay)
                if ok then prior.stack[#prior.stack + 1] = prior prior.active = true
                else report("cleanup_errors", f.event, "popped render-target restoration failed", f.source) end
            end
        elseif action.active then
            if action.stack[#action.stack] == action then
                local ok = pcall(action.undo)
                if ok then table.remove(action.stack) action.active = false
                else report("cleanup_errors", f.event, "tracked stack restoration failed", f.source) end
            else report("cleanup_errors", f.event, "untracked state prevents stack restoration", f.source) end
        end
    end
    if f.targetChanged and f.haveTarget and nativeRender.SetRenderTarget then
        local ok = pcall(nativeRender.SetRenderTarget, f.target)
        if not ok then report("cleanup_errors", f.event, "target restoration failed", f.source) end
    end
    busy = busy - 1
end
local function protectedCall(fn, event, ...)
    local f = {event = event, source = functionSource(fn), actions = {}, parent = frame}
    if nativeRender.GetRenderTarget then f.haveTarget, f.target = pcall(nativeRender.GetRenderTarget) end
    local args = pack(...)
    frame = f
    local result = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end, function(err) return tostring(err) end))
    frame = f.parent
    f.completed = result[1]
    if not result[1] then
        cleanup(f)
        report("errors", event, "callback quarantined after a Lua error", f.source)
        return false
    end
    -- Successful nested work is part of its active caller's chronological
    -- undo log. Failed children already cleaned their own log and must not
    -- replay those restores a second time if an ancestor subsequently fails.
    if f.parent then
        for i = 1, #f.actions do
            f.parent.actions[#f.parent.actions + 1] = f.actions[i]
        end
        if f.targetChanged then f.parent.targetChanged = true end
    end
    return true, unpack(result, 2, result.n)
end
local events = {Initialize = true, InitPostEntity = true, OnReloaded = true,
    PreRender = true, PostRender = true, RenderScene = true, RenderScreenspaceEffects = true,
    PreDrawEffects = true, PostDrawEffects = true, PreDrawOpaqueRenderables = true,
    PostDrawOpaqueRenderables = true, PreDrawTranslucentRenderables = true, PostDrawTranslucentRenderables = true,
    PreDrawViewModel = true, PostDrawViewModel = true, PostDrawPlayerHands = true,
    HUDPaint = true, PreDrawHUD = true, PostDrawHUD = true, PostRenderVGUI = true,
    SetupWorldFog = true, SetupSkyboxFog = true, NeedsDepthPass = true,
    InitPostShaderlib = true, InitPostReconstruction = true, PreDrawReconstruction = true, PostDrawReconstruction = true}
local originalCall, getHooks, quarantine = hook.Call, hook.GetTable, {}
hook.Call = function(name, gm, ...)
    if not active() or not events[name] then return originalCall(name, gm, ...) end
    local entries = getHooks()[name]
    local failed = quarantine[name]
    if not failed then failed = setmetatable({}, {__mode = "k"}) quarantine[name] = failed end
    for id, fn in pairs(entries or {}) do
        if type(id) ~= "string" and not IsValid(id) then entries[id] = nil
        elseif failed[id] ~= fn then
            local result
            if type(id) == "string" then result = pack(protectedCall(fn, name, ...))
            else result = pack(protectedCall(fn, name, id, ...)) end
            if not result[1] then failed[id] = fn
            elseif result[2] ~= nil then return unpack(result, 2, 7) end
        end
    end
    local fn = gm and gm[name]
    if fn and failed[gm] ~= fn then
        local result = pack(protectedCall(fn, name, gm, ...))
        if not result[1] then failed[gm] = fn else return unpack(result, 2, result.n) end
    end
end
local function callback(fn, event)
    local failed = false
    return function(...)
        if not active() then return fn(...) end
        if failed then return end
        local result = pack(protectedCall(fn, event, ...))
        if not result[1] then failed = true else return unpack(result, 2, result.n) end
    end
end
if verifiedMultiplayer and not early then
    -- The multiplayer engine may already hold the original hook.Call. Protect
    -- registered render functions themselves in this late path. Loading-hook
    -- identity stays intact for the verified bootstrap's InitPostEntity replay.
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
                if type(fn) == "function" then entries[id] = renderCallback(event, id, fn) end
            end
        end
    end
    local originalAdd = hook.Add
    hook.Add = function(event, id, fn, ...)
        if lateEvents[event] and id ~= nil and type(fn) == "function" then
            fn = renderCallback(event, id, fn)
        end
        return originalAdd(event, id, fn, ...)
    end
    state.late_render_wrappers = true
end
if timer and timer.Create then
    local original = timer.Create
    timer.Create = function(id, delay, count, fn, ...)
        if type(fn) == "function" then fn = callback(fn, "timer.Create") end
        return original(id, delay, count, fn, ...)
    end
end
if timer and timer.Simple then
    local original = timer.Simple
    timer.Simple = function(delay, fn, ...)
        if type(fn) == "function" then fn = callback(fn, "timer.Simple") end
        return original(delay, fn, ...)
    end
end
if cvars and cvars.AddChangeCallback then
    local original = cvars.AddChangeCallback
    cvars.AddChangeCallback = function(name, fn, id, ...)
        if type(fn) == "function" then fn = callback(fn, "cvars.AddChangeCallback") end
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
