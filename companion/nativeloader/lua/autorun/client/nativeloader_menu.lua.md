# nativeloader_menu.lua

The companion's "RTX Remix" spawn-menu tab ([ADR 0022](../../../../../docs/decisions/0022-companion-rtx-session-guard.md)).
Client only; it runs in RTX sessions (the companion ships in the RTX-only package).

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
  - fog distance and scattering;
  - sky brightness, sun height and direction, clouds;
  - post effects and tone-map purity.

  How a value reaches Remix:
  - Each choice is saved as a client setting `nativeloader_remix_<name>`.
  - It is given to Remix at every session start (4 s after `InitPostEntity`) and when it changes,
    through the RTX fixes' `RemixConfig.SetConfigVariable`, which writes into Remix's user layer.
  - An empty value leaves the option to Remix's files: the package defaults, `rtx.conf`, `user.conf`.
  - `nativeloader_remix_reset` clears them all.
  - The option names and their numbers are the runtime's own: `rtx_options.h` and
    `rtx_graphics_preset.h` of the fork.
