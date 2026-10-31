# mainmenu.js

Two independent parts, appended to the stock control.Menu.js by the loader's exact read redirect.

**The verified RTX multiplayer bootstrap trigger** (ADR 0052). When the loader sets
`window.NativeLoaderClientBootstrap` (the committed generation holds the `gmsv_nlrtxclient` helper),
it runs `require( "nlrtxclient" )` once through the menu's Lua bridge, waiting up to two minutes
for that bridge. It does not depend on the diagnostics panel or its data, and the loader installs it
even when the stock menu controller the overlay decorates has changed (a GMod menu update): that
view carries only the trigger, with a startup note
([ADR 0056](../../../docs/decisions/0056-guard-and-startup-fallbacks.md)).

**The display-only diagnostics panel**, appended only beside the stock menu controller. Shows OS,
CPU/logical threads, physical RAM, graphics adapters/VRAM, the game's own version/branch, loader
version/file SHA-256 and deployed native package versions/manifest SHA-256. Hashes are
abbreviated visually, available in hover text and copied in full by the explicit copy button.
The panel appears on the main-menu home screen only and follows the menu language. Values use
textContent, never HTML. No upload, automatic URL opening, startup-log reading or disk writes.
The project link and clipboard functions run only on a click. Labels are in labels.json;
layout/style and project URL are edited here. Compiled into winmm.dll through CMake.

## R6 performance tier

Shows one localized line for the effective performance tier and source (automatic, config override
or built-in fallback) only when an adapter description and a listed tier layer are present.
Startup prepares its data after tier writes; failed/vanilla activation has no tier row. High and
pre-R6 medium have no tier layer and no row. Read-only previews apply the rendering-recipe gate.
It never consumes GPU diagnostics or reads stale status.
The new non-English tier/source translations in `labels.json` are agent-written, awaiting review;
JSON catalogs do not permit comments. Inputs/outputs and exit behavior are unchanged.
