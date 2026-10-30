# 0031: The companion drives the runtime's physical sky: time of day from the map's sun, and the weather presets

- Status: Accepted 2026-10-29
- Decided by: the user ("Upgrade the skybox to better simulate the sky: When we were working on the
  modern house pbr, one testing run was done in a night sky. Here, in RTX settings, add environmental
  control to change the direction of the sun and time of the day, also cloud (weather) the effect
  should look realistic and well tuned"), Claude choosing how
- Builds on: [0021](0021-remix-defaults-in-one-low-layer.md) (the Remix defaults layer),
  [0022](0022-companion-rtx-session-guard.md) (the companion's RTX Remix tab),
  [0029](0029-companion-translations.md) (its translations)

## Context

Facts in [RESEARCH.md](../RESEARCH.md) section 28.

- **The runtime has a physical sky.** The user's fork has `rtx.skyMode 1` ("Numos"):
  - Hillaire scattering, volumetric clouds, stars, up to four moons, lightning and rain/snow particles;
  - twelve weather presets of 63 values each, with a blender that crossfades between them;
  - in Numos mode, the sun and the moon are distant lights the atmosphere adds itself.

  The RTX fixes' `rtx.conf` leaves the sky mode at 0, the map's skybox rasterised into a probe.
- **What sessions get today.** The package's Remix defaults layer (0021) is merged from the classic
  install's files, and the classic install's `user.conf` holds what Modern House RTX once pushed:
  `rtx.skyMode 1`, the sun 21 degrees high at bearing 222, its fair-weather clouds, cloud shadows off.
  So every map runs one frozen Modern House afternoon.
- **The companion's Remix settings had sun height, sun direction and a clouds switch.** These were
  raw options: no time of day, nothing for the moon or the stars, no weather.
- **What Lua can reach.**
  - The blender is driven by `remixapi_SetGameValue("__weather.target", <preset>)`, which the RTX
    fixes' Lua module (`RemixConfig`) does not expose.
  - `RemixConfig.SetConfigVariable` can set every option the presets drive.
  - `GetConfigVariable` reads `rtx.conf` from disk, not the live value.
- **The runtime's own day cycle** (`rtx.atmosphere.timeCycleEnable`) moves only the sun. The moon's
  position and phase and the stars' rotation are for the game to drive. With the cycle off,
  `timeOfDayHours` does nothing.
- **Maps say where their sun is.** A map's `light_environment` (pitch and yaw in the BSP's entity lump)
  is where its designer put the sun. gm_construct's is 56 degrees high in the north-west, at bearing
  324.
- **Modern House RTX sets its own sky** on `modern_house`, and puts it back 3, 23, 43 and 63 s after
  the map starts.

## Decision

1. **The physical sky by default.** In an RTX session the companion turns on `rtx.skyMode 1` and
   ignores the map's own fixed-function sun (`rtx.ignoreGameDirectionalLights True`), because the
   atmosphere makes the sun. "The map's skybox" is the other choice (`nativeloader_sky 0`).
2. **One clock places the sun, the moon and the stars.**
   - The companion's model ([`sky_model.lua`](../../companion/nativeloader/lua/nativeloader/sky_model.lua.md))
     uses the runtime's solar formula at latitude 40, for a season and a time of day.
   - It places the moon of a chosen phase on the ecliptic, and turns the stars with the sidereal time
     about a pole at the latitude.
   - `rtx.atmosphere.timeCycleEnable` stays off. The clock can run, a day lasting a chosen number of
     real minutes.
3. **By default the sky follows the map's sun.**
   - The time is the afternoon time at which the sun stands as high as the map's sun.
   - The map's north is turned so the sun stands where the map's does.
   - The map's sun comes from its `light_environment`, else its `env_sun`, else `util.GetSunInfo`.
   - A map whose sky texture's name says night or dusk starts at 23:00 with the moon where its light
     comes from, or with the sun low.
   - Moving the time or the direction takes the sky off the map's sun.
4. **The weather is the runtime's twelve presets, blended by the companion.**
   - [`tools/weather_presets.py`](../../tools/weather_presets.py.md) generates the table from the
     fork's `rtx_weather.h`.
   - The companion blends with the runtime's formulas over a chosen time, eased.
   - It adds the runtime's recommended slow variation of the cloud cover and the wind for each preset.
   - The default is partly cloudy. Choosing nothing leaves clouds, fog and rain to Remix's files.
5. **A map's own sky add-on keeps its sky** until the player changes a sky setting in that session.
   Add-ons say so through the hook `NativeLoaderSkyOwner`; Modern House RTX is recognised by its
   `MHRTX_Config`. After the player takes over, the companion puts its sky back every 10 s, so the
   add-on's repeats do not win.
6. **Where the settings are.** They are client settings (`nativeloader_sky*`, `nativeloader_weather*`),
   in the RTX Remix tab under "Sky and weather". The sun, cloud and fog entries leave "Remix settings":
   the fog belongs to the weather.

## Consequences

- Each map starts with its own sun in a physical sky. The player sets the time, the direction, the
  season, the moon and the weather, and can let the time run.
- The values go to Remix's user layer, as the Remix settings already do.
  - Remix's own Save (Alt+X) writes them into the game folder's `user.conf` like any other user-layer
    value, which is the player's choice.
  - The companion never writes `user.conf`.
- The sky no longer matches the classic install, whose sky is the frozen Modern House afternoon. For
  the sky, parity is not the aim.
- **The ground below the horizon.** From high up, where the map has no geometry, the atmosphere's
  virtual planet ground shows below the horizon; at sunset it is a red band. Its albedo is a constant
  in the runtime (`kGroundAlbedo`), so a fix belongs in the runtime.
- **Handing the weather to the runtime.** If the RTX fixes exposed `SetGameValue`, the companion could
  hand the weather to the runtime's own blender: transient state, outside the user layer. The presets'
  values would be the same.

## Alternatives considered

- **The runtime's own day cycle.** It moves only the sun: the moon and the stars would stay still, and
  Lua cannot read its clock.
- **A `SetGameValue` binding in the RTX fixes' binary module, to use the runtime's blender.** That is a
  native change and rebuild in another repository (GPL), for the same values.
- **Keep the map's skybox by default.** A painted skybox has no time of day, its painted sun does not
  light the map, and the user asked for the upgrade.
- **Guess a map's time from its skybox texture's colours.** Unreliable; the sun's entities and the
  sky's name are used instead.
