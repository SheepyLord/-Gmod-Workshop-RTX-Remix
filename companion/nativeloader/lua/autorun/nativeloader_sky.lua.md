# nativeloader_sky.lua

R20-B: Time passes defaults on and a day lasts 20 real minutes. The defaults autorun migrates only
the untouched old `0`/`30` pair once, before this file installs callbacks or starts its clock
([ADR 0117](../../../../docs/decisions/0117-startup-upscaling-hint-and-sky-defaults.md)). Reset uses
`1`/`20` too. The slider remains 2–240 minutes; 20 is within that range. A map's starting sun and
R16's sky-add-on ownership rules below are preserved.

R14-H rewords four help lines of the Sky and weather panel (Follow the map's sun, Day length, Sky
update interval, Weather) in the guide's terms; the controls and their behaviour are unchanged.

Common Remix fog presets take precedence only when the menu's `NativeLoaderRemixFogOverride` hook
returns true, after a preset was applied in this session. An archived draft with startup replay off
does not suppress the weather's fog (ADR 0044).

The sky in RTX sessions ([ADR 0031](../../../../docs/decisions/0031-physical-sky-time-and-weather.md),
[ADR 0032](../../../../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)).
The runtime has a physical sky that the RTX fixes leave off: `rtx.skyMode 1`, with scattering,
volumetric clouds, stars and moons. This file turns it on and drives it:

- the sun, the moon and the stars for a time of day, by default the time and direction of the map's
  own sun;
- a clock that can run;
- the moon's phase, and lunar and solar eclipses;
- the night sky image (the runtime's Night Sky HD LE layers: stars, galaxy, nebulae) or the procedural stars;
- the runtime's twelve weather presets, blended into each other.

Everything reaches Remix through the RTX fixes' `RemixConfig.SetConfigVariable`, which writes Remix's
user layer, as the "Remix settings" panel does. Shared autorun: the server only sends this file,
[`sky_model.lua`](../nativeloader/sky_model.lua.md) (the arithmetic) and
[`weather_presets.lua`](../nativeloader/weather_presets.lua.md) (the presets) to clients.

## Settings

Saved client settings, shown in the RTX Remix tab under "Sky and weather":

| Setting | Default | What |
|---|---|---|
| `nativeloader_sky` | `1` | 1: the physical sky; 0: the map's own skybox |
| `nativeloader_sky_follow_map` | `1` | The time and the sun's direction come from the map's own sun |
| `nativeloader_sky_hour` | `14.5` | Time of day, 0-24. Following the map, it shows the map's time |
| `nativeloader_sky_direction` | `0` | Turns the sun's path around the sky (the map's north bearing), in degrees |
| `nativeloader_sky_time_passes` | `1` | The clock runs |
| `nativeloader_sky_day_minutes` | `20` | Real minutes for a whole day while the clock runs |
| `nativeloader_sky_season` | `summer` | `spring`, `summer`, `autumn`, `winter`: how high the sun climbs and how long the day is |
| `nativeloader_sky_moon` | `full` | Moon phase: `new`, `waxingCrescent`, `firstQuarter`, `waxingGibbous`, `full`, `waningGibbous`, `lastQuarter`, `waningCrescent` |
| `nativeloader_sky_eclipse` | (empty) | `lunar` or `solar`; empty for none. An eclipse sets the moon's phase (full, new) |
| `nativeloader_sky_eclipse_amount` | `100` | How far through the eclipse, 0-100: first contact to the middle; lunar total from 70, solar from 90 |
| `nativeloader_sky_stars` | `map` | Night sky: `map` (the night sky image: stars, galaxy and nebulae) or `procedural` |
| `nativeloader_weather` | `partlyCloudy` | One of the twelve presets (`clear`, `partlyCloudy`, `overcast`, `hazy`, `foggy`, `drizzle`, `rainstorm`, `thunderstorm`, `snow`, `blizzard`, `sandstorm`, `smoggy`); empty leaves clouds, fog and rain to Remix's files (see "Weather left to Remix") |
| `nativeloader_weather_seconds` | `30` | How long a change of weather takes |
| `nativeloader_sky_interval` | `0.02` | Seconds between updates of the sun, moon, stars and weather, 0-1: 0.02 is 50 a second, 0 every frame. Changing it does not take a map's sky over (R3-015) |

Moving the time or the direction turns `nativeloader_sky_follow_map` off. The other one keeps the
map's value, which the panel shows.

- **The panel's sliders write back what they show.** The direction slider has no decimals and the
  time slider two. While the sky follows the map, a value within that rounding of the map's own counts
  as the companion's, not the player's.
- **Values the companion writes itself** (the map's time and direction, the time a stopped clock
  reached) do not count as the player's either.
- **Choosing an eclipse** with the sun on the wrong side of the horizon for it (higher than 8 degrees
  below it for a lunar one, lower than 15 degrees up for a solar one) sets the time to 00:00 or 12:00,
  and so turns `nativeloader_sky_follow_map` off.

