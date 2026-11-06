local input = assert(io.open(arg[1], "rb"))
local source = input:read("*a"); input:close()
local token, payload = 'start"\\\n', nil
local files, reads = {}, 0
function IsValid(value) return value ~= nil end
function isstring(value) return type(value) == "string" end
cookie = {GetString = function(key, default) reads = reads + 1; return files[key] or default end}
util = {TableToJSON = function(value) payload = value; return "{}" end}
pnlMainMenu = {Call = function(_, js) assert(js == "window.NativeLoaderReceiveMenuState({})") end}
local function run() assert(loadstring(string.format(source, string.format("%q", token))))() end
run(); assert(not payload.update_seen and not payload.multiplayer_dismissed and payload.ignored_version == "")
files["nativeloader.loader-update-ignored"] = "0.16.0"
files["nativeloader.multiplayer-warning-dismissed"] = "1"
NativeLoaderUpdateSession = token
run(); assert(payload.update_seen and payload.multiplayer_dismissed and payload.ignored_version == "0.16.0")
files["nativeloader.loader-update-ignored"] = string.rep("x", 129)
files["nativeloader.multiplayer-warning-dismissed"] = "true"
NativeLoaderUpdateSession = "another-start"
local before = reads
run(); assert(not payload.update_seen and not payload.multiplayer_dismissed and payload.ignored_version == "")
assert(reads == before + 2, "both cookies read, over-limit value discarded")
pnlMainMenu = nil; before = reads; run(); assert(reads == before)
print("PASS menu choices")
