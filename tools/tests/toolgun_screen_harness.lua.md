# toolgun_screen_harness.lua

Runs the shipped screen redraw with generated mesh/bone fixtures and mocked GMod rendering APIs.
Arguments: companion Lua path, scenario. Checks weighted pose-to-bone transforms, the actual
viewmodel projection, current live texture, separate-depth target, no original-material edits,
unsupported views, stale frames, resize, allocation retry and exception cleanup. Writes no files,
launches no game and sends no network requests. Exit 0/PASS or nonzero/assertion failure.
