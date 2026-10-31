# 0057: The toolgun screen is redrawn as a projected 2D overlay

- Status: Accepted. Supersedes in part [0046](0046-toolgun-screen-after-upscaling.md): its mechanism (a
  full-resolution offscreen layer rendered through the view model camera with a gun/hands depth mask).
  0046's intent stands: only the toolgun's live screen is redrawn, after Remix's upscaling, and the
  screen add-ons keep owning the texture.
- Date: 2026-10-31. Decided by Claude in review R4, on the user's report that the toolgun's rolling
  text was still smeared, under the user's instruction to decide autonomously.

## Context

Field evidence (R4, the user's install, Dynamic Toolgun Screen subscribed):

- The redraw ran (`nativeloader_toolgun_status`: 344 captures, 172 draws, texture
  `dtscreen_screen512`), yet the gun showed only the path-traced screen: crisp static text, smeared
  scrolling text (temporal reconstruction of moving content without motion vectors).
- Dynamic Toolgun Screen's render target itself was sharp when drawn flat on the HUD, whether it was
  rendered in the 3D pass (its `SWEP:RenderScreen`) or from `HUDPaint`.
- Under Remix, 2D draws into a render target from `HUDPaint` rasterize (cleared and redrawn every
  frame, no trails); the same draws from a 3D pass hook leave the target black. A perspective draw is
  taken into Remix's scene. 0046's layer is a perspective draw (`cam.Start` with the view model
  camera) into a target, so it never reached the screen; making its alpha opaque changed nothing.

## Decision

The companion projects the captured screen vertices itself, with the view's origin, angles and view
model field of view (CViewSetup's horizontal field of view, already scaled to the aspect ratio), and
draws the live texture as screen-space triangles in `HUDPaint` (`surface.DrawPoly`), each mesh triangle
cut into 8 x 8 so the texture follows the perspective. Remix rasterizes 2D HUD draws after upscaling,
so the text is sharp and aligned with the bezel (checked in the field, `out\qa-field\toolgun`).

## Consequences

- No render targets, cameras, overrides or depth state: nothing to restore or leak.
- No depth test: something of the model in front of the screen would be drawn over. The stock toolgun
  has nothing there (its paper note sits above the screen).
- The test harness offers no render-target or camera functions, so a regression to a perspective draw
  fails `tools/tests/test_toolgun_screen.py`.
