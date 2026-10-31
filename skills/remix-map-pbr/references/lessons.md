# Lessons from the three remasters

Each entry: what you would see, why, what fixed it, and where and when it was found (local dates). PR =
gm_poolrooms (2026-10-26), BR = the Backrooms maps (2026-10-27/28), MH = modern_house (2026-10-27/29).

## Skinned models and engine settings

**R3-016: limbs, clothes and hair in bind pose around the pelvis** (MH, found by the user, fixed 2026-10-29)
- Symptom: on modern_house, new HSR characters, their ragdolls, the player model and the hands were drawn
  with every limb at the pelvis; Model Hotloader's models and models with a `.sw.vtx` looked right.
- Cause: the remaster scoped `r_forcehwlight 1`. The RTX fixes then light every model on the GPU, and with
  `r_forcehwskin 0` Source skins a model without a `.sw.vtx` through its fixed-function hardware path,
  which never sets `D3DRS_VERTEXBLEND`, indexed blending or `WORLDMATRIX(1+)`. Remix reads that as "not
  skinned" and draws the mesh rigid on its first bone. The classic install never had it on: its launch
  option `+r_forcehwlight 1` runs before the variable exists.
- Fix: Modern House no longer sets it (fork `claude/modern-house-rtx` `e96ad7f`; item 3829275998 updated to
  `0.0.0-dev.202610300425+d7efd636`); the user confirmed the models in game. `mat_softwareskin 1` would
  cover it, but it is a cheat variable that Source resets when `sv_cheats` goes back to 0. Rule: no add-on
  forces `r_forcehwlight 1` (this repository's QoL handover, R3 triage, RESEARCH.md section 32).
- Still open: the Backrooms addon (`gm_br_rtx/lua/autorun/br_rtx.lua`, on both its branch and the Modern
  House branch) still scopes `r_forcehwlight 1`, and `docs/GM_BR_RTX.md` and `docs/MODERN_HOUSE_RTX.md` still
  say "models use hardware lighting". Backrooms measured a real cost of turning it off: 34.7 → 62 ms a frame
  in a whole-map state on gm_br_complex (2026-10-27, before the `r_novis` fix). Re-measure in the PAS state
  and let the user decide; until then do not copy that line into a new map.

**`r_forcehwskin 1` draws player and NPC models as flexed faces without bodies** (BR, 2026-10-27)
- gmRTX persists `r_forcehwskin` in GMod's `cl.db` cookie table and applies it at startup; a test left it at
  1 and the row had to be removed. Don't set it.

**Calling gmRTX's model reload mid-game crashes** (BR, 2026-10-27)
- `RTX_ReloadModelsAfterHardwareSkinningSettings()` crashed GMod twice in the MDLCache flush; gmRTX calls it
  only during a load. Don't call it from a test.

**`sv_cheats 0` changes the session** (BR, 2026-10-27)
- It resets every cheat variable gmRTX's `autoexec.cfg` set (`r_novis`, `mat_softwareskin 1`,
  `mat_frame_sync_enable 0`, `mat_fastnobump 1`, `r_unloadlightmaps 1`, ...). A session where it happened is
  not normal GMod RTX; Backrooms' first stock figure (128 ms) and its fast "first session" came from one.

**Archived convars keep their saved value** (MH and BR, 2026-10-27/28)
- An archived client convar is written to `cfg/client.vdf` even at its default, so changing the default never
  reaches an install where it was saved (`mhrtx_pvs` and `brrtx_pvs` defaulted to 1). Rename the convar
  (`mhrtx_cull_pvs`, `brrtx_vis`).

## Visibility and frame time

**Rooms next door vanished from the ray-traced scene** (MH 2026-10-27, BR 2026-10-28; the user's report)
- Symptom: the user, playing with DLSS and frame generation at about 200 fps, found "the culling is too
  aggressive and when entered a room, the room next to it are hidden". Reflections, shadows and bounce from
  neighbouring rooms were missing.
- Cause: the client drew only the engine's PVS (the remaster had turned it back on), lights were switched by
  distance, and the server sent only entities in the player's PVS (a fifth of modern_house; on Backrooms the
  PVS is about 1 % of the map).
