<div align="center">

# RTX Remix for Garry's Mod

**Path tracing rendering for 64-bit Garry's Mod via workshop distribution**<br>
This project aims to implement RTX-Remix installation via Steam Workshop and delivers lots of compatibility and optimization changes to make it more accessible.

[![Build](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/actions/workflows/build.yml)
[![Steam Workshop](https://img.shields.io/badge/Steam%20Workshop-3829070317-1b2838?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3829070317)
[![Platform](https://img.shields.io/badge/platform-Windows%20x64-0078d4)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-2ea44f)](LICENSE)

![A tiled pool corridor in Garry's Mod, path traced with RTX Remix](companion/nativeloader/materials/nativeloader/guide/rtx_on.jpg)

[Features](#features) · [Requirements](#requirements) · [Installation](#installation) ·
[Troubleshooting](#troubleshooting) · [FAQ](#faq) · [Download](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/latest)

</div>

## About

[RTX Remix](https://www.nvidia.com/en-us/geforce/rtx-remix/) adds path tracing to older DirectX 8
and 9 games. This project brings it to Garry's Mod without changing the game itself. A binary module needs to be installed to `bin\win64\winmm.dll`, into the game folder and subscribe to the RTX package on the Steam
Workshop. When the game starts, the loader installs the package (or updates it) and starts RTX Remix
before the game sets up its graphics.

The loader never writes to Steam's own files. Game updates and **Verify
integrity of game files** does not remove the loader dll. If you want plain Garry's Mod back, you turn RTX off with one setting or
delete the winmm.dll.

## Features

**Easy instllation and uninstallation and live update**

- One file in the game folder. Everything else are distributed through the Steam Workshop.
- Steam's files are never touched, so game updates and file verification still works.
- Easy to switch off. A setting turns RTX off, the `-nonativeloader` launch option disables RTX-Remix when not needed (useful when you are troubleshooting).
- Your own files, data and settings are safe. It works like a normal Workshop addon and does modify any settings. 
- If you used RTXLauncher before, you can install into the same folder. This project is compatiable to all other binary modules.

**Ready to play**

- An **RTX Remix** tab in the spawn menu holds every RTX setting. It has a *Start here* page and a
  guide you can read in the game, in seven languages: English, French, Japanese, Korean, Russian,
  Simplified Chinese and Traditional Chinese.
- Settings adjust automatically based on graphics card. The loader reads the card's model and video
  memory and picks a high, medium or low performance tier. It also sizes RAM use to your available RAM.
- A fine-tuned sky with the sun, moon and stars, moon phases and eclipses, and twelve weather presets that
  blend into one another. Time passes by default, with a full day every twenty minutes.
- Realistic glass, water and blood decals. 
- Add-ons that use particles and decals, such as Physics Blood, render correctly.
- Multiplayer works natively, including on servers that set `sv_allowcslua 0`, without `-insecure`. RTX-Remix will still work.
- ReShade in RTX sessions will work along side Remix if you had ReShade installed, with minor performance loss.
- Upscaling and frame generation support.
- RTX content are also distributed via Workshop items, such as the PBR materials for characters and maps. 

**Additional Tools that come with the RTX package**
Model Hotloader, Advanced Material Editor, Advanced Bodygroup Tool, Procedural Bodygroup Destruction,
Character Motion Importer, Dynamic Toolgun Screen and Blood Overhaul RTX.

## Requirements

| | |
|---|---|
| **System** | Windows 10 or 11, 64-bit |
| **Game** | Garry's Mod on Steam, on the **x86-64** beta branch |
| **Graphics card** | A GPU with hardware ray tracing: NVIDIA GeForce RTX 30 series or newer (recommended), AMD Radeon RX 6000 series or newer, or Intel Arc |
| **Video memory** | 8 GB at least; 16 GB or more recommended. Smaller cards run on the low performance tier. |
| **System memory** | 16 GB at least; 32 GB recommended |
| **Disk space** | About 4.5 GB: the Workshop download (about 2.2 GB) plus the copy that the loader installs into the game folder |

- DLSS, DLSS Frame Generation and Reflex need an NVIDIA card. Frame generation needs an RTX 40
  series or newer. Multi-frame generation (3x, 4x) needs an RTX 50 series.
- AMD and Intel cards use FSR and XeSS instead. Nobody has tested this on Radeon or Arc hardware
  yet.
- Integrated graphics are not recommended. In one test, the integrated Radeon graphics of a Ryzen
  processor lost the GPU about a minute into a session. 
- Not supported: 32-bit Garry's Mod
- Planned: Linux and Proton support.

## Installation
1. Close Garry's Mod.
2. Download `gmod-native-loader-<version>.zip` from the
   [latest release](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/latest). You
   only need the `-symbols` zip if you are looking into a crash.
3. Extract the zip into your Garry's Mod folder, the one that contains `gmod.exe`. To find it,
   right-click Garry's Mod in Steam and choose **Manage → Browse local files**. A typical path is
   `C:\Program Files (x86)\Steam\steamapps\common\GarrysMod`. If Windows asks whether to merge the
   folders, say yes. This adds `bin\win64\winmm.dll` and `native-loader\config.json`.
4. Subscribe to the [RTX Remix package](https://steamcommunity.com/sharedfiles/filedetails/?id=3829070317)
   on the Steam Workshop.
5. In Steam, open Garry's Mod's **Properties → Betas** and choose **x86-64**.
6. Start the game. The first time after a download, the loader installs the package (about 2.2 GB).
   That takes a few seconds.

> [!IMPORTANT]
> If `bin\win64` already has a `winmm.dll` from another mod, keep a copy before you extract the zip,
> because this one replaces it. Put the copy back if you remove the loader later.

> [!NOTE]
> **Coming from RTXLauncher?** You can install into a folder that RTXLauncher set up. The loader
> recognises the old RTX Remix setup and backs up the files that it replaces in
> `native-loader\backup\legacy`. Your `user.conf`, your own Remix mods and your data stay as they are.
> If the loader finds changes to Steam's files that it cannot undo safely, it leaves them alone and
> says so in its log. Verifying the game files in Steam fixes them.

## Using it in the game

- Open the spawn menu (**Q**) and go to the **RTX Remix** tab. *Start here* shows which performance
  tier you got and why. *Remix settings* holds the options people change most, such as frame
  generation.
- The guide opens by itself the first time. To open it again, type `nativeloader_guide` in the
  console.
- Press **Alt+X** for RTX Remix's own menu. Settings that you save there win over the package's
  defaults.
- If you use ReShade, press **Home** for its overlay.
- With RTX on, the game runs as a borderless window that covers your main screen, because exclusive
  fullscreen crashes the RTX Remix runtime. For another size, add `-w <width> -h <height>` to the
  game's launch options.

![The RTX Remix menu (Alt+X) in Garry's Mod](companion/nativeloader/materials/nativeloader/guide/remix_menu.jpg)

## Settings

The loader reads `native-loader\config.json` in your Garry's Mod folder. The file that comes with the
release allows the RTX package and needs no changes:

```json
{ "schema": 1, "allow": { "workshop": ["3829070317"] } }
```

| To | Add |
|---|---|
| Turn RTX off without uninstalling | `"remix": { "enabled": false }` |
| Turn the loader off entirely | `"enabled": false` |
| Pick the performance tier yourself | `"remix": { "performance_tier": "low" }` (`"auto"`, `"high"`, `"medium"` or `"low"`) |
| Pick the memory profile yourself | `"remix": { "memory_profile": "minimum" }` (`"minimum"`, `"recommended"` or `"high"`) |
| Turn off ReShade in RTX sessions | `"remix": { "reshade": "off" }` |
| Capture a GPU crash dump on the next start | `"diagnostics": { "gpu_crash_dumps": "next_start" }` |
| Stop recording the memory history | `"diagnostics": { "memory_telemetry": "off" }` |
| Load only the packages on the allow list | `"subscribed_content": false` inside `"allow"` |

For example, to force the low performance tier:

```json
{ "schema": 1, "allow": { "workshop": ["3829070317"] }, "remix": { "performance_tier": "low" } }
```

To change RTX Remix's own settings, edit `dxvk.conf`, `rtx.conf` or `user.conf` in the Garry's Mod
folder. They win over the package's files. The player guide in the release,
[README-native-loader.txt](dist/README-native-loader.txt), explains every option.

## Updating

- **The RTX package** updates through the Steam Workshop. Steam downloads the new version, and the
  loader installs it the next time Garry's Mod starts.
- **The loader** cannot update itself through the Workshop. When the package needs a newer loader,
  the main menu shows a reminder (on loader 0.15.0 or newer; older loaders show it once a map has
  loaded). Download the release and replace only `bin\win64\winmm.dll`. Keep your
  `native-loader\config.json`.

## Uninstalling

1. Unsubscribe from the RTX Remix package, then start Garry's Mod once from Steam. The loader removes
   every file that it installed and puts back any of your own files that it had moved aside.
2. Delete `bin\win64\winmm.dll`. The next start is plain Garry's Mod.
3. If you like, delete the `native-loader` folder too. It holds your settings, logs and backups,
   including copies of package files that you had edited (`native-loader\backup\edits`).

To skip the loader for one session without uninstalling, add `-nonativeloader` to the game's launch
options. That option is for troubleshooting: the package's add-ons stay in the game and run without
Remix. To play without RTX, set `"remix": { "enabled": false }` in `native-loader\config.json`.

## Troubleshooting

| Problem | Solution |
|---|---|
| The game crashes or closes when RTX starts | Check that your graphics card supports hardware ray tracing (see [Requirements](#requirements)). Start once with `-nonativeloader` to confirm that the game itself runs, then read the message that appears after the crash. |
| Low frame rate, stutter, or the card runs out of video memory | Set a lower performance tier in `config.json`, lower the resolution, or try frame generation. The guide's *Performance and memory* page covers 8 GB cards and PCs with 16 GB of RAM. |
| The window says "Not Responding" while a big map loads | The game is still working. Mounting hundreds of add-ons or loading a large map can take minutes. Since loader 0.12.1, Windows no longer marks the window during these loads. |
| My ReShade presets don't appear with RTX | RTX Remix draws through Vulkan, so a Direct3D 9 ReShade has nothing to work on. The package brings its own ReShade for RTX sessions and copies your settings on the first RTX start. Press **Home** to open it. |
| A package from the Workshop doesn't load | Content packages (Remix mods and Lua add-ons) load from any item that you subscribed to. Since loader 0.14.0 they never load from an item that only a server made the game download. A package that contains native code is skipped until you add its Workshop ID to `"allow"`. Only do that for authors you trust. |

**Reporting a problem:** include the newest folder in `native-loader\logs\sessions`,
`native-loader\logs\loader.log`, your graphics card, and the steps that lead to the problem.

## FAQ

**Does it modify Garry's Mod's files?** No. Steam's files stay exactly as Steam installed them. The
one exception is moving over from RTXLauncher. There, old changes to Steam's files are put back to
the verified originals, and the replaced versions are archived first.

**Is anything sent over the internet?** No, this project is completely offline. Logs, crash dumps and the memory history stay on your PC. Steam handles the Workshop download itself.

**Can a Workshop item run code on my PC through the loader?** Only the items listed under `"allow"`
in `config.json` may install or run native code, and by default that is only the RTX package. Other
subscribed items may only bring RTX content: Remix mods and Lua add-ons. The loader checks every
file against its SHA-256 hash when it installs it.

**Does it work in multiplayer?** Yes, including on servers that block client Lua
(`sv_allowcslua 0`). Server-side tools still need the matching add-on on the server. Some servers
forbid Remix or ReShade, so check each server's rules.

**Can I go back to the normal Garry's Mod?** Yes. To play without RTX, turn it off in `config.json`
(`"remix": { "enabled": false }`). To go back for good, [uninstall](#uninstalling) the loader.
`-nonativeloader` skips the loader for one start, for troubleshooting.

## How it works

```
GarrysMod\bin\win64\winmm.dll        installed once; Windows loads it into the game at start-up
   │
   ├─ finds the packages: the RTX package on the allow list, RTX content from other subscriptions
   ├─ installs their files: the RTX Remix runtime, the RTX fixes, the tools and add-ons
   ├─ checks every file, keeps a journal, and backs up anything that it replaces
   ├─ starts the RTX Remix runtime before the game creates its renderer
   └─ hands over to the game. With RTX off, it loads nothing and the game runs as usual.
```

The loader stands in for the Windows `winmm.dll` and forwards every call to the real one, which is
how it can run before the game engine does. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes
the start-up sequence step by step.

## For developers

This repository holds the loader (C++20), the in-game companion (Lua), the glass system, this
project's patches to the RTX Remix runtime, and every input that the RTX package is built from.

**Building** needs Windows with the Visual Studio 2022 Build Tools (MSVC x64, which brings CMake and
Ninja), Python 3.10 or newer, and Git LFS for the package inputs. LuaJIT is optional; it runs the
Lua tests.

```powershell
tools\test.ps1 -Config Release   # conventions, Python and Lua tests, C++ build and CTest
tools\workflow.ps1               # what CI runs: the checks, then the release bundle in out\dist
```

**Contributing:** read [AGENTS.md](AGENTS.md) first. It holds the rules that every change follows:
what may be committed, which documentation each change needs, and how the Workshop item is
published.

| Path | Contents |
|---|---|
| [`loader/`](loader/) | The loader: the core library, the `winmm.dll` proxy, the `nlctl` command-line tool and the tests |
| [`companion/`](companion/README.md) | The in-game RTX Remix tab, the guide, the sky and weather, and the translations |
| [`glass/`](glass/README.md) | The glass system: the Lua add-on and the Jolt Physics module |
| [`runtime/`](runtime/README.md) | This project's patches to the RTX Remix runtime, and the script that rebuilds it |
| [`packages/`](packages/README.md) | The inputs of the RTX package's parts, each with its licence |
| [`tools/`](tools/) | Build, test, packaging and maintenance scripts, each documented in a file beside it |
| [`skills/`](skills/README.md) | Agent skills: AI PBR materials for characters and maps, and Workshop content packs |
| [`docs/`](docs/) | Architecture, package format, on-disk layout, testing, research and design decisions |

| Document | What it covers |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | The start-up sequence, the components and the data flow |
| [Components](docs/COMPONENTS.md) | Every component and script, with its status |
| [Package format](docs/PACKAGE_FORMAT.md) | What a package `.gma` contains |
| [On-disk layout](docs/ON_DISK_LAYOUT.md) | What the loader writes into the game folder |
| [Testing](docs/TESTING.md) | The test levels and the release QA protocol |
| [Design decisions](docs/decisions/README.md) | Why the project is built the way it is |
| [Roadmap](docs/ROADMAP.md) and [changelog](CHANGELOG.md) | Where the project stands and what changed |

## Credits

- [NVIDIA RTX Remix](https://github.com/NVIDIAGameWorks/rtx-remix), through the Garry's Mod fork of
  its runtime, [sambow23/dxvk-remix-gmod](https://github.com/sambow23/dxvk-remix-gmod)
- The RTX fixes for Garry's Mod, from Xenthio's
  [garrys-mod-rtx-remixed](https://github.com/Xenthio/garrys-mod-rtx-remixed), and
  [RTXLauncher](https://github.com/Xenthio/RTXLauncher), the setup that this project replaces
- Crunchy's [2022 Blood Overhaul](https://steamcommunity.com/sharedfiles/filedetails/?id=2683396098),
  whose textures and the PBR made from them ship in the package with the author's permission
- [Jolt Physics](https://github.com/jrouwe/JoltPhysics) by Jorrit Rouwe,
  [ReShade](https://reshade.me) by crosire, the LZMA SDK by Igor Pavlov, and the Garry's Mod headers
  from [garrysmod_common](https://github.com/danielga/garrysmod_common)

## License

This project's own code is released under the [MIT License](LICENSE). The RTX Remix runtime,
NVIDIA's components and every other bundled part keep their own licences, which sit beside each part
in [`packages/`](packages/README.md) and [`third_party/`](third_party/). The RTX fixes are licensed
under GPL-2.0. Blood Overhaul's textures and the PBR made from them remain their author's and are not
under the MIT licence.

NVIDIA, RTX, RTX Remix, DLSS and Reflex are trademarks of NVIDIA Corporation. Garry's Mod is a
trademark of Facepunch Studios, and Steam is a trademark of Valve Corporation. This is an independent
community project. NVIDIA, Facepunch Studios and Valve are not affiliated with it and do not endorse
it.