## What it gives Remix

### The sky

With the physical sky on (`nativeloader_sky 1`):

- `rtx.skyMode 1`.
- `rtx.ignoreGameDirectionalLights True`: the map's sun reaches Remix as a fixed-function light, and
  in this mode the atmosphere makes the sun.
- `rtx.atmosphere.timeCycleEnable False`: the runtime's own clock moves only the sun.
- The look (`LOOK`):
  - moon 0 on, 1.6 degrees across instead of 3.5, a touch cool. The moonlight scales with the disc's
    area, so the ground light (`surfaceMoonBrightness`) is raised from 50 to 240 to make up for the
    smaller disc. It fades in with the twilight, from none with the sun 4 degrees down to all of it at
    12. The runtime lights the ground fully as soon as the sun is down, which lit the towers orange
    from a rising moon at dusk;
  - the cumulus-shaped cloud shadows on the ground (`cloudVoxelShadowsEnable`), which the classic
    install's settings, and so the package's Remix defaults, turned off;
  - the real Moon's face (`moonTextureEnable True`, the runtime's default too), its relief at 0.6
    (`moonReliefStrength`; at the runtime's 1 the terminator broke into dark notches when zoomed in);
  - eclipses on, with the shadow and sun scales the eclipse stages assume (`eclipseEnable`,
    `eclipseUmbraScale 2.65`, `eclipsePenumbraScale 4.8`, `eclipseSunScale 0.97`, from
    `sky_model.ECLIPSE`).
- `rtx.atmosphere.starMapEnable`: `True` for the night sky image (`nativeloader_sky_stars map`),
  `False` for the procedural one.

With the map's skybox (`nativeloader_sky 0`): `rtx.skyMode 0`, and
`rtx.ignoreGameDirectionalLights` back to its `rtx.conf` value (`False` if none).

### The sun, the moon and the stars

From the model, at latitude 40, for the clock, the season, the moon phase and the north bearing:

- `rtx.atmosphere.sunElevation`, `sunRotation`;
- `moon0.elevation`, `moon0.rotation`, `moon0.phase`;
- `starRotation`, `starAxisElevation`, `starAxisRotation`.

They are sent at the start of a map, on every change, and every `nativeloader_sky_interval` seconds
(0.02 by default; it was 0.25 until R3-015, and a running clock then moved the sky in visible steps).
An unchanged value is not sent again.

**The moon off the ecliptic.** The runtime draws an eclipse wherever the geometry has one, so the
moon is never quite on the ecliptic:

- **No eclipse:** it passes 5.64 degrees north of it, just clear of Earth's penumbra for its size.
  The real Moon passes up to 5.1 degrees off, and so mostly misses the shadow.
- **An eclipse:** the moon is full (lunar) or new (solar), and its distance from the shadow's centre
  or the sun's comes from `nativeloader_sky_eclipse_amount`, by stages. The model's
  `eclipseSeparation` says which.

### Following the map

The map's sun comes from:

1. the first `light_environment` of the map's BSP entity lump (lump 0, read with `file.Open`; a
   compressed lump is skipped);
2. else the first `env_sun`;
3. else `util.GetSunInfo`.

What it does with that sun:

- The time is the afternoon time at which the sun stands that high on the season's day (noon if it
  never climbs that high), and the north is turned so the sun stands where the map's does.
- A map whose sky texture (worldspawn `skyname`, else `sv_skyname`) is named for the night starts at
  23:00, with the moon where the map's light comes from.
- One named for dusk starts with the sun 3 degrees high, where the map's light comes from.
- No sun: 14:30, north 0.

### The weather

The presets' values for their 36 varying fields, blended as the runtime's blender does it:

- the blend runs over `nativeloader_weather_seconds`, eased;
- the start of a map sets them at once;
- while a weather is set, the runtime's recommended variation for that preset wanders: the cloud cover
  (±15 %) and the wind's speed (±30 %) and direction (±10 degrees), on a 300 s noise.

What GMod's scale changes. A Remix metre is 100 units (`rtx.sceneScale 1`), 1.905 real metres, so a
whole map is a few dozen Remix metres across:

- **Fog.** Each preset's fog distance comes from a visibility in real metres, 400 m (foggy) to
  13 km (clear), keeping the preset's tint: the distance at which what one sees fades to 5 %. The
  runtime reads the fog colour as sRGB and uses it linear, so the extinction is worked out from the
  linear colour. The runtime lights its froxel fog from lights only, not from the sky, so denser fog
  turns dark. The visibilities stay at 300 m or more.
- **Rain and snow** fall from 8 Remix metres around the player, 6 above, instead of 20 and 14, so
  the same particles fall near enough to be seen. Drops are 1.6 times as wide.
- **Cover.** The runtime's own test for cover (`occludeUnderCover`) traces up to 100 000 units. A
  map's 3D skybox room hangs above most maps within that and counted as cover everywhere, so no drop
  was ever born. The test is off; instead the game's trace straight up from the view decides, and
  under a roof the rain and snow fade out in half a second (by the time passed, whatever
  `nativeloader_sky_interval` is).

