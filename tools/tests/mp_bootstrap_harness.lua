-- Exercise the complete production initializer with standard-Lua package fixtures.
local source, scenario, modelReloadSource = ...
local function equal(actual, expected, context)
    assert(actual == expected, (context or '') .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected))
end
if scenario == 'normal_load_marker' then
    -- The actual cl_rtx.lua line that tells the verified initializer the payload already ran.
    local input = assert(io.open(assert(modelReloadSource, 'cl_rtx.lua path required'), 'rb'))
    local actual = input:read('*a')
    input:close()
    local line = assert(actual:match('[^\r\n]*NATIVELOADER_RTX_NORMAL_LOAD[^\r\n]*'), 'normal-load marker not found in cl_rtx.lua')
    local _, count = actual:gsub('NATIVELOADER_RTX_NORMAL_LOAD', '')
    equal(count, 1, 'one marker statement')
    local first = actual:find(line, 1, true)
    assert(first > actual:find('IsBinaryModuleInstalled', 1, true), 'set only once the binary module check passed')
    assert(first < actual:find('require("niknaks")', 1, true), 'set before the payload starts loading')
    local normal = {}
    setfenv(assert(loadstring(line, '@actual-cl_rtx-marker')), setmetatable({}, {__index = _G, __newindex = normal}))()
    equal(normal.NATIVELOADER_RTX_NORMAL_LOAD, true, 'normal loading sets the global marker')
    local verified, written = {NATIVELOADER_VERIFIED_MULTIPLAYER = true}, {}
    setfenv(assert(loadstring(line, '@actual-cl_rtx-marker')), setmetatable(verified, {__index = _G, __newindex = written}))()
    equal(next(written), nil, 'the verified environment never sets it')
    print('PASS ' .. scenario)
    return
