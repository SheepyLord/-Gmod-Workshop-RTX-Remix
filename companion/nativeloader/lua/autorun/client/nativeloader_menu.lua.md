# nativeloader_menu.lua

The maximum-bounce draft defaults to 12 and is bounded at 15, matching the runtime. It remains
an opt-in numeric override: opening the panel cannot replace the user's saved Remix setting.

Since ADR 0044, Remix's saved files take precedence at launch unless the player explicitly enables
`nativeloader_remix_reapply` (default 0). Changes made in this panel still apply immediately during
the session; use Remix's Save Settings in Alt+X to save them in its user layer. The panel shows its
retained override drafts, not live runtime values: the bundled GetConfigVariable reads only a file.

Numeric overrides have an explicit archived `<name>_enabled` flag, default 0. Their unbound sliders
are initialized and synchronized under a write guard. Only an enabled, valid numeric edit sends a
value. Existing numeric ConVars are retained but inactive until explicitly selected, because older
widgets could turn an empty sentinel into an archived zero. Zero remains valid for brightness and
purity; purity now matches Remix's 0–5 range. Draft defaults are 12 bounces, brightness 1 and purity 1.
An unset control displays this draft default without writing it. Invalid, non-finite and out-of-range
values are not sent. Choices and booleans also reject invalid archived strings.

`nativeloader_remix_reset` clears drafts, numeric selections and startup replay; it sends no synthetic
default to Remix. Its saved files take effect next start. The fog selection suppresses weather fog
only after the preset was actually applied, through the `NativeLoaderRemixFogOverride` hook.

Player models under RTX Remix / Rendering adds the archived rtx_pseudoplayer shadow toggle and
rtx_pseudoplayer_offset_z height slider (-32 to 64 units). The RTX fixes own `rtx_pseudoplayer`:
`cl_rtx_misc.lua` creates it with default 1 before this file runs, so the menu does not create it.
Turning the proxy on requests `rtx.playerModel.enablePrimaryShadows = True` through RemixConfig (a
change callback). At map start it is requested only with `nativeloader_remix_reapply` on, like the
other overrides: otherwise a shadow the player turned off in Alt+X and saved stays off
([ADR 0044](../../../../../docs/decisions/0044-remix-settings-persistence.md)). Height affects only
the proxy's render bones. Labels/help are in all six companion catalogs; user.conf is never written.

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
  - It is given to Remix when deliberately changed, and at session start (4 s after `InitPostEntity`)
    only if `nativeloader_remix_reapply` is enabled,
    through the RTX fixes' `RemixConfig.SetConfigVariable`, which writes into Remix's user layer.
  - With startup replay off, all settings load from Remix's files. With it on, empty choices and
    numeric overrides whose `_enabled` switch is off still leave the option to Remix's files.
  - `nativeloader_remix_reset` clears them all.
  - The option names and their numbers are the runtime's own: `rtx_options.h` and
    `rtx_graphics_preset.h` of the fork.

Moved RTX panels and the companion panels use `i18n.PreparePanel` so long translated slider/combo labels are shown above their controls. Other tabs retain their original builders.

Rendering also contains a translated Toolgun screen panel. Its Keep toolgun text sharp checkbox
controls `nativeloader_toolgun_screen` (default on); see [nativeloader_toolgun.lua](nativeloader_toolgun.lua.md).

Model outlines has a default-on suppression control (`nativeloader_ignore_outlines`: outline
materials of loaded models, by name). The runtime's front-cull shell rule is a separate, console-only
opt-in (`nativeloader_ignore_outline_shells`, default 0; [ADR 0059](../../../../../docs/decisions/0059-outline-shell-rule-opt-in.md)).
Both manage only the companion's nonpersistent native options; see [nativeloader_model_layers.lua](nativeloader_model_layers.lua.md).
