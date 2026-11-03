# guide_pages.lua

The pages of the in-game RTX Remix guide, as data. [`../autorun/client/nativeloader_guide.lua`](../autorun/client/nativeloader_guide.lua.md)
includes it and draws them; it returns `{ pages = { ... } }`. No hooks, no files, no console commands.
The server sends it to clients with the translations ([`../autorun/nativeloader_i18n.lua`](../autorun/nativeloader_i18n.lua.md)).

Every text a player reads is written `N("...")` (one Lua string literal on one line), so that
[`tools/companion_i18n.py`](../../../../tools/companion_i18n.py.md) `update` puts it into the catalogs
in `companion/i18n`; the guide translates it with `L` when it draws the page. JSON examples are plain
long strings and stay untranslated.

## Pages, in their order

| `id` | Title | What it covers |
|---|---|---|
| `welcome` | Welcome | What runs; the three places (the RTX Remix tab, Alt+X, the guide), with the spawn menu pictured; first steps; the words used (path tracing, DLSS, frame generation, graphics preset, PBR, Remix mod, Remix API, VRAM) |
| `tab` | The RTX Remix tab | The tab's groups, pictured, then one section per group: Start here, Remix settings, Sky and weather, Rendering (Base Options and Performance pictured), Lights (Flashlight pictured), Water and glass (Glass settings pictured) |
| `remix_menu` | The Remix menu (Alt+X) | The simple menu and the developer menu, pictured; keeping changes (Custom first, View Changes, the two Save buttons, pictured); the Migrate button; the preset and the loader's tier |
| `characters` | Characters | Importing with the Model Hotloader and spawning, pictured; loading on first use; automatic PBR for game characters and manual choices (Imported game PBR, pictured); eye whites (Model outlines and the chooser, pictured); motions |
| `memory` | Performance and memory | What a computer needs; the performance tier and the memory profile; choosing them in `config.json` (the complete example); tips for 8 GB / 16 GB; reading memory; after a crash |
| `troubleshooting` | Troubleshooting | `nativeloader_status`; symptoms and what to do; the files to look at; turning RTX off; the game window |

`nativeloader_stability_guide` opens `memory`. Section ids (each heading's `id`) are what
`nativeloader_guide <page> <section>` and the `link` items open.

## Items

| Item | Shown as |
|---|---|
| `{ "h", text, id = section }` | A heading; with an `id` it is listed under its page in the navigation |
| `{ "p", text }` | A paragraph |
| `{ "steps", text, ... }` | Numbered steps; an entry may be `{ text, when = ... }` |
| `{ "list", text, ... }` | A list; entries as in steps |
| `{ "image", path, legend, ... }` | A picture from `materials/`, with its legend: entry *n* explains badge *n* in the picture. The numbers are drawn, so they need no translation |
| `{ "term", word, meaning }` | A word and what it means |
| `{ "q", text }` | A symptom (bold), followed by a paragraph saying what to do |
| `{ "tip", text }`, `{ "warn", text }` | A note, a caution |
| `{ "code", literal }` | Text shown as it is |
| `{ "button", label, command, ... }` | A button that runs the console commands |
| `{ "link", label, page, section }` | A button that opens another part of the guide |

Any item may carry `when`: `"r6"` (the loader reports a performance tier: 0.11.0 or later), `"legacy"`
(it does not), `"r13"` (it reports a memory profile: 0.13.0 or later) or `"pre13"` (it does not). The
guide reads that from `garrysmod/data/native-loader/status.json` at every opening, so an older
`winmm.dll` is never told to write a configuration key it would reject.

## Pictures

Each picture's badges are drawn by [`tools/guide_annotate.py`](../../../../tools/guide_annotate.py.md)
from the spec in `tools/guide_pictures.json`; the number of badges there equals the number of legend
entries here, which [`tools/tests/test_companion_guide.py`](../../../../tools/tests/test_companion_guide.py.md)
checks.
