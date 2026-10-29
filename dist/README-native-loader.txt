GMod native loader: RTX Remix for Garry's Mod (64-bit)
=======================================================

This zip holds the loader and its settings:

  bin\win64\winmm.dll          the loader
  native-loader\config.json    its settings: allows the RTX Remix Workshop item 3829070317

Install
-------

1. Close Garry's Mod.
2. Extract this zip into your Garry's Mod folder, the one that holds gmod.exe, for example
   C:\Program Files (x86)\Steam\steamapps\common\GarrysMod
   Windows may ask whether to merge the folders: say yes.
3. Subscribe to the RTX Remix item on the Steam Workshop:
   https://steamcommunity.com/sharedfiles/filedetails/?id=3829070317
4. In Steam, set Garry's Mod's beta branch to x86-64 (Properties > Betas), then start the game.
   - The first start after a download deploys the package, about 1.5 GB, which takes a few seconds.
     It needs this loader (0.5.0 or later); an older loader keeps the version it has.
   - The package also brings Model Hotloader (with its native files), Advanced Material Editor,
     Advanced Bodygroup Tool, Procedural Bodygroup Destruction and the Character Motion Importer for
     RTX sessions. If you put copies of them into garrysmod\addons or their files into
     garrysmod\lua\bin yourself, move those out first: the loader never replaces files it did not
     place, and stops at them.
   - The console line "Couldn't mount file" for the item is expected: the loader deploys it instead
     of GMod.
   - With RTX the game opens as a borderless window covering your main screen. Exclusive fullscreen
     crashes the RTX Remix runtime. For another size, add -w <width> -h <height> to the game's launch
     options in Steam; a -windowed or -fullscreen of yours there is used as it is.
   - In the game: the spawn menu's "RTX Remix" tab holds every RTX setting, and the console command
     nativeloader_guide opens a guide (it opens by itself the first time).

Graphics cards
--------------

- RTX Remix needs a GPU with hardware ray tracing: NVIDIA RTX 20 or newer, AMD Radeon RX 6000 or
  newer, Intel Arc. An older card cannot start an RTX session; turn RTX off ("remix": { "enabled":
  false } below) or start with -nonativeloader.
- On AMD and Intel: DLSS, DLSS frame generation and Reflex are NVIDIA-only. FSR (upscaling and frame
  generation) and XeSS are there instead; they have not been tried on a Radeon or Arc card yet.
  Without an NVIDIA GPU, Remix picks its graphics preset for your GPU at the start
  (native-loader\remix\non-nvidia.conf); a preset you choose in Remix's menu (Alt+X) and save there
  still wins. The first time each effect is used you may see a short stutter.
- The integrated Radeon graphics of a Ryzen processor could not run an RTX session in a test: the GPU
  was lost about a minute in. With a separate graphics card, Remix uses that card.

Settings (native-loader\config.json)
------------------------------------

- RTX off, without uninstalling:  { "schema": 1, "allow": { "workshop": ["3829070317"] }, "remix": { "enabled": false } }
- The loader off:                  add "enabled": false
- Nothing else in the file is needed. Native code comes only from what "allow" lists.

RTX content from other Workshop items
-------------------------------------

- Subscribe to an RTX content package (Remix materials and mods, such as a character's PBR textures)
  and it loads at your next start, with loader 0.4.0 or later. No change to config.json is needed.
- Such a package may only hold Remix mods and Lua add-ons. A package that also carries native code
  is skipped until you add its Workshop id to "workshop" under "allow".
- To use only what "allow" lists: add "subscribed_content": false under "allow".

ReShade
-------

- RTX Remix draws through Vulkan, so a ReShade installed for Direct3D 9 (bin\win64\d3d9.dll) has
  nothing to work on with RTX. It never loads into an RTX session, and the loader never changes
  its files: without RTX it works exactly as before.
- The RTX package brings ReShade 6.8.0 (by crosire, BSD 3-clause) for RTX sessions instead. If
  ReShade is set up for the game (bin\win64\ReShade.ini), the first RTX session copies its settings
  and presets into native-loader\reshade, and RTX sessions use those copies from then on. Your own
  ReShade.ini and presets stay as they are, so turning RTX off or removing the package needs no
  restoring.
- Home opens ReShade's overlay in an RTX session, as usual.
- ReShade costs some frame rate. Measured on an RTX 5090: nothing measurable at 1280 x 720; at
  3840 x 2160 a light effect cost about 0.9 ms a frame (7 %) and a heavy full-screen blur 2.8 ms.
  With "auto", the default, it is on only where ReShade is set up for the game. Setting
  "remix": { "reshade": "off" } in config.json turns it off; "on" turns it on for a game without a
  ReShade of its own.
- To take your Direct3D 9 settings over again, delete native-loader\reshade\ReShade.ini.

Updating
--------

- The RTX package updates through the Workshop. Steam downloads a new version, and the next start of
  Garry's Mod deploys it. An in-game message says when a restart is needed.
- A new loader: replace only bin\win64\winmm.dll. Keep your native-loader\config.json.

Removing
--------

- Unsubscribe from the RTX Remix item: Steam deletes it when you next start the game from Steam, and
  the loader (0.3.1 or later) then removes the package and every file it deployed. Files you changed
  yourself stay. Subscribing again brings it back.
- Delete bin\win64\winmm.dll: the next start is plain Garry's Mod again.
- The files the loader deployed stay where they are but are no longer used. To remove them too, see
  the project's uninstall steps: "nlctl uninstall" in the loader's repository.
