local input = assert(io.open(arg[1], "rb"))
local source = input:read("*a"); input:close()
local token, payload = 'start"\\\n', nil
local files, reads = {}, 0
function IsValid(value) return value ~= nil end
function isstring(value) return type(value) == "string" end
file = {
    Size = function(path, realm) assert(realm == "DATA"); return files[path] and #files[path] or -1 end,
    Read = function(path, realm) assert(realm == "DATA"); reads = reads + 1; return files[path] end
}
util = {TableToJSON = function(value) payload = value; return "{}" end}
pnlMainMenu = {Call = function(_, js) assert(js == "window.NativeLoaderReceiveMenuState({})") end}
local function run() assert(loadstring(string.format(source, string.format("%q", token))))() end
run(); assert(not payload.update_seen and not payload.multiplayer_dismissed and payload.ignored_version == "")
files["native-loader/loader-update-ignored.txt"] = "0.16.0"
files["native-loader/multiplayer-warning-dismissed.txt"] = "1"
NativeLoaderUpdateSession = token
run(); assert(payload.update_seen and payload.multiplayer_dismissed and payload.ignored_version == "0.16.0")
files["native-loader/loader-update-ignored.txt"] = string.rep("x", 129)
files["native-loader/multiplayer-warning-dismissed.txt"] = "true"
NativeLoaderUpdateSession = "another-start"
local before = reads
run(); assert(not payload.update_seen and not payload.multiplayer_dismissed and payload.ignored_version == "")
assert(reads == before + 1, "over-limit preference never read")
pnlMainMenu = nil; before = reads; run(); assert(reads == before)
print("PASS menu choices")
