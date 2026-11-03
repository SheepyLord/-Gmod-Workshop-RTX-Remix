-- The sky in RTX sessions (ADR 0031, ADR 0032). The runtime has a physical sky (rtx.skyMode 1:
-- Hillaire scattering with volumetric clouds, stars and moons) that the RTX fixes leave off. This
-- turns it on and drives it: the sun, the moon and the stars for a time of day (by default the time
-- and direction of the map's own sun), a clock that can run, the moon's phase and lunar and solar
-- eclipses, the real night sky or the procedural one, and the runtime's twelve weather presets
-- blended into each other. Everything goes to Remix through the RTX fixes'
-- RemixConfig.SetConfigVariable. The settings are saved client settings (nativeloader_sky*,
-- nativeloader_weather*), shown in the RTX Remix tab under "Sky and weather". Documented in
-- nativeloader_sky.lua.md beside this file.
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("nativeloader/sky_model.lua")
    AddCSLuaFile("nativeloader/weather_presets.lua")
    return
end

local model = include("nativeloader/sky_model.lua")
local presets = include("nativeloader/weather_presets.lua")
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N

local DEFAULTS = {
    nativeloader_sky = "1", nativeloader_sky_follow_map = "1", nativeloader_sky_hour = "14.5",
    nativeloader_sky_direction = "0", nativeloader_sky_time_passes = "0", nativeloader_sky_day_minutes = "30",
    nativeloader_sky_season = "summer", nativeloader_sky_moon = "full",
    nativeloader_sky_eclipse = "", nativeloader_sky_eclipse_amount = "100", nativeloader_sky_stars = "map",
    nativeloader_weather = "partlyCloudy", nativeloader_weather_seconds = "30", nativeloader_sky_interval = "0.02",
}
local HELP = {
    nativeloader_sky = "Sky in RTX sessions: 1 the physical sky (sun, clouds, stars, moon), 0 the map's own skybox",
    nativeloader_sky_follow_map = "1: the time of day and the sun's direction come from the map's own sun",
    nativeloader_sky_hour = "Time of day in hours, 0-24 (with nativeloader_sky_follow_map 0)",
    nativeloader_sky_direction = "Turns the sun's path around the sky, in degrees (with nativeloader_sky_follow_map 0)",
    nativeloader_sky_time_passes = "1: the time of day runs on",
    nativeloader_sky_day_minutes = "Real minutes for a whole day while the time runs on",
    nativeloader_sky_season = "spring, summer, autumn or winter: how high the sun climbs and how long the day is",
    nativeloader_sky_moon = "Moon phase: new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, "
        .. "lastQuarter or waningCrescent",
    nativeloader_sky_eclipse = "Eclipse: lunar or solar; empty for none. It sets the moon's phase",
    nativeloader_sky_eclipse_amount = "How far through the eclipse, 0-100: lunar total from 70, solar from 90",
    nativeloader_sky_stars = "Night sky: map (the night sky image: stars, galaxy and nebulae) or procedural",
    nativeloader_weather = "Weather: clear, partlyCloudy, overcast, hazy, foggy, drizzle, rainstorm, thunderstorm, "
        .. "snow, blizzard, sandstorm, smoggy; empty leaves clouds, fog and rain to Remix's own settings",
    nativeloader_weather_seconds = "Seconds a change of weather takes",
    nativeloader_sky_interval = "Seconds between updates of the sun, moon, stars and weather, 0-1: 0.02 is 50 a second, "
        .. "0 every frame",
}
local cv = {}
for name, value in pairs(DEFAULTS) do cv[name] = CreateClientConVar(name, value, true, false, HELP[name]) end

-- How often the sky moves on (R3-015): every frame, as games move their sky, would be 0; 0.02 keeps a
-- running clock smooth at a fraction of the calls.
local function interval()
    return math.Clamp(cv.nativeloader_sky_interval:GetFloat(), 0, 1)
end

-- How the look of the physical sky differs from the runtime's defaults, whatever the weather
-- (tuned in the PoC, RESEARCH.md section 28).
local LOOK = {
    ["rtx.atmosphere.timeCycleEnable"] = "False", -- the sun is placed from here
    ["rtx.atmosphere.moon0.enabled"] = "True",
    -- Cumulus-shaped cloud shadows drifting over the ground (the runtime's default; the classic
    -- install's settings, which the package's defaults carry, turned them off).
    ["rtx.atmosphere.cloudVoxelShadowsEnable"] = "True",
    -- A moon about three times the real one's 0.52 degrees (the runtime's 3.5 is a stylised giant),
    -- a touch cool. Its ground light is MOONLIGHT below. The option holds the diameter.
    ["rtx.atmosphere.moon0.angularRadius"] = "1.6",
    ["rtx.atmosphere.moon0.color"] = "0.11, 0.12, 0.135",
    -- The real Moon's face (the runtime's moon textures; on by default there too), its relief at 0.6:
    -- at the full 1 the terminator broke into dark notches when zoomed in (RESEARCH.md section 29).
    ["rtx.atmosphere.moonTextureEnable"] = "True",
    ["rtx.atmosphere.moonReliefStrength"] = "0.6",
    -- The eclipse geometry the stages of sky_model.eclipseSeparation assume.
    ["rtx.atmosphere.eclipseEnable"] = "True",
    ["rtx.atmosphere.eclipseUmbraScale"] = tostring(model.ECLIPSE.umbra),
    ["rtx.atmosphere.eclipsePenumbraScale"] = tostring(model.ECLIPSE.penumbra),
    ["rtx.atmosphere.eclipseSunScale"] = tostring(model.ECLIPSE.sun),
}
local MOON_RADIUS = tonumber(LOOK["rtx.atmosphere.moon0.angularRadius"]) / 2
-- The moon's light on the ground (rtx.atmosphere.surfaceMoonBrightness, 50 in the runtime). It falls
-- with the disc's area (moonSolidAngleSr), so (3.5 / 1.6)^2 times as much keeps a full moon's night as
-- light as the runtime's default one. The runtime gives it full strength as soon as the sun is below
-- the horizon, so a rising full moon lit the towers orange at dusk; it fades in with the twilight
-- instead, from none with the sun 4 degrees down to all of it at 12 (nautical twilight), when real
-- moonlight starts to matter.
local MOONLIGHT = 240
local function moonlight(sunElevation)
    return MOONLIGHT * model.ease((-sunElevation - 4) / 8)
