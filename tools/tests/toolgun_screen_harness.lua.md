# toolgun_screen_harness.lua

Runs the shipped screen redraw with generated mesh/bone fixtures and mocked GMod rendering APIs.
Arguments: companion Lua path, scenario. Checks weighted pose-to-bone transforms, the projection of
each screen vertex with the view model field of view (against hand-computed coordinates), UVs carried
to the 2D triangles (2 mesh triangles x 64), the current live texture, no original-material edits,
unsupported views, a screen behind the camera, stale frames, resize, and that one drawing failure is
reported once and recovers when the ConVar is toggled. The mocked `render` offers no render targets,
cameras, overrides or depth, so any such call fails the run: the redraw must stay a 2D HUD draw. Writes
no files, launches no game and sends no network requests. Exit 0/PASS or nonzero/assertion failure.

`hud_first` / `hud_after_ui` model the runtime's orthographic UI injection boundary. Before injection,
an opaque depth-writing material enters the lit scene; after injection, the same draw accidentally
rasterizes. Both orders must draw every screen triangle in the raster HUD. This is a CPU contract
fixture, supplemented by R20-T's actual 4K noon/night and HUD-order captures; it does not simulate a GPU.
