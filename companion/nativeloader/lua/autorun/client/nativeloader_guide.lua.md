# nativeloader_guide.lua

The Common Remix paragraph follows ADR 0044: edits apply to the current session, Remix's Save keeps
them, startup replay is opt-in, and numeric overrides must be selected explicitly. It does not
describe the former automatic replay behavior.

The in-game RTX Remix guide. Client only, in RTX sessions (the companion ships in the RTX-only
package). The console command `nativeloader_guide`, or RTX Remix tab > Start here, opens a window with
six pages, in the player's language ([`../../nativeloader/i18n.lua`](../../nativeloader/i18n.lua.md): the page
titles, headings and paragraphs are marked with `N("...")` and translated when the window opens):

| Page | What it says |
|---|---|
| Welcome | What runs (the loader and the Workshop package); RTX off with `"remix": { "enabled": false }`; the borderless window and `-w`/`-h` in Steam's launch options |
| Remix menu | Alt+X; set the preset to Custom before changing single settings; which Save button writes `user.conf` and which `rtx.conf`; why not to press "Migrate N Developer Settings" |
| Settings | The classic defaults and `nativeloader_rtx_defaults`; the RTX Remix tab's Remix settings and its fog presets; Sky and weather: the physical sky following the map's sun, the time, the real Moon and night sky, eclipses, the weather, `nativeloader_sky_time` and `nativeloader_sky_status` |
| Lights | The flashlight, map lights (light updater or API lights), the Advanced MMD Animation Player's flashlight and its radius |
| Memory and stability | 8 GB GPU/16 GB RAM guidance: page file and commit, texture detail and frame generation, loader performance tiers, local CSV readings, bounded session evidence and the extra files/context to send after a crash |
| Troubleshooting | `nativeloader_status`; `native-loader\logs\loader.log`, `status.json`, `session.json`, `rtx-remix\logs\remix-dxvk.log`; start-up crashes, add-on conflicts (`nativeloader_guard`), frame rate, "Couldn't mount file", settings that come back |

Images come from `materials/nativeloader/guide/` (`rtx_on.jpg`, `remix_menu.jpg`), screenshots taken
with [`tools/poc_session.py`](../../../../../tools/poc_session.py.md). A missing image is left out.

On the first RTX session it opens by itself, 8 s after the player spawns, once. The marker is
`garrysmod/data/nativeloader_companion/guide_shown.txt`.

The performance paragraph reflects the package default: frame generation is off for stability. It no longer describes every frame-generation method as requiring an RTX 40 GPU.

R6 adds `nativeloader_stability_guide`, linked from RTX Remix > Start here, which opens directly on
**Memory and stability**. The ordinary command and first-run timer still open the default page.
The same player guidance is maintained in [`docs/STABILITY.md`](../../../../../docs/STABILITY.md).
New R6 translations in the six non-English gettext catalogs are marked agent-written and need
human review. No diagnostics switch, tier setting or Remix configuration is written by the guide.

On each opening the guide reads DATA `native-loader/status.json`. Only schema 1 with an
`activation.performance_tier` object shows tier configuration, loader memory telemetry, automatic
session collection and GPU-dump instructions. Older, missing, malformed or unreadable reports get
bootstrap-update/manual-log-copy guidance. Workshop companion updates do not update winmm.dll;
0.10.1 rejects R6 configuration keys and would start without RTX. The R6 page includes a complete
minimal JSON example preserving the shipped `allow` list, tells customized installs to preserve
their own entries/settings, and warns that invalid JSON turns RTX off. JSON code is untranslated.

All versions say to save frame generation off and copy status.json, session.json, companion CSVs
and runtime logs **before restarting**. The next start rewrites both JSON reports and the evidence
collector does not copy them. GPU dumps use the persistent `next_start` config value: delete
`native-loader/remix/gpu-crash-dumps.used` to request another diagnostic start. Translation
provenance is retained in [`companion/i18n/README.md`](../../../../i18n/README.md), since extraction
regenerates PO comments.

The guide names the runtime’s new static migration button; the count is now on the line above it. The warning against migrating map-specific settings is unchanged.
