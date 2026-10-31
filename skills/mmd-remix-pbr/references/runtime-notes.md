# Runtime notes: this machine's Garry's Mod RTX, Remix and Model Hotloader

## Paths

| What | Where |
| --- | --- |
| Game | `H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c` (rpai stores it in `%USERPROFILE%\.rpai\config.json`) |
| Remix runtime | `bin\win64\d3d9.dll`. The log identifies it as `DXVK_Remix: remix-main+384581b1` |
| Remix live log | `rtx-remix\logs\remix-dxvk.log`; the timestamped files are old sessions |
| Mods | `rtx-remix\mods\`. rpai writes only `ai_pbr\` |
| Remix config | `rtx.conf`, `user.conf` in the game root. Read them freely; never edit without asking |
| Screenshots | `garrysmod\screenshots\<map>NNNN.jpg` (console `jpeg`) |
| Console log | `garrysmod\console.log` |
| rpai runtime | `%USERPROFILE%\.rpai`: venv (Python 3.12, torch 2.8 cu129), `models\pbrify`, `work\<model key>` |
| Model Hotloader Lua | `garrysmod\addons\mmd_hotloader\lua\mmdhl\` (the user's own addon) |

## Remix mod loading

- **Runtime build.** Since 2026-10-25 12:29 the game runs `remix-main+c6b48ed1` (the log's first
  `DXVK_Remix:` line); earlier sessions ran `384581b1`. Check that line before trusting the notes
  below about logging.
- The runtime watches only `mod.usda`'s timestamp. rpai rewrites it atomically on every publish,
  and the reload takes about a second. `384581b1` logs "Async reloaded USD data swapped in
  successfully" (with many preloaded textures the swap can lag about 9 s). **`c6b48ed1` logs no
  reload line at all**, so `abtest.py` and `rpai compare` wait 30 s for it and then rely on their
  settle time; reloads still apply (verified in game on Guinaifen's stockings).
- After a swap, auto-exposure re-adapts for several seconds: with an 8 s settle the first shot of a
  variant was 8/255 darker than its repeat, on the leg and the floor alike. `abtest.py` now
  defaults to `--settle 20 --camera-settle 6` (repeat noise 0.9-1.9/255).
- A new mod folder is only discovered at startup, or via Alt+X → Enhancements → Loaded USD Files →
  "Rescan Mods & Reload USD Stage".
- Mods are checked in path order, and the first one with a hash wins:
  `!advanced_material_editor` < `ai_pbr` < `~gmod_topbr`.
  - The user's Advanced Material Editor profiles override rpai.
  - Never write into `!advanced_material_editor`: its bridge owns and resets that folder.
- Remix's legacy material defaults (`rtx.conf`): roughness 0.7, metallic 0.01.

## Texture hashes

- A Remix override is keyed by the texture hash: XXH64 of the top mip as uploaded, because
  `rtx.useObsoleteHashOnTextureUpload = True`.
- **Live hashes are authoritative.** The game reports them through `RemixMaterial` in client Lua.
- **Offline prediction** from the VTF is only a fallback for parts the game has not drawn yet:
  - VTFs with an alpha flag upload as BGRA (5 of 5 matched; 7 of 7 on Robin R18, every upload);
  - opaque VTFs upload as BGR0, but only 4 of 7 matched. Why (verified 2026-10-26): Source uploads
    them as X8R8G8B8 and writes only the B, G, R bytes; the pad byte keeps whatever the upload
    memory held before, and Remix hashes it too. So an opaque sheet hashes to BGR0 (fresh memory),
    BGRF (pad 0xFF) or leftover bytes: Robin R18's `衣.png` hash `0xA669FF339EF9704B` is exactly
    its BGR plus the alpha of `inmon2.png`, the sheet uploaded before it;
  - on Guinevere 8 of 13 predictions agreed overall;
  - compiled addons' DXT5 VTFs upload their blocks unchanged: XXH64 of the top mip's raw blocks
    matched all 3 of Robin's live hashes (`robin_zzz.mdl`, 2026-10-25).
  Show hidden parts in game (part visibility, morphs) and re-run `rpai hashes`.
- `RemixMaterial.GetAllTextureHashes` reports a compiled model's texture hash on only one of the
  materials that share it (Robin: `Body`, `Brows`, `Bangs`); the others return none. rpai merges
  them per texture, so this costs nothing.
- The same texture can upload with a different hash in a new game session. After a restart,
  Guinevere's `灰.jpg` and `sita.png` changed. rpai therefore keeps the union of every hash the game
  ever reported per content-addressed texture key, and `rpai hashes` should be re-run after a
  restart.
  - Only opaque sheets drift (the pad byte above). It also happens within one map instance: on
    2026-10-26 Source re-uploaded every texture about 13 times on gm_poolrooms, and Robin R18's
    `衣.png`, `颜.png` and `发.png` got new hashes from the second upload on, so their PBR vanished
    until `rpai hashes` + `publish` added them. When an opaque sheet loses its PBR, re-run both.
- A busy or loading game does not abort `hashes` any more: earlier verified hashes are kept.
- `--no-live` is safe now, but only because of that union. Before the fix, it silently replaced
  verified hashes with predictions, and 3 overrides stopped applying.
- Model Hotloader caps imported textures at 4096 (the user may lift this). A re-import with changed
  textures changes the hashes, so run `rpai run` again.

## This Remix build's quirks (verified in source and in game)

This build is a fork, sambow23/dxvk-remix-gmod at commit 384581b1 (2026-08-09). It is based on
upstream 68ee7965, between remix-1.5.2 and 1.6.0, and is about 200 commits behind upstream main.

- **No colour inputs.**
  - The fork's "fix crashes" commit 061b8be0 added an `IsHolding<Vector3>` check in
    `rtx_material_data.h` and `rtx_lights_data.cpp`. No USD value ever holds dxvk's own `Vector3`,
    so every `color3f`, `float3`, `double3`, `half3`, `color3d` and `color3h` input is rejected with
    "has unexpected type, using default value". This affects materials and lights.
  - `uint8` inputs load only when written as `uchar`. `alpha_test_type` and `blend_type` never load.
  - A rejected value still hides weaker layers' values behind the default.
  - Workarounds: give colours as textures; for lights use `enableColorTemperature` and
    `colorTemperature`. The Advanced Material Editor's colour constants are affected too.
- **Emission:** `emissive_mask_texture` (an sRGB colour, used as-is) times `emissive_intensity` (MDL
  default 40), gated by `enable_emission`. With a texture, `emissive_color_constant` is ignored.
- **Subsurface scattering works only under two conditions.** Measured on Guinevere's forearm:
  - diffusion profile on → the diffuse is replaced by a scattering term from one probe ray per pixel;
  - **the material must be forced opaque** (`bool inputs:use_legacy_alpha_state = 0`,
    `bool inputs:blend_enabled = 0`). Model Hotloader's draws are non-opaque, so the opaque-only
    probe never lands. Remix then drops the diffuse and adds nothing, which renders near-black.
    Force opaque only on body sheets: decal sheets need their alpha;
  - **the skin colour must come from `subsurface_transmittance_texture`.** In this mode the colour
    is the transmittance (default grey), and colour constants cannot be set;
  - `subsurface_radius_scale` below about 0.5 makes the probe too short. Upstream fixed this in
    remix-1.6.0 (5941c63c, REMIX-5909); this fork does not have it;
  - the mean free path is radius × radius_scale × `rtx.subsurface.diffusionProfileScale` × 0.01
    world units. `subsurface_max_sample_radius` 16 means R = 1.0;
  - the indirect path (ReSTIR GI or NRC) has no scattering case;
  - thin-opaque transmission (`subsurface_measurement_distance`) only adds light from behind;
  - SSS is not part of the standard: it would need its own full-body AABB and the user's decision.
  - **On `c6b48ed1` (Guinaifen, 2026-10-25):** with `use_legacy_alpha_state = 0`, `blend_enabled =
    0`, the albedo as transmittance, `subsurface_radius_scale` 5 and `color3f subsurface_radius`
    (1, 0.35, 0.2) (colour inputs load in this build), scattering renders, warms the skin and lets
    red bleed between fingers and toes. It also darkened the skin 3-8/255, softened normal-map
    relief, drew streaks along both forearms that the same layer without SSS did not have, and
    showed a band where the body meets a skin piece that cannot scatter (her upper neck is skin on
    the cloth atlas, and SSS is per material). On the face sheet it dulled the eye whites. rpai
    turns it on through the `sss` class field, only for sheets whose every class asks for it.
- **Eyes:** the runtime's `rtx.eye.*` shading applies only to Source eyeball draw calls, not to MMD
  eye meshes.
- **Anisotropy works** (`anisotropy_constant` and `anisotropy_texture`, -1..1, the texture stored as
  0..1). The tangent follows the texture's +U axis: on legs unwrapped with V down the leg, a negative
  value stretches highlights along the leg and a positive one widens them around it (probe at
  ±0.7 on Guinaifen's stockings, 2026-10-25). rpai writes it from the `aniso` class field.
- **Huge textures:** over 96 MB, Remix logs "doesn't fit into STAGING memory" and uploads them
  synchronously. This is harmless.

## Commit memory while the game runs (WDDM)

Measured 2026-10-27 with the RTX game up: the game holds about 22 GB private, and only 3-12 GB
of the system commit limit (about 90-106 GB, a system-managed pagefile that grows on demand) were
free. Under WDDM the VRAM torch reserves is charged to system commit, so the AI stage alone can
exhaust it:

- uncapped, the DAT x4 upscaler took the process to ~9 GB within 12 s (one 512 px tile with cuDNN
  reserved 4.3 GB of VRAM). Free commit fell from 9.1 to 0.62 GB;
- with cuDNN off, the CUDA pool capped at 1 GB and `--tile 128`, it stays near 4.5 GB.

`H:\BACKUP_20260815\Modding\ipg\zzz_33_c\pbr\tools\rpai_capped.py <GB> <rpai args>` sets
`torch.cuda.set_per_process_memory_fraction` and `cudnn.enabled = False` before rpai's CLI.
`run_rpai_guarded.ps1` beside it samples free commit and stops only its own rpai below a threshold.
The venv's `python.exe` is a launcher stub; the interpreter is its child.

Before a generate:

- check free commit, and other sessions' `-m rpai` processes (an uncapped run elsewhere held 17 GB);
- run one AI stage at a time.

## Model Hotloader facts used by rpai

- Imports live in the game's Model Hotloader cache. rpai finds an import by PMX path, or by the
  manifest `sourceHash` (the SHA-256 of the PMX), so a moved or renamed folder still works.
- The model key is `<english name slug>_<asset id[:8]>`, for example `new_mmd_model_9cdc990f`. Work
  files go to `%USERPROFILE%\.rpai\work\<key>`, and the per-model preset is
  `tool/presets/models/<key>.json`.
- Part visibility, the camera and morphs: see `testing-protocol.md`.