end

-- GMod's scale. Remix takes 100 units for a metre (rtx.sceneScale 1), and a GMod unit is 1.905 cm,
-- so a Remix metre is 1.905 real ones and a whole map is a few dozen Remix metres across.
--   * Fog. The presets' fog is made for worlds kilometres wide and barely shows inside a map; each
--     weather's fog is set from how far one sees in it, in real metres, keeping the preset's tint.
--     Denser fog turns dark here: the runtime lights its froxel fog from lights only, not from the
--     sky, so the visibilities stay at 300 m or more.
--   * Rain and snow fall from a smaller volume around the player, so the same particles fall near
--     enough to be seen.
--   * The runtime's own test for cover (occludeUnderCover) traces up to 1 km of Remix distance,
--     100 000 units here, and a map's 3D skybox room hangs above most maps within that: it found
--     cover everywhere and no drop was ever born. The companion checks for cover with the game's
--     own trace instead (sheltered(), below) and lets the rain fade out under a roof.
local VISIBILITY = {
    clear = 13000, partlyCloudy = 8800, overcast = 4400, hazy = 1300, foggy = 400, drizzle = 880,
    rainstorm = 530, thunderstorm = 400, snow = 660, blizzard = 310, sandstorm = 320, smoggy = 670,
}
local WEATHER_LOOK = {
    ["rtx.weather.precipitation.spawnRadiusMeters"] = "8",
    ["rtx.weather.precipitation.spawnHeightMeters"] = "6",
    ["rtx.weather.precipitation.fallMarginMeters"] = "4",
    ["rtx.weather.precipitation.occludeUnderCover"] = "False",
    ["rtx.weather.precipitation.appearance.widthScale"] = "1.6",
}

-- The runtime's recommended weather variation per preset (dxvk-remix-gmod
-- docs/integrators/weather-presets.md, section 8): how fast and how far the cloud cover and the
-- wind wander.
local VARIATION = {
    clear = { 0.6, 0.5 }, partlyCloudy = { 1.0, 1.0 }, overcast = { 0.7, 0.7 }, hazy = { 0.8, 0.6 },
    foggy = { 0.5, 0.4 }, drizzle = { 1.2, 1.1 }, rainstorm = { 1.6, 1.4 }, thunderstorm = { 2.0, 1.6 },
    snow = { 0.9, 0.8 }, blizzard = { 1.8, 1.5 }, sandstorm = { 1.5, 1.6 }, smoggy = { 0.8, 0.7 },
}
-- The fields that wander (rtx_weather.cpp kDriftTable): cover and wind speed in proportion, the wind's
-- direction in degrees; the index seeds the noise.
local WANDER = { { "cloudCoverageMean", 0, 0.15, 0, 1 }, { "cloudWindSpeed", 6, 0.30, 0, math.huge },
    { "cloudWindDirection", 7, 10 } }

local function ready()
    return istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable)
end

-- Option -> text last given to Remix, so an unchanged value is not sent again.
local sent = {}
local function set(option, text)
    if sent[option] == text then return end
    local ok, result = pcall(RemixConfig.SetConfigVariable, option, text)
    if ok and result ~= false then sent[option] = text end
