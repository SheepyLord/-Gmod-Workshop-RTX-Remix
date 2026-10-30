-- The sky's arithmetic, with no Garry's Mod functions in it (so it runs under plain LuaJIT in the
-- tests): where the sun, the moon and the stars stand for a time of day, where a map's own sun is,
-- and how weather values blend. Angles are degrees. A bearing is a compass direction in the map:
-- 0 = the map's +y, 90 = its +x, which is how the Remix atmosphere's rotation options count
-- (rtx.zUp). Documented in sky_model.lua.md beside this file.
local M = {}

local sin, cos, asin, acos, atan2 = math.sin, math.cos, math.asin, math.acos, math.atan2
local rad, deg, abs, floor, max, min = math.rad, math.deg, math.abs, math.floor, math.max, math.min

local OBLIQUITY = 23.44 -- tilt of the Earth's axis
M.LATITUDE = 40 -- the observer: a temperate northern latitude
M.SEASONS = { spring = 80, summer = 172, autumn = 266, winter = 355 } -- days of the year
-- Moon phases: 0 new, 0.5 full (the runtime's convention), waxing before full and waning after.
-- The runtime lights the Moon from the sun's side of the sky, so a waxing Moon is bright on the
-- west, towards the set sun, and a waning one on the east.
M.MOON_PHASES = {
    new = 0, waxingCrescent = 0.15, firstQuarter = 0.25, waxingGibbous = 0.35, full = 0.5,
    waningGibbous = 0.65, lastQuarter = 0.75, waningCrescent = 0.85,
}
-- Earth's shadow and the drawn sun in Moon radii: the runtime's eclipse geometry
-- (rtx.atmosphere.eclipseUmbraScale, eclipsePenumbraScale, eclipseSunScale), which the companion
-- sets to these so the stages below line up with what the runtime draws.
M.ECLIPSE = { umbra = 2.65, penumbra = 4.8, sun = 0.97 }

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
local function wrap360(a) return a % 360 end
local function wrap180(a) return (a + 180) % 360 - 180 end
M.clamp, M.wrap360, M.wrap180 = clamp, wrap360, wrap180

-- Ecliptic longitude of the sun on a day of the year (0 at the March equinox, day 80).
local function sunLongitude(day) return 360 * (day - 80) / 365.25 end

-- Right ascension and declination of a point at ecliptic `longitude` and `latitude` (0: on it).
local function equatorial(longitude, latitude)
    local l, b, e = rad(longitude), rad(latitude or 0), rad(OBLIQUITY)
    local ra = atan2(sin(l) * cos(b) * cos(e) - sin(b) * sin(e), cos(l) * cos(b))
    local dec = asin(clamp(sin(b) * cos(e) + cos(b) * sin(e) * sin(l), -1, 1))
    return wrap360(deg(ra)), deg(dec)
end

-- Elevation and azimuth (from north, clockwise) of a body at an hour angle (0 = due south at its
-- highest, positive afterwards) and declination, for a latitude. The runtime's own day cycle uses
-- the same model (RtxAtmosphere::computeTimeCycleSunAngles).
function M.horizontal(hourAngle, declination, latitude)
    local sl, cl = sin(rad(latitude)), cos(rad(latitude))
    local sd, cd = sin(rad(declination)), cos(rad(declination))
    local h = rad(hourAngle)
    local se = clamp(sl * sd + cl * cd * cos(h), -1, 1)
    local elevation = asin(se)
    local denominator = cos(elevation) * cl
    local azimuth = 0
    if abs(denominator) > 1e-6 then
        azimuth = deg(acos(clamp((sd - se * sl) / denominator, -1, 1)))
        if wrap180(hourAngle) > 0 then azimuth = 360 - azimuth end
    end
    return deg(elevation), azimuth
end

-- The whole sky at `hours` (0-24) on `day` (1-365): the sun, the moon of `phase` (0-1) and the
-- stars' turn, with the map's north at `north` (a bearing). `moonLatitude` puts the moon that many
-- degrees north of the ecliptic (its orbit is tilted; see moonLatitude below); 0 when left out.
-- Returns a table:
--   sun = { elevation, bearing }, moon = { elevation, bearing, phase },
--   stars = { rotation, poleElevation, poleBearing }
function M.sky(hours, day, phase, north, latitude, moonLatitude)
    latitude = latitude or M.LATITUDE
    local lambda = sunLongitude(day)
    local raSun, decSun = equatorial(lambda)
    local hourSun = (hours - 12) * 15
    local sunElevation, sunAzimuth = M.horizontal(hourSun, decSun, latitude)
    -- The moon is `phase` of a turn east of the sun along the ecliptic: new beside the sun, full
    -- opposite it, rising as the sun sets.
    local raMoon, decMoon = equatorial(lambda + 360 * phase, moonLatitude)
    local moonElevation, moonAzimuth = M.horizontal(hourSun - wrap180(raMoon - raSun), decMoon, latitude)
    -- The stars turn about the celestial pole with the local sidereal time (the sun's right ascension
    -- plus its hour angle). The runtime rotates the sky direction it samples, so the field appears
    -- to turn the other way: hence the minus.
    local sidereal = raSun + hourSun
    return {
        sun = { elevation = sunElevation, bearing = wrap360(sunAzimuth + north) },
        moon = { elevation = moonElevation, bearing = wrap360(moonAzimuth + north), phase = phase },
        stars = { rotation = wrap360(-sidereal), poleElevation = latitude, poleBearing = wrap360(north) },
    }
end

local function sunDeclination(day) return select(2, equatorial(sunLongitude(day))) end

---------------------------------------------------------------- eclipses

-- How far the moon's centre is from the centre of Earth's shadow (lunar) or from the sun's (solar),
-- in degrees, `amount` (0-1) of the way through an eclipse of a moon of `radius` degrees. The stages
-- get set stretches of the way rather than equal ones, so the dramatic part has room:
--   lunar: 0 first touches the penumbra, 0.3 first touches the umbra, 0.7 is wholly inside it
--          (total), 1 is the middle of the shadow;
--   solar: 0 first touches the sun, 0.9 covers it (total; for a sun larger than the moon, annular),
--          1 is centred.
local LUNAR_STAGES = { { 0, "penumbra", 1 }, { 0.3, "umbra", 1 }, { 0.7, "umbra", -1 }, { 1, nil, 0 } }
local SOLAR_STAGES = { { 0, "sun", 1 }, { 0.9, "sun", -1 }, { 1, nil, 0 } }
function M.eclipseSeparation(kind, amount, radius)
    local stages = kind == "solar" and SOLAR_STAGES or LUNAR_STAGES
    amount = clamp(amount, 0, 1)
    -- Each stage is a contact: a shadow (or sun) radius plus (1) or minus (-1) the moon's.
    local function at(stage)
        if not stage[2] then return 0 end
        return abs(M.ECLIPSE[stage[2]] + stage[3]) * radius
    end
    for i = 1, #stages - 1 do
        local a, b = stages[i], stages[i + 1]
        if amount <= b[1] then
            return at(a) + (at(b) - at(a)) * (amount - a[1]) / (b[1] - a[1])
        end
    end
    return 0
end

-- The phase an eclipse needs (full for a lunar one, new for a solar one), or nil for no eclipse.
function M.eclipsePhase(kind)
    if kind == "lunar" then return 0.5 end
    if kind == "solar" then return 0 end
    return nil
end

-- The moon's ecliptic latitude, in degrees. In an eclipse, its distance from the shadow or the sun
-- (eclipseSeparation). Otherwise just clear of the penumbra: the runtime draws an eclipse wherever
-- the geometry has one, and a full moon on the ecliptic would sit in the middle of the shadow every
-- month (the real one passes up to 5.1 degrees north or south of it and so mostly misses).
function M.moonLatitude(kind, amount, radius)
    if kind == "lunar" or kind == "solar" then return M.eclipseSeparation(kind, amount, radius) end
    return (M.ECLIPSE.penumbra + 1) * radius + 1
end

-- The time of day at which the sun stands `elevation` degrees high, before noon (`morning`) or after.
-- A sun that never climbs that high gives noon; one that never sinks that low, midnight.
function M.timeForElevation(elevation, morning, day, latitude)
    latitude = latitude or M.LATITUDE
    local dec = sunDeclination(day)
    local sl, cl = sin(rad(latitude)), cos(rad(latitude))
    local sd, cd = sin(rad(dec)), cos(rad(dec))
    local c = (sin(rad(elevation)) - sl * sd) / (cl * cd)
    if c >= 1 then return 12 end
    if c <= -1 then return morning and 0 or 24 end
    local hourAngle = deg(acos(c))
    return morning and 12 - hourAngle / 15 or 12 + hourAngle / 15
end

-- The sun of a map: what its light_environment says, as an elevation and a bearing. `pitch` is the
-- entity's pitch key (or its angles' pitch): negative points the light down. `yaw` is where the
-- light shines; the sun is on the other side. Nil for a light that does not shine down.
function M.mapSun(pitch, yaw)
    pitch, yaw = tonumber(pitch), tonumber(yaw)
    if not pitch or not yaw then return nil end
    local elevation = -pitch
    if elevation <= 0 or elevation > 90 then return nil end
    return { elevation = elevation, bearing = wrap360(270 - yaw) }