**Weather left to Remix** (`nativeloader_weather` empty, "(leave to Remix)" in the panel). At the
start of a map the companion then sends nothing for the weather. Cleared during a session, every
option the weather had set goes back to Remix's own value (R3-009): `rtx.conf`'s (RemixConfig's
`GetConfigVariable` reads only that file), else what Remix has without it, the package's classic layer
or the runtime's default, from [`weather_presets.lua`](../nativeloader/weather_presets.lua.md)
`defaults`. What the RTX fixes set for the map is not known here, and is not put back. A fog preset
chosen under "Remix settings" keeps its fog.

**Another add-on's later change** of an option the weather sets (or one made in the Remix menu, Alt+X)
stays until the weather's own value for it changes, or the map starts again: the companion sends a
value when its own changes, and does not take back what others set (R3-010, rejected). Only on a map
whose add-on sets the sky, once the player has taken it over, is everything put back every 10 s.

**Under the night sky image** the weather's airglow (`rtx.atmosphere.nightSkyBrightness`, 0.008 to
0.012 in the presets) goes out at 5 % of the preset's value. In Skyrim, where the image comes from,
the space between the nebulae is black. The full airglow left it slate blue and washed the image out;
the ground stays about as light, lit by the image itself
([RESEARCH.md](../../../../docs/RESEARCH.md) section 29). The simulated stars keep the full value.

**A fog preset** chosen under "Remix settings" (`nativeloader_remix_fog`,
[`nativeloader_menu.lua`](client/nativeloader_menu.lua.md)) replaces the weather's fog: the weather
then sends none of its four `rtx.volumetrics` values. It forgets what it last sent of them, so they
go out again once the preset is cleared.

## A map whose add-on sets the sky

Some maps' RTX add-ons set the sky themselves. Modern House RTX does it on `modern_house`, and puts
it back 3, 23, 43 and 63 s after the map starts.

- **The player's own time and weather apply from the map's start** (R16, the user's item 44;
  [ADR 0105](../../../../docs/decisions/0105-the-players-sky-applies-from-a-maps-start.md)): with
  "Follow the map's sun" unticked, the companion is in charge of the sky from the start, also on such a
  map. Before R16 the add-on's sky stayed until the player changed a setting, so a chosen time and
  weather seemed not to apply until the Sky and weather panel was touched.
- **Following the map keeps such an add-on's sky** ("Follow the map's sun" ticked, the default) until
  the player changes a sky or weather setting in that session.
- Once the companion is in charge, its sky is put back every 10 s, and at once whenever the add-on sets
  its own again (below). The add-on's `ApplySettings` is wrapped from the sky's first tick after the
  add-on loaded (Modern House RTX loads after InitPostEntity), not only by the 10 s timer.
- **How the companion knows.** An add-on says so by answering the hook `NativeLoaderSkyOwner` with
  its name. Modern House RTX is recognised by its `MHRTX_Config` on `modern_house`.
- **When the add-on sets its sky again**, it runs the hook `NativeLoaderSkySet`, and a sky the player
  has taken over goes back in the same tick. Modern House RTX does not run it, so the companion wraps
  its `MHRTX.ApplySettings` to run it afterwards (at the start of the map, and on the 10 s timer
  whenever the function is not the wrapper: not loaded yet, or replaced by a reload of that add-on). Before R5 the player's sky waited for the 10 s timer: on `modern_house` the
  afternoon sun came up for as long as 10 s in the middle of the player's night, three times in the
  first minute, and the daylight lingered in the image's temporal history wherever the camera had
  looked, a haze over the stars with a straight edge where the view had turned (native loader review
  R5, 2026-10-31; [`night_sky_probe.lua`](../../../../tools/qa/night_sky_probe.lua.md) shows it).

## Commands

- `nativeloader_sky_time <time>`: `hh:mm`, hours, or `sunrise`, `morning`, `noon`, `afternoon`,
  `golden`, `sunset`, `dusk`, `night` (23:00) or `midnight`. Named times are sun heights on the
  season's day.
- `nativeloader_sky_status`: prints the sky, the time, the sun and moon (or the eclipse and its
  progress), the night sky, the map's own sun and sky name, and the weather.
- `nativeloader_sky_reset`: all of these settings back to their defaults.

## Timing

- **When.** At `InitPostEntity`, then everything again 5 s later, after the RTX fixes' per-map Remix
  settings.
- **Ticks.** A timer every `nativeloader_sky_interval` seconds (0.02 by default; `timer.Adjust` when the
  setting changes) runs the clock, the weather blend, the variation and the cover check.
- **The panel.** `NATIVELOADER_SKY` holds the panel builder and the clock for the panel (and
  tests).

Tested by [`tools/tests/test_companion_sky.py`](../../../../tools/tests/test_companion_sky.py.md).
