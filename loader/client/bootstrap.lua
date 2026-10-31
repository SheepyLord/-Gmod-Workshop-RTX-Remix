local api = __NATIVELOADER_CLIENT_API
__NATIVELOADER_CLIENT_API = nil
if not api or not CLIENT_DLL or SERVER or MENU_DLL then return end
if not GAMEMODE or not hook or not CompileString or not IsValid(LocalPlayer()) then return end
if game.SinglePlayer() then api.finish(0, 0, 'normal single-player loading') return end

local files, keys = {}, api.list()
for _, key in ipairs(keys) do files[key] = true end
local originalInclude, originalRequire, originalFile = include, require, file
local errors, loaded, loading, required = {}, 0, {}, {}
local newInit, originalHook = {}, hook
-- Client rendering remains useful when the remote server has none of the bundled tools.
-- Keep their absent-channel traffic local to these environments; never replace global net.
local missingChannels, droppedMessage, originalNet = {}, false, net
local scopedNet = setmetatable({}, {__index = function(_, name)
    local value = originalNet[name]
    if type(value) == 'function' and type(name) == 'string' and name:match('^Write') then
        return function(...) if not droppedMessage then return value(...) end end
    end
    return value
end})
scopedNet.Start = function(name, ...)
    droppedMessage = false
    if type(name) == 'string' and util and util.NetworkStringToID and util.NetworkStringToID(name) == 0 then
        missingChannels[name] = true
        droppedMessage = true
        return false
    end
    return originalNet.Start(name, ...)
end
scopedNet.BytesWritten = function(...)
    if droppedMessage then return 0, 0 end
    return originalNet.BytesWritten(...)
end
for _, name in ipairs({'SendToServer', 'Send', 'SendOmit', 'Broadcast', 'Abort'}) do
    local operation = name
    scopedNet[operation] = function(...)
        local dropped = droppedMessage
        droppedMessage = false
        if not dropped then return originalNet[operation](...) end
    end
