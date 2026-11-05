-- R19 (proxy F-02): runs the companion's render guard, the production file, with only what its
-- installation decision reads, once per case, and checks whether it went on to install. Its first
-- call after the decision is CreateClientConVar, which ends the run here.
-- Usage: luajit guard_session_marker.lua <companion/nativeloader/lua/autorun/_nativeloader_guard.lua>
local guardPath = assert(arg and arg[1], "usage: luajit guard_session_marker.lua <_nativeloader_guard.lua>")
local handle = assert(io.open(guardPath, "rb"))
local source = handle:read("*a")
handle:close()

local marker = "native-loader/rtx-session.txt"

-- status.json as the loader writes it: the fields the guard reads, in the writer's order.
local function status(version, outcome)
    return '{\n"schema":1,"loader_version":"' .. version .. '","previous_session":null,'
        .. '"utc":"2026-11-05T00:00:00.000Z","process_id":4242,"session_token":"4242-133000000000000000",'
        .. '"startup_elapsed_ms":1.0,\n"deployment":{"outcome":"unchanged"},\n'
        .. '"activation":{"outcome":"' .. outcome .. '","reason":"runtime gmod-rtx-remix 1.0.0"},\n"session":{}\n}\n'
end

-- case.status: the report's text (nil: none). case.exists: what file.Exists says about the marker
-- (nil: no such function; "error": it raises). case.find: the names file.Find lists (nil: no such
-- function). case.early: the generated initializer's flag.
local function installs(case)
    local installed = false
    local env = setmetatable({}, {__index = _G})
    env.CLIENT, env.SERVER, env.MENU_DLL = true, false, false
    env.__NATIVELOADER_RTX_GUARD_EARLY = case.early == true
    local fake = {}
    function fake.Read(name, realm)
        assert(name == "native-loader/status.json" and realm == "DATA", "unexpected read of " .. tostring(name))
        return case.status
    end
    if case.exists ~= nil then
        function fake.Exists(name, realm)
            assert(name == marker and realm == "DATA", "unexpected existence check of " .. tostring(name))
            if case.exists == "error" then error("engine refused") end
            return case.exists
        end
    end
    if case.find ~= nil then
        function fake.Find(pattern, realm)
            assert(pattern == marker and realm == "DATA", "unexpected search for " .. tostring(pattern))
            return case.find, {}
        end
    end
    env.file = fake
    env.CreateClientConVar = function() installed = true error("installing", 0) end
    local chunk = assert(loadstring(source, "=lua/autorun/_nativeloader_guard.lua"))
    setfenv(chunk, env)
    local ok, reason = pcall(chunk)
    assert(ok or reason == "installing", "the guard failed before deciding: " .. tostring(reason))
    return installed
end

local cases = {
    -- A start of loader 0.14.0 or later in an RTX session holds the marker.
    {"RTX start, marker held", true, {status = status("0.14.0", "active"), exists = true}},
    {"RTX start, early view, marker held", true, {status = status("0.14.0", "active"), exists = true, early = true}},
    {"RTX start, only the listing sees the marker", true, {status = status("0.14.0", "active"), exists = false, find = {"rtx-session.txt"}}},
    {"RTX start, the existence check raises", true, {status = status("0.14.0", "active"), exists = "error", find = {"RTX-Session.txt"}}},
    {"later loader, marker held", true, {status = status("1.2.3", "active"), exists = true}},
    -- The finding: a report an earlier RTX start left, read in a start through an off switch.
    {"off-switch start after an RTX start", false, {status = status("0.14.0", "active"), exists = false, find = {}}},
    {"off-switch start, early view served by a host", false, {status = status("0.14.0", "active"), exists = false, find = {}, early = true}},
    {"stale report, no file functions", false, {status = status("0.15.2", "active")}},
    {"stale report, other files listed", false, {status = status("0.14.0", "active"), exists = false, find = {"status.json", "rtx-session.txt.old"}}},
    -- An older loader holds no marker: its report alone decides, as before.
    {"loader 0.13.x RTX start", true, {status = status("0.13.4", "active"), exists = false, find = {}}},
    {"loader 0.10.1 RTX start", true, {status = status("0.10.1", "active")}},
    -- This start's report says RTX is off: a marker is another game's (two games at once).
    {"RTX off, another game's marker", false, {status = status("0.14.0", "inactive"), exists = true}},
    {"activation failed", false, {status = status("0.14.0", "failed"), exists = true}},
    -- No report (it is written last and can fail): the marker alone shows this start's RTX.
    {"no report, marker held", true, {exists = true}},
    {"no report, marker held, early view", true, {exists = true, early = true}},
    {"no report, no marker (a remote vanilla client)", false, {exists = false, find = {}}},
    {"unreadable report, marker held", true, {status = "garbage", exists = true}},
    {"unreadable report, no marker", false, {status = "garbage", exists = false}},
}

local failures = 0
for _, case in ipairs(cases) do
    local name, expected, setup = case[1], case[2], case[3]
    local ok, result = pcall(installs, setup)
    if not ok then
        failures = failures + 1
        print("FAIL " .. name .. ": " .. tostring(result))
    elseif result ~= expected then
        failures = failures + 1
        print("FAIL " .. name .. ": installed " .. tostring(result) .. ", expected " .. tostring(expected))
    else
        print("ok   " .. name)
    end
end
if failures > 0 then
    print(failures .. " of " .. #cases .. " cases failed")
    os.exit(1)
end
print("PASS guard session marker: " .. #cases .. " cases")
