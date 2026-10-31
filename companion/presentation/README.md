# Startup message

Edit startup_message.txt for the English top-left launch text. The six suffixed files are its
translations, selected by Remix's rtx.gui.language setting. Keep {hotkey} and {seconds}; the runtime
substitutes the actual key binding and countdown. Text is UTF-8, at most 8192 bytes, and displayed
literally, so percent signs do not act as format commands. The project URL is ordinary text here.

The fixes packager deploys these to garrysmod/data/nativeloader_ui with
create-only policy. Editing the installed text there also persists: user-edited files stay theirs.
Source changes are rebuilt into the Workshop package by the usual main publishing hooks. The new
runtime reads each language once per launch (or when its language changes); missing/invalid files
fall back to English and then the compiled project message.

Main-menu layout/project link are in loader/proxy/ui/mainmenu.js and its labels.json catalog.
That panel requires loader 0.8.1's winmm.dll, delivered in the loader bundle, not just a runtime update.