end

-- The afternoon time and the north bearing that put the sun where a map's own sun is on `day` (a
-- sun higher than that day's noon sun: noon, in the map sun's direction).
function M.followMap(sun, day, latitude)
    latitude = latitude or M.LATITUDE
    local hours = M.timeForElevation(sun.elevation, false, day, latitude)
    local _, azimuth = M.horizontal((hours - 12) * 15, sunDeclination(day), latitude)
    return hours, wrap360(sun.bearing - azimuth)
end

-- The entities of a BSP entity lump (its text), as key/value tables; only those whose classname is
-- in `classes` (a set) when given.
function M.parseEntities(text, classes)
    local found = {}
    for block in string.gmatch(text, "{(.-)}") do
        local entity = {}
        for key, value in string.gmatch(block, '"([^"]*)"%s+"([^"]*)"') do entity[key] = value end
        if not classes or classes[entity.classname or ""] then found[#found + 1] = entity end
    end
    return found
end

-- The map's sun from its entities: the first light_environment (its pitch key wins over its angles'
-- pitch, as in VRAD), else the first env_sun. Nil without either.
function M.sunOfEntities(entities)
    for _, class in ipairs({ "light_environment", "env_sun" }) do
        for _, e in ipairs(entities) do
            if e.classname == class then
                local p, y = string.match(e.angles or "", "^%s*(%S+)%s+(%S+)")
                local sun = M.mapSun(e.pitch or p, y)
                if sun then return sun end
            end
        end
    end
    return nil
