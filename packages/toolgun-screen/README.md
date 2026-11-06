# toolgun-screen

Dynamic Toolgun Screen 1.3.1, by SheepyLord, bundled at the owner's request (R20 item 48).
Read-only source: `H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\dynamic_toolgun_screen`.
The original `addon.json` filter retains 30 files: all shipping Lua, thirteen language catalogs,
metadata and the screen picture. Development Python/tools/Markdown are excluded. Original shipping
input bytes are unchanged; `files.json` records their SHA-256 and import source. The code uses this
repository's MIT licence by the owner's direction; artwork attribution is in `licenses/CREDITS.txt`.

The part deploys as `nldynamic_toolgun_screen`, keeping the standalone folder beside it. The packager
attaches the companion's small marker and early coexistence bootstrap, plus licence and credits.
Its autorun adapter skips an already-loaded standalone client; the original initializer is attached
verbatim at a private path, so neither normal nor verified multiplayer loading initializes it twice.
GMod resolves duplicate virtual Lua paths once; the bootstrap additionally prevents repeat module
initialization. The thirteen language includes remain repeatable for live language changes.

The complete companion moves the tracking tool and its settings to RTX Remix / Rendering, beside
Toolgun screen, and removes the redundant Utilities shortcut. The tracking tool's console command,
presets, preview and translations remain those of the original add-on. No standalone folder is
renamed or deleted. See [ADR 0118](../../docs/decisions/0118-bundled-toolgun-screen-and-owned-blood-patterns.md).

LFS: one PNG, **24,316 compressed bytes**. All other inputs are text. Import/update with the
`package_content.py` inventory and `inputs.py import`; do not edit indexed bytes by hand.
