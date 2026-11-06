-- nativeloader: prints the native loader's start-up and session status to the console, once when
-- the client starts and again on the console command nativeloader_status. It reads
-- garrysmod/data/native-loader/status.json and session.json, which the loader's bootstrap
-- (bin/win64/winmm.dll) writes, and (M6) says when a Workshop package has a newer version that the
-- next start deploys (steamworks.FileInfo, every ten minutes). Also reminds older loaders to update.
-- Documented in nativeloader.lua.md beside this file.

if not CLIENT then return end

local STATUS_FILE = "native-loader/status.json"
local SESSION_FILE = "native-loader/session.json"
local STALE_AFTER = 15 * 60 -- a report older than this when the client started is from another session

local client_start = os.time()

local function say(line)
    MsgN("[nativeloader] " .. line)
end

-- The update notice is shown in the player's language (nativeloader/i18n.lua); the console lines stay
-- English, for reports.
local function L(text)
    local ok, i18n = pcall(include, "nativeloader/i18n.lua")
    return ok and istable(i18n) and i18n.L(text) or text
end

-- t[k1][k2]... without erroring on a missing level.
local function field(t, ...)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end

local function text(value, default)
    if value == nil or value == "" then return default or "?" end
    return tostring(value)
end

local function list(value)
    return type(value) == "table" and value or {}
end

-- A JSON file from the DATA path as a table, or nil and why not.
local function read_json(path)
    local ok, result = pcall(function()
        if not file.Exists(path, "DATA") then return "missing" end
        local body = file.Read(path, "DATA")
        if not body or body == "" then return "empty" end
        local data = util.JSONToTable(body)
        if type(data) ~= "table" then return "not valid JSON" end
        return data
    end)
    if not ok then return nil, "unreadable: " .. tostring(result) end
    if type(result) ~= "table" then return nil, result end
    return result
end

-- Seconds since 1970 for "YYYY-MM-DDThh:mm:ss[.fff]Z", computed without the local time zone
-- (days_from_civil, H. Hinnant), or nil.
local function parse_utc(stamp)
    if type(stamp) ~= "string" then return nil end
    local y, mo, d, h, mi, s = stamp:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if not y then return nil end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    if mo <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * ((mo + 9) % 12) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468
    return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds < 120 then return seconds .. " s" end
    if seconds < 7200 then return math.floor(seconds / 60) .. " min" end
    if seconds < 172800 then return string.format("%.1f h", seconds / 3600) end
    return string.format("%.1f days", seconds / 86400)
end

-- "written ... before this client started", and whether that makes the report stale.
local function freshness(report)
    local written = parse_utc(report.utc)
    if not written then return "written at an unknown time (utc " .. text(report.utc) .. ")", true end
    local age = client_start - written
    local when = "written " .. duration(age) .. " before this client started"
    if age > STALE_AFTER then return when .. ": STALE, not from this session", true end
    return when, false
end

