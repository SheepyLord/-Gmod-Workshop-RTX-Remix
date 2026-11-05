# 0110: Thin decks close; the middle deck has a cover of its own; sun dogs; a milky haze; a longer twilight

- Status: Accepted 2026-11-05
- Decided by: the agent in R18, on the user's request: "Address the limits you left for later, make sure
  it is efficient without a lot of performance and memory constraint, ask questions if needed." The
  limits are the ones [ADR 0109](0109-cloud-genera-per-weather-a-sun-disc-and-a-high-cloud-layer.md) and
  the [R17 report](../handover/R17-report.md) left. None needed the user's choice, so none was asked.
- Runtime patch: `runtime/patches/0032-*` ([runtime/README.md](../../runtime/README.md)).

## Context

R17 left these limits, in its closing message and its report:

1. **Thin decks did not close.** The low layer's density is its body's signed distance field eroded by
   noise, ramped over `nvdfProfileDepthKm` (0.6 km) from the surface inward. A deck thinner than about
   twice that never reaches its full interior, and the erosion carves through it. So R17 drew overcast,
   drizzle and fog 1.2-1.8 km deep, where real stratus is 0.2-1 km.
2. **The middle deck had no cover of its own.** The echo deck reads layer 1's body field at its own
   height, with one uniform cover. Its patches were layer 1's cells, and it closed wherever layer 1 had
   baked a closed deck.
3. **No sun dogs**, nor the other halos of ice: the 46 degree halo, the circumzenithal arc.
4. **Hazy was a flat grey sky in dim, warm light.** Its preset flattened the air's colour (Rayleigh
   (7, 11, 20)e-3) and warmed the sun (17, 16, 14), and the runtime's aerosol absorbs more than it
   scatters (`mieAbsorption` 4.4e-3 against `mieScattering` 4.0e-3 per km, a single-scattering albedo
   of 0.48), which hazy nearly doubled.
5. **The twilight sky went black at 5 degrees below the horizon**, a guard against the sky LUT's
   residual glow, in the middle of civil twilight.

## Decision

1. **A thin deck closes with a shallow profile.** `nvdfProfileDepthKm` becomes a weather field. Overcast
   draws a 0.9 km deck at 0.25 km, drizzle 0.6 km at 0.18, fog 0.45 km at 0.15, with densities of 7-8
   so they stay grey. Drizzle and fog bake at a cover of 2, so no column of the deck is thin. The other
   weathers keep 0.6. Experiment 1 (`out/r18/e1`, the R17 runtime with the options set live): a 0.9 km
   deck has km-wide gaps at 0.6 and is closed at 0.25.
   - **The shape displacement shrinks with the profile depth.** `nubis3ShapeVarietyKm` pushes and pulls
     the body surface by up to half a km at 2.4 km wavelengths, which cut smooth km-wide holes through
     the 0.6 km drizzle deck even with every column whole (session 3). It is scaled by
     `saturate((profileDepth - 0.1) / 0.5)`: all of it for the cumulus weathers at 0.6, 30 % for
     overcast, 16 % for drizzle, 10 % for fog. Overcast keeps its lumpy base from the erosion.
2. **The middle deck has a cover of its own.** A 2D field in the deck's frame says where the deck is:
   patches and bands `cloudLayer2PatchSizeKm` (14 km) across, longer along the wind, filling the share
   of the sky that its cover asks for.
   - Outside a patch the cloudlets shrink away. The mask is the sampler's cover against a nominal of 1,
     a level-set offset of up to 1.6 km in the field's units, more than any body is deep.
   - Inside a patch the deck reads layer 1's body field `cloudLayer2FieldScale` times finer, so its
     cloudlets are `cloudLayer2CellSizeKm` (0.5 km) across, whatever layer 1's cell size. Altocumulus
     elements are 1-5 degrees across (WMO). The bodies also grow by 0.25 km (in the field's units),
     so the cells of a broken layer 1 nearly touch, and partly cloudy's deck density is 1.2: at
     R17's 0.6 and without the growth the cloudlets were faint, sparse puffs (session 3).
   - The mask is read where a ray enters, crosses the middle of and leaves the deck. A ray that meets no
     patch marches nothing, so the gaps cost nothing. The empty-space skip leaves the mask's shrink out
     of its bound, so the bound holds for any mask.
   - No second body field: a second NVDF would hold 8 MiB more, and its bake would cost as much again.
3. **Plate crystals make sun dogs and the circumzenithal arc**, as phase terms of the high layer, for
   the sun and moon 0. Ice's index for red, green and blue light is 1.3072, 1.3104 and 1.3160.
   - **The sun dogs** sit at the light's height, at the minimum deviation of a 60 degree prism for
     Bravais' index sqrt(n^2 - sin^2 e) / cos e: 21.9 degrees from a sun on the horizon, 23.1 at 20
     degrees, 25 at 30, none above 61. A sharp red inner edge, a white tail outward.
   - **The circumzenithal arc**: an arc around the zenith at elevation asin(sqrt(n^2 - cos^2 e)), 46
     degrees above a sun at 20-25 degrees, none above 32. Red toward the sun.
   - **The 46 degree halo**: from the same random columns as the 22 degree one, a tenth as bright.
   - The veil and the fibres hold the plates (`0.6 sheet + 0.45 fibrous + 0.1 dappled` of the shares),
     faded with the layer's optical depth like the halo. Primary view only.
     `rtx.atmosphere.cirrusArcStrength`.
4. **Hazy is a milky haze.** Two more weather fields:
   - `aerosolAbsorption` scales `mieAbsorption`: hazy 0.12, an albedo of about 0.9, as water and sulfate
     haze have;
   - `mieAnisotropy`: hazy 0.8, broader than the clear sky's 0.97.

   Hazy's air colour and sun are the clear sky's, and its aerosol is a little denser (3). Its sky is a
   pale bluish white under the veil (R17's, measured in the same view, was a neutral grey). The aerosol's
   optical depth is small in this model (about 0.014 at 3; 10 and 25 changed the sky little), so the air
   colour and the veil do most of it. The other weathers keep their values, so smog stays grey-brown.
   Both fields fall back to the configuration where every preset agrees, like the air's colour.
5. **The twilight lasts.** The sky LUT's own twilight is kept whole to half of
   `rtx.atmosphere.twilightFadeDepth` (16 degrees) and faded out over the other half. The LUT already
   dims by orders of magnitude by 8 degrees down. Session 2 (`out/r18/e2`) found no glow and no blobs
   left at 12 and 15 degrees down with the fade at 18.

## Alternatives

- **Less erosion for stratiform types** instead of the profile depth: the erosion is what gives the
  deck's base its lumps; the profile depth only changes how deep the soft edge goes.
- **A second body field (NVDF) for the middle deck**: its own bodies at its own cover and cell size,
  for 8 MiB of memory and a second bake. The patch mask and the finer reading give it a cover and a
  cloudlet size of its own for a few ALU per ray.
- **Analytic altocumulus (2D cells with a profile)**: a new density model, outside the lighting the
  rest of the clouds share.
- **The cirrus' shadow on the ground**: thin ice scatters forward, within degrees of the sun, so the
  ground's light barely changes (about 2 % at the veil's optical depth). Left out.
- **A brighter global aerosol** (changing `mieAbsorption`): every weather would change; only hazy needs
  it.

## Consequences

- Cost and memory: see the [R18 report](../handover/R18-report.md) and RESEARCH.md "R18". No texture or
  buffer is added; the constant buffer grows by one 16-byte row.
- The companion's weather table holds 54 of the 81 fields.
- 15 new menu strings, translated in the six catalogs.
