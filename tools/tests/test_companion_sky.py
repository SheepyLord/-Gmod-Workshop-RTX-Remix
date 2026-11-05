"""The companion's sky under LuaJIT: the arithmetic (companion/nativeloader/lua/nativeloader/sky_model.lua)
and the session logic (autorun/nativeloader_sky.lua) with the GMod functions it uses mocked: what it
gives Remix at the start of a map, a change of weather blending over time, the clock, a map whose
add-on sets the sky, the map's own skybox and a night map. Skipped when LuaJIT is not installed."""
import json
import math
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'companion' / 'nativeloader' / 'lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe']
                                          if p.is_file()), None)


def lua_string(data: bytes) -> str:
    """Any bytes as a Lua string literal (decimal escapes for everything but plain ASCII)."""
    return '"' + ''.join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else f'\\{b:03d}' for b in data) + '"'


def bsp(entities: str) -> bytes:
    """A BSP as far as the companion reads it: the header with lump 0 (the entity lump) and its text."""
    text = entities.encode('latin-1')
    header = b'VBSP' + struct.pack('<i', 20) + struct.pack('<iiii', 8 + 64 * 16, len(text), 0, 0) + bytes(16 * 63)
    return header + text


CONSTRUCT = ('{\n"skyname" "painted"\n"classname" "worldspawn"\n}\n'
             '{\n"pitch" "-56"\n"angles" "0 306 0"\n"_light" "242 234 218 560"\n"classname" "light_environment"\n}\n'
             '{\n"pitch" "-50"\n"angles" "0 306 0"\n"classname" "env_sun"\n}\n')

MODEL = r'''
local M = dofile(LUA .. "/nativeloader/sky_model.lua")
local function out(key, ...) local t = {} for i = 1, select("#", ...) do t[i] = string.format("%.4f", (select(i, ...))) end print(key .. " " .. table.concat(t, " ")) end
for name, day in pairs(M.SEASONS) do
  local s = M.sky(12, day, 0.5, 0).sun
  out("noon_" .. name, s.elevation, s.bearing, M.timeForElevation(-0.83, true, day), M.timeForElevation(-0.83, false, day))
end
local s = M.mapSun(-56, 306)
out("mapsun", s.elevation, s.bearing)
print("mapsun_up " .. tostring(M.mapSun(10, 0)) .. " " .. tostring(M.mapSun("x", 0)))
for i, sun in ipairs({ { 56, 324 }, { 20, 10 }, { 73, 200 }, { 85, 90 }, { 5, 270 } }) do
  local hours, north = M.followMap({ elevation = sun[1], bearing = sun[2] }, M.SEASONS.summer)
  local at = M.sky(hours, M.SEASONS.summer, 0.5, north).sun
  out("follow" .. i, hours, at.elevation, at.bearing)
end
for _, p in ipairs({ 0, 0.25, 0.5 }) do
  local sky = M.sky(20, M.SEASONS.spring, p, 0)
  out("moon" .. p, sky.moon.elevation, sky.moon.bearing, sky.sun.elevation, sky.sun.bearing)
end
local a, b = M.sky(22, 172, 0.5, 30).stars, M.sky(23, 172, 0.5, 30).stars
out("stars", a.rotation, b.rotation, a.poleElevation, a.poleBearing)
local entities = M.parseEntities(CONSTRUCT, { light_environment = true, env_sun = true })
local sun = M.sunOfEntities(entities)
out("entities", #entities, sun.elevation, sun.bearing)
local only = M.sunOfEntities(M.parseEntities('{ "classname" "env_sun" "angles" "-40 90 0" }'))
out("env_sun", only.elevation, only.bearing)
print("none " .. tostring(M.sunOfEntities({})))
print("names " .. tostring(M.skyTimeOfName("sky_borealis01")) .. " " .. tostring(M.skyTimeOfName("sky_day01_01"))
  .. " " .. tostring(M.skyTimeOfName("Dusk_Sky")))
out("blend", M.blend("angle", 350, 10, 0.5), M.blend("extinction", 100, 1000, 0.5), M.blend("scalar", 1, 3, 0.25),
  M.blend("color", { 0, 1, 2 }, { 1, 1, 0 }, 0.5)[3])
print("step " .. tostring(M.blend("step", false, true, 0.49)) .. " " .. tostring(M.blend("step", false, true, 0.5)))
print("text " .. M.optionText(true) .. "|" .. M.optionText({ 0.5, 1, 0.25 }) .. "|" .. M.optionText(2.4, true)
  .. "|" .. M.optionText(0.00330001))
print("clock " .. M.clock(0) .. " " .. M.clock(13.999) .. " " .. M.clock(-1) .. " " .. tostring(M.parseClock("7:05"))
  .. " " .. tostring(M.parseClock("24:00")) .. " " .. tostring(M.parseClock("x")))
out("drift", M.drift(0, 0), M.drift(150, 0), M.drift(0, 6))
out("lunar", M.eclipseSeparation("lunar", 0, 0.8), M.eclipseSeparation("lunar", 0.3, 0.8),
  M.eclipseSeparation("lunar", 0.5, 0.8), M.eclipseSeparation("lunar", 0.7, 0.8), M.eclipseSeparation("lunar", 1, 0.8))
out("solar", M.eclipseSeparation("solar", 0, 0.8), M.eclipseSeparation("solar", 0.45, 0.8),
  M.eclipseSeparation("solar", 0.9, 0.8), M.eclipseSeparation("solar", 1, 0.8), M.moonLatitude(nil, 1, 0.8))
print("phases " .. tostring(M.eclipsePhase("lunar")) .. " " .. tostring(M.eclipsePhase("solar")) .. " "
  .. tostring(M.eclipsePhase(nil)) .. " " .. M.MOON_PHASES.waxingCrescent .. " " .. M.MOON_PHASES.waningCrescent)
-- The moon off the ecliptic: its distance from the antisolar point (full) or the sun (new) is its
-- latitude, whatever the hour and season.
local function dir(e, b) e, b = math.rad(e), math.rad(b) return { math.cos(e) * math.sin(b), math.sin(e), math.cos(e) * math.cos(b) } end
local function angle(a, b) return math.deg(math.acos(math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3])))) end
for i, case in ipairs({ { 0, M.SEASONS.summer, 0.5, 2.12 }, { 3, M.SEASONS.winter, 0.5, 5.64 }, { 12, M.SEASONS.spring, 0, 0.71 } }) do
  local sky = M.sky(case[1], case[2], case[3], 25, nil, case[4])
  local sun, moon = dir(sky.sun.elevation, sky.sun.bearing), dir(sky.moon.elevation, sky.moon.bearing)
  out("offset" .. i, angle(moon, case[3] == 0 and sun or { -sun[1], -sun[2], -sun[3] }))
end
'''

