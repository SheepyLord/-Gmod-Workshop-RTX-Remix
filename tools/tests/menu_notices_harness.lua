-- Execute the actual embedded menu reader with file/JSON/UI fixtures, without a game.
local input = assert(io.open(arg[1], "rb"))
local source = input:read("*a")
input:close()
local token, process_id = '123-456"\\\n', 123
local files, decoded, calls, payload, reads
local function reset()
    files, decoded, calls, payload, reads = {}, {}, 0, nil, 0
    _G.NativeLoaderRAMWarningSession = nil
    pnlMainMenu = { Call = function(_, js)
        calls = calls + 1
        assert(js == "window.NativeLoaderReceiveNotices({})")
    end }
end
function IsValid(value) return value ~= nil end
function istable(value) return type(value) == "table" end
file = {
    Size = function(path, realm) assert(realm == "DATA"); return files[path] and #files[path] or -1 end,
    Read = function(path, realm) assert(realm == "DATA"); reads = reads + 1; return files[path] end
}
util = {
    JSONToTable = function(text) return decoded[text] end,
    TableToJSON = function(value) payload = value; return "{}" end
}
local function put(path, text, value) files["native-loader/" .. path .. ".json"] = text; decoded[text] = value end
local function run() assert(loadstring(string.format(source, string.format("%q", token), process_id)))() end
reset()
put("status", "status", {process_id = process_id, session_token = token, previous_session = {reason = "crash", folder = "<literal>"}})
put("memory", "memory", {schema = 1, session_token = token, warning = true})
run()
assert(calls == 1 and reads == 2)
assert(payload.session_token == token and payload.warning_allowed)
assert(payload.previous_session.reason == "crash" and payload.previous_session.folder == "<literal>")
assert(payload.commit.warning)
_G.NativeLoaderRAMWarningSession = token
run()
assert(not payload.warning_allowed, "once-per-start acknowledgement stays in the menu Lua realm")
reset()
put("status", "old-status", {process_id = 999, session_token = token, previous_session = {reason = "device_lost"}})
put("memory", "old-memory", {schema = 1, session_token = "other-process", warning = true})
run()
assert(payload.previous_session == nil and payload.commit == nil)
put("status", "reused-pid", {process_id = process_id, session_token = "old-start", previous_session = {reason = "crash"}})
run()
assert(payload.previous_session == nil, "PID reuse cannot resurrect another start's status")
reset()
put("status", string.rep("x", 1048577), {})
put("memory", string.rep("y", 4097), {})
run()
assert(reads == 0 and payload.previous_session == nil and payload.commit == nil)
reset()
put("status", "bad-json", false)
put("memory", "scalar-json", 5)
run()
assert(payload.previous_session == nil and payload.commit == nil)
reset()
pnlMainMenu = nil
run()
assert(reads == 0 and calls == 0)
print("PASS menu notices")
