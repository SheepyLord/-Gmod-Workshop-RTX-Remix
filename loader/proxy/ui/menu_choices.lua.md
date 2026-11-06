# menu_choices.lua

Embedded menu-realm reader for R20 choices. No CLI; stock `lua.Run` supplies one quoted process token
at `%s`. Reads stock menu cookies `nativeloader.loader-update-ignored` and
`nativeloader.multiplayer-warning-dismissed`, accepting strings at most 128 bytes. A missing/oversized
value is an empty choice. Only exactly `1` dismisses the multiplayer warning. It also reads the menu realm's
`NativeLoaderUpdateSession` acknowledgement for this token. Sends parsed fields as re-encoded JSON
to `NativeLoaderReceiveMenuState` through the valid `pnlMainMenu`; a missing panel does nothing.

No writes, network requests, imports or exit codes. The JavaScript's explicit buttons perform fixed
cookie.Set writes and acknowledgement separately. Menu cookies persist in GMod's local mn.db;
file.Write cannot be used in this realm on the tested stock build (File:Write is absent). Tested by
`tools/tests/menu_choices_harness.lua` through `test_presentation_ui.py`.
