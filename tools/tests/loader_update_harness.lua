-- Run the actual companion autorun, including the physical-file trust checks and Derma callbacks.
local source = assert(arg[1])
CLIENT, TOP, BOTTOM = true, 1, 2
local files, tables, hooks, timers, panels, opened, fonts, readCounts
local url = "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v"
local recordPath = "garrysmod/addons/nativeloader/resource/loader-release.json"
local journalPath = "native-loader/state.json"
local record, status, journal
local height = 1080
local function sha(value) return "digest:" .. value end
function MsgN() end
function istable(value) return type(value) == "table" end
function isfunction(value) return type(value) == "function" end
function include() return {L = function(value) return value end} end
function ScrH() return height end
function ScrW() return height * 16 / 9 end
concommand = {Add = function() end}
timer = {Simple = function(_, fn) timers[#timers + 1] = fn end, Create = function() end}
hook = {Add = function(event, name, fn) hooks[name] = fn end}
notification = {}
steamworks = {}
util = {JSONToTable = function(bytes) return tables[bytes] end, SHA256 = sha}
gui = {OpenURL = function(value) opened[#opened + 1] = value end}
surface = {CreateFont = function(_, definition) fonts[#fonts + 1] = definition end}
file = {
    Exists = function(path) return files["DATA:" .. path] ~= nil end,
    Read = function(path, realm) return files[realm .. ":" .. path] end,
    CreateDir = function(path) assert(path == "native-loader") end,
    Write = function(path, value) files["DATA:" .. path] = value end,
    Open = function(path, mode, realm)
        assert(mode == "rb" and (realm == "BASE_PATH" or realm == "DATA"))
        local bytes = files[realm .. ":" .. path]
        if not bytes then return end
        return {Size = function() return #bytes end, Close = function() end,
            Read = function(_, size) assert(size == #bytes); readCounts[path] = (readCounts[path] or 0) + 1; return bytes end}
    end
}
vgui = {Create = function(kind, parent)
    local panel = {kind = kind, parent = parent}
    for _, name in ipairs({"Center", "MakePopup", "Dock", "DockPadding", "DockMargin", "SetWrap", "SetAutoStretchVertical", "SetPaintBackground", "SetFont"}) do
        panel[name] = function() end
    end
    if kind == "DFrame" then
        local function control()
            return {SetFont = function() end, SetVisible = function() end, SetPos = function() end, SetSize = function() end}
        end
        panel.lblTitle, panel.btnClose, panel.btnMinim, panel.btnMaxim = control(), control(), control(), control()
        panel.PerformLayout = function() end
    end
    panel.SetText = function(_, value) panel.text = value end
    panel.SetTitle = panel.SetText
    panel.SetSize = function(_, w, h) panel.width, panel.height = w, h end
    panel.SetTall = function(_, value) panel.tall = value end
    panel.Close = function() panel.closed = true end
    panels[#panels + 1] = panel
    return panel
end}
local function release(value)
    record = {version = value, url = url .. value}
    local bytes = '{"version":"' .. value .. '","url":"' .. record.url .. '"}'
    files["BASE_PATH:" .. recordPath] = bytes
    tables[bytes] = record
    journal.current.files = {{path = recordPath, package = "gmod-rtx-remix", size = #bytes, sha256 = sha(bytes)}}
end
local function reset(current, latest)
    files, tables, hooks, timers, panels, opened, fonts, readCounts = {}, {}, {}, {}, {}, {}, {}, {}
    status = {schema = 1, loader_version = current or "0.14.0", process_id = 42, session_token = "42-start", utc = "2099-01-01T00:00:00Z",
        activation = {outcome = "active", runtime = {id = "gmod-rtx-remix"}},
        packages = {{id = "gmod-rtx-remix", version = "1.0.0", source = "workshop", label = "3829070317"}}}
    journal = {schema = 1, current = {packages = {{id = "gmod-rtx-remix", version = "1.0.0", source = "workshop", remix = {}}}}}
    files["DATA:native-loader/status.json"] = "STATUS"
    files["BASE_PATH:" .. journalPath] = "JOURNAL"
    tables.STATUS, tables.JOURNAL = status, journal
    release(latest or "0.15.0")
end
local function firstMap()
    dofile(source)
    assert(hooks.nativeloader_loader_update)
    hooks.nativeloader_loader_update()
    local queued = timers
    timers = {}
    for _, fn in ipairs(queued) do fn() end
end
local function frames()
    local count = 0
    for _, panel in ipairs(panels) do if panel.kind == "DFrame" then count = count + 1 end end
    return count
end
local function click(text)
    for _, panel in ipairs(panels) do if panel.kind == "DButton" and panel.text == text then panel.DoClick() return end end
    error("button missing: " .. text)
end
for _, pair in ipairs({
    {"0.14.0", "0.15.0", true}, {"0.14.0", "0.14.0", false}, {"0.14.1", "0.14.0", false},
    {"0.15.0", "0.16.0", false}, {"0.16.0", "0.17.0", false},
    {"0.14.0-rc.2", "0.14.0-rc.10", true}, {"0.14.0-rc.10", "0.14.0-rc.2", false},
    {"0.14.0-rc.1", "0.14.0", true}, {"0.14.0", "0.14.0-rc.1", false},
    {"0.14.0-alpha", "0.14.0-alpha.1", true}, {"0.14.0-9", "0.14.0-alpha", true},
    {"0.14.0-a", "0.14.0-b", true}, {"bad", "0.15.0", false},
    {"0.14.0", "01.0.0", false}, {"0.14.0", "0.15.0+build", false},
    {"0.14.0", "0.15.0-01", false}, {"0.14.0", "0.15.0-a..b", false},
    {"0.14.0", "18446744073709551616.0.0", false}
}) do
    reset(pair[1], pair[2]); firstMap()
    assert((frames() == 1) == pair[3], pair[1] .. " versus " .. pair[2])
end
reset(); firstMap(); click("Later"); firstMap()
assert(frames() == 1, "DATA token survives a new client realm on map change")
assert(not files["DATA:native-loader/loader-update-ignored.txt"])
status.session_token = "43-new-start"; firstMap(); assert(frames() == 2, "next process asks again after Later")
reset(); firstMap(); click("Don't remind me about 0.15.0")
status.session_token = "new-start"; firstMap(); assert(frames() == 1)
release("0.16.0"); firstMap(); assert(frames() == 2, "ignore is per version")
reset(); firstMap(); click("Open the download page"); assert(opened[1] == url .. "0.15.0")
for _, mutate in ipairs({
    function() status.activation.outcome = "inactive" end,
    function() status.activation.runtime.id = "foreign" end,
    function() status.packages[1].label = "12345" end,
    function() status.packages[1].version = "9.0.0" end,
    function() journal.pending = {} end,
    function() journal.current.packages[1].remix = nil end,
    function() journal.current.packages[2] = journal.current.packages[1] end,
    function() journal.current.files[1].package = "content" end,
    function() journal.current.files[1].sha256 = "wrong" end,
    function() journal.current.files[2] = journal.current.files[1] end,
    function() files["BASE_PATH:" .. recordPath] = string.rep("x", 1025) end,
    function() files["BASE_PATH:" .. journalPath] = string.rep("x", 16 * 1024 * 1024 + 1) end,
    function() files["BASE_PATH:" .. recordPath] = '{"version":"0.16.0","version":"0.15.0","url":"' .. url .. '0.15.0"}' end,
    function() record.url = "https://evil.test/" end,
    function() files["GAME:resource/loader-release.json"] = files["BASE_PATH:" .. recordPath]; files["BASE_PATH:" .. recordPath] = nil end
}) do
    reset(); mutate(); firstMap(); assert(frames() == 0, "untrusted/invalid record must be silent")
end
for _, resolution in ipairs({900, 2160}) do
    reset(); height = resolution; firstMap(); assert(frames() == 1)
    assert(fonts[1].size == math.floor(21 * resolution / 1080))
    assert(panels[1].width < ScrW() and panels[1].height < ScrH())
end
reset(); files["BASE_PATH:" .. recordPath] = string.rep("x", 1025); firstMap(); assert(not readCounts[recordPath], "size check before allocation")
print("PASS companion loader reminders")
