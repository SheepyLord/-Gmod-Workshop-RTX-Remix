# test_presentation_ui.py

R7-B rejects replacement question marks and U+FFFD in every catalog value, catching lossy
Windows shell encodings before apparently complete translated catalogs reach the embedded DLL.

Offline checks for all seven startup templates, supported placeholders/project URL, complete
seven-language main-menu labels, and the real JavaScript UI in Node, including the multiplayer
bootstrap trigger with and without the diagnostics overlay. Run with tools/test.ps1 or unittest
discover. Node is optional in environments without it (that one case is skipped, as before); the
asset checks always run. No game, browser, network, clipboard or filesystem mutation. Exit zero on
success.

R6 also runs `menu_notices_harness.lua` with already-installed LuaJIT (optional when absent),
executing the actual embedded `read_notices.lua` against local file/JSON/UI fixtures. Covers bounded
reads, malformed data, process-token/PID checks including PID reuse and once-per-start state.
The Node harness checks failure/RAM notices across all seven languages and before-map visibility.