- Fix: MH draws everything, keeps all 341 lights on, and adds 31 PVS-cover points to every player's PVS on
  the server (16.6 ms against 17.1 ms, within the noise). BR widens every PVS lookup to the PAS
  (`rtx_patch_vis_pas`, 2-5 % of the map; 13.2 against 13.6 ms) and switches its lights by PAS with no
  distance limit. The user confirmed both, with no performance change.

**Fresh sessions ran Backrooms at 41-48 ms instead of 13 ms** (BR, 2026-10-27)
- Cause: gmRTX turns the PVS off twice, `autoexec.cfg`'s `r_novis 1` and the `rtx_patch_forcenovis` patch;
  the addon turned off only the patch. The first session was fast only because `sv_cheats 0` had reset
  `r_novis`.
- Fix: scope `r_novis 0` as well. After changing it, the camera must move to another vis cluster before the
  engine recomputes the visible set (46.8 ms with the camera still, 12.8 ms after moving). Ruled out on the
  way: Lua, focus, frame generation, CPU-die affinity, the light updater, opacity micromaps, replacement
  materials, junction against real folders.

**The whole map is CPU-bound on big maps** (BR, 2026-10-27)
- About 46 ms a frame with 5000-9000 model renders: about 40 % Source model rendering, 30 % Remix per-draw
  preparation (12 % one global lock in every `RtxOption` read), 11 % one `ReadProcessMemory` per model render
  in RTXFixesBinary's `R_StudioRenderFinal` hook. Fixed in the hook (`62f4af0`, 46.4 → 44.6 ms) and in the
  runtime (lock-free option reads, build `A8E39D93`, 44.0 → 35.5 ms). Still too slow to draw these maps whole.

**Low GPU use, three game threads pegged, 22 fps on modern_house** (MH, 2026-10-27)
- Cause: the user had moved add-ons out to load faster, `modern_house_rtx` among them; the Remix mod still
  loaded, but gmRTX's light updater drew a helper model at each of 1069 map lights every frame.
- Measured: 45 ms and GPU 35-40 % with the updater, 19.6 ms and GPU 87 % with its three hooks paused.
- Fix: the addon back. Ship and install both halves; check for the addon's `created` line. Low GPU use with
  pegged game threads: suspect the light updater first.

**gmRTX's own map lights doubled the remaster's** (BR, 2026-10-27)
- Light2RTX made 1255 and 2278 always-on API lights on top of the remaster's. Flipping `rtx_lightupdater`
  instead ran Light2RTX over the whole map (seconds of hull traces) and set `rtx.skyBrightness` 0.0424.
- Fix: scope `rtx_api_map_lights_autospawn 0`, clear what Light2RTX made, suspend the updater's three hooks
  while the map runs, and never change the user's archived `rtx_lightupdater`.

**Distance-switched lights saved nothing and darkened far rooms** (MH, 2026-10-27)
- 341 lights on against the 30-300 a distance manager kept: no measurable difference at 4K (an earlier
  3-5 ms estimate did not reproduce); at night the far rooms looked dark from the lawn.

**Overlay FPS is four times the engine rate** (MH, 2026-10-27)
- The user's overlay includes DLSS 4x frame generation; divide by 4, or measure engine frames
  (`rtx_agent_frames`).

**Measurements spoiled by other work** (MH, 2026-10-27)
- A concurrent NVTT encode put stock modern_house at 90+ ms (37.2 ms idle) and the first load at 389 s
  (150 s clean). A mod hot reload is followed by seconds of texture streaming (18 fps against 12.7 ms on BR).
  GMod clamps `FrameTime()` at 100 ms (BR's stock runs): count frames by wall clock.

## Loading

**Hang at "Collecting materials for Lua fixers"** (BR, 2026-10-27)
- gmRTX's material collector built every mesh of every static-prop instance (`NikNaks.ModelMaterials` →
  `util.GetModelMeshes`). Fixed in gmRTX Lua (`672ada9`): each model's materials read once from its `.mdl`
  header.

