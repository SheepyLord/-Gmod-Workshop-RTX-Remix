-- The actual sampler over an in-memory DATA realm and a clock advanced by timer ticks.
local source, scenario = ...
CLIENT = scenario ~= "server"
local files, writes, tick, settings, callbacks = {}, 0, nil, {}, {}
local now, calls = 0, 0
local current, previous = "native-loader/vram.csv", "native-loader/vram.previous.csv"
local fields = {
    "driverBudgetBytes", "driverAllocatedBytes", "totalAllocatedBytes", "totalUsedBytes",
    "poolRetainedBytes", "usedReplacementGeometryBytes", "usedBufferBytes",
    "usedAccelerationStructureBytes", "usedOpacityMicromapBytes", "usedMaterialTextureBytes",
    "usedRenderTargetBytes", "forkTextureCacheCount", "usedAppTextureBytes", "usedAppBufferBytes",
}
local header = "time_utc," .. table.concat(fields, ",") .. "\n"
local valid_row = "1970-01-01T00:00:00Z," .. string.rep("1,", #fields - 1) .. "1\n"
local function stats()
    calls = calls + 1
    local result = {}
    for i, name in ipairs(fields) do result[name] = 10000000000 + i end
    return result
end
RemixResource = {GetVramStats = stats}
function CreateClientConVar(name, default, archived, userinfo)
    assert(name == "nativeloader_vram_telemetry" and default == "1" and archived and not userinfo)
    if settings[name] == nil then settings[name] = default end
    return {GetBool = function() return settings[name] == "1" end}
end
cvars = {AddChangeCallback = function(name, fn, id)
    assert(name == "nativeloader_vram_telemetry" and id == "nativeloader_vram")
    callbacks[name] = fn
end}
local function set_enabled(value)
    local old = settings.nativeloader_vram_telemetry
    settings.nativeloader_vram_telemetry = value
    if callbacks.nativeloader_vram_telemetry then
        callbacks.nativeloader_vram_telemetry("nativeloader_vram_telemetry", old, value)
    end
end
local function data(realm) assert(realm == "DATA", "read outside DATA") end
file = {
    Exists = function(path, realm) data(realm) return files[path] ~= nil end,
    Size = function(path, realm) data(realm) return #(files[path] or "") end,
    Read = function(path, realm)
        data(realm)
        assert(#(files[path] or "") <= 128 * 1024, "oversized segment must be renamed without reading it")
        return files[path]
    end,
    CreateDir = function(path) assert(path == "native-loader") writes = writes + 1 end,
    Write = function(path, body) assert(path == current or path == previous) files[path] = body writes = writes + 1 end,
    Append = function(path, body) assert(path == current) files[path] = (files[path] or "") .. body writes = writes + 1 end,
    Delete = function(path) assert(path == previous) files[path] = nil writes = writes + 1 end,
    Rename = function(from, to)
        assert(from == current and to == previous and files[from] and not files[to])
        files[to], files[from] = files[from], nil
        writes = writes + 1
    end,
}
timer = {Create = function(id, interval, repeats, fn)
    assert(id == "nativeloader_vram" and interval == 30 and repeats == 0)
    tick = function() now = now + 30 fn() end
end}
local date = os.date
os.date = function(format) assert(format == "!%Y-%m-%dT%H:%M:%SZ") return date(format, now) end
local function row_count(path)
    if not files[path] then return 0 end
    local _, count = files[path]:gsub("\n", "")
    return count - 1
end
if scenario == "missing" or scenario == "late_api" then RemixResource = nil end
if scenario == "disabled" then settings.nativeloader_vram_telemetry = "0" end
if scenario == "foreign_file" then files[current] = "player,notes\nkeep,this\n" end
if scenario == "oversized" then files[current] = header .. string.rep("x", 128 * 1024) .. "\n" end
if scenario == "truncated_tail" then files[current] = header .. valid_row .. "1970-01-01T00:01:00Z,1,2" end
if scenario == "nul_tail" then files[current] = header .. valid_row .. string.rep("\0", 64) .. "\n" end
if scenario == "crlf" then files[current] = (header .. valid_row):gsub("\n", "\r\n") end
if scenario == "partial_row" then files[current] = header .. valid_row .. "1970-01-01T00:01:00Z,1,2\n" end
if scenario == "excess_rows" then files[current] = header .. string.rep(valid_row, 121) end
if scenario == "rename_error" then files[current] = "old,schema\n" file.Rename = function() end end
if scenario == "file_error" then file.Append = function() error("disk unavailable") end end
dofile(source)
if scenario == "server" then
    assert(not tick and not next(settings) and writes == 0 and calls == 0)
elseif scenario == "missing" then
    for i = 1, 300 do tick() end
    RemixResource = {} tick()
    assert(writes == 0 and not next(files) and calls == 0)
elseif scenario == "disabled" then
    tick() assert(writes == 0 and calls == 0)
    set_enabled("1") tick()
    assert(row_count(current) == 1 and calls == 1)
    local old = files[current]
    set_enabled("0") tick()
    assert(files[current] == old and calls == 1)
elseif scenario == "late_api" then
    tick() assert(writes == 0)
    RemixResource = {GetVramStats = stats} tick()
    assert(row_count(current) == 1)
elseif scenario == "invalid" then
    for _, fn in ipairs({function() return nil end, function() error("not ready") end,
                         function() return "invalid" end, function() return {} end}) do
        RemixResource.GetVramStats = fn tick() assert(writes == 0)
        set_enabled("0") set_enabled("1")
    end
    RemixResource.GetVramStats = function()
        return {driverBudgetBytes = 0, driverAllocatedBytes = -1, totalAllocatedBytes = 0/0,
                totalUsedBytes = math.huge, poolRetainedBytes = "100"}
    end
    tick()
    assert(files[current] == header .. "1970-01-01T00:02:30Z,0,,,,,,,,,,,,,\n", files[current])
elseif scenario == "rotation" or scenario == "restart" then
    for i = 1, 120 do tick() end
    assert(row_count(current) == 120 and not files[previous])
    if scenario == "restart" then dofile(source) end
    tick()
    assert(row_count(previous) == 120 and row_count(current) == 1)
    assert(files[previous]:find("1970-01-01T00:00:30Z", 1, true))
    for i = 122, 600 do
        if scenario == "restart" and i % 73 == 0 then dofile(source) end
        tick()
        assert(row_count(current) <= 120 and row_count(previous) <= 120)
    end
    assert(row_count(current) + row_count(previous) == 240)
    assert(files[previous]:find("1970-01-01T03:00:30Z", 1, true), "previous segment too old")
    assert(files[current]:find("1970-01-01T04:00:30Z", 1, true), "current segment too old")
elseif scenario == "foreign_file" or scenario == "oversized" or scenario == "truncated_tail" or
    scenario == "nul_tail" or scenario == "crlf" or scenario == "partial_row" or scenario == "excess_rows" then
    local old = files[current]
    files[previous] = "older segment\n"
    tick() tick()
    assert(files[previous] == old, "rotation must preserve every byte of the damaged/foreign segment")
    assert(files[current]:sub(1, #header) == header and row_count(current) == 2, "sampler did not recover")
    dofile(source) tick()
    assert(files[previous] == old and row_count(current) == 3, "recovery did not survive reload")
elseif scenario == "rename_error" then
    local old = files[current]
    tick() tick()
    assert(files[current] == old and not files[previous], "failed rename destroyed the source")
    file.Rename = function(from, to) files[to], files[from] = files[from], nil end
    tick()
    assert(files[previous] == old and row_count(current) == 1)
elseif scenario == "nil_backoff" or scenario == "error_backoff" then
    RemixResource.GetVramStats = function()
        calls = calls + 1
        if scenario == "error_backoff" then error("unsupported API") end
        return nil
    end
    for i = 1, 300 do tick() end
    assert(calls == 3 and writes == 0, "repeated native failures must stop after three calls")
    RemixResource.GetVramStats = stats tick()
    assert(calls == 3, "back-off unexpectedly retried the API")
    set_enabled("0") set_enabled("1") tick()
    assert(calls == 4 and row_count(current) == 1, "off/on must permit a retry without waiting for a tick")
elseif scenario == "failure_reset" then
    local function fail() calls = calls + 1 return nil end
    for i = 1, 4 do
        RemixResource.GetVramStats = fail tick() tick()
        RemixResource.GetVramStats = stats tick()
    end
    assert(calls == 12 and row_count(current) == 4, "successful samples must reset consecutive failures")
elseif scenario == "file_error" then
    tick() tick() -- errors must not escape the timer, and recovery must work
    file.Append = function(path, body) files[path] = files[path] .. body end
    tick() assert(row_count(current) == 1)
else
    tick()
    local values = {}
    for i = 1, #fields do values[#values + 1] = tostring(10000000000 + i) end
    assert(files[current] == header .. "1970-01-01T00:00:30Z," .. table.concat(values, ",") .. "\n")
    assert(calls == 1 and not files[previous])
    tick() assert(row_count(current) == 2)
end
print("PASS " .. scenario)
