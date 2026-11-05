# 0109: Each weather has its cloud genera; the sun has a disc; a 2D high cloud layer

- Status: Accepted 2026-11-05
- Decided by: the agent in R17, on the user's request: "Implement a better sun and cloud in Numos. The
  current cloud is very monotonic with the sun only being a scattered lamp, and must fit the weather.
  The current cloud is also not volumetric. Your task is to research available sources for cloud types
  and cloud shapes and implement a better and efficient atmospheric system based on Numos." The user
  left the choices to the agent: "You should decide yourself and not ask for human intervention."
- Runtime patch: `runtime/patches/0031-*` ([runtime/README.md](../../runtime/README.md)).

## Context

Numos (`rtx.skyMode 1`) draws the sky from Hillaire's LUTs and the clouds with a Nubis Cubed (2023)
march of a signed-distance cloud body (NVDF) at reduced resolution, with an optional second "echo"
deck. R17's study in the PoC (`out/r17`, [R17 report](../handover/R17-report.md)) found:

1. **One cloud for every weather.** Every preset used the same layer at the same height, cell size
   and edge detail; only its cover, kind and density moved. No middle or high clouds.
2. **Not volumetric.** The presets' `cloudDensity` was 0.4 to 3 (the option's default is 4), so the
   clouds were translucent and flat, with no shaded undersides; the edge billows
   (`cloudDetailStrength`) were off.
3. **Overcast never closed.** The cloud bodies are baked at a nominal cover (`nvdfNominalCoverage`,
   pinned at 0.65) and a weather's cover only moves their surface by 0.2 km per unit of cover, so
   overcast, rain and snow left km-wide blue gaps.
4. **The sun was a scattered lamp.** Outside an eclipse the sky had no disc: only the Mie aureole of
   the sky LUT (g = 0.8, half brightness about 10 degrees out).

What the research gave (sources in [RESEARCH.md](../RESEARCH.md), "R17: clouds and the sun"):

- The WMO genera have height bands (low 0-2 km, middle 2-7 km, high 5-13 km), shapes and optics.
- Real-time engines layer them: volumetric low clouds, with the alto and cirro clouds as 2D layers
  above 4 km (Horizon Zero Dawn, 2015). Red Dead Redemption 2 (2019) does likewise.
- Cirrus is thin (median optical depth 0.6) and made of ice: asymmetry about 0.75 and the 22 degree
  halo.
- The sun's disc is 0.53 degrees across, limb-darkened, and coloured by the transmittance along its
  ray. Engines draw it at its true size and leave the glare to post-processing.

## Decision

1. **The cloud genera are weather fields.** Fifteen fields join `WEATHER_PRESET_FIELD_LIST`, so each
   weather owns them, the runtime's blender and the companion blend them, and a game can override
   them per preset (`rtx.weather.preset.<weather>.<weather>_<field>`). The fields:
   - the low layer's base (`cloudAltitude`), edge billows (`cloudDetailStrength`), cell size
     (`cloudCellSizeKm`, a step) and bake cover (`nvdfNominalCoverage`, a step);
   - the middle deck, altocumulus or altostratus (`cloudLayer2Enable`, a step, and its height,
     depth, kind, cover and density);
   - the high layer (`cirrusCoverage`, the shares `cirrusFibrous`, `cirrusSheet` and
     `cirrusDappled`, and `cirrusOpticalDepth`).

   The twelve presets map to genera (the table is in the [R17 report](../handover/R17-report.md)):

   | Weather | Clouds |
   |---|---|
   | clear | cumulus humilis and cirrus |
   | partly cloudy | cumulus mediocris, altocumulus patches and cirrus |
   | overcast | a closed stratocumulus deck under altostratus |
   | hazy | a cirrostratus veil with its halo |
   | foggy | stratus at 250 m |
   | drizzle | low stratus |
   | rain | nimbostratus |
   | thunderstorm | cumulonimbus with anvil cirrus |
   | snow, blizzard | nimbostratus |
   | sandstorm, smoggy | sparse high cumulus and thin cirrus |

   The clouds' densities rise to 3.5-8, so they shade.
2. **The cloud bodies bake at the weather's cover.** `nvdfNominalCoverage` is a step field. It
   switches at a blend's midpoint together with the cell size, so a change of weather re-bakes the
   bodies once (amortized over a few frames).
   - **Above 1 the deck closes.** The bake now accepts up to 2: every column then has full
     presence. Overcast bakes at 1.35, drizzle and snow at 1.5, fog, rain and blizzard at 1.6. The live
     cover counts such a bake as 1, so full cover keeps the deck as baked.
   - **The thin decks are drawn deeper.** The noise erosion carves through a slab thinner than about
     twice `nvdfProfileDepthKm`, so overcast, drizzle and fog are drawn 1.2-1.8 km deep. Real
     stratus is thinner but optically far thicker.

   The alternatives:
   - The option's auto mode (0) re-bakes at every 0.25 of cover, three visible re-bakes in one blend.
   - A larger `nvdfCoverageOffsetKm` would change every weather's response, and it empties a clear
     sky.
