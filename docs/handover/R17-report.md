# R17 report: a sky that fits the weather, and the package workflow started by hand

The user's request (2026-11-05):

> "Very good, we only build the workshop package when actual release. During development, we still build
> gma on local and update to the workshop. All workflows to build the large gma package should only be
> initiated by human.
>
> Make a QoL updates: 1. Implement a better sun and cloud in Numos. The current cloud is very monotonic
> with the sun only being a scattered lamp, and must fit the weather. The current cloud is also not
> volumetric. Your task is to research available sources for cloud types and cloud shapes and implement a
> better and efficient atmospheric system based on Numos. Test and push to workshop and Github after you
> finish."

With a chart of the cloud genera by height, and a note during the work: "You may download available
resources for cloud types and real-time cloud methods. Check different time to avoid shading and
brightness problem. You should decide yourself and not ask for human intervention."

Who did what:

- **Claude, in the main session on `r17`:** the engineering and the tests.
- **A Claude research subagent:** the sources (WMO Cloud Atlas, Met Office, lidar climatology, the
  real-time cloud talks, the solar optics), in [RESEARCH.md](../RESEARCH.md), "R17: clouds and the sun".
- **Codex:** only translated the new menu text.

Decisions:

- [ADR 0108](../decisions/0108-releases-built-on-github-by-hand-development-built-here.md): the
  workflow.
- [ADR 0109](../decisions/0109-cloud-genera-per-weather-a-sun-disc-and-a-high-cloud-layer.md): the
  sky.

## The package workflow

`package.yml` starts only by hand (`workflow_dispatch`): a person runs it for a release, and
`publish_workshop.py --from-ci --commit <sha>` uploads that run's `.gma`. During development the hooks
are back to building the package locally: after commits and merges on `main`, and before pushes of it.
They upload when the content changed. `--local-upload` is gone. Tests:
`test_the_package_workflow_starts_only_by_hand`, and the hooks test checks that no hook calls
`--from-ci`.

## The sky

### What was wrong

From the PoC study (`out/r17/base1`, `ab-detail`, `ab-density`; details in RESEARCH.md):

- **Every weather had the same cloud:** one layer at 1.3 km with 2 km cells and no edge detail. Its
  density was 0.4-3, so the clouds were translucent and flat.
- **Overcast, rain and fog kept km-wide blue gaps.** The cloud bodies bake at a pinned cover of 0.65,
  and the weather's cover only moved their surface by 70 m.
- **There was no sun disc outside an eclipse.** The sun was the broad Mie glow of the sky.

### What changed (runtime patch 0031, the companion's table)

**Cloud genera for each weather.** Fifteen new weather fields:

- the low layer's base, edge billows, cell size and bake cover;
- the middle deck (altocumulus, altostratus): on/off, height, depth, kind, cover, density;
- the high layer: cover, the three kinds' shares, optical depth.

The densities rise to 3.5-8, so the clouds shade. The decks of overcast, drizzle, fog, rain and snow
are baked at a cover above 1, which closes them. The presets:

| Weather | Low: base / depth km, cover, kind, density, billows, cell km, bake cover | Middle deck: height / depth km, kind, cover, density | High: cover, fibrous / veil / dappled, optical depth |
|---|---|---|---|
| clear | 1 / 0.7, 0.1, 0.85, 6, 0.7, 0.9, 0.25 | none | 0.18, 1 / 0 / 0, 0.25 |
| partlyCloudy | 1 / 1.5, 0.45, 0.9, 6, 0.8, 1.3, 0.5 | 4.2 / 0.6, 0.45, 0.18, 0.6 | 0.25, 0.8 / 0 / 0.2, 0.3 |
| overcast | 0.9 / 1.8, 1, 0.3, 5, 0.4, 2.5, 1.35 | 3.5 / 1.5, 0.05, 0.85, 0.8 | none |
| hazy | 1.1 / 0.8, 0.1, 0.8, 5, 0.6, 1, 0.25 | none | 0.85, 0.15 / 0.9 / 0, 0.35 |
| foggy | 0.25 / 1.2, 0.95, 0, 5, 0.2, 3, 1.6 | none | none |
| drizzle | 0.45 / 1.5, 0.97, 0.05, 5, 0.3, 3, 1.5 | none | none |
| rainstorm | 0.7 / 3.5, 1, 0.3, 7, 0.4, 4, 1.6 | none | none |
| thunderstorm | 1.1 / 6.5, 0.75, 1, 8, 1, 4.5, 0.75 | none | 0.7, 0.4 / 0.6 / 0, 1.2 |
| snow | 0.6 / 2.5, 0.97, 0.25, 6, 0.3, 3.5, 1.5 | none | none |
| blizzard | 0.35 / 3, 1, 0.25, 7.5, 0.3, 4, 1.6 | none | none |
| sandstorm | 2 / 1, 0.05, 0.5, 3, 0.5, 2, 0.25 | none | 0.1, 1 / 0 / 0, 0.2 |
| smoggy | 1.2 / 0.8, 0.15, 0.8, 5, 0.6, 1, 0.25 | none | 0.15, 0.5 / 0.5 / 0, 0.2 |

**The sun disc.** True to size (`rtx.atmosphere.sunSize`), limb-darkened, and coloured by the air
toward the horizon. Its centre is held to 48 times the daylight, which shows as pure white, with
soft two-pixel edges and no ringing after upscaling. Clouds hide it by their transmittance to the
fourth power, since the model's clouds are about ten times thinner than real ones. Thin cirrus dims it,
and it hands over to the eclipse's disc. It is drawn for the camera's view only; reflections keep the
sun from its light.

**The high cloud layer.** A 2D shell at 9 km. Its kinds:

