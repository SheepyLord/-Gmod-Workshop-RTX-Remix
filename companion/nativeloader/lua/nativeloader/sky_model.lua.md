# sky_model.lua

The sky's arithmetic, as a module (`include("nativeloader/sky_model.lua")` returns it). It uses no
Garry's Mod function, so the tests run it under plain LuaJIT.
[`nativeloader_sky.lua`](../autorun/nativeloader_sky.lua.md) uses it
([ADR 0031](../../../../docs/decisions/0031-physical-sky-time-and-weather.md),
[ADR 0032](../../../../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)).

Angles are in degrees.

- **Bearing:** a compass direction in the map, with 0 the map's +y and 90 its +x. The Remix atmosphere
  counts its rotation options the same way when `rtx.zUp` is on, as it is in GMod.
- **Hour angle:** 0 when a body stands due south at its highest; positive afterwards.

| Function | What |
|---|---|
| `sky(hours, day, phase, north [, latitude [, moonLatitude]])` | The sky at a time of day (0-24) on a day of the year, returned as `{ sun = { elevation, bearing }, moon = { elevation, bearing, phase }, stars = { rotation, poleElevation, poleBearing } }`. `north` is the bearing of the map's north; `moonLatitude` puts the moon that many degrees north of the ecliptic (0 when left out). |
| `eclipseSeparation(kind, amount, radius)` | How far the moon's centre is from the centre of Earth's shadow (`lunar`) or from the sun's (`solar`), in degrees, `amount` (0-1) of the way through an eclipse of a moon of `radius` degrees, by stages (below). |
| `eclipsePhase(kind)` | The phase an eclipse needs: 0.5 (full) for `lunar`, 0 (new) for `solar`, nil for none. |
| `moonLatitude(kind, amount, radius)` | The moon's ecliptic latitude: in an eclipse its `eclipseSeparation`; otherwise just clear of the penumbra, `(ECLIPSE.penumbra + 1) * radius + 1`. |
| `horizontal(hourAngle, declination, latitude)` | Elevation and azimuth (from north, clockwise) of a body. The model is the one the runtime's own day cycle uses (`RtxAtmosphere::computeTimeCycleSunAngles`). |
| `timeForElevation(elevation, morning, day [, latitude])` | When the sun stands that high, before or after noon. A sun that never climbs that high gives noon; one that never sinks that low gives midnight. |
| `mapSun(pitch, yaw)` | The sun of a `light_environment` (pitch negative = shining down; the sun is opposite the yaw), as `{ elevation, bearing }`. Nil for a light that does not shine down. |
| `followMap(sun, day [, latitude])` | The afternoon time and the north bearing that put the sun where `sun` is. A sun higher than that day's noon sun gives noon, in its direction. |
| `parseEntities(text, classes)`, `sunOfEntities(entities)` | A BSP entity lump as key/value tables. The map's sun is the first `light_environment`, whose `pitch` key wins over its angles' pitch as in VRAD; failing that, the first `env_sun`. |
| `skyTimeOfName(skyname)` | `"night"` or `"dusk"` for sky texture names that say so (`night`, `borealis`, `stars`, `dusk`, `sunset`, ...). Nil otherwise. |
| `clock(hours)`, `parseClock(text)` | `hh:mm` text, and back from `hh:mm` or plain hours. |
| `blend(kind, a, b, t)` | One weather value between two presets, as the runtime's blender does it: `angle` the short way round, `extinction` in 1/distance, `step` at the midpoint, colours per channel, the rest linearly. |
| `optionText(value, integer)` | A value as Remix option text: `True`/`False`, `x, y, z`, a whole number or a short decimal. |
| `ease(t)` | Smoothstep, for a blend's progress. |
| `drift(seconds, index)` | The runtime's slow weather-variation noise (`driftNoise1D`): sines with a 300 s base period, about -1 to 1. |

## The model

- **The observer** stands at latitude 40 north (`LATITUDE`). Seasons are days of the year (`SEASONS`):
  spring 80, summer 172, autumn 266, winter 355.
  - The summer sun climbs to 73.4 degrees, between 04:30 and 19:30.
  - The winter sun climbs to 26.6 degrees, between 07:20 and 16:40.
  - Times are solar times: noon is when the sun is highest.
- **The sun** follows the day's declination: its ecliptic longitude (0 at the March equinox, day 80)
  turned into equatorial coordinates, with the Earth's axis tilted 23.44 degrees.
- **The moon** stands `phase` of a turn east of the sun along the ecliptic, `moonLatitude` degrees
  north of it (its orbit is tilted; the real one passes up to 5.1 degrees off).
  - A new moon (0) is beside the sun.
  - A full moon (0.5) is opposite it, rising as the sun sets.
  - `MOON_PHASES` names eight phases in the runtime's convention: `new` 0, `waxingCrescent` 0.15,
    `firstQuarter` 0.25, `waxingGibbous` 0.35, `full` 0.5, `waningGibbous` 0.65, `lastQuarter` 0.75,
    `waningCrescent` 0.85. The runtime lights the moon from the sun's side of the sky, so a waxing
    moon is bright on the west.
- **Eclipses.** `ECLIPSE` holds the runtime's eclipse geometry in moon radii: Earth's umbra 2.65 and
  penumbra 4.8 at the Moon's distance, and the drawn sun 0.97. The companion sets the runtime's
  options to these. `eclipseSeparation` gives each stage a set stretch of `amount`, so the dramatic
  part has room:

  | Eclipse | `amount` 0 | | | 1 |
  |---|---|---|---|---|
  | lunar | touches the penumbra (5.8 radii) | 0.3: touches the umbra (3.65) | 0.7: wholly inside it, total (1.65) | the middle of the shadow |
  | solar | touches the sun (1.97 radii) | | 0.9: covers it, total (0.03) | centred |

  Between the stages the distance changes linearly. A sun larger than the moon (`sun` above 1) makes
  the 0.9 stage the start of an annular eclipse.
- **The stars** turn with the local sidereal time (the sun's right ascension plus its hour angle)
  about the celestial pole, which stands at the latitude's height in the north.
  - The runtime rotates the sky direction it samples, so the rotation given to it is the negative.
  - That way the field turns east to west, like the sun.