**Fatal "Too many verts for a dynamic vertex buffer (57466>32768)"** (BR, 2026-10-27)
- gm_br_pitfalls' `cden_containerset.mdl` group took Source's software path, which rebuilds it in a
  32768-vertex buffer. Wrong guesses first: PVS on, `r_drawbatchdecals 0`, `r_forcehwlight 1`. Found from a
  crash dump and disassembly; fixed in RTXFixesBinary (groups of 32768 vertices or more drawn on the hardware
  path).

**First-frame freeze from the `.sw.vtx` probe** (BR, 2026-10-27)
- RTXFixesBinary looked for a matching `.sw.vtx` on every GAME search path (about 800) per model. Fixed: a
  miss on the GAME-wide lookup ends the search, and misses are cached per map (442 models on pitfalls,
  `6b4794f`). The "30 s" theory was wrong: 1.4 s per load.

**A debug view built its meshes on every load** (MH, 2026-10-27)
- gmRTX's skybox boundary renderer, off by default, walked every BSP leaf in a coroutine for 60-90 s at 3 ms a
  frame. Fixed in gmRTX (`de3bfbd`): built only when switched on.

**Where the rest of the load goes** (MH, 2026-10-27)
- About 35 s of client Lua start-up for the user's ~250 add-ons, the 136 MB BSP (126 MB lightmaps), and
  gmRTX's two model reloads. Not the map's addon. The remaster cannot change the map file.

**`map` sent while the Workshop was still mounting** (PR, 2026-10-26)
- A first partial line ("Mounted 19 of 765") matched too early; the map then failed or the window stopped
  answering. Wait for the full mount (90 % or the second mount line) and a quiet log.

## Materials and USD

**Five textures predicted wrong** (MH, 2026-10-27)
- 106 of 110 predictions matched; HL2's `lights/white*` and two de_elysion metals are uploaded from other
  mounted copies. Fixed with `live_hashes.py` merged by `tex_jobs.py`.

**Old mods never applied** (the blood mods, 2026-10-27)
- Keyed to the other texture-hash scheme; and where they would have matched, the normal and roughness maps
  were swapped and blood was 97 % metallic. Read the hashes back from the game, and check what each map in a
  mod is, before trusting an existing mod.

**Every texel transparent** (rainbow blood, 2026-10-27)
- `int inputs:alpha_test_type = 0` is "never". Leave it out.

**A colour constant did nothing** (MH, 2026-10-27)
- Mirrors and LED strips kept the game texture: an unauthored `diffuse_texture` inherits it. Author it
  empty (`@@`).

**Glow colours warmer than intended, the whole map's balance off** (PR, 2026-10-26)
- Colour constants are decoded as sRGB, and the linear kelvin colours were passed as if sRGB. Large emitters
  light the room through GI, so their colour sets the white balance as much as the lights. Pass sRGB values;
  a bound emissive texture overrides the colour constant.

**Material tints: baked, or applied twice?** (unverified)
- Modern House multiplies a material's `$color`/`$color2` into the composed albedo (the near-black slatted
  wood, the 51 % grey gloss panels). A memory note from the blood work (2026-10-27) says that on gmRTX's
  fixed-function paths a material's `$color` reaches Remix as the texture factor and tints even a replaced
  albedo live. Whether tinted world materials end up tinted twice was not checked: compare a tinted surface
  with and without the baked tint before relying on either.

**Clear glass turned emerald** (MH, 2026-10-27)
- Brush panes with nodraw faces leave a refracting volume open, which keeps absorbing over metres. Fix:
  `thin_walled`.

**Black water and a navy canal** (PR, 2026-10-26)
- Source draws geometry strictly under opaque water only into its refraction target (gmRTX also has
  `r_waterdrawrefraction 0`), so Remix had no pool floor. Theories about decals and nodraw were disproved.
  Fix: set the translucent flag (2097152) in the water materials' `$flags` at runtime. The Water shader binds
  `$normalmap`, so the tag goes there. A translucent caustic layer inside the water volume then turned the
  water navy; the overlay became an unordered emissive particle (`blend_type 6`).

