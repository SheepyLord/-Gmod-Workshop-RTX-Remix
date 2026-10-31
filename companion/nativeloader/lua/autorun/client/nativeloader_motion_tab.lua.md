# nativeloader_motion_tab.lua

Adds a dedicated Motion importer creation tab beside External Models. Its button opens the
bundled importer's existing MMDVMDNPC.OpenMotionManager function and closes the spawn menu.
The button follows late importer availability and never opens a window just by creating the tab.
The title, tooltip and panel use the companion's six translated catalogs; the stable tab key
and language callbacks keep the title correct when Sandbox rebuilds its spawn menu.
No files, network messages, imported data or playback state are changed by the launcher itself.
No process exit code; missing Sandbox APIs skip registration.
