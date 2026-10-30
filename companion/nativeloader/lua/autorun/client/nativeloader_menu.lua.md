# nativeloader_menu.lua

Player models under RTX Remix / Rendering adds the archived rtx_pseudoplayer shadow toggle and
rtx_pseudoplayer_offset_z height slider (-32 to 64 units). Enabling the proxy requests primary
player shadows through RemixConfig, including at startup. Height affects only the proxy's render
bones. Labels/help are in all six companion catalogs; user.conf is never written.

The companion's "RTX Remix" spawn-menu tab ([ADR 0022](../../../../../docs/decisions/0022-companion-rtx-session-guard.md)).
Client only; it runs in RTX sessions (the companion ships in the RTX-only package). Its text is
translated ([`../../nativeloader/i18n.lua`](../../nativeloader/i18n.lua.md), [ADR 0029](../../../../../docs/decisions/0029-companion-translations.md)):
labels are written as `L("...")`, or `N("...")` in tables and translated where they are shown; the
category names stay English inside, only their labels are translated. "Start here" ends with the
choice "Language" (`nativeloader_language`: same as Garry's Mod, or one of the seven languages, each
named in itself). Labels are kept within GMod's widths (about 100 pixels for a combo box, 114 for a
slider); what does not fit is a help line below the control (an option's sixth field).

- **One tab.** The RTX add-ons register their panels under four Utilities categories: "RTX",
  "RTX Remix", "RTX Remix - API Lights" and "Glass Rewrite Remixed". A wrapper around
  `spawnmenu.AddToolMenuOption` moves them, unchanged, into the tab under these categories:
  - "Rendering": Base Options, Performance, ToPBR, Auto-Categorization;
  - "Lights": Flashlight, Map, the wrappers, Entity Light HUD;
  - "Water and glass": RTX Water, Glass settings.

  Nothing in the add-ons' code changes. Panels of other add-ons stay where they are.
- **Start here:** opens the guide (`nativeloader_guide`), prints the status (`nativeloader_status`),
  applies the classic RTX settings (`nativeloader_rtx_defaults`), the guard switch
  (`nativeloader_guard`), and a note on Remix's own menu (Alt+X).
- **Remix settings:** common Remix options as menus and sliders:
  - the graphics preset, the upscaler, DLSS quality, frame generation and the indirect-lighting mode;
  - the most light bounces;
  - sky brightness (the map's own skybox only: `rtx.skyBrightness` scales the rasterised sky probe);
  - **fog** (`nativeloader_remix_fog`): Remix's own volumetric presets, the "Volumetric Visual
    Presets" of its menu (`rtx_global_volumetrics.cpp`), applied as its Apply button does
    ([ADR 0032](../../../../../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)):
    `rtx.volumetrics.enable True`, `enableFogRemap False` and the preset's four values;

    | Choice | `transmittanceColor` | `transmittanceMeasurementDistanceMeters` | `singleScatteringAlbedo` | `anisotropy` |
    |---|---|---|---|---|
    | `default` (Remix default) | 0.999 | 200 | 0.999 | 0 |
    | `heavyFog` | 0.85 | 5 | 0.9 | -0.2 |
    | `lightFog` | 0.93 | 15 | 0.95 | -0.1 |
    | `mist` | 0.96 | 50 | 0.98 | 0.1 |
    | `haze` | 0.9, 0.85, 0.75 | 70 | 0.8 | 0.2 |
    | `dust` | 0.87, 0.73, 0.5 | 60 | 0.85, 0.75, 0.65 | 0.4 |
    | `smoke` | 0.87, 0.73, 0.5 | 20 | 0.85, 0.75, 0.65 | 0.6 |

    While one is chosen the sky's weather leaves the fog alone; "(leave to Remix)" gives it back to
    the weather (or, without one, to Remix's files at the next start). An option whose choice sets
    several Remix values carries the function that sets them (its seventh field);
  - post effects and tone-map purity.

  The sun and the clouds moved to "Sky and weather" ([ADR 0031](../../../../../docs/decisions/0031-physical-sky-time-and-weather.md)),
  and the weather presets set the fog unless a fog preset is chosen here. Saved values of the settings
  that left (`nativeloader_remix_fog_distance`, `_fog_anisotropy`, `_sun_elevation`, `_sun_rotation`,
  `_clouds`) are no longer applied.
- **Sky and weather:** a category of its own, after "Remix settings". Its panel is built by
  [`../nativeloader_sky.lua`](../nativeloader_sky.lua.md).

  How a value reaches Remix:
  - Each choice is saved as a client setting `nativeloader_remix_<name>`.
  - It is given to Remix at every session start (4 s after `InitPostEntity`) and when it changes,
    through the RTX fixes' `RemixConfig.SetConfigVariable`, which writes into Remix's user layer.
  - An empty value leaves the option to Remix's files: the package defaults, `rtx.conf`, `user.conf`.
  - `nativeloader_remix_reset` clears them all.
  - The option names and their numbers are the runtime's own: `rtx_options.h` and
    `rtx_graphics_preset.h` of the fork.

Moved RTX panels and the companion panels use `i18n.PreparePanel` so long translated slider/combo labels are shown above their controls. Other tabs retain their original builders.