# GMod as far as nativeloader_sky.lua (and nativeloader/i18n.lua, which it includes) uses it. The
# console runs commands at once here; GMod runs them on the next frame, which the module allows for.
SESSION = r'''
CLIENT, SERVER = true, false
local calls = {}
RemixConfig = {
  SetConfigVariable = function(k, v) calls[#calls + 1] = { k, v } return true end,
  GetConfigVariable = function(k) return CONF[k] or "" end,
}
if NOAPI then RemixConfig = nil end
istable = function(v) return type(v) == "table" end
isfunction = function(v) return type(v) == "function" end
isstring = function(v) return type(v) == "string" end
local convars, callbacks, commands, hooks, timers = {}, {}, {}, {}, {}
function CreateClientConVar(name, default)
  -- PRESET: saved settings the session starts with, as GMod's client.vdf gives them.
  local c = { value = PRESET and PRESET[name] or default }
  function c:GetString() return self.value end
  function c:GetBool() return (tonumber(self.value) or 0) ~= 0 end
  function c:GetFloat() return tonumber(self.value) or 0 end
  function c:GetInt() return math.floor(tonumber(self.value) or 0) end
  convars[name] = c
  return c
end
function GetConVar(name)
  if name == "sv_skyname" then return { GetString = function() return SKYNAME or "" end } end
  return convars[name]
end
cvars = { AddChangeCallback = function(name, fn) callbacks[name] = callbacks[name] or {} table.insert(callbacks[name], fn) end }
function RunConsoleCommand(name, ...)
  local args = { ... }
  local c = convars[name]
  if c then
    local old = c.value
    c.value = tostring(args[1])
    if old ~= c.value then for _, fn in ipairs(callbacks[name] or {}) do fn(name, old, c.value) end end
  elseif commands[name] then
    commands[name](nil, name, args)
  end
end
concommand = { Add = function(name, fn) commands[name] = fn end }
local simple, delays = {}, {}
timer = {
  Create = function(name, delay, reps, fn) timers[name] = fn delays[name] = delay end,
  Adjust = function(name, delay) delays[name] = delay return timers[name] ~= nil end,
  Simple = function(delay, fn) simple[#simple + 1] = fn end,
  Remove = function(name) timers[name] = nil end,
}
hook = {
  Add = function(event, name, fn) hooks[event] = hooks[event] or {} hooks[event][name] = fn end,
  Run = function(event, ...)
    for _, fn in pairs(hooks[event] or {}) do local r = fn(...) if r ~= nil then return r end end
  end,
}
local now = 1000
function CurTime() return now end
function RealTime() return now end
local function bspFile(data)
  local pos = 0
  return {
    Seek = function(self, p) pos = p end,
    Read = function(self, n) local s = data:sub(pos + 1, pos + n) pos = pos + n return s end,
    ReadLong = function(self)
      local b1, b2, b3, b4 = data:byte(pos + 1, pos + 4) pos = pos + 4
      local v = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
      return v >= 2147483648 and v - 4294967296 or v
    end,
    Close = function() end,
  }
end
file = {
  Open = function(path) if BSP and path == "maps/" .. MAP .. ".bsp" then return bspFile(BSP) end end,
  Exists = function() return false end,
  Read = function() return nil end,
}
game = { GetMap = function() return MAP end }
local vector = {}
vector.__index = vector
vector.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vector) end
function Vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vector) end
function EyePos() return Vector(300, 288, -60) end
function LocalPlayer() return {} end
MASK_SOLID = 1
util = {
  GetSunInfo = function() return nil end,
  TraceLine = function() return { Hit = true, HitSky = not COVERED } end,
}
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
spawnmenu = { AddToolMenuOption = function() end }
function include(path) return dofile(LUA .. "/" .. path) end
function AddCSLuaFile() end
print = print

local M = dofile(LUA .. "/nativeloader/sky_model.lua")
dofile(LUA .. "/autorun/nativeloader_sky.lua")
-- The RTX Remix tab's Remix settings, for the fog presets.
if MENU then dofile(LUA .. "/autorun/client/nativeloader_menu.lua") end

local function value(option)
  for i = #calls, 1, -1 do if calls[i][1] == option then return calls[i][2] end end
  return nil
end
local function report(tag, ...)
  local parts = {}
  for _, option in ipairs({ ... }) do parts[#parts + 1] = option .. "=" .. tostring(value(option)) end
  print(tag .. " " .. #calls .. " " .. table.concat(parts, " "))
end
local function tick(seconds)
  now = now + seconds
  for _, fn in pairs(timers) do fn() end
end
local function cmd(name, ...) RunConsoleCommand(name, ...) end

for _, fn in pairs(hooks.InitPostEntity or {}) do fn() end
for _, fn in ipairs(simple) do fn() end
report("start", "rtx.skyMode", "rtx.ignoreGameDirectionalLights", "rtx.atmosphere.timeCycleEnable",
  "rtx.atmosphere.moon0.enabled", "rtx.atmosphere.sunElevation", "rtx.atmosphere.sunRotation",
  "rtx.atmosphere.cloudDensity", "rtx.volumetrics.transmittanceMeasurementDistanceMeters",
  "rtx.weather.precipitation.intensity", "rtx.atmosphere.starAxisElevation",
  "rtx.atmosphere.surfaceMoonBrightness")
print("convars " .. convars.nativeloader_sky_hour.value .. " " .. convars.nativeloader_sky_direction.value
  .. " " .. convars.nativeloader_sky_follow_map.value)
if SCRIPT == "ownership" then
  tick(1)
  report("owned")
  print("interval " .. tostring(delays.nativeloader_sky))
  cmd("nativeloader_sky_interval", "0.1")  -- how often, not what: the map's sky stays its own
  tick(1)
  report("adjusted")
  print("interval_now " .. tostring(delays.nativeloader_sky))
  cmd("nativeloader_weather", "overcast")
  tick(31)
  report("taken", "rtx.skyMode", "rtx.atmosphere.cloudDensity")
  return
end
if SCRIPT == "entry" then
  -- R16: the player chose a time (Follow the map's sun unticked). Modern House RTX loads after the map
  -- started, sets its sky once its own timer runs, and again later; the player's sky stays.
  report("entered", "rtx.skyMode", "rtx.atmosphere.sunElevation", "rtx.atmosphere.cloudDensity")
  MHRTX_Config = {}
  MHRTX = { ApplySettings = function()
    RemixConfig.SetConfigVariable("rtx.atmosphere.sunElevation", "21")
    RemixConfig.SetConfigVariable("rtx.atmosphere.cloudDensity", "4")
  end }
  tick(0.02)
  print("followed " .. tostring(MHRTX.ApplySettings == MHRTX.nativeLoaderApply))
  MHRTX.ApplySettings()
  report("after", "rtx.atmosphere.sunElevation", "rtx.atmosphere.cloudDensity")
  tick(1)
  report("later", "rtx.atmosphere.sunElevation")
  return
end
if SCRIPT == "follow" then
  -- Modern House RTX setting its sky again (its timer, 23, 43 and 63 s into the map) before and
  -- after the player took the sky over; no timer of the companion runs in between.
  MHRTX.ApplySettings(true)
  report("theirs", "rtx.atmosphere.sunElevation")
  cmd("nativeloader_sky_time", "midnight")
  report("mine", "rtx.atmosphere.sunElevation")
  MHRTX.ApplySettings(true)
  report("again", "rtx.atmosphere.sunElevation", "rtx.atmosphere.cloudDensity")
  print("followed " .. tostring(MHRTX.ApplySettings == MHRTX.nativeLoaderApply))
  -- A reload of the add-on's Lua replaces the function: wrapped again by the 10 s timer.
  MHRTX.ApplySettings = function() RemixConfig.SetConfigVariable("rtx.atmosphere.sunElevation", "35") end
  tick(10)
  MHRTX.ApplySettings(true)
  report("reloaded", "rtx.atmosphere.sunElevation")
  return
end
if SCRIPT == "release" then
  cmd("nativeloader_weather_seconds", "0")
  cmd("nativeloader_weather", "rainstorm")
  tick(0.25)
  report("rain", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity",
    "rtx.weather.precipitation.spawnRadiusMeters", "rtx.atmosphere.lightningStrikesPerMinute")
  cmd("nativeloader_weather", "")
  report("released", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity",
    "rtx.weather.precipitation.spawnRadiusMeters", "rtx.atmosphere.lightningStrikesPerMinute")
  local P = include("nativeloader/weather_presets.lua")
  print("defaults " .. P.defaults["rtx.weather.precipitation.spawnRadiusMeters"] .. " "
    .. P.defaults["rtx.atmosphere.lightningStrikesPerMinute"] .. " " .. P.defaults["rtx.weather.precipitation.intensity"])
  local before = #calls
  tick(10)
  print("quiet " .. (#calls - before))
  return
end
if SCRIPT == "skybox" then
  cmd("nativeloader_sky", "0")
  report("skybox", "rtx.skyMode", "rtx.ignoreGameDirectionalLights")
  return
end
if SCRIPT == "slider" then
  -- The panel's sliders write back what they show: the map's direction rounded to whole degrees,
  -- the time to two decimals. That is not the player moving them.
  local direction = convars.nativeloader_sky_direction.value
  cmd("nativeloader_sky_direction", tostring(math.floor(tonumber(direction) + 0.5)))
  cmd("nativeloader_sky_hour", convars.nativeloader_sky_hour.value)
  print("written_back " .. convars.nativeloader_sky_follow_map.value)
  cmd("nativeloader_sky_direction", tostring(tonumber(direction) + 30))
  print("moved " .. convars.nativeloader_sky_follow_map.value)
  return
end
if SCRIPT == "shelter" then
  cmd("nativeloader_weather_seconds", "0")
  cmd("nativeloader_weather", "rainstorm")
  tick(0.25)
  report("outside", "rtx.weather.precipitation.intensity", "rtx.weather.precipitation.occludeUnderCover")
  COVERED = true
  tick(0.25)
  report("fading", "rtx.weather.precipitation.intensity")
  tick(0.25)
  report("inside", "rtx.weather.precipitation.intensity", "rtx.atmosphere.cloudDensity")
  COVERED = false
  tick(0.25) tick(0.25)
  report("again", "rtx.weather.precipitation.intensity")
  return
end
if SCRIPT == "night" then
  report("moonlight_night", "rtx.atmosphere.surfaceMoonBrightness")
  cmd("nativeloader_sky_time", "dusk")
  report("moonlight_dusk", "rtx.atmosphere.surfaceMoonBrightness")
  cmd("nativeloader_sky_time", "night")
  local north = tonumber(convars.nativeloader_sky_direction.value)
  local sky = M.sky(23, M.SEASONS.summer, M.MOON_PHASES.full, north, nil, M.moonLatitude(nil, 1, 0.8))
  print(string.format("night %.2f %.2f %.2f", sky.moon.bearing, sky.moon.elevation, sky.sun.elevation))
  return
end
if SCRIPT == "eclipse" then
  local function dir(e, b) e, b = math.rad(e), math.rad(b) return { math.cos(e) * math.sin(b), math.sin(e), math.cos(e) * math.cos(b) } end
  local function angle(a, b) return math.deg(math.acos(math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3])))) end
  -- Where Remix was told the sun and the moon are: the moon's distance from the antisolar point and
  -- from the sun, the sun's height, the phase, and the time and follow settings.
  local function geometry(tag)
    local sun = dir(tonumber(value("rtx.atmosphere.sunElevation")), tonumber(value("rtx.atmosphere.sunRotation")))
    local moon = dir(tonumber(value("rtx.atmosphere.moon0.elevation")), tonumber(value("rtx.atmosphere.moon0.rotation")))
    print(string.format("%s %.3f %.3f %.3f %s %s %s", tag, angle(moon, { -sun[1], -sun[2], -sun[3] }), angle(moon, sun),
      tonumber(value("rtx.atmosphere.sunElevation")), value("rtx.atmosphere.moon0.phase"),
      convars.nativeloader_sky_hour.value, convars.nativeloader_sky_follow_map.value))
  end
  report("look", "rtx.atmosphere.eclipseEnable", "rtx.atmosphere.eclipseUmbraScale", "rtx.atmosphere.eclipsePenumbraScale",
    "rtx.atmosphere.eclipseSunScale", "rtx.atmosphere.moonTextureEnable", "rtx.atmosphere.starMapEnable",
    "rtx.atmosphere.nightSkyBrightness")
  geometry("plain")
  cmd("nativeloader_sky_eclipse", "lunar")
  geometry("lunar100")
  cmd("nativeloader_sky_eclipse_amount", "50")
  geometry("lunar50")
  cmd("nativeloader_sky_eclipse", "solar")
  geometry("solar50")
  cmd("nativeloader_sky_eclipse", "")
  geometry("none")
  cmd("nativeloader_sky_stars", "procedural")
  report("stars", "rtx.atmosphere.starMapEnable", "rtx.atmosphere.nightSkyBrightness")
  return
end
if SCRIPT == "fog" then
  -- (Colours hold spaces, so they are printed apart from report's option=value pairs.)
  cmd("nativeloader_remix_fog", "heavyFog")
  report("preset", "rtx.volumetrics.enable", "rtx.volumetrics.enableFogRemap",
    "rtx.volumetrics.transmittanceMeasurementDistanceMeters", "rtx.volumetrics.anisotropy")
  print("colours " .. value("rtx.volumetrics.transmittanceColor") .. "|" .. value("rtx.volumetrics.singleScatteringAlbedo"))
  cmd("nativeloader_weather", "foggy")
  tick(31)
  report("weather", "rtx.volumetrics.transmittanceMeasurementDistanceMeters", "rtx.atmosphere.cloudDensity")
  print("weather_colour " .. value("rtx.volumetrics.transmittanceColor"))
  cmd("nativeloader_remix_fog", "")
  tick(0.25)
  report("cleared", "rtx.volumetrics.transmittanceMeasurementDistanceMeters")
  return
end
cmd("nativeloader_weather", "rainstorm")
tick(15)
report("mid", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity")
tick(16)
report("end", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity", "rtx.atmosphere.lightningStrikesPerMinute")
local north = convars.nativeloader_sky_direction.value
cmd("nativeloader_sky_time", "18:00")
report("hour", "rtx.atmosphere.sunElevation", "rtx.atmosphere.sunRotation")
print("after " .. convars.nativeloader_sky_follow_map.value .. " " .. convars.nativeloader_sky_hour.value .. " "
  .. convars.nativeloader_sky_direction.value .. " " .. north)
local expect = M.sky(18, M.SEASONS.summer, M.MOON_PHASES.full, tonumber(north))
print(string.format("expect %.3f %.3f", expect.sun.elevation, expect.sun.bearing))
cmd("nativeloader_sky_day_minutes", "24")
cmd("nativeloader_sky_time_passes", "1")
for _ = 1, 240 do tick(0.25) end
cmd("nativeloader_sky_time_passes", "0")
print("clock " .. convars.nativeloader_sky_hour.value)
cmd("nativeloader_weather", "")
local before = #calls
tick(10)
print("left " .. (#calls - before))
cmd("nativeloader_sky_status")
'''


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class SkyTests(unittest.TestCase):
    def run_lua(self, body: str, **globals_) -> dict:
        with tempfile.TemporaryDirectory(dir=REPO / 'out' / 'tmp') as scratch:
            script = Path(scratch) / 'harness.lua'
            prelude = f'LUA = {json.dumps(str(LUA))}\nCONSTRUCT = {json.dumps(CONSTRUCT)}\nCONF = {{}}\n'
            for name, value in globals_.items():
                prelude += f'{name} = {lua_string(value) if isinstance(value, bytes) else json.dumps(value)}\n'
            script.write_text(prelude + body, encoding='utf-8')
            done = subprocess.run([LUAJIT, str(script)], capture_output=True, text=True, timeout=60, cwd=scratch)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        lines = {}
        for line in done.stdout.splitlines():
            key, _, rest = line.partition(' ')
            lines.setdefault(key, rest)
        return lines

    @staticmethod
    def numbers(text):
        return [float(v) for v in text.split()]

    def settings(self, text):
        return dict(part.split('=', 1) for part in text.split()[1:])

    def test_the_sun_moon_and_stars(self):
        out = self.run_lua(MODEL)
        # Latitude 40: the equinox's noon sun 50 degrees high in the south, summer's 73.4, winter's 26.6;
        # summer days run 04:30-19:30, winter ones 07:20-16:40 (sunrise and sunset at -0.83 degrees).
        for season, (elevation, rise, sets) in {'spring': (50.0, 5.93, 18.07), 'summer': (73.44, 4.50, 19.50),
                                                'winter': (26.58, 7.33, 16.67)}.items():
            noon = self.numbers(out['noon_' + season])
            self.assertAlmostEqual(noon[0], elevation, delta=0.2)
            self.assertAlmostEqual(noon[1], 180.0, delta=0.01)
            self.assertAlmostEqual(noon[2], rise, delta=0.05)
            self.assertAlmostEqual(noon[3], sets, delta=0.05)
        # gm_construct's light_environment (pitch -56, yaw 306): the sun 56 degrees high at bearing 324.
        self.assertEqual(self.numbers(out['mapsun']), [56.0, 324.0])
        self.assertEqual(out['mapsun_up'], 'nil nil')
        # Following the map puts the sun exactly where the map's is, in the afternoon; a sun higher
        # than summer's noon sun (85) gives noon, in the map sun's direction.
        for i, (elevation, bearing) in enumerate([(56, 324), (20, 10), (73, 200), (85, 90), (5, 270)], 1):
            hours, at_elevation, at_bearing = self.numbers(out[f'follow{i}'])
            self.assertGreaterEqual(hours, 12.0)
            self.assertAlmostEqual(at_bearing, bearing, delta=0.01)
            self.assertAlmostEqual(at_elevation, min(elevation, 73.44), delta=0.05)
        # At 20:00 in spring the sun has set; the full moon has risen opposite it, the new moon set with it.
        new, quarter, full = (self.numbers(out[f'moon{p}']) for p in ('0', '0.25', '0.5'))
        self.assertLess(full[2], 0)
        self.assertGreater(full[0], 0)
        self.assertAlmostEqual((full[1] - full[3]) % 360, 180, delta=15)
        self.assertLess(new[0], 0)
        self.assertGreater(quarter[0], new[0])
        # The stars turn 15 degrees an hour, the field the other way round; the pole stands at the
        # latitude in the north.
        a, b, pole, pole_bearing = self.numbers(out['stars'])
        self.assertAlmostEqual((a - b) % 360, 15.0, delta=0.01)
        self.assertEqual((pole, pole_bearing), (40.0, 30.0))
        self.assertEqual(self.numbers(out['entities']), [2.0, 56.0, 324.0])
        self.assertEqual(self.numbers(out['env_sun']), [40.0, 180.0])
        self.assertEqual(out['none'], 'nil')
        self.assertEqual(out['names'], 'night nil dusk')
        angle, extinction, scalar, colour = self.numbers(out['blend'])
        self.assertAlmostEqual(angle, 0.0, delta=1e-6)
        self.assertAlmostEqual(extinction, 1 / (0.5 * (1 / 100 + 1 / 1000)), delta=1e-3)
        self.assertEqual((scalar, colour), (1.5, 1.0))
        self.assertEqual(out['step'], 'false true')
        self.assertEqual(out['text'], 'True|0.5, 1, 0.25|2|0.00330001')
        self.assertEqual(out['clock'], '00:00 14:00 23:00 7.0833333333333 nil nil')
        d0, d150, d6 = self.numbers(out['drift'])
        self.assertTrue(-1 <= d0 <= 1 and -1 <= d150 <= 1 and d0 != d150 and d0 != d6)
        # Eclipse stages for a moon 0.8 degrees across its radius: lunar, the penumbra touched at 0, the
        # umbra at 0.3, the moon wholly inside it at 0.7, centred at 1; solar, the sun touched at 0 and
        # covered from 0.9. Without an eclipse the moon passes clear of the penumbra.
        self.assertEqual(self.numbers(out['lunar']), [4.64, 2.92, 2.12, 1.32, 0.0])
        s0, s45, s90, s100, clear = self.numbers(out['solar'])
        self.assertEqual((s0, s90, s100, clear), (1.576, 0.024, 0.0, 5.64))
        self.assertAlmostEqual(s45, (1.576 + 0.024) / 2, delta=1e-4)
        self.assertEqual(out['phases'], '0.5 0 nil 0.15 0.85')
        # The moon's ecliptic latitude is its distance from the shadow's centre (or the sun's).
        for i, expected in enumerate([2.12, 5.64, 0.71], 1):
            self.assertAlmostEqual(self.numbers(out[f'offset{i}'])[0], expected, delta=0.01)

    def test_a_map_start_turns_on_the_physical_sky_at_the_maps_sun(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='weather')
        start = self.settings(out['start'])
        self.assertEqual((start['rtx.skyMode'], start['rtx.ignoreGameDirectionalLights']), ('1', 'True'))
        self.assertEqual((start['rtx.atmosphere.timeCycleEnable'], start['rtx.atmosphere.moon0.enabled']), ('False', 'True'))
        self.assertAlmostEqual(float(start['rtx.atmosphere.sunElevation']), 56.0, delta=0.01)
        self.assertAlmostEqual(float(start['rtx.atmosphere.sunRotation']), 324.0, delta=0.01)
        self.assertEqual(start['rtx.atmosphere.starAxisElevation'], '40.000')
        # The default weather, partly cloudy, at once: its cloud density, its fog, no rain.
        self.assertEqual(start['rtx.atmosphere.cloudDensity'], '0.9')
        # Its fog from a visibility of 8.8 km at GMod's scale (a Remix metre is 1.905 real ones): the
        # distance over which the preset's transmittance colour (0.998, sRGB, which the runtime
        # uses linear) is measured.
        linear = ((0.998 + 0.055) / 1.055) ** 2.4
        self.assertAlmostEqual(float(start['rtx.volumetrics.transmittanceMeasurementDistanceMeters']),
                               -math.log(linear) * (8800 / 1.905) / 3, delta=1e-3)
        self.assertEqual(start['rtx.weather.precipitation.intensity'], '0')
        self.assertEqual(start['rtx.atmosphere.surfaceMoonBrightness'], '0.0')  # no moonlight by day
        hour, direction, follow = out['convars'].split()
        self.assertAlmostEqual(float(hour), 14.35, delta=0.01)  # 14:21, the panel shows the map's time
        self.assertEqual(follow, '1')
        # A change of weather blends over nativeloader_weather_seconds (30): halfway there at 15 s.
        mid, end = self.settings(out['mid']), self.settings(out['end'])
        self.assertTrue(0.9 < float(mid['rtx.atmosphere.cloudDensity']) < 2.5)
        self.assertTrue(0 < float(mid['rtx.weather.precipitation.intensity']) < 0.8)
        self.assertEqual((end['rtx.atmosphere.cloudDensity'], end['rtx.weather.precipitation.intensity'],
                          end['rtx.atmosphere.lightningStrikesPerMinute']), ('2.5', '0.8', '4'))
        # Choosing a time takes the sun off the map's: the direction stays the map's.
        hour = self.settings(out['hour'])
        follow, hours, direction_after, direction_before = out['after'].split()
        self.assertEqual((follow, hours, direction_after), ('0', '18.00', direction_before))
        elevation, bearing = self.numbers(out['expect'])
        self.assertAlmostEqual(float(hour['rtx.atmosphere.sunElevation']), elevation, delta=0.002)
        self.assertAlmostEqual(float(hour['rtx.atmosphere.sunRotation']), bearing, delta=0.002)
        # 60 s of a 24-minute day: an hour; stopping the clock keeps the time it got to.
        self.assertAlmostEqual(float(out['clock']), 19.0, delta=0.02)
        # Weather left to Remix: nothing more is sent for it (what it set went back at once, below).
        self.assertEqual(out['left'], '0')
        self.assertTrue(out['[nativeloader]'].startswith('sky: physical; Remix API ready'), out['[nativeloader]'])

    def test_weather_left_to_remix_puts_back_remixs_own_values(self):
        # R3-009: clearing the weather after Rain gave the options back their rtx.conf value, or what
        # Remix has without one (the package's layer, else the runtime's default); not the rain's.
        out = self.run_lua('CONF = { ["rtx.atmosphere.cloudDensity"] = "1.7" }\n' + SESSION, MAP='gm_construct',
                           BSP=bsp(CONSTRUCT), SCRIPT='release')
        rain, released = self.settings(out['rain']), self.settings(out['released'])
        self.assertEqual((rain['rtx.atmosphere.cloudDensity'], rain['rtx.weather.precipitation.intensity'],
                          rain['rtx.weather.precipitation.spawnRadiusMeters']), ('2.5', '0.8', '8'))
        radius, lightning, intensity = out['defaults'].split()
        self.assertEqual(released['rtx.atmosphere.cloudDensity'], '1.7')  # rtx.conf's
        self.assertEqual((released['rtx.weather.precipitation.intensity'], released['rtx.weather.precipitation.spawnRadiusMeters'],
                          released['rtx.atmosphere.lightningStrikesPerMinute']), (intensity, radius, lightning))
        self.assertEqual((intensity, lightning), ('0', '0'))
        self.assertEqual(out['quiet'], '0')

    def test_a_maps_own_sky_add_on_keeps_its_sky_until_the_player_changes_it(self):
        out = self.run_lua('MHRTX_Config = {}\n' + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='ownership')
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['owned'].split()[0], '0')
        # R3-015: 50 updates a second by default; changing how often does not take the map's sky over.
        self.assertEqual(out['interval'], '0.02')
        self.assertEqual((out['adjusted'].split()[0], out['interval_now']), ('0', '0.1'))
        taken = self.settings(out['taken'])
        self.assertEqual((taken['rtx.skyMode'], taken['rtx.atmosphere.cloudDensity']), ('1', '1.8'))

    def test_a_sky_taken_over_comes_back_at_once_when_the_maps_add_on_sets_its_own_again(self):
        # R5: Modern House RTX puts its afternoon sun back three times in the first minute; the
        # player's night used to wait up to 10 s for the companion's timer.
        add_on = ('MHRTX_Config = {}\nMHRTX = { ApplySettings = function()\n'
                  '  RemixConfig.SetConfigVariable("rtx.atmosphere.sunElevation", "35")\n'
                  '  RemixConfig.SetConfigVariable("rtx.atmosphere.cloudDensity", "4")\nend }\n')
        out = self.run_lua(add_on + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='follow')
        self.assertEqual(out['followed'], 'true')
        self.assertEqual(self.settings(out['theirs'])['rtx.atmosphere.sunElevation'], '35')
        mine = float(self.settings(out['mine'])['rtx.atmosphere.sunElevation'])
        self.assertLess(mine, -10)
        again = self.settings(out['again'])
        self.assertEqual(float(again['rtx.atmosphere.sunElevation']), mine)
        self.assertNotEqual(again['rtx.atmosphere.cloudDensity'], '4')
        self.assertEqual(float(self.settings(out['reloaded'])['rtx.atmosphere.sunElevation']), mine)

    def test_the_players_own_time_and_weather_apply_from_the_start_on_a_map_whose_add_on_sets_the_sky(self):
        # R16 (the user's item 44): with Follow the map's sun unticked, the player's sky is in charge from
        # the map's start; Modern House RTX, which loads later and sets its afternoon from its own timer,
        # is followed from its first sky on, and the player's sky comes back in the same call.
        preset = ('PRESET = { nativeloader_sky_follow_map = "0", nativeloader_sky_hour = "9.80", '
                  'nativeloader_weather = "clear" }\n')
        out = self.run_lua(preset + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='entry')
        entered = self.settings(out['entered'])
        self.assertEqual(entered['rtx.skyMode'], '1')
        mine = float(entered['rtx.atmosphere.sunElevation'])
        self.assertGreater(mine, 50)
        self.assertEqual(out['followed'], 'true')
        after = self.settings(out['after'])
        self.assertAlmostEqual(float(after['rtx.atmosphere.sunElevation']), mine, delta=0.5)
        self.assertEqual(after['rtx.atmosphere.cloudDensity'], entered['rtx.atmosphere.cloudDensity'])
        self.assertAlmostEqual(float(self.settings(out['later'])['rtx.atmosphere.sunElevation']), mine, delta=0.5)

    def test_following_the_map_keeps_a_map_add_ons_sky_from_the_start(self):
        # The same map with Follow the map's sun ticked (the default): the add-on keeps its sky.
        preset = 'PRESET = { nativeloader_sky_follow_map = "1" }\nMHRTX_Config = {}\n'
        out = self.run_lua(preset + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='ownership')
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['owned'].split()[0], '0')

    def test_a_slider_writing_back_its_rounded_value_keeps_the_maps_sun(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='slider')
        self.assertEqual(out['written_back'], '1')
        self.assertEqual(out['moved'], '0')

    def test_rain_fades_out_under_cover_and_back_outside(self):
        # The runtime's own cover test is off (it finds the 3D skybox room above every drop); the
        # game's trace up decides, and the rain fades over half a second.
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='shelter')
        outside = self.settings(out['outside'])
        self.assertEqual((outside['rtx.weather.precipitation.intensity'],
                          outside['rtx.weather.precipitation.occludeUnderCover']), ('0.8', 'False'))
        self.assertEqual(self.settings(out['fading'])['rtx.weather.precipitation.intensity'], '0.4')
        inside = self.settings(out['inside'])
        self.assertEqual((inside['rtx.weather.precipitation.intensity'], inside['rtx.atmosphere.cloudDensity']), ('0', '2.5'))
        self.assertEqual(self.settings(out['again'])['rtx.weather.precipitation.intensity'], '0.8')

    def test_the_maps_skybox_gives_back_the_maps_sun(self):
        out = self.run_lua('CONF = { ["rtx.ignoreGameDirectionalLights"] = "False" }\n' + SESSION, MAP='gm_construct',
                           BSP=bsp(CONSTRUCT), SCRIPT='skybox')
        skybox = self.settings(out['skybox'])
        self.assertEqual((skybox['rtx.skyMode'], skybox['rtx.ignoreGameDirectionalLights']), ('0', 'False'))

    def test_a_night_map_starts_at_night_with_the_moon_where_its_light_is(self):
        night = CONSTRUCT.replace('"painted"', '"sky_borealis01"')
        out = self.run_lua(SESSION, MAP='gm_nightcity', BSP=bsp(night), SCRIPT='night')
        hour, _, follow = out['convars'].split()
        self.assertEqual((hour, follow), ('23.00', '1'))
        # The moon's ground light fades in with the twilight: all of it at night (the sun 20 degrees
        # down), a trace at dusk (about 5 degrees down: smoothstep of 1/8 of 240, some 10; the time
        # is kept to two decimals, which moves the sun a little).
        self.assertEqual(self.settings(out['moonlight_night'])['rtx.atmosphere.surfaceMoonBrightness'], '240.0')
        dusk = float(self.settings(out['moonlight_dusk'])['rtx.atmosphere.surfaceMoonBrightness'])
        self.assertTrue(5 < dusk < 20, dusk)
        moon_bearing, moon_elevation, sun_elevation = self.numbers(out['night'])
        self.assertAlmostEqual(moon_bearing, 324.0, delta=0.05)
        self.assertGreater(moon_elevation, 0)
        self.assertLess(sun_elevation, -15)

    def test_an_eclipse_puts_the_moon_in_earths_shadow_or_before_the_sun(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='eclipse')
        self.assertEqual(self.settings(out['look']), {
            'rtx.atmosphere.eclipseEnable': 'True', 'rtx.atmosphere.eclipseUmbraScale': '2.65',
            'rtx.atmosphere.eclipsePenumbraScale': '4.8', 'rtx.atmosphere.eclipseSunScale': '0.97',
            'rtx.atmosphere.moonTextureEnable': 'True', 'rtx.atmosphere.starMapEnable': 'True',
            # Under the night sky image the weather's airglow (partly cloudy: 0.008) is turned down.
            'rtx.atmosphere.nightSkyBrightness': '0.0004'})

        def geometry(tag):
            anti, sun, elevation, phase, hour, follow = out[tag].split()
            return float(anti), float(sun), float(elevation), phase, hour, follow

        # The full moon of the map's afternoon passes clear of Earth's shadow.
        anti, _, _, phase, _, follow = geometry('plain')
        self.assertAlmostEqual(anti, 5.64, delta=0.01)
        self.assertEqual((phase, follow), ('0.500', '1'))
        # A lunar eclipse needs the night: the clock goes to midnight, off the map's sun; at 100 the
        # moon is in the middle of the shadow, at 50 2.12 degrees out (sky_model.eclipseSeparation).
        anti, _, elevation, phase, hour, follow = geometry('lunar100')
        self.assertAlmostEqual(anti, 0.0, delta=0.01)
        self.assertLess(elevation, -8)
        self.assertEqual((phase, hour, follow), ('0.500', '0.00', '0'))
        self.assertAlmostEqual(geometry('lunar50')[0], 2.12, delta=0.01)
        # A solar eclipse needs the day: noon, a new moon 0.71 degrees from the sun at 50.
        _, sun, elevation, phase, hour, _ = geometry('solar50')
        self.assertAlmostEqual(sun, 1.576 + (0.024 - 1.576) * 0.5 / 0.9, delta=0.01)
        self.assertGreater(elevation, 15)
        self.assertEqual((phase, hour), ('0.000', '12.00'))
        # No eclipse: the chosen phase again, the moon clear of the shadow, the time kept.
        anti, _, _, phase, hour, _ = geometry('none')
        self.assertAlmostEqual(anti, 5.64, delta=0.01)
        self.assertEqual((phase, hour), ('0.500', '12.00'))
        self.assertEqual(self.settings(out['stars']), {
            'rtx.atmosphere.starMapEnable': 'False', 'rtx.atmosphere.nightSkyBrightness': '0.008'})

    def test_a_fog_preset_sets_remix_fog_and_the_weather_leaves_it_alone(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='fog', MENU=True)
        # Remix's Heavy Fog preset, as its menu's Apply button sets it.
        self.assertEqual(self.settings(out['preset']), {
            'rtx.volumetrics.enable': 'True', 'rtx.volumetrics.enableFogRemap': 'False',
            'rtx.volumetrics.transmittanceMeasurementDistanceMeters': '5', 'rtx.volumetrics.anisotropy': '-0.2'})
        self.assertEqual(out['colours'], '0.85, 0.85, 0.85|0.9, 0.9, 0.9')
        # A change of weather blends its clouds in but leaves the preset's fog.
        weather = self.settings(out['weather'])
        self.assertEqual(weather['rtx.volumetrics.transmittanceMeasurementDistanceMeters'], '5')
        self.assertNotEqual(weather['rtx.atmosphere.cloudDensity'], '0.9')
        self.assertEqual(out['weather_colour'], '0.85, 0.85, 0.85')
        # Cleared, the weather's fog comes back at the next tick.
        cleared = self.settings(out['cleared'])['rtx.volumetrics.transmittanceMeasurementDistanceMeters']
        self.assertNotEqual(cleared, '5')
        self.assertGreater(float(cleared), 0)

    def test_without_the_remix_api_nothing_is_sent(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='skybox', NOAPI=True)
        self.assertEqual(out['start'].split()[0], '0')


if __name__ == '__main__':
    unittest.main()
