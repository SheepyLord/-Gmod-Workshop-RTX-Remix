# R18 report: R17's sky limits addressed

The user's request (2026-11-05), after R17:

> "Address the limits you left for later, make sure it is efficient without a lot of performance and
> memory constraint, ask questions if needed."

The limits are the ones R17's closing message named (thin decks drawn too deep, the middle deck without
a cover pattern of its own, no sun dogs, hazy's grey-brown haze) and the rest of the
[R17 report](R17-report.md)'s notes on the sky: the 46 degree halo, the cirrus' shadow on the ground and
the twilight sky's fade at 5 degrees down. Every choice had an answer in the physics or in a test, so no
question was asked.

Who did what:

- **Claude, in the main session on `r18`:** the engineering, the experiments and the tests.
- **Codex:** only translated the new menu text.

Decision: [ADR 0110](../decisions/0110-thin-decks-a-middle-deck-of-its-own-ice-arcs-a-milky-haze-and-twilight.md).

## What changed (runtime patch 0032, the companion's table)

**Thin decks close.** The low layer's density is its body's distance field, eroded by noise and ramped
over `nvdfProfileDepthKm` from the surface inward. At 0.6 km a deck needs about 1.2 km before its
middle reaches full density, and the erosion carves through anything thinner; R17 drew the stratiform
decks 1.2-1.8 km deep for that reason. The profile depth is now a weather field:

| Weather | Deck depth (R17 / R18) | Profile depth | Density (R17 / R18) | Bake cover (R17 / R18) |
|---|---|---|---|---|
| overcast | 1.8 / 0.9 km | 0.25 km | 5 / 7 | 1.35 |
| drizzle | 1.5 / 0.6 km | 0.18 km | 5 / 8 | 1.5 / 2 |
| foggy | 1.2 / 0.45 km | 0.15 km | 5 / 8 | 1.6 / 2 |

A bake cover of 2 makes every column of the deck whole, so none is thin enough to erode through. The
other weathers keep 0.6. The shape displacement (`nubis3ShapeVarietyKm`, up to half a km in and out at
2.4 km wavelengths) cut holes through a thin deck even then; it now shrinks with the profile depth, from
all of it at 0.6 to none at 0.1 (overcast 30 %, drizzle 16 %, fog 10 %).

**The middle deck has a cover of its own.** A 2D field in the deck's frame (gradient noise, three
octaves) lays out patches and bands about 14 km across and twice as long along the wind; the deck's
cover sets how much of the sky they fill (partly cloudy: 0.4, overcast's altostratus: 0.85).
- Outside a patch the cloudlets shrink away: the mask is the density sampler's cover against a nominal
  of 1, so a mask of 0 offsets the body field by 1.6 km, more than any body is deep.
- Inside one the deck reads layer 1's body field `cloudLayer2CellSizeKm / cloudCellSizeKm` times finer
  (2.6 times in partly cloudy): its cloudlets are 0.5 km across, a few degrees seen from below, as
  altocumulus elements are. They grow by 0.25 km in the field's units, so the cells nearly touch, and
  partly cloudy's deck density is 1.2 (R17: 0.6).
- The mask is read where a ray enters, crosses the middle of and leaves the deck. A ray that meets no
  patch marches nothing. The empty-space skip leaves the mask out of its bound, so it never steps over
  a patch.

**Sun dogs and the other ice halos.** Plate crystals that fall level make, for the sun and moon 0:
- the sun dogs, at the light's height, 21.9 degrees from a sun on the horizon, 23.1 at 20 degrees, 25
  at 30, none above 61, with a red inner edge and a white tail;
- the circumzenithal arc, an upside-down rainbow around the zenith 46 degrees above a sun at 20-25
  degrees, none above 32;
- with the 22 degree halo's random columns, the faint 46 degree halo.

They are phase terms of the high layer (`rtx.atmosphere.cirrusArcStrength`), weighted by the veil's and
the fibres' shares and faded as the layer thickens, for the primary view only.

**Hazy is a milky haze.** Its sky was a flat grey in dim, warm light: the preset flattened the air's
colour and warmed the sun, and the runtime's aerosol absorbs more than it scatters (an albedo of 0.48).
Two more weather fields: `aerosolAbsorption` scales `mieAbsorption`, and `mieAnisotropy` is the
aerosol's phase. Hazy now has 0.12 of that absorption (an albedo of about 0.88, as water and sulfate
haze have) and g = 0.8, with the clear sky's air colour and sun and a slightly denser aerosol (3): a
pale bluish-white sky under its veil. Auto-exposure evens out the brightness on screen, so the change
shows as colour: away from the sun, (118, 119, 120) in R17 and (113, 121, 131) now. Smog keeps its
brown.

**The twilight lasts.** The sky's light was faded out between the horizon and 5 degrees down. Now the
sky LUT's own twilight is kept whole to half of `rtx.atmosphere.twilightFadeDepth` (16 degrees) and
faded over the other half.

**Not done: the cirrus' shadow on the ground.** Ice scatters forward, within a few degrees of the sun,
so a veil of optical depth 0.35 takes about 2 % of the ground's light; the rest arrives as slightly
softer sunlight. A patchy shadow that faint would not survive the denoiser.

**The menu** gains Dust Absorption, Layer 2 Cell Size and Patch Size, Sun Dogs and Arcs, and Twilight
Depth; Profile Depth, Dust Absorption and Mie Anisotropy show the weather's values while one is set. 15
new entries in each of the six catalogs (Codex).

## Tested