end

---------------------------------------------------------------- the map's sun

-- The map's own sun from its BSP entity lump (lump 0), and its sky texture's name.
local mapInfo
local function readMap()
    local info = {}
    local f = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
    if f then
        f:Seek(8)
        local offset, length = f:ReadLong(), f:ReadLong()
        if offset and length and offset > 0 and length > 0 and length < 32 * 1024 * 1024 then
            f:Seek(offset)
            local text = f:Read(length) or ""
            -- A compressed lump starts with "LZMA"; leave it to the fallbacks below.
            if string.sub(text, 1, 4) ~= "LZMA" then
                local entities = model.parseEntities(text, { light_environment = true, env_sun = true, worldspawn = true })
                info.sun = model.sunOfEntities(entities)
                for _, e in ipairs(entities) do
                    if e.classname == "worldspawn" then info.skyname = e.skyname end
                end
            end
        end
        f:Close()
    end
    if not info.sun and util.GetSunInfo then
        local sun = util.GetSunInfo()
        local d = sun and sun.direction
        if d and d:Length() > 0.5 then
            if d.z < 0 then d = -d end
            local elevation = math.deg(math.asin(math.Clamp(d.z / d:Length(), -1, 1)))
            if elevation > 0 then
                info.sun = { elevation = elevation, bearing = model.wrap360(90 - math.deg(math.atan2(d.y, d.x))) }
            end
        end
    end
    if not info.skyname then
        local skyname = GetConVar("sv_skyname")
        info.skyname = skyname and skyname:GetString() or ""
    end
    info.mood = model.skyTimeOfName(info.skyname)
    return info
end

---------------------------------------------------------------- where the sky is

local function season()
    return model.SEASONS[cv.nativeloader_sky_season:GetString()] or model.SEASONS.summer
end

local function eclipse()
    local kind = cv.nativeloader_sky_eclipse:GetString()
    return (kind == "lunar" or kind == "solar") and kind or nil
end

-- The moon's phase and its latitude off the ecliptic: an eclipse puts it full or new, as far into the
-- shadow or across the sun as the progress says; otherwise the chosen phase, clear of the shadow.
local function moonPhase()
    local kind = eclipse()
    local phase = model.eclipsePhase(kind)
    if not phase then phase = model.MOON_PHASES[cv.nativeloader_sky_moon:GetString()] or model.MOON_PHASES.full end
    local amount = math.Clamp(cv.nativeloader_sky_eclipse_amount:GetFloat() / 100, 0, 1)
    return phase, model.moonLatitude(kind, amount, MOON_RADIUS)
end

local function skyAt(hours, north)
    local phase, moonLatitude = moonPhase()
    return model.sky(hours, season(), phase, north, nil, moonLatitude)
end

