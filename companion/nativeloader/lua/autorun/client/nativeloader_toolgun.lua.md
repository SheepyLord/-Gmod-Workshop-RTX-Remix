# nativeloader_toolgun.lua

RTX-only client screen redraw. `nativeloader_toolgun_screen` defaults to 1; set 0 to disable.
Captures the stock toolgun screen mesh, current skeletal pose and viewmodel projection after the
viewmodel draw. The original tool and custom screen add-ons retain ownership of the live texture.

HUDPaint draws a full-resolution offscreen screen layer with a separate gun/hands depth mask, then
composites it after Remix's upscaling. It does not stop animation, edit model materials, change
upscaler/frame-generation preferences, write Remix categories or modify Steam files. Unsupported
models and non-main views retain their original rendering. Render state is restored on failure;
one error disables the redraw until its ConVar is changed or the session restarts.

Resources: two private UnlitGeneric materials and one render target per used output size. No disk,
network or server changes. `nativeloader_toolgun_status` prints capture/draw counts, current texture,
triangle count and a failure if any. No process exit code; errors go to the game's console.
