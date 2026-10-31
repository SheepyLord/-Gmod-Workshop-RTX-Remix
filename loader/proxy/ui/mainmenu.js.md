# mainmenu.js

Display-only panel appended to the stock menu controller by the loader's exact read redirect.
Shows OS, CPU/logical threads, physical RAM, graphics adapters/VRAM, the game's own version/branch,
loader version/file SHA-256 and deployed native package versions/manifest SHA-256. Hashes are
abbreviated visually, available in hover text and copied in full by the explicit copy button.
The panel appears on the main-menu home screen only and follows the menu language. Values use
textContent, never HTML. No upload, automatic URL opening, startup-log reading or disk writes.
The project link and clipboard functions run only on a click. Labels are in labels.json;
layout/style and project URL are edited here. Compiled into winmm.dll through CMake.
