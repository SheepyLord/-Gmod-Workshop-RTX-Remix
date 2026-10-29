# _nativeloader_guard.lua

The companion's RTX-session guard ([ADR 0022](../../../../docs/decisions/0022-companion-rtx-session-guard.md)).
The companion ships in the RTX-only package (ADR 0013), so this file runs only in sessions with RTX.
Its name sorts first among the autorun files, so it is in place before other add-ons' files run.

- **Session settings stay as set.** It reads the loader's `cfg/nativeloader_session.cfg` (the session
  console variables) and adds `mat_motion_blur_enabled 0`. A Lua write through `RunConsoleCommand` or
  `Player:ConCommand` that would change one of them is dropped. The console says so once per caller
  and variable: `[nativeloader] kept r_threaded_particles at 0 for RTX: lua/autorun/client/cl_antilag.lua tried 1`.
  Typing a command in the console is not Lua, so it still works.
- **Motion blur reads as on.** The engine keeps `mat_motion_blur_enabled` at 0, but Lua that reads it
  through `GetConVar(...)` (`GetInt`, `GetFloat`, `GetBool`, `GetString`) sees it as on, and so does
  `GetConVarNumber`, which GMod builds on `GetConVar`. Draconic Base otherwise printed "Disabling motion
  blur will break addons' effects. Setting mat_motion_blur_strength to 0 instead..." every second and
  asked for it again. The engine and the console still see the real value.
- **No raster post-processing over the path-traced image.** After the client initialises, the stock
  functions `DrawBloom`, `DrawColorModify`, `DrawSharpen`, `DrawMotionBlur`, `DrawToyTown`,
  `DrawMaterialOverlay`, `DrawSobel`, `DrawSunbeams`, `DrawTexturize`, `DrawBokehDOF` and `halo.Render`
  do nothing. Their shaders cannot run at shader model 0, and the screen copy and quad they leave
  would cover the path-traced frame. The RTX fixes already turn `halo.Add` off.
- **Exempt:** the RTX fixes (`remixbinary`, `remixlua`) and the companion itself.
- **Off switch:** `nativeloader_guard 0` (a saved client setting) passes everything through, at once.

Found by the add-on audit of 2026-10-28 ([RESEARCH.md](../../../../docs/RESEARCH.md) section 19):
FPS Boost sets `r_threaded_particles 1` and queued-rendering variables at every client start, and
Draconic Base turns engine motion blur back on every second.
