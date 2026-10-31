# night_sky_probe.lua

Client Lua for `poc_session.py run --lua tools\qa\night_sky_probe.lua --lua-shots 180`: finds a place
under open sky near the spawn (the spawn may be indoors: on the ground, with sky straight up and in at
least six of eight directions 50 degrees up, by brush-only traces outward up to 6000 units), sets a
clear midnight through the companion's sky commands (`nativeloader_weather_seconds 0`,
`nativeloader_weather clear`, `nativeloader_sky_time 0`), waits 8 s, prints `nativeloader_sky_status`,
then turns the view there with a `CalcView` hook (90 degree field of view, HUD and view model hidden)
to eight bearings 50 degrees up and two near the zenith, one screenshot each
(`NL_SHOT sky_p<pitch>_y<yaw>`, answered by the session driver with `nl_shot_taken`), and prints
`NL_SHOT_DONE`. No cheats needed.

Prints `NL_SKY place <x y z> open <n>` (the place, or `nil` when none was found and the player's own
view is used) and `NL_SKY kept {...}` (the player's sky settings it will put back).

Made for the R5 night sky line: on `modern_house` the sky showed a haze with a straight edge, stars on
one side only. A tour run in the first minute of the map caught Modern House RTX setting its afternoon
sun again while the companion held the night (fixed in
[`nativeloader_sky.lua`](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md), "A map whose
add-on sets the sky"); a clean tour there is the check.

Side effects: the session's time of day and weather. The companion's sky settings it changes
(`nativeloader_weather_seconds`, `nativeloader_weather`, `nativeloader_sky_follow_map`,
`nativeloader_sky_hour`, archived) are put back to the player's values when the tour ends; the probe
taking the sky over on a map whose add-on sets it lasts for the session. Exit codes: none (client Lua).