**Giant tiles on arches and columns** (PR, 2026-10-26)
- `$seamless_scale` triplanar mapping is ignored by Remix; the faces show tiles 16x too large. Unfold the
  faces offline at the real tile size, redraw them from Lua, hide the originals (NO_DRAW flag).

**Lens emission included the trim ring; rails glowed** (MH, BR, 2026-10-27)
- Self-illuminated lamps: the alpha mask times a brightness threshold. Atlases: `emit_rects` limits emission to
  the lamp's part (slum fixtures).

**Aluminium frames turned silver; marble and paving looked wrong under parallax** (MH, 2026-10-27)
- No F0 lift for anodised aluminium (only chrome); marble without height; the paving's AI height read albedo
  blotches as bumps (noise at grazing angles): height 0, gentle normal.

**Parallax on props showed UV seams** (all)
- Height only on world textures; forced to 0 on model textures.

**Interiors too orange; Level 0 radioactive yellow; a cyan cast** (MH, BR, PR)
- MH: kelvins moved (downlights 3400 K, LEDs 3200 K) and purity 1.12. BR: yellow multiplies itself through
  every bounce in a closed yellow room: wallpaper saturation 0.7 and exposure 0.88, purity 1.15, haze 55 m.
  PR: a neutral tile albedo and 5500 K lights (6000 K too cyan, 4800 K too beige).

**PBRify's normal of a pale texture is flat** (PR plaster, 2026-10-26)
- Use the artist's normal map plus high-pass relief from the upscaled albedo.

**Production DDS took hours** (MH, 2026-10-27)
- Production BC7 for 490 files ran about 3 hours (about 25x the default) for no visible gain. Use `normal`.
  gm_poolrooms' few textures took 5 minutes at production.

**Duplicate DDS per material** (PR, 2026-10-26)
- Name textures by source and content digest so materials share them.

**Classification errors** (BR, MH, 2026-10-27)
- `maps/` (cubemap copies) matched a paper rule; stainless matched a decal rule; doors came out as wood; a
  mirror rule anchored at the name's end never matched because the key includes the texture name. Strip
  cubemap names first, order rules from specific to general, check every class on contact sheets.

**`compose.py` failed with "image has wrong mode"** (BR, 2026-10-27)
- Pillow's Gaussian blur does not take 16-bit images: use scipy's `gaussian_filter` on floats.

## Lights and sky

**Light calibration 10x too dim; entity brightness up to 75000** (BR, 2026-10-27)
- Calibrate from flux, compress above a knee (1000), cap radiance (2000, growing the radius instead).

**Batched troffer models gave no panels** (BR, 2026-10-27)
- Prop-combined lamp models cannot be split by vertex proximity; split them by VTX triangle connectivity.

**Spots pointed the wrong way; uplights missing** (MH, PR)
- A light entity's `pitch` is an elevation (-90 points down), the opposite of a camera pitch. The garden
  uplights were `light_inset` props set into the ground pointing up: a separate "uplight" kind.

**The sun blew the scene out** (MH, 2026-10-27)
- Radiance 2200 on a distant light; a distant light's radiance is what a white surface facing it shows (about
  4-5).

**The physical sky gave no sun shadows** (MH, 2026-10-27)
- Its default clouds (coverage 0.85 with voxel shadows) hid the sun. Coverage 0.27, `cloudShadowStrength 0`,
  `cloudVoxelShadowsEnable False`. Don't add a second sun: the atmosphere makes its own.

**A region box boosted the wrong room** (BR, 2026-10-27)
- The cistern's box also covered the grey rooms' point lights. Check region boxes in game with traces.

**Hall panels read grey** (PR, 2026-10-26)
- Smaller and brighter: 64 x 160 units, radiance and emission 18.

## Mirrors, sprites and map clean-up