All on `gm_construct` in the PoC (evidence in `out/r18` of the main checkout), each weather at the hours
that show it, with views toward the sun, away from it, high up, straight up, and for the halos a view 22
degrees above the sun. In every session the PoC lock was released and `client.vdf` and the loader's
config were put back byte for byte, with no Lua error.

- **Experiment 1** (`e1`, R17's runtime, the options set live):
  - overcast at 0.9 km had km-wide gaps at the old profile depth and closed at 0.25 km; drizzle at
    0.6 km (0.18) and fog at 0.45 km (0.15) closed too;
  - hazy with a tenth of the aerosol's absorption and the clear sky's air and sun turned from a dark
    grey-brown into a pale, milky blue; g 0.8 was milkier than 0.97.
- **Session 2** (`e2`, the first R18 build):
  - overcast closed and lumpy; drizzle closed in two views but had a km-wide hole in the third;
  - hazy milky at 11 h; at 17.5 h (sun 20 degrees) the sun dogs just outside the halo and the
    circumzenithal arc above;
  - twilight with the fade at 10 degrees: purple at 3.6 down, nearly black by 6.3; with the fade at 18,
    nothing left at 12.4 and 15.5 down (no glow, no blobs).
- **Session 3** (`e3`, the second build):
  - drizzle still had holes with every column whole: the shape displacement (up to half a km) cuts
    through a thin deck. It now shrinks with the profile depth;
  - the middle deck alone (layer 1 at density 0): patches of cloudlets beside the cirrus, but sparse,
    faint puffs. Inside a patch they now grow by 0.25 km (in the field's units) and partly cloudy's deck
    density is 1.2;
  - sun dogs (brighter) and the arc at 20 and 11.6 degrees of sun;
  - twilight kept whole to 8 degrees down: a purple sky over an orange band at 4.1 down, a deep blue
    with a glow over the sunset at 6.3, the glow alone at 7.8 and 9.1, night at 10.8.
## Cost and memory

At 3840x2160 (the GPU binds there; at 1600x900 the game is CPU-bound), the published R17 package and R18
in two sessions with the same states and views (the table is in RESEARCH.md, "R18"):

- **On average R18 costs what R17 did:** 11.62 ms over 17 views of six weathers against 11.77 ms.
- **The middle deck** costs 0.15-0.3 ms where it is drawn, as R17's did; its gaps cost nothing.
- **The sun dogs and the arc** cost nothing measurable (within 0.2 ms of noise).
- **Overcast toward the horizon costs 1 ms more** (13.3 against 12.3 ms): the march takes as many steps
  across the 0.9 km deck as across R17's 1.8 km one, so a grazing ray lights twice as many dense samples
  before it turns opaque. Its views toward the sun and overhead cost the same; drizzle is 0.2-0.7 ms
  cheaper.
- **Memory:** no texture, buffer or grid is added. The atmosphere's constants grow by 16 bytes, and
  the DLL by 2.7 MB of shader code (417,072,128 bytes).

## Publication and the field check

**Published.** `r18` was merged into `main` as `daf4ce9` and pushed (`6e4c46f..daf4ce9`; one LFS object
of 61 MB, the runtime). The post-merge hook built the package here and uploaded it to item 3829070317 as
0.0.0-dev.20261105202808+39480017 (1,814,543,303 bytes; the pre-push hook's run found the same inputs).
Its `d3d9.dll` is the one tested in the PoC (SHA-256 `7d8a0ad8...`); its weather table differs from the
tested package's only in line endings (a CRLF checkout). The package workflow on GitHub was not started.

**Checked in the field.** Before the starts, no other lab, game or PoC lock was active.
`tools\steam\verify_install.py` found the field install intact; only the user's `autoexec.cfg` differs.
The field's `cfg/client.vdf` (the companion's sky settings) was saved first and is byte-identical afterwards;
`config.cfg` was put back by the session. Evidence: `out\r18\field\` in the main checkout.

| Start | Result |
|---|---|
| 01-download | Steam downloaded the new item (`gmod-rtx-remix-0.0.0-dev.20261105202808_39480017.gma`, 1,814,543,303 bytes) as the game started; the game still ran R17's 235d458f (the first start only downloads). The map loaded and the game quit normally |
| 02-sky | Deployed and active: 0.0.0-dev.20261105202808+39480017. The sky probe on `gm_construct` under the user's own settings showed partly cloudy with cumulus and cirrus, overcast as a closed grey deck, hazy at 17.5 h with the 22 degree halo, the sun dogs and the circumzenithal arc, and the blue hour with its orange glow 6.3 degrees after sunset. Frames took 7.8-8.2 ms, with no Lua error and a normal quit |

## Notes for the next round

- **The middle deck's cloudlets are layer 1's bodies, read finer.** Inside a patch they follow layer 1's
  bake: broken cumulus makes altocumulus cells, and a closed deck (overcast) makes an altostratus sheet.
  A body field of its own would let them differ more, for 8 MiB and a second bake.
- **The aerosol is optically thin in this model.** `aerosolDensity` 1 is a vertical optical depth of
  about 0.005, so the weathers make their haze with the air's colour, the veil and the volumetric fog. A
  real haze or dust storm (0.3-1 and more) would need a thicker aerosol layer (a larger scale height,
  or a haze layer of its own).
- **Not drawn:** the upper tangent arc and the parhelic circle; the cirrus' shadow on the ground (about
  2 % of the light, see above).
- **Already in the sky before R18:** the dark wireframe object above `gm_construct` that shows in many
  views toward the sun, likely part of the map, and the bright shaft in R17's thunderstorm shot.