-- The time and the north bearing that match the map: its sun in the afternoon, or for a map set at
-- dusk or at night (by its sky's name) the sun low or gone, with the map's light where the setting
-- sun or the moon stands.
local function followed()
    local day, sun = season(), mapInfo and mapInfo.sun
    local mood = mapInfo and mapInfo.mood
    if mood == "night" then
        local hours = 23
        if not sun then return hours, 0 end
        return hours, model.wrap360(sun.bearing - skyAt(hours, 0).moon.bearing)
    end
    if mood == "dusk" then
        local hours = model.timeForElevation(3, false, day)
        if not sun then return hours, 0 end
        return hours, model.wrap360(sun.bearing - skyAt(hours, 0).sun.bearing)
    end
    if not sun then return tonumber(DEFAULTS.nativeloader_sky_hour), 0 end
    return model.followMap(sun, day)
end

-- The settings changed by this file itself (to show the map's time and direction), so their change
-- callbacks do not take them for the player's.
local writing = {}
local function write(name, value)
    if cv[name]:GetString() == value then return end
    writing[name] = value
    RunConsoleCommand(name, value)
end

local clock -- the time of day now, in hours
local followHours, followNorth -- the map's time and north bearing, while the sky follows it
local function startClock()
    if cv.nativeloader_sky_follow_map:GetBool() then
        followHours, followNorth = followed()
        clock = followHours
        write("nativeloader_sky_hour", string.format("%.2f", followHours))
        write("nativeloader_sky_direction", string.format("%.1f", followNorth))
    else
        clock = model.parseClock(cv.nativeloader_sky_hour:GetString()) or tonumber(DEFAULTS.nativeloader_sky_hour)
        followHours, followNorth = nil, nil
    end
end

-- Whether a change of a setting is this file's own: what write() sent, or, while the sky follows the
-- map, a slider of the panel writing back the map's value as it shows it (rounded to its decimals:
-- two for the time, none for the direction). Only a real move takes the sky off the map's sun.
local function ours(name, value)
    if writing[name] == value then
        writing[name] = nil
        return true
    end
    local n = tonumber(value)
    if not n or not followNorth then return false end
    if name == "nativeloader_sky_hour" then return math.abs(n - followHours) < 0.006 end
    if name == "nativeloader_sky_direction" then return math.abs(model.wrap180(n - followNorth)) < 0.51 end
    return false
end

local function north()
    return followNorth or model.wrap360(cv.nativeloader_sky_direction:GetFloat())
end

local function now()
    return skyAt(clock or 12, north())
end

---------------------------------------------------------------- weather

local weather = { values = nil, from = nil, to = nil, began = 0, seconds = 0, name = nil }

-- A preset as GMod gets it: its fog distance from its visibility (VISIBILITY). The preset gives the
-- fog's transmittance colour over a measuring distance; the distance is chosen so that what one sees
-- fades to 5 % at the visibility (Koschmieder), with the colour's tint kept. The runtime reads the
-- colour as gamma-encoded sRGB and uses it linear (rtx_global_volumetrics.cpp, getVolumeArgs), so the
-- extinction is worked out from the linear colour too.
local function linear(c)
    return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
local tunedPresets = {}
local function presetValues(name)
    if tunedPresets[name] then return tunedPresets[name] end
    local values = presets.presets[name]
    if not values then return nil end
    local copy = {}
    for k, v in pairs(values) do copy[k] = v end
    local c, visibility = values.transmittanceColor, VISIBILITY[name]
    if c and visibility then
        local configured = ready() and RemixConfig.GetConfigVariable and tonumber(RemixConfig.GetConfigVariable("rtx.sceneScale"))
        local remixMetre = 1.905 * (configured and configured > 0 and configured or 1)
        local extinction = (-math.log(linear(c[1])) - math.log(linear(c[2])) - math.log(linear(c[3]))) / 3
        copy.transmittanceMeasurementDistanceMeters = extinction * (visibility / remixMetre) / 3
    end
    tunedPresets[name] = copy
    return copy
end

local function weatherName()
    local name = cv.nativeloader_weather:GetString()
    if name == "" or not presetValues(name) then return nil end
    return name
end

-- Whether the view is under cover: the game's trace straight up ends on something other than the
-- sky. Rain and snow fade out under a roof and back in outside (see WEATHER_LOOK).
local outdoors = 1
local function sheltered()
    local eye = EyePos()
    local tr = util.TraceLine({ start = eye, endpos = eye + Vector(0, 0, 32768), mask = MASK_SOLID, filter = LocalPlayer() })
    return tr.Hit and not tr.HitSky
end

-- A fog preset chosen under Remix settings (nativeloader_menu.lua) replaces the weather's fog.
local function fogPresetChosen()
    return hook.Run("NativeLoaderRemixFogOverride") == true
end

-- Under the night sky image the weather's airglow is turned down to this fraction: as in Skyrim, the
-- image's nebulae are the night's glow and the space between them is dark. The ground stays as light:
-- the image lights it about as much as the airglow did (RESEARCH.md section 29).
local IMAGE_AIRGLOW = 0.05
local function nightSkyImage()
    return cv.nativeloader_sky_stars:GetString() ~= "procedural"
end

-- The options this session's weather has set, which leaving the weather to Remix puts back.
local weatherSet = {}

local function pushWeather(values)
    for option, text in pairs(WEATHER_LOOK) do
        set(option, text)
        weatherSet[option] = true
    end
    local ownFog = fogPresetChosen()
    for _, field in ipairs(presets.fields) do
        local v = values[field.name]
        if field.name == "precipitationIntensity" and v then v = v * outdoors end
        if field.name == "nightSkyBrightness" and v and nightSkyImage() then v = v * IMAGE_AIRGLOW end
        if ownFog and string.find(field.option, "rtx.volumetrics.", 1, true) == 1 then
            -- Forget what was sent, so the weather's fog comes back once the preset is cleared.
            sent[field.option] = nil
        elseif v ~= nil then
            set(field.option, model.optionText(v, field.integer))
            weatherSet[field.option] = true
        end
    end
end

-- What an option goes back to when the weather is left to Remix again (R3-009): rtx.conf's value
-- (GetConfigVariable reads only that file), else what Remix has without it (weather_presets.lua: the
-- package's classic layer, else the runtime's default). The RTX fixes' per-map settings are not
-- known here and are not put back.
local function remixValue(option)
    local ok, configured = pcall(RemixConfig.GetConfigVariable or function() end, option)
    if ok and isstring(configured) and configured ~= "" then return configured end
    return presets.defaults[option]
end

local function releaseWeather()
    if not ready() then return end
    local ownFog = fogPresetChosen()
    for option in pairs(weatherSet) do
        -- A fog preset chosen under Remix settings keeps the fog it set.
        if not (ownFog and string.find(option, "rtx.volumetrics.", 1, true) == 1) then
            local text = remixValue(option)
            if text then set(option, text) end
        end
    end
    weatherSet = {}
end

-- The values now: the blend between two presets, plus the slow variation of the cover and the wind.
local function weatherNow(t)
    local values = {}
    local progress = weather.seconds > 0 and model.ease((t - weather.began) / weather.seconds) or 1
    for _, field in ipairs(presets.fields) do
        local a, b = weather.from[field.name], weather.to[field.name]
        values[field.name] = (progress >= 1 or a == nil) and b or model.blend(field.kind, a, b, progress)
    end
    local variation = VARIATION[weather.name]
    if variation then
        local phase = t * variation[1]
        for _, w in ipairs(WANDER) do
            local v, swing = values[w[1]], model.drift(phase, w[2]) * w[3] * variation[2]
            if w[4] then values[w[1]] = math.Clamp(v + swing * v, w[4], w[5]) else values[w[1]] = model.wrap360(v + swing) end
        end
    end
    return values, progress
end

local function setWeather(instantly)
    local name = weatherName()
    if not name then
        -- Left to Remix: what the weather set goes back to Remix's own values, not the last preset's.
        if weather.name then releaseWeather() end
        weather.name = nil
        return
    end
    local target = presetValues(name)
    local t = CurTime()
    weather.from = (not instantly and weather.values) or target
    weather.to, weather.name, weather.began = target, name, t
    weather.seconds = instantly and 0 or math.max(cv.nativeloader_weather_seconds:GetFloat(), 0)
end

---------------------------------------------------------------- whose sky it is

-- A map's own RTX add-on may set the sky itself (Modern House RTX does on modern_house, and puts its
-- settings back three times in the first minute). Such a sky is left alone unless the player changes
-- a sky setting in that session. Add-ons say so by answering the hook NativeLoaderSkyOwner with
-- their name.
local takenOver = false
local function owner()
    local name = hook.Run("NativeLoaderSkyOwner")
    if isstring(name) and name ~= "" then return name end
    if istable(MHRTX_Config) and game.GetMap() == "modern_house" then return "Modern House RTX" end
    return nil
