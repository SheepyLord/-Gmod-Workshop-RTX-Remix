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
     It needs this loader (0.3.0 or later).
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

Settings (native-loader\config.json)
------------------------------------

- RTX off, without uninstalling:  { "schema": 1, "allow": { "workshop": ["3829070317"] }, "remix": { "enabled": false } }
- The loader off:                  add "enabled": false
- Nothing else in the file is needed. The loader only ever uses what "allow" lists.

Updating
--------

- The RTX package updates through the Workshop. Steam downloads a new version, and the next start of
  Garry's Mod deploys it. An in-game message says when a restart is needed.
- A new loader: replace only bin\win64\winmm.dll. Keep your native-loader\config.json.

Removing
--------

- Delete bin\win64\winmm.dll: the next start is plain Garry's Mod again.
- The files the loader deployed stay where they are but are no longer used. To remove them too, see
  the project's uninstall steps: "nlctl uninstall" in the loader's repository.
