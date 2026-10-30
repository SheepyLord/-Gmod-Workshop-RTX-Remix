# 0032: The real Moon and night sky, eclipses from the geometry, and Remix's fog presets

- Status: Accepted 2026-10-29
- Decided by: the user ("Give a better, realistic texture to the moon. Enhance the look of the night
  sky, add real stellar features and night sky image instead of simulated light dots. (Toggleable)
  Implement moon phase and lunar eclipse, sun phase (just solar eclipse), adjustable in the menu. Fog
  could be implemented in the Remix settings, there is some volumetric preset that is relevant."),
  Claude choosing how
- Builds on: [0031](0031-physical-sky-time-and-weather.md) (the companion drives the physical sky)

## Context

Facts in [RESEARCH.md](../RESEARCH.md) section 29.

- **The runtime's Moon and stars are procedural.**
  - The Moon is noise ("Rocky" or "Volcanic") on a flat disc, its terminator always on the same side
    whatever the sun does.
  - The stars are a hash grid of dots with a noise band for the Milky Way.
  - There is no eclipse model, and no sun disc: the visible sun is the aerosol glow baked into the
    sky-view table, and the Moon is drawn only while the sun is down.
- **Real maps are free to use.** NASA's Scientific Visualization Studio publishes the Moon's colour
  and elevation (CGI Moon Kit) in simple cylindrical projection, and asks for a credit line and
  nothing else.
- **A star map made for the sky of a game is sharper.** NASA's all-sky map (Deep Star Maps 2020)
  was tried first: at 8192 pixels round the sky its stars are blobs several pixels wide when
  magnified, and its poles streaked (the user rejected it). The Skyrim mod Night Sky HD LE
  (PraedythXVI) draws the sky from layers made for a game:
  - a star sphere of small, sharp stars tiled over two hemispheres;
  - a galaxy band, and a nebula sphere (FullNebula, edited from Era-7's free nebula images);
  - constellations.
  Its permissions allow converting it for other games with credit, not in anything sold. Era-7's
  images are free, open assets, and the user has permission to use them.
- **The runtime's texture manager streams.** It demotes, purges on a scene change and samples
  feedback for replacement assets, which suits a mod's textures, not a texture the sky needs every
  frame of the session.
- **Remix's fog presets are a menu button.** "Volumetric Visual Presets" (Default, Heavy Fog, Light
  Fog, Mist, Haze, Dust, Smoke) set four `rtx.volumetrics` values and turn fog remapping off. There is
  no option to choose one, and the weather (0031) sets the same four values.

## Decision

1. **The runtime draws moon 0 as the real Moon** (the fork, branch `claude/sky-night`).
   - From `atmosphere\moon_albedo.dds` and `moon_normal.dds` beside the runtime's `d3d9.dll`
     (`rtx.atmosphere.moonTextureEnable`, on by default; the paths are options).
   - A sphere lit from the sun's side of the sky: the phase option sets the angle between the sunlight
     and the view, the real sun's position sets which limb is lit. Lommel-Seeliger with a little
     Lambert, relief from the normal map, earthshine on the night side.
   - The terminator follows the smooth sphere, softened over about two pixels. The relief shades
     the lit side and darkens slopes turned from the sun without cutting them to black.
   - The sky's textures choose their mips from the pixel size with the materials' upscaler mip bias.
   - North points at the ecliptic pole. Moons 1-3 stay procedural.
2. **The runtime draws the night sky from Night Sky HD LE's layers** when
   `rtx.atmosphere.starMapEnable` is set (off in the runtime, on in the companion).
   - Three textures: the stars, the galaxy band and the nebula sphere with the constellations baked in.
   - Each is sampled through the mapping of the mod's own sky meshes, so the result matches the mod.
   - The layers add up in gamma space as Skyrim blends them, then are decoded and scaled by
     `starMapBrightness` (0.12: the mod's look at Remix's night exposure).
   - Each direction's right ascension and declination come from the star axis and `starRotation`
     (the companion's -LST), so the sky turns with the hour, the season and the latitude.
   - **Under the image the companion sends the weather's airglow at 5 %.** In Skyrim the space
     between the nebulae is black. At full strength the airglow (0.008 for a clear night) held it
     slate blue under Remix's night exposure, which sits at its limit, and washed the image out.
     The image lights the ground about as much as the airglow did. The simulated stars keep the full
     airglow.
   - The procedural field stays as the other choice.
3. **Eclipses follow from the geometry** (`rtx.atmosphere.eclipseEnable`, on).
   - **Lunar.**
     - Earth's umbra and penumbra, sized in Moon radii so the enlarged Moon still fits, shade moon 0's
       disc per pixel: copper red inside, with a turquoise band at the umbra's edge.
     - Averaged over the disc, the same shadow scales and reddens moon 0's albedo, which every
       moonlight path reads (sky, halo, clouds, the light on the ground).
   - **Solar.**
     - While moon 0 nears the sun, the sky draws a sun disc sized from the Moon, with the chromosphere
       and a corona, behind the Moon's silhouette; primary rays only.
     - The drawn light is held to 64 times the daylight left. At the real disc's brightness, about
       4e4, the upscaler turned the step from it to the dark Moon into black pixels along the Moon's
       limb.
     - The covered fraction scales the sun's illuminance for everything else. A floor
       (`eclipseTotalityLight`) stands for the light from outside the Moon's shadow. Stars come out at
       totality.
4. **The sky owns its textures.** `RtxAtmosphere` loads the DDS files itself, uploads them once and
   keeps them for the session. It loads only in physical-sky sessions and only what is switched on.
   A missing file is logged and the procedural look stays.
5. **The companion places the eclipse.**
   - "Eclipse" (none, lunar, solar) and "Eclipse progress" (0 first contact to 100 the middle; total
     from 70 lunar, from 90 solar) set the Moon's phase and its latitude off the ecliptic.
   - Choosing an eclipse with the sun on the wrong side of the horizon moves the clock to midnight or
     noon.
   - Without an eclipse the Moon passes 5.64 degrees off the ecliptic, clear of the shadow: on the
     ecliptic every full moon would be eclipsed.
   - The Moon has eight phases. "Night sky" chooses the real stars or the procedural ones.
6. **Remix's fog presets are a choice under Remix settings.** "Fog" applies the seven presets as
   Remix's own Apply button does (volumetrics on, fog remapping off). While one is chosen the
   weather leaves the fog alone; "(leave to Remix)" hands it back.
7. **runtime-b6** is runtime-b5 with the sky fork's `d3d9.dll` and the `atmosphere` folder:
   - the Moon's two maps;
   - the night sky's three layers;
   - `CREDITS.txt`, with NASA's, PraedythXVI's and Era-7's credit lines and the permissions.
   - A second dxvk layer, `02_compiler_threads.conf`, sets `dxvk.numCompilerThreads = -2`: shaders
     compile on every hardware thread but two (the user, 2026-10-29).
   - The fork reads a negative count as "all but that many". The classic layer's `1` stays below it,
     as the classic install's value.

## Consequences

- The RTX package grows by 228 MB: two 8192-square layers of 89.5 MB each, the 44.7 MB galaxy and
  4.2 MB for the Moon. With the night sky image on, the runtime holds about 220 MB more GPU memory.
- **Licence of the night sky.** The mod's permissions forbid selling it. The RTX package is free,
  and `CREDITS.txt` travels with the textures. Era-7's nebulae are used with the user's permission.
- **The Moon at a high zoom.** At 5 degrees of view (about 15 times the usual zoom) the lit side
  along the terminator and the earthshine side break into diamond-shaped blocks a few pixels across.
  The clouds, the volumetric fog, Ray Reconstruction and the upscale (DLAA) leave them as they are.
  The relief adds dark notches along the terminator, so the companion sets it to 0.6. At 20 degrees
  the Moon is clean.
- **One geometry, two places.** The companion's eclipse stages assume the runtime's shadow and sun
  scales, so the companion sets them (`sky_model.ECLIPSE`); a change has to go to both.
- **What is simplified.**
  - The corona and prominences are procedural.
  - The Moon shows no libration.
  - Ground shadows stay round during a partial eclipse.
  - Reflections show the eclipsed sky without the sun disc.
- Another game on the same fork sees an eclipse only if it puts a moon opposite or in front of the
  sun; the star map stays off unless it asks for it.

## Alternatives considered

- **Load the textures through the texture manager.** Its streaming and scene purges would drop the
  Moon or the stars after a map change, and its sampler feedback would decide their mips.
- **Eclipses from the companion alone** (dimming the sun and moonlight options from Lua). The shadow
  across the Moon's face and the covered sun disc need the shader anyway, and the dimming has to
  reach every light path in the same frame.
- **NASA's Deep Star Maps 2020** (Gaia DR2, 8192 x 4096). Real star positions, but blurry stars at
  the sizes a game shows, and streaks at the poles: rejected in testing.
- **Baking the mod's layers into one equirectangular map.** One texture and one sample, but its
  stars would be resampled and lose the sharpness the mod was chosen for.
- **The real Moon's size (0.52 degrees).** About 11 pixels across at 1080p and 90 degrees; the Moon
  stays 1.6 degrees (0031), and the shadow and the drawn sun scale with it.