end

local function inCharge()
    return ready() and (takenOver or not owner())
end

---------------------------------------------------------------- giving it to Remix

local physical -- what the sky is now: true physical, false the map's skybox, nil not set yet
local function pushSky()
    local want = cv.nativeloader_sky:GetBool()
    if want then
        set("rtx.skyMode", "1")
        -- The map's own sun reaches Remix as a fixed-function light; the atmosphere makes the sun.
        set("rtx.ignoreGameDirectionalLights", "True")
        for option, text in pairs(LOOK) do set(option, text) end
        -- The night sky: the runtime's night sky image (stars, galaxy, nebulae) or its procedural field.
        set("rtx.atmosphere.starMapEnable", nightSkyImage() and "True" or "False")
    elseif physical ~= false then
        set("rtx.skyMode", "0")
        local configured = RemixConfig.GetConfigVariable and RemixConfig.GetConfigVariable("rtx.ignoreGameDirectionalLights")
        set("rtx.ignoreGameDirectionalLights", (isstring(configured) and configured ~= "") and configured or "False")
    end
    physical = want
end

local function pushCelestial()
    local sky = now()
    set("rtx.atmosphere.sunElevation", string.format("%.3f", sky.sun.elevation))
    set("rtx.atmosphere.sunRotation", string.format("%.3f", sky.sun.bearing))
    set("rtx.atmosphere.moon0.elevation", string.format("%.3f", sky.moon.elevation))
    set("rtx.atmosphere.moon0.rotation", string.format("%.3f", sky.moon.bearing))
    set("rtx.atmosphere.moon0.phase", string.format("%.3f", sky.moon.phase))
    set("rtx.atmosphere.starRotation", string.format("%.3f", sky.stars.rotation))
    set("rtx.atmosphere.starAxisElevation", string.format("%.3f", sky.stars.poleElevation))
    set("rtx.atmosphere.starAxisRotation", string.format("%.3f", sky.stars.poleBearing))
    set("rtx.atmosphere.surfaceMoonBrightness", string.format("%.1f", moonlight(sky.sun.elevation)))
end

local function apply()
    if not inCharge() then return end
    pushSky()
    if physical then pushCelestial() end
    if weather.name then
        local values = weatherNow(CurTime())
        weather.values = values
        pushWeather(values)
    end
end

-- Everything again, as if nothing had been sent (after another add-on may have changed it).
local function applyAll()
    sent = {}
    apply()
end

