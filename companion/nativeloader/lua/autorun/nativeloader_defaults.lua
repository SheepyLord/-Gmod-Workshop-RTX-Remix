-- First-run defaults for the RTX add-ons' settings (ADR 0020). The values come from the classic RTX
-- install (nativeloader/classic_defaults.lua). Once per table version and realm, a setting still at
-- its add-on's own default gets the classic value; a value the player chose is never touched.
-- "nativeloader_rtx_defaults" applies every classic value again (the server half in single-player
-- or for an admin), for a player who wants the classic look back.
AddCSLuaFile()
AddCSLuaFile("nativeloader/classic_defaults.lua")

local defaults = include("nativeloader/classic_defaults.lua")
local realm = SERVER and "server" or "client"
local MARKER_FOLDER = "nativeloader_companion"
-- Settings the RTX fixes keep as cookies (cl.db), not console variables, with the classic install's
-- value. Only the forced command sets them: a cookie that exists was set by the player.
local CLASSIC_COOKIES = { r_forcehwskin = "0" }
local marker = MARKER_FOLDER .. "/classic_defaults_" .. realm .. "_v" .. defaults.version .. ".txt"

local function same(a, b)
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < 1e-6 end
    return a == b
end

-- R20: saved copies of both old sky defaults move together once. Run synchronously, just after
-- the sky creates its ConVars and before it installs callbacks/starts its clock: this is a default
-- migration, not a player edit that takes a map add-on's sky over. SetString is immediate, unlike
-- queued RunConsoleCommand. A skipped pair is marked too, preserving every later player choice.
if CLIENT then
    hook.Add("NativeLoaderSkyDefaults", "nativeloader_defaults", function()
        local skyMarker = MARKER_FOLDER .. "/sky_defaults_client_v1.txt"
        if file.Exists(skyMarker, "DATA") then return end
        local passes = GetConVar("nativeloader_sky_time_passes")
        local minutes = GetConVar("nativeloader_sky_day_minutes")
        if not passes or not minutes then return end
        local changed = tonumber(passes:GetString()) == 0 and tonumber(minutes:GetString()) == 30
        if changed then
            passes:SetString("1")
            minutes:SetString("20")
        end
        file.CreateDir(MARKER_FOLDER)
        file.Write(skyMarker, changed and "migrated 0/30 to 1/20\n" or "kept player settings\n")
    end)
end

-- Sets the classic values; only those still at the add-on's default unless `all`. Returns how many
-- settings changed and how many of the table's settings exist in this session.
local function apply(all)
    local changed, present = 0, 0
    for name, value in SortedPairs(defaults[realm] or {}) do
        local convar = GetConVar(name)
        if convar then
            present = present + 1
            local current = convar:GetString()
            if not same(current, value) and (all or same(current, convar:GetDefault())) then
                RunConsoleCommand(name, value)
                changed = changed + 1
            end
        end
    end
    return changed, present
end

local function first_run()
    if file.Exists(marker, "DATA") then return end
    local changed, present = apply(false)
    -- Without RTX the RTX add-ons are left out of the session (ADR 0013) and their settings do not
    -- exist: try again in the next session that has them.
    if present == 0 then return end
    file.CreateDir(MARKER_FOLDER)
    file.Write(marker, os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. changed .. " of " .. present .. "\n")
    -- MsgN, not MsgC: coloured text does not reach console.log (-condebug).
    MsgN(string.format("[nativeloader] %s: %d of %d RTX settings set to the classic RTX install's values " ..
        "(first run). nativeloader_rtx_defaults applies all of them again.", realm, changed, present))
end

-- The RTX add-ons create their settings while they load; wait until the session is up.
hook.Add(SERVER and "Initialize" or "InitPostEntity", "nativeloader_defaults", function()
    timer.Simple(5, first_run)
end)

if SERVER then
    concommand.Add("nativeloader_rtx_defaults_server", function(ply)
        if IsValid(ply) and not (game.SinglePlayer() or ply:IsSuperAdmin()) then return end
        local changed, present = apply(true)
        print(string.format("[nativeloader] server: %d of %d RTX settings set to the classic values.", changed, present))
    end)
else
    concommand.Add("nativeloader_rtx_defaults", function()
        local changed, present = apply(true)
        for name, value in pairs(CLASSIC_COOKIES) do
            if cookie.GetString(name, value) ~= value then
                cookie.Set(name, value)
                changed = changed + 1
            end
        end
        print(string.format("[nativeloader] client: %d of %d RTX settings set to the classic values " ..
            "(hardware skinning follows at the next map).", changed, present))
        RunConsoleCommand("nativeloader_rtx_defaults_server")
    end)
end
