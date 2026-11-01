# eye_white_probe.lua

Client Lua for `poc_session.py run --console "<placement>" --lua tools\qa\eye_white_probe.lua --lua-shots 150`:
spawns a Model Hotloader character where the player is looking, pins a camera on its face and takes one
screenshot per sky condition, so [`eye_white_patches.py`](eye_white_patches.py.md) can measure the eye
whites against the skin as the light changes. Made for C-16, the anime eye whites that turned grey by
day and glowed at night ([C16 plan](../../docs/handover/C16-plan.md),
[TESTING.md](../../docs/TESTING.md#c-16-scene-adaptive-emission)). No cheats needed.

What it does, in order:

1. Sets clear weather now (`nativeloader_weather_seconds 0`, `nativeloader_weather clear`) and prints
   `NL_EYE start pos <x y z> ang <pitch yaw roll>`, where the player stands and looks.
2. Asks Model Hotloader to spawn the asset (`mmdhl.RequestSpawn`; Robin's
   `f9c3e4b4...d32b` unless `NL_EYE_ASSET` is set). The server places it at the player's eye trace,
   turned toward the player, and the ragdoll falls. Prints `NL_EYE request <ok> <error>` and each
   `NL_EYE spawn <state> <entity index> <message>`.
3. Three seconds after `ready`, prints `NL_EYE entity <entity> valid <bool>` and pins the view with a
   `CalcView` hook: 22 units above the head bone (`ValveBiped.Bip01_Head1`, else the entity's centre),
   straight down, 38 degree field of view. HUD and view model are hidden. This frames a character that
   lies face up.
4. For each condition (default noon 12, golden 17.25, dusk 19, night 0; `NL_EYE_CONDITIONS` replaces
   them, `{{label, hour}, ...}`) sets `nativeloader_sky_time`, waits 10 s for auto exposure
   (tau 0.15-0.75 s) and the denoisers, prints `NL_EYE <label> hour <h> head <x y z>` and
   `NL_SHOT <label>`, and goes on when the session driver answers `nl_shot_taken`.
5. Removes the character with Model Hotloader's own action (`mmdhl.Action("remove", nil, ent)`;
   client Lua may not run `lua_run`), puts the player's four sky settings back
   (`nativeloader_weather_seconds`, `nativeloader_weather`, `nativeloader_sky_follow_map`,
   `nativeloader_sky_hour`) and prints `NL_SHOT_DONE`.

Without Model Hotloader it prints `NL_EYE spawn error nil Model Hotloader is not loaded` and ends; a
spawn error (an asset the player may not spawn, aiming at the sky) ends it the same way, and so does a
ragdoll this client cannot see three seconds after `ready` (`valid false`: it fell out of the world,
or the spot is outside the visible map).

## The same framing every run

gm_construct puts the player at one of several spawn points, and where the character lands decides
both the framing and the light it is in (one spawn point gave half the skin luminance at night of
another). Client Lua may not run `lua_run` (`RunConsoleCommand: Command is blocked! (lua_run)`), so
place the player from the console: `poc_session.py`'s `--console` lines are sent after the map and
before `--lua` files. The C-16 measurements used a gm_construct spawn point, facing west:

```powershell
python tools\poc_session.py --evidence out\qa-poc\c16 run --name eye --addons --map gm_construct --width 1920 --height 1080 --console "lua_run local p=Entity(1) p:SetPos(Vector(831.235,576,-143.08)) p:SetEyeAngles(Angle(0,180,0)) p:SetVelocity(-p:GetVelocity())" --lua tools\qa\eye_white_probe.lua --lua-shots 150 --extra=-insecure
```

Robin then lands face up on the field near (-2544, 572, -75), and
[`eye_white_patches.py`](eye_white_patches.py.md)'s default boxes fit the 1920x1080 frame. The line has
no `;` or `//` (the console would split or cut it there).

## Side effects

The session's time of day and weather while it runs; the four sky settings are put back. The character
it spawned is removed; the hooks it added (`CalcView`, `HUDShouldDraw`, `PreDrawViewModel`) are removed.
It adds the console command `nl_shot_taken`. Exit codes: none (client Lua).