**Mirrors missing** (MH, 2026-10-27)
- gmRTX deletes `func_reflective_glass` at map start. Redraw the quads from Lua with a tag texture. The
  mirrors' texture was also the cooktop's, so the tag keeps the cooktop black glass.

**Loading a save broke the frame** (MH, 2026-10-27)
- A same-map `gm_load` (and the spawn menu's clean-up) runs `game.CleanUpMap()`, which recreated the eight
  `func_reflective_glass`; their planar reflection pass took the walls and floors out of the Remix frame and
  cost about 30 % fps. A camera cut in that state hung the GPU (display driver reset, `VK_ERROR_DEVICE_LOST`).
- Fix in gmRTX (`d958da6` on the fork's `main`): remove the class whenever it is created. Any entity your
  addon removes or hides must be handled at `PostCleanupMap` and on creation too.

**Lua meshes invisible to Remix** (PR, 2026-10-26)
- Drawn in `PostDrawOpaqueRenderables`, whatever the settings; `PreDrawTranslucentRenderables` draws reach
  Remix.

**Crash on every map change** (PR, 2026-10-26)
- The addon changed a world material in the `ShutDown` hook; GMod ran the queued change after the material
  was freed. Leave map materials alone at unload.

**Remix API mesh and material calls crashed** (RTX Water, 2026-10-26)
- `CreateMesh`, `DestroyMesh`, `CreateMaterial`, `DestroyMaterial` from Lua race GMod's render thread; use
  `CreateMeshBatched` and persistent instances, or ordinary GMod meshes with tag textures.

## Driving the game

**A script could have killed another session's game** (PR, 2026-10-26)
- `game.py` and `restart.py` matched any `gmod.exe`; a peer ran a vanilla GMod beside it. They now check the
  executable path of the configured install. Never stop a game you did not start.

**Settings not readable** (PR, 2026-10-26)
- `RemixConfig.GetConfigVariable` returns the `rtx.conf` value, not the live one; the addons re-apply their
  options three times in the first minute and restore from `rtx.conf` or their defaults.

**Lua autorefresh** (PR, 2026-10-26)
- Editing an installed addon's file re-runs it (repeated `created` lines); hook closures can keep the old
  code. Reload with `include` and restart the addon. New Lua files are not on the cached Lua path until a
  restart (blood, 2026-10-27).

**`IsValid(game.GetWorld())` is false on the client** (PR, 2026-10-26)
- Test the world entity directly.

**HUD in the shots** (MH, 2026-10-27)
- The toolgun's panel ignores `cl_drawhud`: switch to `weapon_physgun` for tours.

**The console stops answering** (BR, MH)
- During a map load, gmRTX's model reloads, Light2RTX processing or a lost device. Wait once; if the device is
  lost, the game must be closed (with permission). Running the AI batch beside the game caused one
  `VK_ERROR_DEVICE_LOST`.

**Script text corrupted by the shell** (all)
- Heredocs turned `\b` in a regex into a backspace and `\n` in a Lua string into a newline (an autorun syntax
  error, a NUL byte). Write scripts and patches with the file-writing tool, not inline shell text.

## Packaging and licensing

**`nlctl` refuses a hard-linked package folder** (MH package, 2026-10-29)
- `package_content.py --link` stages hard links to avoid copying 3.3 GB; the linked build is checked as the
  packed archive instead. The build took 9 s: 500 files, 3,322,961,921 bytes; `gmpublish create` uploaded it
  in 50 s as a hidden item; Steam installed it byte-identical.

**Derived textures and where they went** (2026-10-29)
- Modern House's textures derive from another author's map: its branch stays local and its item hidden (the
  user chose "Keep it local"). Check the same before shipping any remaster; poolrooms' upscaled plaster and
  ladder textures are committed on the pushed fork branch and in the RTX package, which this rule would
  question (ask the user).

**A remaster leaks into other maps** (MH, BR, 2026-10-27)
- Hash replacements are global. Backrooms replaced 209 base-game textures, so they look Backrooms-tuned on
  every map; on modern_house five textures kept other mods' versions because those folders sort first.
  Decide per texture (tag, leave to Remix, or accept) and tell the user.
