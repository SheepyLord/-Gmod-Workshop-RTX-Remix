# 0028: ReShade in RTX sessions: the Direct3D 9 one stays out, the package brings a Vulkan layer

- Status: Accepted 2026-10-29
- Decided by: the user ("Reshade, if installed in d3d9 mode, should be blocked when RTX-Remix is
  installed. Make the payload also comes with a RTX-Remix (likely vulkan) compatible Reshade (Reshade
  is open-sourced in BSD 3-clause) which saves user's current reshade settings and restore them when
  Remix is uninstalled or disabled. Test in a separate gmod client about the performance and
  compatibility."), Claude choosing how
- Builds on: [0003](0003-native-trust-allowlist.md) (ReShade's DLL is native code: it comes with the
  allowlisted RTX package), [0004](0004-runtime-in-versioned-folder.md) and
  [0008](0008-activation-at-startup.md) (the runtime's `d3d9.dll` preloaded at the entry point),
  [0010](0010-rtx-session-extras.md) (RTX sessions only)

## Context

Measured in a separate client, `GarrysMod_ReShade` (a vanilla copy made with
[`make_vanilla_copy.py`](../../tools/steam/make_vanilla_copy.py.md)), with ReShade 6.8.0 set up the way
its setup does for Direct3D 9 (`bin\win64\d3d9.dll`, `ReShade.ini`, a preset, `reshade-shaders`) and a
marker effect of our own ([RESEARCH.md](../RESEARCH.md) section 26):

- **The Direct3D 9 ReShade never reaches an RTX session.** The bootstrap loads the runtime's `d3d9.dll`
  by absolute path at the entry point, and `shaderapidx9.dll`'s import binds to that module. The game
  process never loads `bin\win64\d3d9.dll`; its three files stayed byte-identical through more than
  30 RTX sessions. GMod's Chromium helper process loads it (it loads `d3d9.dll` by name), as it does
  without the loader; it draws nothing there. Without RTX (`remix.enabled` false) it loads and works.
- **The runtime renders through Vulkan**, so ReShade has to be a Vulkan layer to see the frame.
  ReShade 6.8.0's layer works on the runtime: it takes the runtime's instance, device and swap chain,
  and its effect shows in the path-traced frame, DLSS frame generation on or off.
- **ReShade's base folder** (settings, presets, log) is `[INSTALL] BasePath` of a `ReShade.ini` beside
  the executable if it names one, else `RESHADE_BASE_PATH_OVERRIDE`, else the executable's folder for a
  layer (`source/dll_main.cpp:55-73`). Relative paths in its settings resolve against that folder. A
  layer loads only where that folder has a `ReShade.ini`. A second ReShade in a process aborts its own load.
- **ReShade's setup in Vulkan mode** registers `VK_LAYER_reshade` as an implicit layer for every
  Vulkan application (`HKLM\SOFTWARE\Khronos\Vulkan\ImplicitLayers`, administrator rights).
- **Cost.** On a quiet machine (RTX 5090, gm_construct, the camera pinned, DLSS frame generation on),
  the layer cost nothing measurable at 1280 x 720 (143-148 frames a second with or without it). At
  3840 x 2160 a light effect (our marker) cost 0.9 ms a frame (83-84 frames a second against 90, 7 %)
  and a heavy blur 2.8 ms (72). While other work kept the processor busy (a runtime build, `.gma`
  packing), the 1280 x 720 runs with the layer lost 35 % against 3 % for runs without ReShade: the
  layer's work sits on the runtime's command threads. The full table is in RESEARCH.md section 26.

## Decision

1. **The Direct3D 9 ReShade stays out by design.** No change is needed: the preload already keeps any
   `bin\win64\d3d9.dll` out of an RTX session. The loader never writes `bin\win64\d3d9.dll`,
   `ReShade.ini`, presets or shaders.
2. **The package carries ReShade 6.8.0 as a Vulkan layer.** [`package_reshade.py`](../../tools/package_reshade.py.md)
   takes `ReShade64.dll` unchanged from the official setup (setup and DLL SHA-256 pinned), and adds a
   layer manifest of our own (`VK_LAYER_nativeloader_reshade`, no implicit-layer switch, so it never
   collides with a ReShade the setup registered), ReShade's licence (BSD 3-clause,
   [third_party/reshade](../../third_party/reshade/README.md)) and a notice. Manifest section `reshade`,
   kind `reshade`, loader 0.5.0 ([PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md)).
3. **When.** RTX sessions only, by `remix.reshade` in `config.json`: `"auto"` (default) when the game
   has a ReShade (`bin\win64\ReShade.ini`) or RTX sessions already have settings
   (`native-loader\reshade\ReShade.ini`); `"on"` always; `"off"` never. Not when the game's
   `ReShade.ini` sets `[INSTALL] BasePath`: ReShade would then use and change the game's own settings.
4. **Settings of their own.** `native-loader\reshade` is ReShade's base folder in RTX sessions. The first
   RTX session makes its `ReShade.ini` from the game's: every path ReShade resolves against its folder
   becomes absolute (effect and texture search paths, screenshots, fonts, sounds, cache, add-ons), keys
   whose default is that folder are written out, and the presets (current, startup, shortcut, and the
   other presets in the current preset's folder) are copied in and pointed to. Without a game ReShade
   (`"on"`), new settings. After that the folder is the user's and is never rewritten.
5. **"Restore".** Since the game's ReShade files are never written, nothing needs restoring: with RTX
   off, the package removed or the loader gone, the Direct3D 9 ReShade starts with its own settings,
   exactly as before. Deleting `native-loader\reshade\ReShade.ini` takes the game's settings over again.
6. **How it is enabled.** At activation, after the runtime's own variables: the layer's folder first in
   `VK_ADD_LAYER_PATH`, the layer first in `VK_INSTANCE_LAYERS`, `RESHADE_BASE_PATH_OVERRIDE` the folder,
   and `DISABLE_VK_LAYER_reshade_1=1` (a globally registered ReShade stays out of the session). The
   layer manifest and DLL must be as deployed. A ReShade that cannot be prepared costs ReShade, not the
   session; `status.json` `activation.reshade` says what happened.
7. **Uninstall keeps `native-loader\reshade`**: it holds the user's settings.

## Consequences

- A player with ReShade for GMod gets it in RTX sessions too, with their effects and presets, at the
  next start after this package; one without ReShade sees no change.
- The RTX package needs loader 0.5.0: an older loader keeps the generation it has deployed ("requires a
  newer loader") until `bin\win64\winmm.dll` is replaced.
- Child processes inherit the variables. GMod's Chromium helper then reads the RTX folder's settings
  for the Direct3D 9 ReShade it loads, and logs there (`ReShade.log1`); it draws nothing.
- Add-ons: ReShade looks for them in its base folder unless `[ADDON] AddonPath` says otherwise, so the
  game's `bin\win64\*.addon64` stay out of RTX sessions unless the game's settings name their folder.
- Effects that read depth get whatever depth buffer ReShade's Generic Depth add-on finds among the
  runtime's internal passes; such effects were not tested.
- A new ReShade version is a new pin in `package_reshade.py` and its licence in `third_party/reshade`.

## Alternatives considered

- **The Vulkan ReShade on the game's own `ReShade.ini`, saving a copy and restoring it when RTX is off**:
  it writes the user's files, two ReShades would share one settings file, and a restore cannot tell
  the user's edits from the RTX sessions'.
- **ReShade's setup in Vulkan mode (a global implicit layer)**: changes system settings with
  administrator rights and reaches every Vulkan application.
- **ReShade under a proxy name in the runtime folder**: `d3d9.dll` is the runtime's name, and `dxgi.dll`
  would never see Vulkan.
- **Upstream's `ReShade64.json` unchanged (`VK_LAYER_reshade`)**: the same name as a globally registered
  ReShade, and which manifest the Vulkan loader takes for that name is not ours to decide.
- **On for everyone**: every RTX session would show ReShade's start-up banner and carry its hooks
  without any effect to show.
- **Blocking the Direct3D 9 ReShade in GMod's Chromium helper too** (a System32 `d3d9.dll` preload
  there): it draws nothing there, and the helpers stay a pure pass-through (ADR 0001).