end

-- Sky texture names that mean the map is set at night or at dusk.
local NIGHT = { "night", "nite", "midnight", "dark", "starry", "stars", "space", "borealis", "moon" }
local DUSK = { "dusk", "sunset", "evening", "twilight" }
function M.skyTimeOfName(skyname)
    skyname = string.lower(skyname or "")
    for _, word in ipairs(NIGHT) do if string.find(skyname, word, 1, true) then return "night" end end
    for _, word in ipairs(DUSK) do if string.find(skyname, word, 1, true) then return "dusk" end end
    return nil
end

-- Hours as "hh:mm".
function M.clock(hours)
    local minutes = floor((hours % 24) * 60 + 0.5) % 1440
    return string.format("%02d:%02d", floor(minutes / 60), minutes % 60)
end

-- "14", "14.5", "14:30" or "2:30" as hours; nil for anything else.
function M.parseClock(text)
    text = tostring(text or "")
    local h, m = string.match(text, "^%s*(%d%d?):(%d%d)%s*$")
    if h then
        h, m = tonumber(h), tonumber(m)
        if h < 24 and m < 60 then return h + m / 60 end
        return nil
    end
    local n = tonumber(text)
    if n and n >= 0 and n <= 24 then return n end
    return nil
end

---------------------------------------------------------------- weather

-- One value between two presets' values, the way the runtime's blender does it (rtx_weather.cpp):
-- angles the short way round, fog distance in extinction (1/distance), switches at the midpoint,
-- colours per channel, the rest linearly.
function M.blend(kind, a, b, t)
    if kind == "step" then return t >= 0.5 and b or a end
    if type(a) == "table" then
        return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
    end
    if kind == "angle" then return wrap360(a + wrap180(b - a) * t) end
    if kind == "extinction" then
        local ea, eb = 1 / max(a, 1e-4), 1 / max(b, 1e-4)
        return 1 / max(ea + (eb - ea) * t, 1e-4)
    end
    return a + (b - a) * t
end

-- A value as Remix option text: True/False, "x, y, z", a whole number or a short decimal.
function M.optionText(v, integer)
    if type(v) == "boolean" then return v and "True" or "False" end
    if type(v) == "table" then return string.format("%.6g, %.6g, %.6g", v[1], v[2], v[3]) end
    if integer then return tostring(floor(v + 0.5)) end
    return string.format("%.6g", v)
end

-- Ease in and out (smoothstep) for a blend's progress.
function M.ease(t)
    t = clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

-- Slow weather variation: the runtime's drift noise (a sum of incommensurate sines with a 300 s base
-- period, rtx_weather.cpp driftNoise1D), about -1 to 1, for a field index.
function M.drift(seconds, index)
    local p = seconds / 300
    local seed = index * 0.618 + 100
    return 0.5 * sin(2 * math.pi * p + seed) + 0.3 * sin(2 * math.pi * p / 1.527 + seed * 1.731)
        + 0.2 * sin(2 * math.pi * p / 0.701 + seed * 2.331)
end

return M
