# nativeloader_toolgun.lua

RTX-only client screen redraw. `nativeloader_toolgun_screen` defaults to 1; set 0 to disable.
Captures the stock toolgun screen mesh, current skeletal pose and viewmodel projection after the
viewmodel draw. The original tool and custom screen add-ons (Dynamic Toolgun Screen) retain ownership
of the live texture.

HUDPaint draws the screen as screen-space triangles: each captured screen vertex is projected with the
view's origin, angles and view model field of view (CViewSetup's horizontal field of view, already
scaled to the aspect ratio), and each mesh triangle is cut into 8 x 8 smaller ones so the texture
follows the perspective. Remix rasterizes such 2D HUD draws after its upscaling, so scrolling text stays
sharp. Review R4 (2026-10-31) replaced the earlier redraw, which rendered the screen through a 3D camera
into an offscreen target: Remix takes every perspective draw into its path-traced scene, even one made
in HUDPaint into a render target, so that layer never reached the screen and the scrolling text kept
Remix's temporal smear. The 2D layer has no depth test; the screen sits in its bezel, and parts of the
model in front of it (none on the stock toolgun) would be drawn over.

R20-T also sets `$ignorez` on the private material: its opaque UnlitGeneric defaults otherwise write
depth, so Remix's orthographic-UI test does not recognize it when it is the first HUD draw. The screen
then enters the lit, temporally reconstructed scene and becomes nearly black at night; an earlier
ordinary HUD draw or a screen preview can accidentally hide the defect. Disabling depth on this HUD
material makes the same live texture rasterize after upscaling regardless of hook order. Screen art,
backlight, colours, and the original model/add-on materials remain the original renderer's choices.

It does not stop animation, edit model materials, change upscaler/frame-generation preferences, write
Remix categories or modify Steam files. Unsupported models, non-main views and a screen behind the
camera keep their original rendering. One error disables the redraw until its ConVar is changed or the
session restarts.

Resources: one private UnlitGeneric material. No disk, network or server changes.
`nativeloader_toolgun_status` prints capture/draw counts, current texture, triangle count and a failure
if any. No process exit code; errors go to the game's console.
