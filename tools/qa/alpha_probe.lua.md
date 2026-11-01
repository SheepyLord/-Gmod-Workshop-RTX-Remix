# alpha_probe.lua

Client Lua for `poc_session.py run --lua tools\qa\alpha_probe.lua --lua-shots 60` on gm_construct (R7-A,
transparent materials that render black under RTX, [R7 plan](../../docs/handover/R7-plan.md)). It needs a
temporary QA add-on `nlqa_alpha` in the test install's `garrysmod/addons` whose `materials/nlqa_alpha/`
holds the texture under test and one VMT per variant; the session driver makes it and removes it after.

What it does: sets clear weather at noon (`nativeloader_weather_seconds 0`, `nativeloader_weather clear`,
`nativeloader_sky_time 12`), lays one client-side `models/hunter/plates/plate1x1.mdl` per variant flat,
30 units above the open ground west of the gm_construct spawn (two rows of four, 60 units apart, the
first row nearest the camera, variants left to right), prints `NL_ALPHA plate <n> <variant> row <r>
column <c> at <pos>`, pins a `CalcView` camera above and behind the rows (HUD hidden), and after ten
seconds prints `NL_SHOT plates`. When the driver answers `nl_shot_taken` it removes the plates and
prints `NL_SHOT_DONE`. The default variants are `a_hotloader` (Model Hotloader's material as generated),
`b_no_atoc`, `c_ref02`, `d_translucent`, `e_plain_alphatest`, `f_no_vertexcolor`, `g_unlit_alphatest`
and `h_opaque`; the globals `NL_ALPHA_VARIANTS` and `NL_ALPHA_CENTER` replace them.

Side effects: the session's weather and sky time; client-side models only. Exit codes: none (game Lua).