-- The clock and the weather, every nativeloader_sky_interval seconds; what has not changed is not
-- sent again (set).
local lastTick
timer.Create("nativeloader_sky", interval(), 0, function()
    if not clock or not inCharge() then return end
    local t = RealTime()
    local dt = lastTick and math.max(t - lastTick, 0) or 0
    lastTick = t
    if cv.nativeloader_sky_time_passes:GetBool() then
        local minutes = math.max(cv.nativeloader_sky_day_minutes:GetFloat(), 0.1)
        clock = (clock + dt / (minutes * 60) * 24) % 24
    end
    if physical then pushCelestial() end
    if weather.name then
        local values = weatherNow(CurTime())
        weather.values = values
        if (values.precipitationIntensity or 0) > 0 then
            -- Half a second to fade, either way, however often this runs.
            local target, step = sheltered() and 0 or 1, math.min(dt * 2, 1)
            outdoors = target > outdoors and math.min(outdoors + step, target) or math.max(outdoors - step, target)
        end
        pushWeather(values)
    end
end)

-- A map's add-on that sets its sky again after the player took it over showed that sky until the
-- timer below put the player's back. Modern House RTX does so 23, 43 and 63 s after the map starts:
-- its afternoon sun came up for as long as 10 s in the middle of the player's night, and the daylight
-- then lingered in the image's temporal history wherever the camera had looked, a haze over the
-- stars with a straight edge where the view had turned (native loader review R5, 2026-10-31). An
-- add-on that runs the hook NativeLoaderSkySet after setting the sky gets the player's sky back in
-- the same tick; Modern House RTX's MHRTX.ApplySettings is wrapped to run it (again after a reload
-- of that add-on's Lua replaced it).
local function followMapAddon()
    if not (istable(MHRTX) and isfunction(MHRTX.ApplySettings)) or MHRTX.ApplySettings == MHRTX.nativeLoaderApply then return end
    local applySettings = MHRTX.ApplySettings
    MHRTX.nativeLoaderApply = function(...)
        applySettings(...)
        hook.Run("NativeLoaderSkySet")
    end
    MHRTX.ApplySettings = MHRTX.nativeLoaderApply
end
hook.Add("NativeLoaderSkySet", "nativeloader_sky", function()
    if takenOver and owner() and ready() then applyAll() end
end)

-- On a map whose add-on set the sky, once the player took it over: put it back every 10 s.
timer.Create("nativeloader_sky_owned", 10, 0, function()
    followMapAddon()
    if takenOver and owner() and ready() then applyAll() end
end)

---------------------------------------------------------------- settings changing

