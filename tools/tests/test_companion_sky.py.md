# test_companion_sky.py

Runs the companion's sky under LuaJIT. Two parts are tested:

- the arithmetic, [`sky_model.lua`](../../companion/nativeloader/lua/nativeloader/sky_model.lua.md);
- the session logic, [`nativeloader_sky.lua`](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md),
  with the GMod functions it uses mocked: client settings and their change callbacks, the console,
  timers, hooks, the clock, `file.Open` on a made-up BSP, and the RTX fixes' `RemixConfig`, which
  records every option it is given.

The harness is written to a scratch folder under `out\tmp`.

## The arithmetic

- **The sun at latitude 40:**
  - noon heights: 50 degrees at the equinox, 73.4 in summer, 26.6 in winter;
  - sunrise and sunset: 04:30-19:30 in summer, 07:20-16:40 in winter.
- **The map's sun:** gm_construct's `light_environment` (pitch -56, yaw 306) is 56 degrees high at
  bearing 324. Following the map puts the sun exactly there, in the afternoon. A sun higher than
  summer's noon sun gives noon in its direction.
- **The moon:** at 20:00 in spring the full moon has risen opposite the set sun; the new moon has set
  with the sun.
- **The stars:** they turn 15 degrees an hour, and the pole stands at the latitude, in the north.
- **Eclipses** for a moon 0.8 degrees in radius: the stages of `eclipseSeparation` (lunar 4.64,
  2.92, 1.32 and 0 degrees at 0, 0.3, 0.7 and 1; solar 1.576, 0.024 and 0 at 0, 0.9 and 1), the
  phases an eclipse needs, and the moon's latitude without one (5.64). The moon's latitude is its
  distance from the antisolar point (full) or the sun (new), at three hours and seasons.
- **Entities:** the entity lump parser and the map's sun, from `light_environment` or `env_sun`.
- **Sky names:** night and dusk names are recognised.
- **Weather values:**
  - the blend kinds: an angle the short way round, extinction, a switch at the midpoint, colours;
  - option text;
  - `hh:mm` both ways;
  - the variation noise.

## The session

- **The start of gm_construct.** The physical sky is on (`rtx.skyMode 1`), the map's own sun is ignored
  (`rtx.ignoreGameDirectionalLights True`), the runtime's day cycle is off and the moon is on. The sun
  stands at the map's sun (56 degrees, bearing 324). The default weather, partly cloudy, is set at
  once. The time setting shows the map's time, 14:21.
- **A change of weather** to a rainstorm blends over 30 s: in between at 15 s, the preset's own values
  at 31 s.
- **Choosing a time** (`nativeloader_sky_time 18:00`) takes the sky off the map's sun. The direction
  stays the map's, and the sun moves to where the model puts it at 18:00.
- **The panel's sliders.** Writing back the map's direction rounded to whole degrees, and its time to
  two decimals, keeps the sky on the map's sun. A real move of the direction takes it off.
- **Rain under cover.** Rain falls at the preset's intensity with the runtime's cover test off. When
  the game's trace up hits a roof, it fades to nothing in half a second (and the clouds stay), and it
  comes back outside.
- **The clock.** With the time passing and a 24-minute day, 60 s is an hour, and stopping the clock
  keeps the time it reached.
- **Weather left to Remix:** nothing more is sent for it.
- **A map whose add-on sets the sky** (`MHRTX_Config` on `modern_house`): nothing is sent until the
  player changes a sky setting; then the companion takes over.
- **The map's own skybox** (`nativeloader_sky 0`) gives back `rtx.skyMode 0` and the configured
  `rtx.ignoreGameDirectionalLights`.
- **A night map** (sky `sky_borealis01`) starts at 23:00, with the full moon where the map's light
  comes from.
- **Eclipses.** The start sends the eclipse geometry (`eclipseEnable`, the umbra, penumbra and sun
  scales), the moon's texture and the star map. The afternoon's full moon passes 5.64 degrees from
  the antisolar point. Choosing a lunar eclipse moves the clock to midnight (off the map's sun) and
  puts the full moon in the middle of the shadow at 100, 2.12 degrees out at 50; a solar eclipse moves
  it to noon and puts a new moon 0.71 degrees from the sun at 50. No eclipse gives back the chosen
  phase, clear of the shadow. "Procedural" turns the star map off.
- **A fog preset** (with the RTX Remix tab's [`nativeloader_menu.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader_menu.lua.md)
  loaded too): Heavy Fog sets Remix's four fog values, volumetrics on and fog remapping off. A change
  of weather then blends its clouds but leaves the fog, and clearing the preset brings the weather's
  fog back at the next tick.
- **Without the Remix API** nothing is sent.

Run with the other tool tests: `python -m unittest discover -s tests` from `tools\` (as
`tools\test.ps1` does). Skipped when LuaJIT is not installed (on `PATH` or in
`%LOCALAPPDATA%\Programs\LuaJIT\bin`). Exit 0 when the tests pass or are skipped.

- `test_weather_left_to_remix_puts_back_remixs_own_values` (R3-009): after Rain, clearing the weather gives
  cloud density rtx.conf's value (the mock's) and the rain's intensity, spawn radius and lightning the
  table's defaults; nothing more is sent after that.
- In `test_a_maps_own_sky_add_on_keeps_its_sky_until_the_player_changes_it` (R3-015): the sky timer runs every
  0.02 s, `nativeloader_sky_interval 0.1` adjusts it, and that change does not take the map's sky over.
