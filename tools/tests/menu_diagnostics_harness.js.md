# menu_diagnostics_harness.js

Node standard-library test of the complete mainmenu.js in a small DOM/engine fixture. Checks
text-only insertion of hostile-looking values, full hashes on hover/copy, no automatic outbound
action, explicit project link, language/version updates, menu-home-only visibility and idempotent
installation. The `client_bootstrap: true` cases (`window.NativeLoaderClientBootstrap`) check that
the verified multiplayer bootstrap is requested exactly once per menu page, with the diagnostics
overlay and without its data (the view the loader installs when the stock menu controller
changed), that it waits for the Lua bridge and stops polling after a bounded number of attempts
([ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md)). Run through
test_presentation_ui.py. No browser, clipboard, network or file writes. Exit zero on success,
nonzero on assertion failure.