end
if scenario:match('^model_reload_') then
    local input = assert(io.open(assert(modelReloadSource, 'model reload source path required'), 'rb'))
    local actual = input:read('*a')
    input:close()
    local first = assert(actual:find('local function ReloadModelsAfterHardwareSkinningSetting', 1, true),
        'model reload function not found in actual cl_rtx.lua')
    local last = assert(actual:find('-- Load all sub-addons', first, true), 'model reload section end not found')
    local verified = scenario:match('^model_reload_verified_') ~= nil
    local retry = scenario == 'model_reload_normal_retry'
    local flag = verified and true or nil
    if scenario == 'model_reload_normal_false' then flag = false end
    local queue, delays, callbacks, errors = {}, {}, {}, {}
    local reloads, convarReads = 0, 0
    -- The final reload switches queued rendering off for its flush (R4-28): mat_queue_mode, the
    -- console commands, frames and the Think hook it waits on are mocked here.
    local queueMode = scenario == 'model_reload_normal_queue_off' and '0' or '2'
    local refused = scenario == 'model_reload_normal_queue_refused'
    local commands, thinks, printed, reloadModes, frame = {}, {}, {}, {}, 100
    local env = setmetatable({NATIVELOADER_VERIFIED_MULTIPLAYER = flag}, {__index = _G})
    env.FrameNumber = function() return frame end
    env.print = function(text) printed[#printed + 1] = text end
    env.RunConsoleCommand = function(name, value)
        commands[#commands + 1] = name .. ' ' .. tostring(value)
        if name == 'mat_queue_mode' and not refused then queueMode = value end
    end
    env.GetConVar = function(name)
        if name == 'mat_queue_mode' then return {GetString = function() return queueMode end} end
        equal(name, 'r_forcehwskin', 'model reload convar')
        convarReads = convarReads + 1
        if scenario == 'model_reload_verified_missing' then return nil end
        return {GetString = function()
            if scenario == 'model_reload_verified_mismatch' or (retry and convarReads < 3) then return '1' end
            return '0'
        end}
    end
    env.RTX_ReloadModelsAfterHardwareSkinningSettings = function()
        reloads = reloads + 1
        reloadModes[reloads] = {mode = queueMode, frame = frame}
    end
    env.ErrorNoHalt = function(reason) errors[#errors + 1] = reason end
    env.timer = {Simple = function(delay, fn)
        delays[#delays + 1] = delay
        queue[#queue + 1] = {delay = delay, fn = fn}
    end}
    env.hook = {
        Add = function(event, name, fn)
            equal(name, 'RTXHardwareSkinning_FinalModelReload', 'model reload hook ID')
            if event == 'Think' then
                thinks[name] = fn
                return
            end
            equal(event, 'InitPostEntity', 'model reload hook event')
            assert(callbacks[name] == nil, 'model reload hook registered twice')
            callbacks[name] = fn
        end,
        Remove = function(event, name)
            equal(event, 'Think', 'only the frame wait is removed')
            thinks[name] = nil
        end,
    }
    local fn = assert(loadstring('local desiredForceHardwareSkinning = "0"\n' .. actual:sub(first, last - 1),
        '@actual-cl_rtx-model-reload'))
    setfenv(fn, env)()
    equal(#queue, 1, 'initial model reload is queued')
    equal(delays[1], 0, 'initial model reload delay')
    equal(reloads, 0, 'no synchronous model cache reload')
    local function drain()
        local steps = 0
        while #queue > 0 do
            steps = steps + 1
            assert(steps <= 65, 'model reload timer did not terminate')
            table.remove(queue, 1).fn()
        end
    end
    drain()
    equal(reloads, verified and 0 or 1, 'initial queued model reload')
    equal(convarReads, verified and 0 or (retry and 3 or 1), 'hardware convar restoration retries')
    local before = #delays
    assert(callbacks.RTXHardwareSkinning_FinalModelReload, 'final model reload hook missing')()
    if verified then
        equal(#queue, 0, 'verified late hook never queues a cache flush')
        equal(#delays, 1, 'verified late path never retries')
    else
        equal(#queue, 1, 'normal map initialization queues final model reload')
        equal(#delays, before + 1, 'one final reload timer')
        equal(delays[#delays], 1, 'final model reload delay')
    end
    drain()
    local started, waited = frame, 0
    while thinks.RTXHardwareSkinning_FinalModelReload do
        waited = waited + 1
        assert(waited <= 10, 'the final reload waits only a few frames')
        frame = frame + 1
        thinks.RTXHardwareSkinning_FinalModelReload()
    end
    if verified then
        equal(#commands, 0, 'verified path never touches queued rendering')
    elseif scenario == 'model_reload_normal_queue_off' then
        equal(#commands, 0, 'queued rendering already off: nothing switched')
        equal(waited, 0, 'flushed at once')
    else
        -- Queued rendering goes off before the flush and comes back as the player had it.
        equal(table.concat(commands, ';'), 'mat_queue_mode 0;mat_queue_mode 2', 'switched off and back')
        equal(queueMode, '2', 'the player value is back')
        assert(waited >= 4, 'the flush waits frames for the material system to leave queued mode')
    end
    if refused then
        equal(reloads, 1, 'a switch that did not take skips the final flush')
        assert(printed[1] and printed[1]:find('skipped', 1, true), 'the skip is reported')
    else
        equal(reloads, verified and 0 or 2, 'complete early/late model reload behavior')
        if not verified then
            equal(reloadModes[2].mode, '0', 'the final flush runs with queued rendering off')
            assert(reloadModes[2].frame - started >= 4 or waited == 0, 'the final flush waited its frames')
        end
    end
    equal(#errors, 0, 'no hardware restoration timeout')
    equal(NATIVELOADER_VERIFIED_MULTIPLAYER, nil, 'model reload marker did not leak globally')
    print('PASS ' .. scenario)
    return
end
local trace, messages = {}, {}
local reads, finished, listed = {}, {}, 0
local includeCalls, requireCalls, fileCalls = {}, {}, {}
local hooks, registered = {InitPostEntity = {}}, {}
local oldInitCalls, foreignInitCalls, overwrittenCalls, removedCalls = 0, 0, 0, 0
local ownedInitCalls, objectInitCalls = 0, 0
local validPlayer = scenario ~= 'not_ready'
local player = {valid = true, IsListenServerHost = function() return scenario == 'normal_load' end}
CLIENT_DLL = scenario ~= 'server' and scenario ~= 'menu'
SERVER = scenario == 'server'
MENU_DLL = scenario == 'menu'
GAMEMODE = {}
game = {SinglePlayer = function() return scenario == 'single_player' end}
function LocalPlayer() return validPlayer and player or nil end
function IsValid(value) return type(value) == 'table' and value.valid == true end
function MsgN(value) messages[#messages + 1] = value end
function CompileString(text, name)
    local fn, reason = loadstring(text, name)
    return fn or reason
end
if scenario == 'missing_api' then CompileString = nil end
-- The packaged cl_rtx.lua ran through normal loading in this realm (listen host, sv_allowcslua 1).
-- normal_load is a listen host, normal_load_allowcslua an sv_allowcslua 1 server: every local add-on ran.
-- normal_load_server delivered only its own copy of the add-on whose cl_rtx.lua set the marker.
if scenario:match('^normal_load') and scenario ~= 'normal_load_marker' then NATIVELOADER_RTX_NORMAL_LOAD = true end
function GetConVar(name)
    if name == 'sv_allowcslua' then return {GetBool = function() return scenario == 'normal_load_allowcslua' end} end
end
local serverEntity = scenario == 'server_entity'

local originalHook = {}
function originalHook.GetTable() return hooks end
function originalHook.Add(event, name, fn)
    hooks[event] = hooks[event] or {}
    hooks[event][name] = fn
end
function originalHook.Remove(event, name) if hooks[event] then hooks[event][name] = nil end end
hook = originalHook
hooks.InitPostEntity.before = function() oldInitCalls = oldInitCalls + 1 end
hooks.Initialize = {before = function() oldInitCalls = oldInitCalls + 1 end}
hooks.OnGamemodeLoaded = {before = function() oldInitCalls = oldInitCalls + 1 end}
function RegisterForeignHook()
    originalHook.Add('InitPostEntity', 'foreign', function() foreignInitCalls = foreignInitCalls + 1 end)
end
function ReplaceHookExternally(name)
    originalHook.Add('InitPostEntity', name, function() foreignInitCalls = foreignInitCalls + 1 end)
end
OWNED_OBJECT = {valid = true}
INVALID_OBJECT = {valid = false}
function OwnedInit()
    if not serverEntity then
        assert(registered.owned_entity and registered.owned_entity.Shared, 'owned Init ran before entity registration')
    end
    TRACE[#TRACE + 1] = 'replay:InitPostEntity'
    ownedInitCalls = ownedInitCalls + 1
end
function OwnedObjectInit(value)
    equal(value, OWNED_OBJECT, 'object-ID self argument')
    if not serverEntity then assert(registered.owned_entity and registered.owned_entity.Shared) end
    objectInitCalls = objectInitCalls + 1
end
function OwnedLoading(event)
    return function()
        assert(OWNED_LIBRARY and CLIENT_AUTORUN_RAN, event .. ' replayed before the autoruns finished')
        TRACE[#TRACE + 1] = 'replay:' .. event
    end
end
function OverwrittenInit() overwrittenCalls = overwrittenCalls + 1 end
function RemovedInit() removedCalls = removedCalls + 1 end

local function engineInclude(name)
    includeCalls[#includeCalls + 1] = name
    if name == 'engine/approved.lua' then return 'engine-approved-include' end
    if name == 'remixlua/shared_helper.lua' and scenario == 'normal_load_server' then return 'server-copy' end
    error('engine policy denied local include: ' .. tostring(name))
end
local nativeModule = {native = true}
local function engineRequire(name)
    requireCalls[#requireCalls + 1] = name
    if name == 'native_render_module' then return nativeModule end
    error('engine policy denied local require: ' .. tostring(name))
end
include, require = engineInclude, engineRequire
local originalFile = {}
function originalFile.Exists(name, realm)
    fileCalls[#fileCalls + 1] = {'Exists', name, realm}
    return name == 'engine/approved.lua' and realm == 'LUA'
end
function originalFile.Read(name, realm)
    fileCalls[#fileCalls + 1] = {'Read', name, realm}
    if name == 'engine/approved.lua' and realm == 'LUA' then return 'engine-approved-source' end
    if name == 'settings.json' and realm == 'DATA' then return '{"asset":true}' end
    return nil
end
function originalFile.Find(pattern, realm, sorting)
    fileCalls[#fileCalls + 1] = {'Find', pattern, realm, sorting}
    if realm == 'LUA' then return {'remote.lua'}, {'remote_dir'} end
    return {'asset.dat'}, {'assets'}
end
file = originalFile
local networkCalls, channelLookups, receivers = {}, {}, {}
local networkChannels = {rtx_registered = 12}
local networkMessage
local originalNet = {}
local function recordNetwork(operation, ...)
    networkCalls[#networkCalls + 1] = {operation, ...}
end
function originalNet.Start(name, unreliable)
    assert(type(name) == 'string', 'engine invalid channel name')
    assert(unreliable == nil or type(unreliable) == 'boolean', 'engine invalid unreliable argument')
    assert(networkChannels[name], 'engine unpooled channel: ' .. name)
    recordNetwork('Start', name, unreliable)
    networkMessage = {name = name, writes = 0}
    return 'engine-started', name, unreliable
end
local function writeNetwork(operation, value, bits)
    assert(networkMessage, 'engine write without message')
    if operation == 'WriteString' then assert(type(value) == 'string', 'engine invalid string argument') end
    if operation == 'WriteUInt' then
        assert(type(value) == 'number' and type(bits) == 'number', 'engine invalid uint arguments')
    end
    recordNetwork(operation, value, bits)
    networkMessage.writes = networkMessage.writes + 1
    return 'engine-wrote', operation
end
function originalNet.WriteString(value) return writeNetwork('WriteString', value) end
function originalNet.WriteUInt(value, bits) return writeNetwork('WriteUInt', value, bits) end
function originalNet.WriteTable(value) return writeNetwork('WriteTable', value) end
function originalNet.BytesWritten()
    assert(networkMessage, 'engine byte count without message')
    recordNetwork('BytesWritten')
    return networkMessage.writes * 3, networkMessage.writes * 8 + 2
end
for _, name in ipairs({'SendToServer', 'Send', 'SendOmit', 'Broadcast', 'Abort'}) do
    local operation = name
    originalNet[operation] = function(...)
        assert(networkMessage, 'engine finish without message')
        recordNetwork(operation, ...)
        networkMessage = nil
        return 'engine-' .. operation, ...
    end
end
function originalNet.Receive(name, fn)
    receivers[name] = fn
    return 'engine-receiver'
end
function originalNet.ReadString() return 'engine-read' end
local originalNetFunctions = {}
for name, fn in pairs(originalNet) do originalNetFunctions[name] = fn end
net = originalNet
local originalUtil = {NetworkStringToID = function(name)
    assert(type(name) == 'string', 'channel lookup received invalid name')
    channelLookups[#channelLookups + 1] = name
    return networkChannels[name] or 0
end}
util = originalUtil
NETWORK_CALLS, NETWORK_LOOKUPS, NETWORK_CHANNELS = networkCalls, channelLookups, networkChannels
ENT = {original = true}
local originalENT = ENT
local serverDefinition = {ClassName = 'owned_entity', FromServer = true}
scripted_ents = {Register = function(ent, name)
    assert(OWNED_LIBRARY and SHARED_B_READY, 'entity registered before shared libraries')
    registered[name] = ent
    trace[#trace + 1] = 'entity:' .. name
end, GetStored = function(name)
    if serverEntity and name == 'owned_entity' then return serverDefinition end
end}
TRACE = trace

local scripts = {
    ['alpha/autorun/a_library.lua'] = [=[
assert(_G.__NATIVELOADER_CLIENT_API == nil, 'temporary API leaked while running source')
assert(NATIVELOADER_VERIFIED_MULTIPLAYER == true, 'verified marker missing from owned environment')
assert(_G.NATIVELOADER_VERIFIED_MULTIPLAYER == nil, 'verified marker leaked globally')
TRACE[#TRACE + 1] = 'shared-a'
OWNED_LIBRARY = {ready = true}
local one = include('lib/relative.lua')
assert(one == 'owner-relative')
assert(include('lib/../shared/helper.lua') == 'parent-relative')
assert(include('shared/cross.lua') == 'cross-approved')
local first, second = require('owned_module'), require('owned_module')
assert(first == second and first.value == 'module')
assert(require('side_effect_only') == true and require('side_effect_only') == true)
assert(require('native_render_module').native)
local ok = pcall(require, 'community_module') assert(not ok)
assert(include('engine/approved.lua') == 'engine-approved-include')
ok = pcall(include, 'community/local.lua') assert(not ok)
ok = pcall(include, '../../../../community/local.lua') assert(not ok)
assert(file.Exists('AUTORUN/LIB/RELATIVE.LUA', 'LUA'))
assert(file.Read('autorun/lib/relative.lua', 'LUA'):find('owner%-relative'))
assert(not file.Exists('community/local.lua', 'LUA'))
assert(file.Read('community/local.lua', 'LUA') == nil)
assert(file.Read('engine/approved.lua', 'LUA') == 'engine-approved-source')
assert(file.Read('settings.json', 'DATA') == '{"asset":true}')
local names, dirs = file.Find('AUTORUN/LIB/*.LUA', 'LUA', 'nameasc')
assert(table.concat(names, ',') == 'relative.lua,remote.lua', table.concat(names, ','))
local _, folders = file.Find('AUTORUN/*', 'LUA')
local found = {} for _, name in ipairs(folders) do found[name] = true end
assert(found.lib and found.shared and found.client and found.remote_dir)
local ordinary, ordinaryDirs = file.Find('test/*', 'DATA')
assert(ordinary[1] == 'asset.dat' and ordinaryDirs[1] == 'assets')
hook.Add('InitPostEntity', 'owned', OwnedInit)
hook.Add('Initialize', 'owned_initialize', OwnedLoading('Initialize'))
hook.Add('PostGamemodeLoaded', 'owned_post_loaded', OwnedLoading('PostGamemodeLoaded'))
hook.Add('OnGamemodeLoaded', 'owned_loaded', OwnedLoading('OnGamemodeLoaded'))
hook.Add('InitPostEntity', 'scoped_marker', function()
    assert(NATIVELOADER_VERIFIED_MULTIPLAYER == true, 'callback lost scoped verified marker')
    assert(_G.NATIVELOADER_VERIFIED_MULTIPLAYER == nil, 'callback exposed global verified marker')
    VERIFIED_CALLBACK_RAN = true
end)
hook.Add('InitPostEntity', OWNED_OBJECT, OwnedObjectInit)
hook.Add('InitPostEntity', INVALID_OBJECT, function() error('invalid hook ID was replayed') end)
hook.Add('InitPostEntity', 'overwritten', OverwrittenInit)
ReplaceHookExternally('overwritten')
hook.Add('InitPostEntity', 'removed', RemovedInit)
hook.Remove('InitPostEntity', 'removed')
RegisterForeignHook()
]=],
    ['alpha/autorun/lib/relative.lua'] = [=[
assert(NATIVELOADER_VERIFIED_MULTIPLAYER == true and _G.NATIVELOADER_VERIFIED_MULTIPLAYER == nil)
OWNER_RELATIVE_RUNS = (OWNER_RELATIVE_RUNS or 0) + 1
return 'owner-relative'
]=],
    ['beta/autorun/lib/relative.lua'] = [=[error('wrong owner resolved')]=],
    ['alpha/autorun/shared/helper.lua'] = [=[return 'parent-relative']=],
    ['beta/shared/cross.lua'] = [=[CROSS_RUNS = (CROSS_RUNS or 0) + 1 return 'cross-approved']=],
    ['alpha/includes/modules/owned_module.lua'] = [=[
assert(NATIVELOADER_VERIFIED_MULTIPLAYER == true and _G.NATIVELOADER_VERIFIED_MULTIPLAYER == nil)
MODULE_RUNS = (MODULE_RUNS or 0) + 1
return {value = 'module'}
]=],
    ['alpha/includes/modules/side_effect_only.lua'] = [=[SIDE_EFFECT_RUNS = (SIDE_EFFECT_RUNS or 0) + 1]=],
    ['beta/autorun/b_shared.lua'] = [=[SHARED_B_READY = true TRACE[#TRACE + 1] = 'shared-b']=],
    ['alpha/autorun/client/z_client.lua'] = [=[
assert(NATIVELOADER_VERIFIED_MULTIPLAYER == true and _G.NATIVELOADER_VERIFIED_MULTIPLAYER == nil)
assert(OWNED_LIBRARY and SHARED_B_READY, 'client autorun preceded a shared autorun')
TRACE[#TRACE + 1] = 'client'
CLIENT_AUTORUN_RAN = true
]=],
    ['alpha/entities/owned_entity/cl_init.lua'] = [=[
assert(NATIVELOADER_VERIFIED_MULTIPLAYER == true and _G.NATIVELOADER_VERIFIED_MULTIPLAYER == nil)
assert(OWNED_LIBRARY and SHARED_B_READY, 'entity definition preceded libraries')
include('shared.lua')
ENT.FromClient = true
]=],
    ['alpha/entities/owned_entity/shared.lua'] = [=[ENT.Shared = true ENT.Base = 'base_anim']=],
}
if scenario == 'script_error' then scripts['alpha/autorun/c_failure.lua'] = [=[error('intentional owned failure')]=] end
if scenario == 'normal_load_server' then
    scripts['remixfix/autorun/cl_rtx.lua'] = [=[REMIXFIX_RUNS = (REMIXFIX_RUNS or 0) + 1]=]
    scripts['remixfix/remixlua/shared_helper.lua'] = [=[REMIXFIX_HELPER_RUNS = (REMIXFIX_HELPER_RUNS or 0) + 1 return 'catalog-copy']=]
    scripts['remixfix/entities/remix_entity.lua'] = [=[ENT.Remix = true]=]
    scripts['alpha/autorun/client/zz_uses_fix.lua'] = [=[
assert(include('remixlua/shared_helper.lua') == 'server-copy', 'normally loaded add-on served from the catalog')
USES_FIX_RAN = true
]=]
end
if scenario == 'network' then
    scripts['beta/net/network_helper.lua'] = [=[
assert(net ~= _G.net, 'helper received global net table')
return {
    start = function(...) return net.Start(...) end,
    write = function(value)
        net.WriteString(value)
        net.WriteUInt(7, 8)
        net.WriteTable({value = value})
    end,
    finish = function(...) return net.SendToServer(...) end,
    bytes = function(...) return net.BytesWritten(...) end,
}
]=]
    scripts['alpha/autorun/client/zz_network.lua'] = [=[
assert(net ~= _G.net, 'catalog script received global net table')
local helper = include('net/network_helper.lua')
local count = #NETWORK_CALLS
assert(net.Start('rtx_missing') == false)
helper.write('drop across catalog environments')
local bytes, bits = helper.bytes()
assert(bytes == 0 and bits == 0)
assert(helper.finish() == nil)
assert(#NETWORK_CALLS == count, 'absent channel reached engine net APIs')

-- A helper can begin the dropped message and the caller can write/finish it.
assert(helper.start('rtx_helper_missing') == false)
net.WriteString('drop in caller')
net.WriteUInt(11, 8)
assert(net.SendToServer() == nil)
assert(#NETWORK_CALLS == count, 'cross-script drop state was not shared')

-- Every finish/abort form resets the shared drop state, without calling the engine.
for _, operation in ipairs({'SendToServer', 'Send', 'SendOmit', 'Broadcast', 'Abort'}) do
    assert(net.Start('rtx_missing') == false)
    helper.write('discard')
    assert(net[operation]({recipient = true}) == nil)
    assert(#NETWORK_CALLS == count, 'dropped finish was forwarded: ' .. operation)
    local ok, reason = pcall(net.WriteString, 'no message')
    assert(not ok and tostring(reason):find('engine write without message', 1, true),
        'finish did not restore genuine engine errors: ' .. operation)
end

-- Invalid Start arguments use the real API, and also end any stale drop state.
assert(net.Start('rtx_missing') == false)
local lookups = #NETWORK_LOOKUPS
local ok, reason = pcall(net.Start, {})
assert(not ok and tostring(reason):find('engine invalid channel name', 1, true))
assert(#NETWORK_LOOKUPS == lookups, 'invalid name reached channel lookup')
ok, reason = pcall(net.WriteString, 'invalid start did not open a message')
assert(not ok and tostring(reason):find('engine write without message', 1, true))
ok, reason = pcall(net.Start, 'rtx_registered', 'not a boolean')
assert(not ok and tostring(reason):find('engine invalid unreliable argument', 1, true))

-- A subsequent registered channel clears dropping and forwards args/multiple returns.
assert(net.Start('rtx_missing') == false)
local result, name, unreliable = helper.start('rtx_registered', true)
assert(result == 'engine-started' and name == 'rtx_registered' and unreliable == true)
local before = #NETWORK_CALLS
helper.write('registered payload')
assert(#NETWORK_CALLS == before + 3)
assert(NETWORK_CALLS[before + 1][1] == 'WriteString')
assert(NETWORK_CALLS[before + 1][2] == 'registered payload')
assert(NETWORK_CALLS[before + 2][1] == 'WriteUInt' and NETWORK_CALLS[before + 2][3] == 8)
bytes, bits = net.BytesWritten()
assert(bytes == 9 and bits == 26, 'registered byte count lost engine return values')
ok, reason = pcall(net.WriteString, 99)
assert(not ok and tostring(reason):find('engine invalid string argument', 1, true))
ok, reason = pcall(net.WriteUInt, 'invalid', 8)
assert(not ok and tostring(reason):find('engine invalid uint arguments', 1, true))
assert(helper.finish() == 'engine-SendToServer')

for _, operation in ipairs({'Send', 'SendOmit', 'Broadcast', 'Abort'}) do
    net.Start('rtx_registered')
    local recipient, tail = {valid = true}, 'preserved-vararg'
    local returned, first, second = net[operation](recipient, tail)
    assert(returned == 'engine-' .. operation and first == recipient and second == tail,
        'registered finish lost engine arguments/returns: ' .. operation)
end

-- Missing registration is checked at each Start, rather than cached forever.
assert(net.Start('rtx_late') == false)
NETWORK_CHANNELS.rtx_late = 13
assert(net.Start('rtx_late') == 'engine-started')
assert(net.Abort() == 'engine-Abort')

local callback = function() end
assert(net.Receive('client_callback', callback) == 'engine-receiver')
assert(net.ReadString() == 'engine-read')
OWNED_NET_TEST_COMPLETE = true
]=]
end
local keys = {}
for key in pairs(scripts) do keys[#keys + 1] = key end
table.sort(keys)
local api = {identity = 'verified-fixture'}
api.list = function() listed = listed + 1 return keys end
api.read = function(key)
    assert(scripts[key], 'native read escaped the verified catalog: ' .. tostring(key))
    reads[#reads + 1] = key
    return scripts[key]
end
api.finish = function(loaded, errors, reason) finished[#finished + 1] = {loaded = loaded, errors = errors, reason = reason} end
__NATIVELOADER_CLIENT_API = scenario ~= 'no_api' and api or nil
dofile(source)
equal(__NATIVELOADER_CLIENT_API, nil, 'temporary API global removed')
equal(NATIVELOADER_VERIFIED_MULTIPLAYER, nil, 'verified marker stays environment-only')
equal(include, engineInclude, 'global include retained')
equal(require, engineRequire, 'global require retained')
equal(file, originalFile, 'global file retained')
equal(hook, originalHook, 'global hook retained')
equal(net, originalNet, 'global net retained')
equal(util, originalUtil, 'global util retained')
for name, fn in pairs(originalNetFunctions) do equal(net[name], fn, 'global net function retained: ' .. name) end
equal(ENT, originalENT, 'global ENT retained')

local finishing = {single_player = 'normal single-player loading', normal_load = 'normal loading already ran the RTX payload',
    normal_load_allowcslua = 'normal loading already ran the RTX payload',
    missing_api = 'the client realm has no hook library or CompileString'}
local early = finishing[scenario] or scenario == 'not_ready' or scenario == 'server' or scenario == 'menu' or scenario == 'no_api'
if early then
    equal(listed, 0, 'no catalog before realm/readiness approval')
    equal(#reads, 0, 'no forced source before approval')
    equal(CLIENT_AUTORUN_RAN, nil, 'no client autorun before approval')
    equal(NATIVELOADER_CLIENT_PAYLOAD, nil, 'no completion payload before approval')
    -- A final exit finishes, so the menu stops polling; a realm that is not ready yet does not.
    equal(#finished, finishing[scenario] and 1 or 0, 'early finish count')
    if finishing[scenario] then
        equal(finished[1].loaded, 0) equal(finished[1].errors, 0) equal(finished[1].reason, finishing[scenario])
    end
    equal(ownedInitCalls + objectInitCalls + oldInitCalls, 0, 'nothing replayed')
else
    equal(listed, 1, 'one sealed catalog')
    equal(#finished, 1, 'one completion')
    assert(finished[1].loaded > 0, 'completion did not report loaded roots')
    equal(finished[1].loaded, NATIVELOADER_CLIENT_PAYLOAD.loaded, 'completion/status load count')
    local expectedErrors = scenario == 'script_error' and 1 or 0
    equal(finished[1].errors, expectedErrors, 'captured source errors')
    equal(#NATIVELOADER_CLIENT_PAYLOAD.errors, expectedErrors, 'status errors')
    equal(NATIVELOADER_CLIENT_PAYLOAD.identity, 'verified-fixture', 'status identity')
    equal(NATIVELOADER_CLIENT_PAYLOAD.multiplayer, true, 'status multiplayer')
    equal(CLIENT_AUTORUN_RAN, true, 'client autorun executed')
    equal(OWNER_RELATIVE_RUNS, 1, 'owner relative include')
    equal(CROSS_RUNS, 1, 'cross-owned catalog include')
    equal(MODULE_RUNS, 1, 'require cache')
    equal(SIDE_EFFECT_RUNS, 1, 'nil-return require cache')
    equal(ownedInitCalls, 1, 'owned hook replay')
    equal(VERIFIED_CALLBACK_RAN, true, 'replayed callback retains environment-only marker')
    equal(objectInitCalls, 1, 'owned object hook replay')
    equal(oldInitCalls, 0, 'old hooks not replayed')
    equal(foreignInitCalls, 0, 'foreign/replaced hooks not replayed')
    equal(overwrittenCalls, 0, 'superseded owned hook not replayed')
    equal(removedCalls, 0, 'removed owned hook not replayed')
    equal(trace[1], 'shared-a', 'shared startup order')
    equal(trace[2], 'shared-b', 'all shared scripts precede client scripts')
    equal(trace[3], 'client', 'client startup order')
    local replayAt = 4
    if serverEntity then
        -- The server delivered this class: its definition stays, the owned copy is not run.
        equal(registered.owned_entity, nil, 'server-delivered entity not re-registered')
        equal(NATIVELOADER_CLIENT_PAYLOAD.server_entities[1], 'owned_entity', 'kept server entity reported')
        for _, key in ipairs(reads) do assert(not key:find('owned_entity', 1, true), 'owned entity source was run') end
    else
        equal(trace[4], 'entity:owned_entity', 'entity registration follows libraries')
        equal(#NATIVELOADER_CLIENT_PAYLOAD.server_entities, 0, 'no server entity reported')
        replayAt = 5
    end
    -- Owned loading callbacks are replayed once each, gamemode-loaded events first, InitPostEntity last.
    equal(trace[replayAt], 'replay:OnGamemodeLoaded', 'OnGamemodeLoaded replay')
    equal(trace[replayAt + 1], 'replay:PostGamemodeLoaded', 'PostGamemodeLoaded replay')
    equal(trace[replayAt + 2], 'replay:Initialize', 'Initialize replay')
    equal(trace[replayAt + 3], 'replay:InitPostEntity', 'InitPostEntity replay last')
    equal(#trace, replayAt + 3, 'each owned loading callback replayed once')
    equal(#includeCalls, scenario == 'normal_load_server' and 4 or 3, 'normal include fallback calls')
    equal(includeCalls[1], 'engine/approved.lua')
    equal(includeCalls[2], 'community/local.lua')
    equal(includeCalls[3], '../../../../community/local.lua')
    if scenario == 'normal_load_server' then
        equal(includeCalls[4], 'remixlua/shared_helper.lua', 'a normally loaded file comes from the engine')
        equal(USES_FIX_RAN, true, 'other owned add-ons still load')
        equal(REMIXFIX_RUNS, nil, 'the normally loaded add-on is not run again')
        equal(REMIXFIX_HELPER_RUNS, nil, 'nor its files through a cross-owner include')
        equal(registered.remix_entity, nil, 'nor its entities')
        equal(NATIVELOADER_CLIENT_PAYLOAD.normally_loaded[1], 'remixfix', 'normally loaded owner reported')
        equal(#NATIVELOADER_CLIENT_PAYLOAD.normally_loaded, 1)
    else
        equal(#NATIVELOADER_CLIENT_PAYLOAD.normally_loaded, 0, 'no normally loaded owner reported')
    end
    equal(#requireCalls, 2, 'normal require fallback calls')
    equal(requireCalls[1], 'native_render_module') equal(requireCalls[2], 'community_module')
    if scenario == 'network' then
        equal(OWNED_NET_TEST_COMPLETE, true, 'complete network fixture executed')
        local missing = NATIVELOADER_CLIENT_PAYLOAD.missing_server_channels
        equal(missing.rtx_missing, true, 'absent channel recorded')
        equal(missing.rtx_helper_missing, true, 'cross-script absent channel recorded')
        equal(missing.rtx_late, true, 'late channel records earlier absence')
        equal(missing.rtx_registered, nil, 'registered channel not reported missing')
        local count = 0 for _ in pairs(missing) do count = count + 1 end
        equal(count, 3, 'only absent owned channel names recorded')
        assert(receivers.client_callback, 'ordinary receive registration was not forwarded')
        local ok, reason = pcall(net.Start, 'community_missing')
        assert(not ok and tostring(reason):find('engine unpooled channel', 1, true),
            'global net missing-channel policy was altered')
        equal(missing.community_missing, nil, 'unscoped traffic not added to owner status')
        equal(networkMessage, nil, 'network fixture left an active engine message')
    else
        equal(#networkCalls, 0, 'non-network scenarios did not send traffic')
    end
    if expectedErrors == 1 then
        assert(NATIVELOADER_CLIENT_PAYLOAD.errors[1]:find('intentional owned failure', 1, true))
        equal(#messages, 1, 'error remains a local diagnostic')
    else equal(#messages, 0, 'clean load has no error diagnostics') end
end
print('PASS ' .. scenario)
