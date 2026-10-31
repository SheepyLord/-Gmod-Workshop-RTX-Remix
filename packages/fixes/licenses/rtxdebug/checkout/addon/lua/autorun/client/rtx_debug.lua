-- The native module owns the console command and all engine-facing functions.
-- This layer handles JSON files so requests use the same console.log handshake
-- as rtx_agent without putting a JSON parser or a socket on a render thread.

local loaded, err = pcall(require, "rtxdebug")
if not loaded then
    ErrorNoHalt("[RTXDebug] require failed: " .. tostring(err) .. "\n")
    return
end

local PROTOCOL = 1
local processId = RTXDebug.Status().process_id
local requestDir = "rtx_debug/requests"
local resultDir = "rtx_debug/results"
file.CreateDir("rtx_debug")
file.CreateDir(requestDir)
file.CreateDir(resultDir)

local function plain(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = type(value)
    if kind == "number" then
        return (value ~= value or value == math.huge or value == -math.huge) and tostring(value) or value
    end
    if kind == "string" or kind == "boolean" or kind == "nil" then return value end
    if kind == "Vector" then return { value.x, value.y, value.z } end
    if kind == "Angle" then return { value.p, value.y, value.r } end
    if kind == "Entity" or kind == "Player" or kind == "NPC" or kind == "Weapon" then
        return IsValid(value) and { index = value:EntIndex(), class = value:GetClass() } or "NULL"
    end
    if kind == "table" then
        if depth >= 8 then return "<depth>" end
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local out = {}
        for key, item in pairs(value) do
            out[type(key) == "number" and key or tostring(key)] = plain(item, depth + 1, seen)
        end
        seen[value] = nil
        return out
    end
    return tostring(value)
end

-- Requests may call RTXDebug.<TopLevel> or RTXDebug.<Section>.<Function>.
local topLevel = { Status = true, RestoreAll = true }
local sections = { Engine = true, Interfaces = true, Lua = true, Remix = true,
                   Memory = true, Detours = true }

local function resolveMethod(name)
    if not isstring(name) or #name > 96 then return nil end
    if topLevel[name] then return rawget(RTXDebug, name) end
    local section, member = name:match("^(%a+)%.([%a_][%w_]*)$")
    if not section or not sections[section] then return nil end
    local node = rawget(RTXDebug, section)
    local fn = istable(node) and rawget(node, member) or nil
    return isfunction(fn) and fn or nil
end

local function writeResult(id, body)
    body.id = id
    body.protocol = PROTOCOL
    body.time = SysTime()
    body.process_id = processId
    local encoded = util.TableToJSON(plain(body), true)
    if not encoded or #encoded > 8 * 1024 * 1024 then
        encoded = util.TableToJSON({ id = id, protocol = PROTOCOL, ok = false,
            process_id = processId, error = "result is not JSON serializable or exceeds 8 MiB" }, true)
    end
    file.Write(resultDir .. "/" .. id .. ".json", encoded)
    MsgN("[RTXDebug] DONE " .. id)
end

function RTXDebug.DispatchRequest(id)
    if not isstring(id) or #id < 1 or #id > 64 or not id:match("^[A-Za-z0-9_-]+$") then
        return false
    end

    local raw = file.Read(requestDir .. "/" .. id .. ".json", "DATA")
    if not raw then
        writeResult(id, { ok = false, error = "request file is missing" })
        return false
    end
    if #raw > 1024 * 1024 then
        writeResult(id, { ok = false, error = "request exceeds 1 MiB" })
        return false
    end

    local request = util.JSONToTable(raw)
    if not istable(request) or (request.id ~= nil and request.id ~= id) then
        writeResult(id, { ok = false, error = "invalid JSON request or mismatched id" })
        return false
    end
    if request.process_id ~= nil and (not isnumber(request.process_id)
        or request.process_id ~= processId) then
        writeResult(id, { ok = false, error = "request belongs to another process" })
        return false
    end
    local fn = resolveMethod(request.method)
    if not fn or (request.args ~= nil and not istable(request.args)) then
        writeResult(id, { ok = false, error = "unknown method or invalid args" })
        return false
    end

    -- JSON nulls leave holes in args; maxn keeps the later arguments in place.
    local args = request.args or {}
    local results = { pcall(fn, unpack(args, 1, table.maxn(args))) }
    if not results[1] then
        writeResult(id, { ok = false, error = tostring(results[2]) })
        return false
    end
    -- RTXDebug functions report failure as nil plus a message.
    if results[2] == nil and results[3] ~= nil then
        writeResult(id, { ok = false, error = tostring(results[3]) })
        return false
    end
    writeResult(id, { ok = true, result = results[2] })
    return true
end

-- Binary modules are closed after this hook, and RTXFixesBinary's RemixConfig
-- stops working once that module closes, so restore everything here first.
hook.Add("ShutDown", "RTXDebug.RestoreAll", function()
    if not (RTXDebug and RTXDebug.RestoreAll) then return end
    local ok, summary = pcall(RTXDebug.RestoreAll)
    if not ok then
        ErrorNoHalt("[RTXDebug] RestoreAll failed: " .. tostring(summary) .. "\n")
    end
end)

MsgN("[RTXDebug] JSON request dispatcher ready")
