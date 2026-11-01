# debris_view.lua

Client-only helper included by `debris.lua`. `Capture()` reads `render.GetViewSetup()` once per
draw pass, including scripted/third-person camera origin/angles/FOV/aspect; EyePos/EyeAngles are
fallbacks. Without a camera, culling is disabled. It caches numeric rotation/frustum coefficients
and viewport scale. Both Source's 4:3 reference FOV and literal horizontal FOV fit its conservative
bounds. Pitch, yaw and roll are supported. `Visible(position, radius, small)` uses sphere-plane
tests, an 8192-unit distance (plus radius), and optionally a projected radius below 0.75 pixels
beyond 256 units. Actual pixel scale follows screen height; nearby tiny shards remain visible.
Only rendering is culled; physics, budget and lifetime continue. Settled areas use conservative
cell bounding spheres without subpixel rejection. No per-piece allocations, files, networking,
hooks or process exit code.