3. **The sun has a disc.** For primary rays only, `sunSize` across, limb-darkened (linear law, u =
   0.6). It is as bright as the sun's illuminance spread over it and coloured by the same Kasten-Young
   transmittance that lights the clouds and the moons.
   - Its centre is held to 48 times the daylight (the brightest channel of `sunIlluminance`).
     Physically it would be about 3e5, past half floats and white on screen long before.
   - It sits behind the clouds by their transmittance to the fourth power. The model's clouds are
     about ten times thinner optically than real ones, so a deck that leaves T = 0.01 still blots the
     sun out.
   - It hands over to the eclipse's own disc as the Moon approaches.
   - Reflections and indirect light keep the sun from its light, so they never count it twice.
   - Options: `rtx.atmosphere.sunDiskEnable`, `sunDiskBrightness`, `sunDiskLimbDarkening`.
4. **A 2D high cloud layer.** The cirrus family is drawn on one shell at `cirrusAltitude` (9 km), per
   sky ray, from a few octaves of 2D gradient noise. Its parts:
   - **Kinds:** streaks drawn out along the wind and bent by a broad warp (cirrus); an even veil
     (cirrostratus); grains about 0.2 km across in rows (cirrocumulus, under a degree as the WMO has
     them). The weather sets their shares.
   - **Optics:** ice scattering (asymmetry about 0.7) plus the 22 degree halo, red innermost. The halo
     fades as the veil thickens, because it is single scattering.
   - **Light:**
     - the sun from the layer's own height, which keeps it lit and red for a while after sunset;
     - the sky above it, and the sunlit ground and low air below it;
     - moon 0 and the airglow at night.
   - **Compositing:** it dims only the share of the sky's light made above it. An exponential
     atmosphere holds 1 - exp(-h / H) of its column below h, two thirds of the Rayleigh air at 9 km.
     It dims in full what lies beyond the air: the airglow, the moons, the disc and the stars.
   - **Detail:** each octave fades out as its wavelength nears the pixel's footprint, so the far layer
     does not shimmer. Rays other than the primary view take a coarse version.
   - **Drift:** the layer drifts along its own streaks, 1.6 times as fast as the low layer. The streaks
     turn after the wind at no more than 0.2 degrees a second, so a weather's new wind never swings
     the whole layer round.
5. **The middle deck skips its march when it has no cover** (most weathers keep it enabled at cover 0).
6. **The galaxy band and the nebula of the night-sky image fade in with astronomical twilight** (full
   at about 16 degrees down). The single stars keep their fade. The diffuse layers had been full by 9
   degrees down, a night sky in the middle of nautical twilight.

## Alternatives

- **Volumetric cirrus through the echo deck.** The deck shares the low layer's body field and noise
  (its cover is one uniform sheet), and a second march at 9 km costs a march for the thinnest clouds in
  the sky. The 2D layer is cheaper, has the cirrus shapes and the halo, and is what HZD and RDR2 do.
- **A sun glare sprite or a wider aureole.** The glare belongs to the camera's bloom, and a broad lobe
  is exactly the scattered lamp the user described.
- **New volumetric genera (anvils, towers).** The NVDF bake models columns from one placement field;
  cumulonimbus comes from tall cells, a deep layer and the type, and the anvil from the high layer.

## Consequences

- **Cost**, measured in the PoC (RESEARCH.md "R17: clouds and the sun"):
  - At 3840x2160 the high layer costs nothing measurable, up to 0.5 ms where the veil fills the view.
  - The middle deck costs 0.3-1.2 ms where it is drawn.
  - The weathers as a whole cost what they did, within about 0.4 ms.
  - At 1600x900 the game is CPU-bound and no frame time moved.
- A change of weather re-bakes the cloud bodies once, at the blend's midpoint. Cover, heights and
  densities still blend smoothly.
- The companion's weather table holds 51 of the 78 fields. `tools/weather_presets.py` now reads the fork
  as the runtime is built from it (its base commit with `runtime/patches`), because patch 0031 changes
  the presets.
- The dev menu shows the weather's values, greyed, for the fields a weather owns, the middle deck's
  among them.
- 41 new or changed menu strings are translated in the six catalogs (Codex, checked against the
  English for printf conversions and script).
