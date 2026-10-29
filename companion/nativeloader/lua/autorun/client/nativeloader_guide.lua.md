# nativeloader_guide.lua

The in-game RTX Remix guide. Client only, in RTX sessions (the companion ships in the RTX-only
package). The console command `nativeloader_guide`, or RTX Remix tab > Start here, opens a window with
five pages:

| Page | What it says |
|---|---|
| Welcome | What runs (the loader and the Workshop package); RTX off with `"remix": { "enabled": false }`; the borderless window and `-w`/`-h` in Steam's launch options |
| Remix menu | Alt+X; set the preset to Custom before changing single settings; which Save button writes `user.conf` and which `rtx.conf`; why not to press "Migrate N Developer Settings" |
| Settings | The classic defaults and `nativeloader_rtx_defaults`; the RTX Remix tab's Remix settings |
| Lights | The flashlight, map lights (light updater or API lights), the Advanced MMD Animation Player's flashlight and its radius |
| Troubleshooting | `nativeloader_status`; `native-loader\logs\loader.log`, `status.json`, `session.json`, `rtx-remix\logs\remix-dxvk.log`; start-up crashes, add-on conflicts (`nativeloader_guard`), frame rate, "Couldn't mount file", settings that come back |

Images come from `materials/nativeloader/guide/` (`rtx_on.jpg`, `remix_menu.jpg`), screenshots taken
with [`tools/poc_session.py`](../../../../../tools/poc_session.py.md). A missing image is left out.

On the first RTX session it opens by itself, 8 s after the player spawns, once. The marker is
`garrysmod/data/nativeloader_companion/guide_shown.txt`.