- fibrous cirrus: streaks along the wind, bent by a broad warp;
- the cirrostratus veil, with the 22 degree halo (red inside) around the sun and the moon;
- cirrocumulus grains in rows.

It is lit by the sun at its own height (lit and red after sunset), the sky above, the ground and low
air below, and the moon at night. It dims only the third of the skylight made above it, and in full
the airglow, moons, disc and stars. Detail fades with the pixel's footprint, and reflections take a
coarse version. It drifts along its streaks, turning slowly after the wind.

**Twilight.** The galaxy band and the nebula of the night-sky image fade in between 8 and 17.5 degrees
below the horizon. Before, they were plain at 3.6 degrees down. The stars and the twilight sky keep
their fades.

**The menu.** The dev menu gains Sun Disc (Disc Brightness, Limb Darkening), High Clouds and Edge
Billows. While a weather is set, the fields it owns show its values greyed, the middle deck's among
them. All of it is translated (Codex; 42 entries in each of the six catalogs, three of them option
descriptions earlier patches had left out of `remix.pot`).

**Tools.** `tools/weather_presets.py` now reads the fork as the runtime is built from it: the base
commit with `runtime/patches`. Patch 0031 changes the presets, so the fork's checkout alone is not what
the runtime has. The companion's table holds 51 of 78 fields.

### Tested

Five PoC sessions on `gm_construct` (`out/r17/r17a` to `r17e`), each weather at several hours, with
three views per state: toward the sun, away from it, and overhead. The pictures by time of day:

- **Noon and afternoon:**
  - clear: cumulus humilis under fibrous cirrus;
  - partly cloudy: shaded cumulus mediocris, silver linings, cirrus above;
  - hazy: a neutral milky veil with the halo;
  - thunderstorm: dark cumulonimbus and anvil cirrus;
  - rain, snow and blizzard: closed dark-grey decks;
  - sandstorm and smog: orange and grey skies with the disc.
- **Golden hour and sunset:** warm-lit cumulus, a reddened disc on the horizon, and cirrus glowing
  after the sun has set.
- **Twilight:** at -4 degrees a pink afterglow with lit cirrus streaks; at -7 degrees stars only; from
  -10 degrees the galaxy fades in; by -16 degrees it is full.
- **Night:** stars dimmed by the veil; the moon behind the high layer.

The last session (`r17e`) checked the final tuning:

- overcast: a closed, lumpy grey stratocumulus deck, the sun a diffuse patch;
- drizzle and fog: mostly closed, with small breaks;
- overcast at sunset: a warm grey-pink underside, the sun glowing under its edge;
- rain at sunset: dark;
- partly cloudy and hazy: as before.

In every session the PoC lock was released and its `client.vdf` and loader config were restored byte for byte.

Cost (RESEARCH.md has the table):

- At 1600x900 every view took 7.3-7.8 ms; the game is CPU-bound there.
- At 3840x2160, against the published runtime:
  - the high layer costs nothing measurable (up to 0.5 ms where the veil fills the view);
  - the middle deck costs 0.3-1.2 ms where it is drawn;
  - partly cloudy takes +0.4 ms on average, hazy is 1 ms faster (fewer low clouds), and overcast is
    about the same.

`tools\test.ps1 -Config Release` passed: 26 C++ tests, 631 Python tests (28 + 25 + 578) and the
repository checks.

## Publication and the field check

**Published.** `r17` was merged into `main` as `9a26513`, the hooks were reinstalled
(`--install-hooks`), and `main` was pushed (`0e2faef..9a26513`; one LFS object of 61 MB, the runtime).
The new pre-push hook built the package here and uploaded it to item 3829070317 as
0.0.0-dev.20261105113014+235d458f. Its `d3d9.dll` is the one tested in the PoC (CRC `051ce50c`); its
weather table differs from the tested package's only in line endings (a CRLF checkout).

**Checked in the field.** Before the starts, no other lab, game or PoC lock was active.
`tools\steam\verify_install.py` found the field install intact; only the user's `autoexec.cfg` differs.
The field's `cfg/client.vdf` (the companion's sky settings) was saved first and is byte-identical
afterwards; `config.cfg` was put back by the session. Evidence: `out\r17\field\` in the main checkout.

| Start | Result |
|---|---|
| 01-download | Steam downloaded the new item: `gmod-rtx-remix-0.0.0-dev.20261105113014_235d458f.gma`, 1,811,842,490 bytes. The game still ran fbce366a (the first start only downloads). The map loaded and the game quit normally |
| 02-sky | Deployed and active: 0.0.0-dev.20261105113014+235d458f. The sky probe on `gm_construct` under the user's own settings showed partly cloudy with shaded cumulus, cirrus and the disc; overcast as a closed deck; hazy with the veil and its halo. Frames took 7.6-8.0 ms, with no Lua error and a normal quit |

## Notes for the next round

- **The middle deck shares the low layer's body field.** It has no cover field of its own (a uniform
  sheet), so altocumulus patches come only from its noise. A real field of its own would be a larger
  change to the march.
- **The thin stratiform decks are drawn 1.2-1.8 km deep.** The erosion carves through anything
  thinner than about twice `nvdfProfileDepthKm`. A per-weather profile depth would let a real
  0.5 km stratus close.
- **The hazy preset's own atmosphere is grey-brown** (aerosol 1.9, a warm sun). The veil no longer
  adds to that.
- **Not drawn:** sun dogs, the 46 degree halo and the cirrus' ground shadow. The twilight sky still
  fades out by 5 degrees down: the fork's guard against its LUT's residual glow, which R17 left alone.
- **Already in the sky before R17:** a dark wireframe object above `gm_construct`, in the old shots
  too; and a bright shaft in one thunderstorm shot, likely the fork's lightning.
