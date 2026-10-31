# toolgun_screen_harness.lua

Runs the shipped screen redraw with generated mesh/bone fixtures and mocked GMod rendering APIs.
Arguments: companion Lua path, scenario. Checks weighted pose-to-bone transforms, the projection of
each screen vertex with the view model field of view (against hand-computed coordinates), UVs carried
to the 2D triangles (2 mesh triangles x 64), the current live texture, no original-material edits,
unsupported views, a screen behind the camera, stale frames, resize, and that one drawing failure is
reported once and recovers when the ConVar is toggled. The mocked `render` offers no render targets,
cameras, overrides or depth, so any such call fails the run: the redraw must stay a 2D HUD draw. Writes
no files, launches no game and sends no network requests. Exit 0/PASS or nonzero/assertion failure.
