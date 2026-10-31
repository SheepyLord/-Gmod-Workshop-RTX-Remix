 > This project uses AI-generated code.

<p align="center">
  <img src="https://github.com/user-attachments/assets/fad469d4-b7b2-428c-a093-5b497f02d820" width="500" />
</p>

## Features
- ToPBR: Automatically converts Source Engine materials to PBR at runtime
- Hardware Skinning (For Half-Life 2 RTX Assets)
- Automatic hardware fallback for oversized non-flex model meshes, preserving their compiled bone weights.
- Remix API Support (including Lua bindings for addon creation)
- [Prepared PBR assets in GMA addons](docs/PBR_GMA_LOADER.md): prepare DDS replacements before renderer startup and reuse them on later launches (Windows x64).
- Win64 legacy texture-hash replacement provider for Advanced Material Editor
  ([protocol and safety notes](source/advmat_rtx_bridge/README.md))
- [RTX Water](docs/RTX_WATER.md): path-traced water on any map, with a simulated, shape-aware wave
  field: bodies push the water as their real shapes, moving ones leave Kelvin wakes, walls reflect
  ([how the waves are simulated](docs/rtx_water/wave_simulation.md)).
- [gm_poolrooms RTX](docs/GM_POOLROOMS_RTX.md): a path-traced remaster of the workshop map
  gm_poolrooms (PBR materials, Remix API lights, caustics).
      
## Oversized model meshes

Source's dynamic software draw rejects groups of 32,768 vertices or more. Already hardware-skinned
groups without vertex flexes use a scoped hardware draw instead, including when r_forcehwskin is
off. With that option off, smaller groups retain their normal behavior. When the user enables it,
supported non-flex multi-bone groups also borrow the hardware scope so an engine software setting
cannot silently CPU-skin the geometry while hardware bone matrices are active. Rigid ordinary
props and the existing eye/flex paths retain their behavior. This does not change the user's
skinning convar. Each scoped draw restores its renderer/material flags, bone
palette, blend state and vertex declaration; unreadable required state skips that draw safely.
The same scope protects both the dynamic and direct hardware draw entries, since the latter can
also fall back to software rendering when the engine's software-skin setting is enabled.
The compiled VTX must prove that every used bone slot is assigned by that strip's own palette;
cached assignments from earlier meshes never substitute for missing data.
That complete-strip requirement applies to oversized automatic groups; smaller user-forced groups
retain the legacy remap cache. An unsupported static renderer fallback skips an oversized group
before it can request an unsafe dynamic buffer.
Certified oversized draws upload their required bone state even when the r_hwskin_setbones
diagnostic filter is zero or a different model-bone count, preventing the unsafe software fallback.
Smaller user-forced groups enter the scope only when the legacy filter selects them (mode1 or a
matching bone count); explicit diagnostic disable/filter settings retain their previous path.
The filter's stored value is unchanged.

The standalone [policy and restoration test](tests/oversized_skinning_test.md) needs no GPU.
Real rendering acceptance also needs animated large models, multiple skins, ordinary models and
first-person arms with r_forcehwskin both off and on.

## Installation
- Switch to the `x86-64` branch of Garry's Mod on Steam
- Ensure you've ran the vanilla game at least once, especially if you switched branches.
- Download [RTXLauncher](https://github.com/Xenthio/RTXLauncher/releases) (Use the newer nightly if available).
- **Windows**
   - Run the launcher (**as an Administrator**)
- **Linux**
   - Ensure Steam Play is forced for Garry's Mod with either Proton Experimental or another recent Proton build.
   - Run [GModPatchTool](https://github.com/solsticegamestudios/GModPatchTool)
   - Make sure it's marked as executable `chmod +x ./RTXLauncher.Avalonia.Linux`, and run it.

- Select the Release Channel (Stable or Nightly)
- Select `Start Quick Install` on the main screen and follow the prompts when asked.
- Once it's finished, press `Launch Game` at the bottom of the launcher.

## RTX Remix version
The runtime is [SheepyLord/dxvk-remix-gmod](https://github.com/SheepyLord/dxvk-remix-gmod) (branch `gmod-1.6.1`): the Garry's Mod Remix fork with [RTX Remix 1.6.1](https://github.com/NVIDIAGameWorks/rtx-remix/releases/tag/remix-1.6.1) merged in.
The binary module uses that fork's API extensions and versioning (`0.1000.1`), so stock NVIDIA runtimes reject it. `public/include/remix` holds the runtime's headers.
RTX Remix 1.6 needs NVIDIA driver 616.92 or newer.

## Multiplayer
Multiplayer works best when the server/host has this addon and the cvar `sv_allowcslua 1` set.

You can join servers without the addon but you ***will*** experience visual issues.

## Support
### [Problematic Addons](https://github.com/Xenthio/garrys-mod-rtx-remixed/wiki/Problematic-Addons)
### [Common issues](https://github.com/Xenthio/garrys-mod-rtx-remixed/wiki/Common-Issues)

## Recommended Resources
[HDRI Editor](https://github.com/sambow23/hdri_cube/blob/main/README.md)

## Credits
* [vlazed](https://github.com/vlazed/) for [toggle-cursor](https://github.com/vlazed/toggle-cursor)
* Yosuke Nathan on the RTX Remix Showcase server for making the initial `Garry's Mod Remixed` logo
* Everyone on the RTX Remix Showcase server
* NVIDIA for RTX Remix
* [Nak2](https://github.com/Nak2) for [NikNaks](https://github.com/Nak2/NikNaks)
* [BlueAmulet](https://github.com/BlueAmulet) for [SourceRTXTweaks](https://github.com/BlueAmulet/SourceRTXTweaks)
* [0xNULLderef](https://github.com/0xNULLderef) and [Wolƒe Strider Shoσter](https://github.com/wolfestridershooter) for additional x64 patches (culling and HDR map lighting)
* [King David](https://github.com/KingDavidW) for all of their guidance for getting hardware skinning working.
