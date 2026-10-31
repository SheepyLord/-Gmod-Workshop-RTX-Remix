# menu_diagnostics_harness.js

Node standard-library test of the complete mainmenu.js in a small DOM/engine fixture. Checks
text-only insertion of hostile-looking values, full hashes on hover/copy, no automatic outbound
action, explicit project link, language/version updates, menu-home-only visibility and idempotent
installation. Run through test_presentation_ui.py. No browser, clipboard, network or file writes.
Exit zero on success, nonzero on assertion failure.
