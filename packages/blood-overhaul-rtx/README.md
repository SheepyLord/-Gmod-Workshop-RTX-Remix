# blood-overhaul-rtx

SheepyLord's Blood Overhaul RTX, including Crunchy's Blood Overhaul resources and their PBR by
permission, plus R20-C's bounded client impacts. Read-only source:
`H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx`. `tools/prepare_blood.py` prepares final
inputs; package builds thereafter need only this repository.

Resources by Crunchy, [2022 Blood Overhaul](https://steamcommunity.com/sharedfiles/filedetails/?id=2683396098),
and the PBR derived from them are bundled here. On **2026-11-06** SheepyLord reported the resource
author's permission and asked for the resources to be packaged and published with this project's
RTX package (Workshop item 3829070317), whose inputs this public repository holds. The permission's
terms were not provided. The resources and derivatives remain the author's and **are not under
this repository's MIT licence**. See `licenses/CRUNCHY-RESOURCES.txt` and `licenses/CREDITS.txt`;
no general licence is granted. Owned code/assets retain MIT. No separate subscription is required.

**The eighteen new patterns were made with an AI image model**, using Crunchy's textures as style
references. Source/reference images do not ship. Original prompts remain in `licenses/prompts.json`.
Schema 2 `licenses/provenance.json` audits all 1,477 source-project files: 437 selected unchanged
source files, 1,040 excluded files, reasons/SHA-256s and generated outputs. The original MD5 inventory
identifies 68 unchanged Crunchy files and 14 edited files among the selected source bytes;
conversions/derived PBR and generated patterns have distinct authorship labels.

## Shipped

- Eight original patterns, `bo_blood1..8`, natural and neutral, plus eighteen generated patterns:
  arterial_trail, castoff_sweep, dark_core_halo, directional_spray,
  double_impact, drip_runs, drops_scatter, heavy_splash, impact_dense, long_swipe, mist_cloud,
  pooled_smear, ring_spatter, shotgun_clusters, sparse_mist, spray_fan, streak_web, torn_blotches.
- All runtime VMT/VTF resources from `dist/addon` except the unused old droplet: stock-name
  blood1..8/yblood1..6 and subrects, stains, flesh/alienflesh and antlion impacts, the original
  converted neutral textures and all generated patterns. Selected source bytes are unchanged.
- All 177 source PBR DDSs: wet/drying roughness, meniscus normals, zero metallic; all 182 XXH64/XXH3
  material overrides retained with lazy loading. Every shipped DDS is referenced and every reference
  ships. With the analytic sprites the one private replacement layer has **179 DDSs, 186 entries**.
- Red/alien world/model VMTs from the source, and generated green/worker world/model variants for
  all 26 shapes, at the original published world sizes; twelve schemes and a private shape list.
- Original analytic 128px droplet and 64px mist textures, generated without an existing image.
- Two small sprite-opacity DDSs and four material entries retain their live tint in path tracing,
  with a low scene-adaptive intrinsic fill. World stains remain non-emissive. Their source hashes
  and recipe are in `licenses/particle-pbr.json` and `tools/prepare_blood_particles.py`.
- The packager attaches the maintained companion bootstrap, core, budgets, effect and settings panel
  from `companion/nativeloader`, plus the licence and shipped credits.

## Excluded

The old `particle/bo_droplets` VTF/VMTs are unused: the analytic droplet/mist replace them. Legacy
Lua, source/reference images, GMAs/ZIPs, previews, backups, logs and development work stay out.
The mixer/menu live in the companion; the original scheme data and shape sizes have private paths.
USD layers are assembled under the private mod identity, retaining all source material entries,
lazy loading and the analytic sprite entries. No file is taken from the backup tree for packaging;
the full `dist/addon` is the runtime source and the backup MD5 list is comparison evidence only.

## Behaviour and updating

Deploys to `garrysmod/addons/nlblood` and `rtx-remix/mods/nl_blood_overhaul_rtx`; legacy folders remain
beside them. An exact-path guard skips four legacy blood Lua modules so only the owned mixer runs.
The blood panel is in RTX Remix / Blood, translated in all six companion catalogs. Stock materials
now show Blood Overhaul's textures/PBR while the package is active. Schemes reach engine subrect
and flesh/alienflesh/antlion materials as in the original add-on. The master switch restores every
Lua-changed base texture/tint and disables mixing/extra impacts. It does not unmount packaged
resources/PBR or clear existing decals. Impact off or amount zero uses native impact dispatch.
No shared PCF/material is hidden. Subrect/foreign shaders are not retinted through shared parents.

The effect is ordinary `ParticleEmitter`/`util.DecalEx`, with no new networking or native code.
Hard bounds: 640 particles/s, 512 live, 42 per event, 80 events/s; 48 stains/s and 384 until explicit
decal clearing/map cleanup. Effect scale approximates damage; the event has no exit-wound data.
See [ADR 0119](../../docs/decisions/0119-client-blood-impacts-with-bounded-spatter.md).

**550 indexed inputs; 272 binaries; 365,184,772 uncompressed bytes; 109,378,436 compressed binary
bytes**, 109,680,367 total stored bytes. R20's 261 inputs/112 binaries held 138,668,672 bytes in
55,523,212 compressed binary bytes. R21 adds 287 inputs/160 binaries and **53,855,224 compressed
binary bytes** (51.36 MiB). The unchanged R20 binaries are reused; new binaries are imported once
through `inputs.py import`, after final preparation. Natural/neutral variants share normal/roughness
maps. The SHA-256 audit/prompts are part documents; CREDITS.txt, the scoped MIT LICENSE and the
resource permission notice ship in the add-on.

The review indexed the two shipped notices under `notices/` with a text-only import (2,556 bytes).
Their readable copies remain under `licenses/`, a reserved part-document directory that
`inputs.py import` does not index. The package's `--add-to-addon` flags read the unpacked indexed
copies. All 272 existing binary entries, compressed hashes and LFS objects are unchanged.

See [ADR 0124](../../docs/decisions/0124-blood-overhaul-resources-by-permission.md) for the superseded
R20 exclusions and off-switch scope. A winning legacy VMT remains that add-on's VMT. With Crunchy's
original Subrect/DecalModulate files winning, the PBR layer keeps red/yellow engine blood visible,
but those engine decals retain their natural colours: the controller safely skips those shaders
and their shared parents. All four private mixer families still accept every scheme. For schemes
on the engine decals too, disable the duplicate original add-on so this part's alpha VMTs win.
The field-style Blood Overhaul RTX copy has the same modern VMT bytes and a guarded legacy mixer.
The [R21-A report](../../docs/handover/R21-A-report.md) records actual winners and PoC evidence.
The review's package-only player-step comparison uses the published R20 natives for both packages.
Native blood appears after clearing/cleanup and in the selected R21 scheme. The small Lua impact
stains are not visible on the white test floor in either published R20 or R21, initially or after
clearing, waiting ten seconds or changing maps. That pre-existing visual limitation remains open;
the report records the exact steps, screenshots, counters and unchanged-runtime comparison.
