-- nativeloader: prints the native loader's start-up and session status to the console, once when
-- the client starts and again on the console command nativeloader_status. It reads
-- garrysmod/data/native-loader/status.json and session.json, which the loader's bootstrap
-- (bin/win64/winmm.dll) writes, and (M6) says when a Workshop package has a newer version that the
-- next start deploys (steamworks.FileInfo, every ten minutes). No file writes, no game hooks.
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
local announced = {}
local function check_updates(status)
    if not steamworks or not steamworks.FileInfo then return end
    for _, package in ipairs(list(field(status, "packages"))) do
        local id, item, deployed = field(package, "id"), field(package, "label"), tonumber(field(package, "time_updated"))
        if field(package, "source") == "workshop" and item and deployed and not announced[item] then
            steamworks.FileInfo(item, function(info)
                local updated = info and tonumber(info.updated)
                if not updated or updated <= deployed or announced[item] then return end
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