local function changed(name, _, value)
    if name == "nativeloader_sky_interval" then
        -- How often, not what: it does not take a map's sky over.
        timer.Adjust("nativeloader_sky", interval())
        return
    end
    if ours(name, value) or not clock then return end
    takenOver = true
    if name == "nativeloader_sky_hour" or name == "nativeloader_sky_direction" then
        if followNorth then
            -- Moving the time or the direction takes the sun off the map's: the other one keeps the
            -- map's value it shows.
            writing.nativeloader_sky_follow_map = "0"
            RunConsoleCommand("nativeloader_sky_follow_map", "0")
            followHours, followNorth = nil, nil
        end
        if name == "nativeloader_sky_hour" then clock = model.parseClock(value) or clock end
    elseif name == "nativeloader_sky_follow_map" then
        startClock()
    elseif name == "nativeloader_sky_time_passes" and value == "0" then
        -- Stopping the clock keeps the time it shows.
        write("nativeloader_sky_hour", string.format("%.2f", clock))
    elseif name == "nativeloader_sky_eclipse" and value ~= "" then
        -- An eclipse needs the right side of the horizon: a lunar one the night, a solar one the day.
        -- Choosing one moves the time there if it is not (and so off the map's sun).
        local elevation = now().sun.elevation
        local hours = (value == "lunar" and elevation > -8 and 0) or (value == "solar" and elevation < 15 and 12) or nil
        if hours then
            if followNorth then
                writing.nativeloader_sky_follow_map = "0"
                RunConsoleCommand("nativeloader_sky_follow_map", "0")
                followHours, followNorth = nil, nil
            end
            clock = hours
            write("nativeloader_sky_hour", string.format("%.2f", hours))
        elseif followNorth then
            startClock()
        end
    elseif (name == "nativeloader_sky_season" or name == "nativeloader_sky_moon" or name == "nativeloader_sky_eclipse"
        or name == "nativeloader_sky_eclipse_amount") and followNorth then
        startClock()
    elseif name == "nativeloader_weather" then
        setWeather(false)
    end
    apply()
end
for name in pairs(DEFAULTS) do cvars.AddChangeCallback(name, changed, "nativeloader_sky") end

local function start()
    followMapAddon()
    mapInfo = readMap()
    startClock()
    setWeather(true)
    applyAll()
end

hook.Add("InitPostEntity", "nativeloader_sky", function()
    start()
    -- Once more after the RTX fixes' per-map Remix settings (3-4 s after the map starts).
    timer.Simple(5, applyAll)
end)

---------------------------------------------------------------- commands

-- Named times: the sun's height before or after noon on the chosen season's day.
local NAMED = {
    sunrise = { 1, true }, morning = { 25, true }, afternoon = { 35, false }, golden = { 8, false },
    sunset = { 0.5, false }, dusk = { -5, false },
}
local function namedTime(name)
    name = string.lower(name or "")
    if name == "noon" then return 12 end
    if name == "midnight" or name == "night" then return name == "night" and 23 or 0 end
    local n = NAMED[name]
    if n then return model.timeForElevation(n[1], n[2], season()) end
    return model.parseClock(name)
end

concommand.Add("nativeloader_sky_time", function(_, _, args)
    local hours = namedTime(args[1])
    if not hours then
        print("[nativeloader] nativeloader_sky_time: hh:mm, hours (0-24) or one of sunrise, morning, noon, "
            .. "afternoon, golden, sunset, dusk, night, midnight")
        return
    end
    RunConsoleCommand("nativeloader_sky_hour", string.format("%.2f", hours))
end)

concommand.Add("nativeloader_sky_reset", function()
    for name, value in pairs(DEFAULTS) do RunConsoleCommand(name, value) end
    print("[nativeloader] Sky and weather settings back to their defaults.")
end)

concommand.Add("nativeloader_sky_status", function()
    local sky = now()
    local who = owner()
    print(string.format("[nativeloader] sky: %s; Remix API %s%s", cv.nativeloader_sky:GetBool() and "physical" or "the map's skybox",
        ready() and "ready" or "not available", who and ("; set by " .. who .. (takenOver and ", taken over" or "")) or ""))
    print(string.format("[nativeloader] time %s (%s)%s, %s; sun %.1f deg high at bearing %.1f; moon %.1f deg, %s",
        model.clock(clock or 0), cv.nativeloader_sky_follow_map:GetBool() and "the map's" or "chosen",
        cv.nativeloader_sky_time_passes:GetBool() and ", running" or "", cv.nativeloader_sky_season:GetString(),
        sky.sun.elevation, sky.sun.bearing, sky.moon.elevation,
        eclipse() and string.format("%s eclipse %d %%", eclipse(), cv.nativeloader_sky_eclipse_amount:GetInt())
            or cv.nativeloader_sky_moon:GetString()))
    print(string.format("[nativeloader] night sky %s", nightSkyImage() and "image" or "procedural"))
    local info = mapInfo or {}
    print(string.format("[nativeloader] map sky %q%s; map sun %s", info.skyname or "", info.mood and (" (" .. info.mood .. ")") or "",
        info.sun and string.format("%.1f deg high at bearing %.1f", info.sun.elevation, info.sun.bearing) or "none"))
    print(string.format("[nativeloader] weather %s", weather.name or "left to Remix"))
end)

---------------------------------------------------------------- the panel

NATIVELOADER_SKY = {
    clock = function() return clock end,
    -- The sun, moon and stars as given to Remix now (sky_model.sky's table). RemixConfig's
    -- GetConfigVariable reads rtx.conf from disk, not these live values.
    sky = function() return now() end,
    owner = owner,
    ready = ready,
    model = model,
    presets = presets,
}

local WEATHERS = {
    { N("Clear"), "clear" }, { N("Partly cloudy"), "partlyCloudy" }, { N("Overcast"), "overcast" },
    { N("Hazy"), "hazy" }, { N("Foggy"), "foggy" }, { N("Drizzle"), "drizzle" }, { N("Rain"), "rainstorm" },
    { N("Thunderstorm"), "thunderstorm" }, { N("Snow"), "snow" }, { N("Blizzard"), "blizzard" },
    { N("Sandstorm"), "sandstorm" }, { N("Smog"), "smoggy" },
}
local SEASONS = { { N("Spring"), "spring" }, { N("Summer"), "summer" }, { N("Autumn"), "autumn" }, { N("Winter"), "winter" } }
local MOONS = { { N("New moon"), "new" }, { N("Waxing crescent"), "waxingCrescent" },
    { N("First quarter"), "firstQuarter" }, { N("Waxing gibbous"), "waxingGibbous" }, { N("Full moon"), "full" },
    { N("Waning gibbous"), "waningGibbous" }, { N("Last quarter"), "lastQuarter" },
    { N("Waning crescent"), "waningCrescent" } }
local ECLIPSES = { { N("No eclipse"), "" }, { N("Lunar eclipse"), "lunar" }, { N("Solar eclipse"), "solar" } }
local STARS = { { N("Night sky image"), "map" }, { N("Simulated stars"), "procedural" } }
-- One row of buttons, about 55 pixels each: short names.
local TIMES = { { N("Sunrise"), "sunrise" }, { N("Morning"), "morning" }, { N("Noon"), "noon" },
    { N("Sunset"), "sunset" }, { N("Night"), "night" } }

local function combo(panel, label, name, choices)
    local box = panel:ComboBox(L(label), name)
    for _, choice in ipairs(choices) do box:AddChoice(L(choice[1]), choice[2]) end
    return box
end

local function buildPanel(panel)
    if not ready() then
        panel:Help(L("The Remix API is not available in this session, so these settings cannot be applied. Run nativeloader_status for details."))
    end
    local who = owner()
    if who then
        panel:Help(string.format(L("On this map the sky is set by %s. Changing a setting here takes it over for this session."), who))
    end
    local sky = panel:ComboBox(L("Sky"), "nativeloader_sky")
    sky:AddChoice(L("Physical sky"), "1")
    sky:AddChoice(L("The map's skybox"), "0")
    panel:ControlHelp(L("The physical sky has a sun, clouds, stars and a moon, and lights the map from them."))
    panel:CheckBox(L("Follow the map's sun"), "nativeloader_sky_follow_map")
    panel:ControlHelp(L("Puts the sun where the map's own sun is. Moving Time of day or Sun direction turns this off."))
    panel:NumSlider(L("Time of day"), "nativeloader_sky_hour", 0, 24, 2)
    local nowLabel = panel:Help("")
    local think = nowLabel.Think
    nowLabel.Think = function(self)
        local text = clock and string.format(L("Now %s"), model.clock(clock)) or ""
        if self:GetText() ~= text then self:SetText(text) end
        if think then think(self) end
    end
    local row = vgui.Create("DPanel", panel)
    row:SetPaintBackground(false)
    row:SetTall(22)
    for _, t in ipairs(TIMES) do
        local button = vgui.Create("DButton", row)
        button:SetText(L(t[1]))
        button.DoClick = function() RunConsoleCommand("nativeloader_sky_time", t[2]) end
    end
    row.PerformLayout = function(self, w)
        local buttons = self:GetChildren()
        local width = math.floor((w - (#buttons - 1) * 4) / #buttons)
        for i, b in ipairs(buttons) do b:SetPos((i - 1) * (width + 4), 0) b:SetSize(width, 22) end
    end
    panel:AddItem(row)
    panel:NumSlider(L("Sun direction"), "nativeloader_sky_direction", 0, 360, 0)
    panel:ControlHelp(L("Turns the sun's path around the sky."))
    panel:CheckBox(L("Time passes"), "nativeloader_sky_time_passes")
    panel:NumSlider(L("Day length (min)"), "nativeloader_sky_day_minutes", 2, 240, 0)
    panel:ControlHelp(L("How many real minutes a whole day takes while Time passes is ticked."))
    panel:NumSlider(L("Sky update interval (s)"), "nativeloader_sky_interval", 0, 0.25, 3)
    panel:ControlHelp(L("How often the sun, moon, stars and weather move: 0.02 is 50 times a second, 0 is every frame. A longer interval saves a little time, but the sky moves in steps."))
    combo(panel, N("Season"), "nativeloader_sky_season", SEASONS)
    combo(panel, N("Moon"), "nativeloader_sky_moon", MOONS)
    combo(panel, N("Eclipse"), "nativeloader_sky_eclipse", ECLIPSES)
    panel:NumSlider(L("Eclipse progress"), "nativeloader_sky_eclipse_amount", 0, 100, 0)
    panel:ControlHelp(L("From first contact (0) to the middle (100): a lunar eclipse is total from 70, a solar one from 90. An eclipse sets the moon's phase, and the time if the sun is on the wrong side of the horizon for it."))
    combo(panel, N("Night sky"), "nativeloader_sky_stars", STARS)
    panel:ControlHelp(L("Night sky image: sharp stars, a galaxy and nebulae, turning with the time and the season."))
    local box = panel:ComboBox(L("Weather"), "nativeloader_weather")
    box:AddChoice(L("(leave to Remix)"), "")
    for _, choice in ipairs(WEATHERS) do box:AddChoice(L(choice[1]), choice[2]) end
    panel:ControlHelp(L("Clouds, haze, fog, rain and snow, from Remix's own weather presets."))
    panel:NumSlider(L("Weather change (s)"), "nativeloader_weather_seconds", 0, 300, 0)
    panel:ControlHelp(L("How long a change of weather takes."))
    panel:Button(L("Reset the sky and weather"), "nativeloader_sky_reset")
end

NATIVELOADER_SKY.buildPanel = buildPanel

hook.Add("PopulateToolMenu", "nativeloader_sky", function()
    spawnmenu.AddToolMenuOption("RTX Remix", N("Sky and weather"), "nativeloader_sky", L("Sky and weather"), "", "", buildPanel)
end)