local function report_status()
    local status, why = read_json(STATUS_FILE)
    if not status then
        say("no status: garrysmod/data/" .. STATUS_FILE .. " is " .. why)
        if why == "missing" then say("The loader has not reported in this install (not installed, or uninstalled).") end
        return nil
    end
    if status.schema ~= 1 then
        say("status.json has schema " .. text(status.schema) .. "; this companion reads schema 1")
        return nil
    end
    local when, stale = freshness(status)
    say("loader " .. text(status.loader_version) .. ", process " .. text(status.process_id) .. ", " .. when)
    if stale then
        say("An off switch, a start without the loader or a crash before its report leaves an old status.")
    end

    local deployment = status.deployment
    local line = "deployment: " .. text(field(deployment, "outcome")) .. ", generation " .. text(field(deployment, "generation"))
    local reason = text(field(deployment, "reason"), "")
    if reason ~= "" then line = line .. " (" .. reason .. ")" end
    local blocked = text(field(deployment, "blocked_by"), "none")
    if blocked ~= "none" then line = line .. ", blocked by " .. blocked end
    say(line)
    for _, skipped in ipairs(list(field(deployment, "skipped"))) do
        say("  skipped " .. text(field(skipped, "package")) .. ": " .. text(field(skipped, "reason")))
    end

    local activation = status.activation
    line = "activation: " .. text(field(activation, "outcome"))
    reason = text(field(activation, "reason"), "")
    if reason ~= "" then line = line .. " (" .. reason .. ")" end
    say(line)
    local runtime_id = text(field(activation, "runtime", "id"), "")
    if runtime_id ~= "" then
        say("runtime: " .. runtime_id .. " " .. text(field(activation, "runtime", "version")))
    end
    -- ReShade in RTX sessions (loader 0.5.0, ADR 0028): an older loader's status has no such field.
    local shade = field(activation, "reshade")
    if shade and text(field(shade, "package"), "") ~= "" then
        local settings = text(field(shade, "settings"), "")
        say("reshade: " .. text(field(shade, "outcome")) .. " (" .. text(field(shade, "reason"), "") .. ")" ..
            (settings ~= "" and ", settings " .. settings .. " in native-loader\\reshade" or ""))
    end

    local errors = list(status.errors)
    for i = 1, math.min(#errors, 5) do say("error: " .. text(errors[i])) end
    if #errors > 5 then say("... and " .. (#errors - 5) .. " more errors in status.json") end
    return status
end

local function report_session(status)
    local session, why = read_json(SESSION_FILE)
    if not session then
        say("session: no session.json (" .. why .. "): no patch sets, overrides or session variables reported")
        return
    end
    if session.schema ~= 1 then
        say("session.json has schema " .. text(session.schema) .. "; this companion reads schema 1")
        return
    end
    local when = freshness(session)
    local other = status and session.process_id ~= status.process_id
    say("session: " .. when .. (other and ", from another process than status.json" or ""))

    local patches = list(session.patches)
    local applied = 0
    for _, patch in ipairs(patches) do
        if field(patch, "result") == "applied" then applied = applied + 1 end
    end
    say("patches: " .. applied .. " of " .. #patches .. " applied")
    for _, patch in ipairs(patches) do
        if field(patch, "result") ~= "applied" then
            say("  " .. text(field(patch, "result")) .. " " .. text(field(patch, "module")) .. " " ..
                text(field(patch, "name")) .. ": " .. text(field(patch, "reason"), "no reason given"))
        end
    end

    for _, override in ipairs(list(session.overrides)) do
        local line = "override " .. text(field(override, "module")) .. ": " .. text(field(override, "result"))
        local loaded = text(field(override, "loaded"), "")
        if loaded ~= "" then line = line .. " (" .. loaded .. ")" end
        say(line)
    end

end

-- What start-up set up for this session (status.json "session"): variables and their restore.
local function report_variables(status)
    local s = field(status, "session")
    if type(s) ~= "table" then return end
    if text(s.cvars_exec, "") ~= "" then
        say("session variables: " .. text(s.cvars, "0") .. " set by " .. text(s.cvars_exec) ..
            " (" .. text(s.recorded, "0") .. " of your values kept for the next start without RTX)")
    end
    if text(s.restore_exec, "") ~= "" then
        say("restored variables: " .. text(s.restore_values, "0") .. " of your values put back by " .. text(s.restore_exec))
    end
    for _, note in ipairs(list(s.notes)) do say("note: " .. text(note)) end
end

-- Two-phase updates (M6): a Workshop package is deployed at start-up, so a version Steam downloads
-- during the session is used from the next start. Compare each Workshop package's update time with
-- the one deployed and say so once.
-- steamworks.FileInfo's times pass through a 32-bit float: today's come back rounded to a 128 s step
-- (1793444836 as 1793444864). The deployed time is Steam's exact one, so the very version deployed
-- could look newer, and the restart notice came at every start (2026-10-31, the Evernight and March 7th
-- item). Only a time more than one such step later is a newer version.
local function float_step(seconds)
    local _, exponent = math.frexp(seconds)
    return 2 ^ math.max(exponent - 24, 0)
end
local announced = {}
local function check_updates(status)
    if not steamworks or not steamworks.FileInfo then return end
    for _, package in ipairs(list(field(status, "packages"))) do
        local id, item, deployed = field(package, "id"), field(package, "label"), tonumber(field(package, "time_updated"))
        if field(package, "source") == "workshop" and item and deployed and not announced[item] then
            steamworks.FileInfo(item, function(info)
                local updated = info and tonumber(info.updated)
                if not updated or updated <= deployed + float_step(deployed) or announced[item] then return end
                announced[item] = true
                say(text(id) .. " has a newer Workshop version (" .. os.date("!%Y-%m-%d %H:%M UTC", updated) ..
                    "); it is deployed when Garry's Mod starts again.")
                if notification and notification.AddLegacy then
                    notification.AddLegacy(string.format(L("RTX package %s was updated: restart Garry's Mod to use it"), text(id)),
                                           NOTIFY_HINT or 3, 15)
                end
            end)
        end
    end
end

-- Whether the RTX fixes' module reached the Remix API: it creates RemixLight and RemixConfig only then,
-- and API lights (the fixes' flashlight, AMAP's RTX flashlight) need them.
local function report_api()
    if istable(RemixLight) and isfunction(RemixLight.CreateSphere) then
        say("Remix API: ready (RemixLight" .. (istable(RemixConfig) and ", RemixConfig" or "") .. ")")
    else
        say("Remix API: not available - the RTX fixes' module did not reach the runtime (see the lines from [gmRTX - Binary Module])")
    end
end

local function report()
    local ok, err = pcall(function()
        local status = report_status()
        report_variables(status)
        report_session(status)
        check_updates(status)
    end)
    if not ok then say("could not print the status: " .. tostring(err)) end
    report_api()
end

concommand.Add("nativeloader_status", report, nil, "Prints the native loader's start-up and session status")
report()
-- The fixes' module loads after this file; say whether it reached the API once the session is up.
hook.Add("InitPostEntity", "nativeloader_api", function() timer.Simple(3, report_api) end)
-- Steam may download an update while the game runs: look again every ten minutes.
timer.Create("nativeloader_updates", 600, 0, function()
    local status = read_json(STATUS_FILE)
    if status then pcall(check_updates, status) end
end)

-- R20: old loaders cannot update their compiled-in main menu. Read physical files, never an add-on's
-- mounted alias. The journal identifies the runtime owner and the exact bytes it deployed.
local RELEASE_PATH = "garrysmod/addons/nativeloader/resource/loader-release.json"
local RELEASE_URL = "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v"
local function bounded(path, realm, maximum)
    local f = file.Open(path, "rb", realm)
    if not f then return end
    local size = f:Size()
    if size < 0 or size > maximum then f:Close() return end
    local bytes = f:Read(size)
    f:Close()
    if type(bytes) == "string" and #bytes == size then return bytes end
end
local function decimal(a, b)
    if #a ~= #b then return #a < #b and -1 or 1 end
    return a == b and 0 or a < b and -1 or 1
end
local function version(value)
    if type(value) ~= "string" or #value > 128 then return end
    local core, pre = value:match("^([0-9]+%.[0-9]+%.[0-9]+)%-([0-9A-Za-z%.%-]+)$")
    core = core or value:match("^([0-9]+%.[0-9]+%.[0-9]+)$")
    if not core then return end
    local result = {core = {}, pre = {}}
    for n in core:gmatch("[^%.]+") do
        if #n > 1 and n:sub(1, 1) == "0" or decimal(n, "18446744073709551615") > 0 then return end
        result.core[#result.core + 1] = n
    end
    if pre then
        if pre:sub(1, 1) == "." or pre:sub(-1) == "." or pre:find("..", 1, true) then return end
        for n in pre:gmatch("[^%.]+") do
            if n:match("^%d+$") and #n > 1 and n:sub(1, 1) == "0" then return end
            result.pre[#result.pre + 1] = n
        end
    end
    return result
end
local function compare(a, b)
    for i = 1, 3 do local c = decimal(a.core[i], b.core[i]) if c ~= 0 then return c end end
    if #a.pre == 0 or #b.pre == 0 then return #a.pre == #b.pre and 0 or #a.pre == 0 and 1 or -1 end
    for i = 1, math.min(#a.pre, #b.pre) do
        local x, y = a.pre[i], b.pre[i]
        local xn, yn = x:match("^%d+$") ~= nil, y:match("^%d+$") ~= nil
        local c = xn and yn and decimal(x, y) or xn ~= yn and (xn and -1 or 1) or (x == y and 0 or x < y and -1 or 1)
        if c ~= 0 then return c end
    end
    return #a.pre == #b.pre and 0 or #a.pre < #b.pre and -1 or 1
end
local function trusted_release(status)
    if field(status, "activation", "outcome") ~= "active" or field(status, "activation", "runtime", "id") ~= "gmod-rtx-remix" then return end
    local bytes = bounded(RELEASE_PATH, "BASE_PATH", 1024)
    if not bytes then return end
    -- This deliberately small ASCII record has exactly two unescaped string fields. Unlike
    -- JSONToTable alone, this also rejects duplicate keys and extra JSON values.
    local a, av, b, bv = bytes:match('^%s*{%s*"([a-z]+)"%s*:%s*"([^"\\%c]*)"%s*,%s*"([a-z]+)"%s*:%s*"([^"\\%c]*)"%s*}%s*$')
    if not a or a == b then return end
    local record = util.JSONToTable(bytes)
    if not record or not ((a == "version" and b == "url") or (a == "url" and b == "version")) or
       not version(record.version) or record.url ~= RELEASE_URL .. record.version then return end
    local journalBytes = bounded("native-loader/state.json", "BASE_PATH", 16 * 1024 * 1024)
    local journal = journalBytes and util.JSONToTable(journalBytes)
    if type(journal) ~= "table" or journal.schema ~= 1 or journal.pending ~= nil or type(journal.current) ~= "table" then return end
    local owner
    for _, package in ipairs(list(journal.current.packages)) do
        if package.id == "gmod-rtx-remix" then
            if owner or type(package.remix) ~= "table" then return end
            owner = package
        end
    end
    if not owner then return end
    -- status.packages comes from native discovery, which only labels native packages after their
    -- configured allowlist check. Content subscriptions cannot acquire a remix entry in the journal.
    local allowed = false
    for _, package in ipairs(list(status.packages)) do
        if package.id == owner.id and package.version == owner.version and package.source == owner.source and
           (package.source == "local" or package.source == "dev_folder" or
            package.source == "workshop" and package.label == "3829070317") then allowed = true end
    end
    if not allowed then return end
    local recorded
    for _, item in ipairs(list(journal.current.files)) do
        if type(item.path) == "string" and item.path:lower() == RELEASE_PATH then
            if recorded or item.package ~= owner.id or item.path ~= RELEASE_PATH or item.size ~= #bytes or
               item.sha256 ~= util.SHA256(bytes) then return end
            recorded = item
        end
    end
    if recorded then return record end
end
local function loader_reminder()
    local status = read_json(STATUS_FILE)
    local current = status and status.schema == 1 and version(status.loader_version)
    if not current or compare(current, version("0.15.0")) >= 0 then return end
    local release = trusted_release(status)
    if not release or compare(current, version(release.version)) >= 0 then return end
    local token = type(status.session_token) == "string" and status.session_token or
        tostring(status.process_id) .. ":" .. tostring(status.utc)
    if bounded("native-loader/loader-update-seen.txt", "DATA", 128) == token or
       bounded("native-loader/loader-update-ignored.txt", "DATA", 128) == release.version then return end
    local scale = math.max(0.65, ScrH() / 1080)
    local function px(n) return math.floor(n * scale) end
    surface.CreateFont("NativeLoaderUpdate", {font = "Arial", size = px(21), weight = 400})
    local frame = vgui.Create("DFrame")
    frame:SetTitle(L("A loader update is available"))
    frame:DockPadding(px(8), px(40), px(8), px(8))
    frame.lblTitle:SetFont("NativeLoaderUpdate")
    frame.btnMinim:SetVisible(false)
    frame.btnMaxim:SetVisible(false)
    local originalLayout = frame.PerformLayout
    frame.PerformLayout = function(self, w, h)
        originalLayout(self, w, h)
        self.lblTitle:SetPos(px(10), px(4))
        self.lblTitle:SetSize(w - px(60), px(30))
        self.btnClose:SetPos(w - px(38), 0)
        self.btnClose:SetSize(px(34), px(28))
    end
    frame:SetSize(math.min(px(740), ScrW() - px(40)), math.min(px(480), ScrH() - px(40)))
    frame:Center()
    frame:MakePopup()
    local body = vgui.Create("DLabel", frame)
    body:SetFont("NativeLoaderUpdate")
    body:SetText(string.format(L("You are running loader %s. The latest release is %s."), status.loader_version, release.version) .. "\n\n" ..
        L("Download winmm.dll from the release page, replace bin\\win64\\winmm.dll in your game folder, then restart Garry's Mod. The Workshop package updates automatically; only this file needs a manual update."))
    body:Dock(TOP)
    body:DockMargin(px(16), px(18), px(16), px(12))
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    local actions = vgui.Create("DPanel", frame)
    actions:Dock(BOTTOM)
    actions:SetTall(px(154))
    actions:SetPaintBackground(false)
    local function button(label, action)
        local item = vgui.Create("DButton", actions)
        item:Dock(TOP)
        item:DockMargin(px(16), px(5), px(16), 0)
        item:SetTall(px(42))
        item:SetFont("NativeLoaderUpdate")
        item:SetText(label)
        item.DoClick = function() action() frame:Close() end
    end
    button(L("Open the download page"), function() gui.OpenURL(release.url) end)
    button(L("Later"), function() end)
    button(string.format(L("Don't remind me about %s"), release.version), function()
        file.CreateDir("native-loader")
        file.Write("native-loader/loader-update-ignored.txt", release.version)
    end)
    file.CreateDir("native-loader")
    file.Write("native-loader/loader-update-seen.txt", token)
end
hook.Add("InitPostEntity", "nativeloader_loader_update", function()
    timer.Simple(4, function()
        local ok, err = pcall(loader_reminder)
        if not ok then say("loader update reminder unavailable: " .. tostring(err)) end
    end)
end)
