# hotloader_depth_harness.lua

Runs actual material registration and DrawCarrier code extracted by test_hotloader_depth.py. Engine
stubs reject DepthWrite on Remix, simulate renderer initialization and delayed Source textures, and
record draw/material calls. Checks cache invalidation, both Source depth-view flags, public material
names, color/flashlight draws, Source alpha/cull/texture preservation and render-state restoration.
No game or user files are accessed. Run through the Python test runner.
