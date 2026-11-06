# blood-overhaul-rtx

The redistributable part of SheepyLord's Blood Overhaul RTX, plus R20-C's new client impacts.
Read-only source: `H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx`.
The owner's original README explicitly distinguishes the new patterns from Crunchy's originals.
`tools/prepare_blood.py` makes an import-ready tree from that project. Builds thereafter use only
this repository. The owned code/assets use this repository's MIT licence at the owner's request.
Credit Crunchy's [2022 Blood Overhaul](https://steamcommunity.com/sharedfiles/filedetails/?id=2683396098)
for the base/style; subscribing is optional. **The eighteen new patterns were made with an AI image
model**, using Crunchy's textures as style references. No reference image is distributed. The
original prompts are in `licenses/prompts.json` and the selection audit is in
`licenses/provenance.json` (109 selected source files, 270 excluded output files, SHA-256s/reasons).

## Shipped

- Eighteen generated patterns: arterial_trail, castoff_sweep, dark_core_halo, directional_spray,
  double_impact, drip_runs, drops_scatter, heavy_splash, impact_dense, long_swipe, mist_cloud,
  pooled_smear, ring_spatter, shotgun_clusters, sparse_mist, spray_fan, streak_web, torn_blotches.
- Their 36 natural/neutral VTFs and 72 PBR DDS maps, unchanged. Wet/drying roughness, meniscus normal,
  zero metallic; both XXH64 and XXH3, 72 filtered material blocks. Textures load when used.
- New world/model VMTs for red, yellow, green/zombie and worker blood; twelve original colour schemes
  and a private eighteen-shape list. No stock material names are overridden.
- Original analytic 128px droplet and 64px mist textures, generated without an existing image.
- The packager attaches the maintained companion bootstrap, core, budgets, effect and settings panel
  from `companion/nativeloader`, plus the licence and shipped credits.

## Excluded

No file from `backup/Blood Overhaul (original)` is imported. `bo_blood1..8`, `bo_yblood1..6`, flesh,
alien flesh, antlion impacts and bloodstains, their VTFs and all DDS/PBR maps derived from them are
excluded. The old `particle/bo_droplets/drop.vtf` is also excluded: `tools/publish.py` made it from
Crunchy's blood8. Global blood/antlion subrect VMT overrides and the unfiltered USD layers are
replaced by owned-only files. Original images, source reference images, full GMAs/ZIPs, previews,
backups, logs and development work never enter the part. The old mixed shape list/mixer/menu are
replaced by the companion's private implementation; original owned colour schemes are retained.

## Behaviour and updating

Deploys to `garrysmod/addons/nlblood` and `rtx-remix/mods/nl_blood_overhaul_rtx`; legacy folders remain
beside them. An exact-path guard skips four legacy blood Lua modules so only the owned mixer runs.
The blood panel is in RTX Remix / Blood, translated in all six companion catalogs. Disabling the
master/impact control or setting amount to zero uses the engine's unmodified impact dispatch. No
shared PCF/material is hidden; Crunchy's content still works if installed separately.

The effect is ordinary `ParticleEmitter`/`util.DecalEx`, with no new networking or native code.
Hard bounds: 640 particles/s, 512 live, 42 per event, 80 events/s; 48 stains/s and 384 until explicit
decal clearing/map cleanup. Effect scale approximates damage; the event has no exit-wound data.
See [ADR 0119](../../docs/decisions/0119-client-blood-impacts-with-bounded-spatter.md).

259 indexed inputs; 110 binaries, **55,518,444 compressed bytes** (about 52.95 MiB). Source PNGs and
unneeded original/derived maps are excluded; natural/neutral variants share normal/roughness maps.
Import only the final inventory through `inputs.py import`, once per binary. The SHA-256 audit and
prompts are part documents, not extra game assets; CREDITS.txt and LICENSE are shipped too.
