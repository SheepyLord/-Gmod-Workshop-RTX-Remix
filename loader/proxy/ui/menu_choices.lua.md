# menu_choices.lua

Embedded menu-realm reader for R20 choices. No CLI; stock `lua.Run` supplies one quoted process token
at `%s`. Reads DATA `native-loader/loader-update-ignored.txt` and
`native-loader/multiplayer-warning-dismissed.txt`, each at most 128 bytes. A missing/oversized file is
an empty choice. Only exactly `1` dismisses the multiplayer warning. It also reads the menu realm's
`NativeLoaderUpdateSession` acknowledgement for this token. Sends parsed fields as re-encoded JSON
to `NativeLoaderReceiveMenuState` through the valid `pnlMainMenu`; a missing panel does nothing.

No writes, network requests, imports or exit codes. The JavaScript's explicit buttons perform the
fixed preference writes and acknowledgement separately. Tested by
`tools/tests/menu_choices_harness.lua` through `test_presentation_ui.py`.
