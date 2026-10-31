# glass_spawnmenu.lua

Client autorun: the glass settings. `glass_open_panel` opens the settings window (Visual Effects,
Physics Settings, Player Collision, Advanced, and Reset to Defaults / Test Settings / Player Debug);
the spawn menu's Settings page (Utilities > Glass Rewrite Remixed; with the native-loader companion,
RTX Remix > Water and glass) has the quick controls. Every
control is bound to one of the add-on's replicated server settings (`rtx_glass_*`, created in
`procedural_shard.lua`); only the server's operator (the listen host) can change them.

`rtx_glass_debris_lifetime` (Debris lifetime, 0-600 seconds, default 120; ADR 0061) is in Visual
Effects and on the spawn-menu page, with a help line saying that 0 keeps pieces until map cleanup or
the 256-piece limit. Reset to Defaults sets it back to 120 with the other settings.

Text is marked `NL(...)` and translated through the native-loader companion's bundled-interface
catalog (`companion/i18n/addons`); without the companion it stays English. No files are written.
GPL-2.0.
