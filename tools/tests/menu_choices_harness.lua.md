# menu_choices_harness.lua

Runs the real embedded menu choices reader under LuaJIT with mocked files, JSON and menu panel.
Argument: `loader/proxy/ui/menu_choices.lua`. Tests missing choices, 128-byte bounds, exact dismissal,
process-token acknowledgement and missing panel. No writes, game or network. Prints PASS and exits 0;
assertions/errors exit nonzero. Called by `test_presentation_ui.py`.