end
local function normalize(path)
    if type(path) ~= 'string' or path:find('%z') or path:find(':', 1, true) then return end
    path = path:gsub('\\', '/')
    if path:sub(1, 1) == '/' then return end
    local parts = {}
    for item in path:gmatch('[^/]+') do
        if item == '..' then if #parts == 0 then return end table.remove(parts)
        elseif item ~= '.' then parts[#parts + 1] = item:lower() end
    end
    return table.concat(parts, '/')
end
local function resolve(owner, path, from)
    local global = normalize(path)
    local localPath = normalize((from and from:match('^(.*)/') or '') .. '/' .. path)
    if localPath and files[owner .. '/' .. localPath] then return owner .. '/' .. localPath end
    if global and files[owner .. '/' .. global] then return owner .. '/' .. global end
    local found
    if global then for _, key in ipairs(keys) do
        if key:sub(-#global - 1) == '/' .. global then
            local _, virtual = key:match('^([^/]+)/(.*)$')
            if virtual == global then if found then return end found = key end
        end
    end end
    return found
end
local run
local function environment(key, special)
    local owner, path = key:match('^([^/]+)/(.*)$')
    local env = setmetatable({}, {__index = _G, __newindex = _G})
    rawset(env, 'NATIVELOADER_VERIFIED_MULTIPLAYER', true)
    if special then for name, value in pairs(special) do rawset(env, name, value) end end
    rawset(env, 'include', function(name)
        if name == 'mmdhl/debug.lua' then return end
        local target = resolve(owner, name, path)
        if target then return run(target, special) end
        return originalInclude(name)
    end)
    rawset(env, 'require', function(name)
        local target = resolve(owner, 'includes/modules/' .. tostring(name):gsub('%.', '/') .. '.lua')
        if not target then target = resolve(owner, 'includes/modules/' .. tostring(name):gsub('%.', '/') .. '/init.lua') end
        if not target then return originalRequire(name) end
        if required[target] ~= nil then return required[target] end
        local value = run(target)
        required[target] = value == nil and true or value
        return required[target]
    end)
    local scopedFile = setmetatable({}, {__index = originalFile})
    scopedFile.Exists = function(name, realm)
        if realm == 'LUA' and resolve(owner, name, path) then return true end
        return originalFile.Exists(name, realm)
    end
    scopedFile.Read = function(name, realm)
        local target = realm == 'LUA' and resolve(owner, name, path)
        if target then return api.read(target) end
        return originalFile.Read(name, realm)
    end
    scopedFile.Find = function(pattern, realm, sorting)
        local ordinary, dirs = originalFile.Find(pattern, realm, sorting)
        if realm ~= 'LUA' then return ordinary, dirs end
        local result, seen, folders, seenDirs = {}, {}, {}, {}
        for _, name in ipairs(ordinary or {}) do result[#result + 1] = name seen[name] = true end
        for _, name in ipairs(dirs or {}) do folders[#folders + 1] = name seenDirs[name] = true end
        local folder, mask = pattern:match('^(.-)([^/]*)$')
        folder, mask = folder:lower(), mask:lower()
        local match = '^' .. mask:gsub('([%.%+%-%?%^%$%(%)%[%]%%])', '%%%1'):gsub('%*', '.*') .. '$'
        for _, candidate in ipairs(keys) do
            local _, virtual = candidate:match('^([^/]+)/(.*)$')
            local name = virtual:sub(1, #folder) == folder and virtual:sub(#folder + 1)
            if name then
                local directory = name:match('^([^/]+)/')
                if directory and directory:match(match) and not seenDirs[directory] then
                    folders[#folders + 1] = directory seenDirs[directory] = true
                elseif not directory and name:match(match) and not seen[name] then
                    result[#result + 1] = name seen[name] = true
                end
            end
        end
        table.sort(result) table.sort(folders)
        return result, folders
    end
    rawset(env, 'file', scopedFile)
    rawset(env, 'net', scopedNet)
    local scopedHook = setmetatable({}, {__index = originalHook})
    scopedHook.Add = function(event, name, fn)
        if event == 'InitPostEntity' then newInit[name] = fn end
        return originalHook.Add(event, name, fn)
    end
    rawset(env, 'hook', scopedHook)
    return env
end
run = function(key, special)
    if loading[key] then error('RTX include cycle: ' .. key) end
    local text, reason = api.read(key)
    if not text then error(reason or ('Unverified RTX script: ' .. key)) end
    local chunk = CompileString(text, '@lua/' .. key:match('^[^/]+/(.*)$'), false)
    if type(chunk) ~= 'function' then error(chunk) end
    loading[key] = true
    setfenv(chunk, environment(key, special))
    local result = {pcall(chunk)}
    loading[key] = nil
    if not result[1] then error(result[2]) end
    return unpack(result, 2)
end
local function safely(key, special)
    local ok, reason = pcall(run, key, special)
    if ok then loaded = loaded + 1 else errors[#errors + 1] = key .. ': ' .. tostring(reason) end
    return ok
end
local autoruns = {}
for _, key in ipairs(keys) do
    local path = key:match('^[^/]+/(.*)$')
    local area = path:match('^(.*)/[^/]+%.lua$')
    if area == 'autorun' or area == 'autorun/client' then autoruns[#autoruns + 1] = key end
end
table.sort(autoruns, function(a, b)
    local x, y = a:match('^[^/]+/(.*)$'), b:match('^[^/]+/(.*)$')
    local cx, cy = x:sub(1, 15) == 'autorun/client/', y:sub(1, 15) == 'autorun/client/'
    if cx ~= cy then return not cx end
    return x == y and a < b or x < y
end)
for _, key in ipairs(autoruns) do
    local path = key:match('^[^/]+/(.*)$')
    safely(key)
end
-- Definitions follow their libraries; only our newly installed InitPostEntity callbacks are replayed.
for _, key in ipairs(keys) do
    local path = key:match('^[^/]+/(.*)$')
    local name = path:match('^entities/([^/]+)%.lua$') or path:match('^entities/([^/]+)/cl_init%.lua$')
    if name then
        local ent = {Type = 'anim', Base = 'base_anim', ClassName = name}
        if safely(key, {ENT = ent}) and scripted_ents then scripted_ents.Register(ent, name) end
    end
end
for name, fn in pairs(newInit) do
    if (hook.GetTable().InitPostEntity or {})[name] == fn and (type(name) == 'string' or IsValid(name)) then
        local ok, reason
        if type(name) == 'string' then ok, reason = pcall(fn) else ok, reason = pcall(fn, name) end
        if not ok then errors[#errors + 1] = 'InitPostEntity/' .. tostring(name) .. ': ' .. tostring(reason) end
    end
end
NATIVELOADER_CLIENT_PAYLOAD = {identity = api.identity, loaded = loaded, errors = errors, multiplayer = true,
    missing_server_channels = missingChannels}
for _, reason in ipairs(errors) do MsgN('[NativeLoader RTX client] ' .. reason) end
api.finish(loaded, #errors, 'verified client payload loaded')
