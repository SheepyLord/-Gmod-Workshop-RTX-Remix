# weather_presets.lua

Generated data, not code to edit: the Remix fork's twelve weather presets. Each field comes with the
Remix option it sets and how it blends, as
`return { order = {...}, fields = {{ name, option, kind, integer }, ...}, defaults = { [option] = text },
presets = { name = {...} } }`. `defaults` holds what Remix has for each option the weather sets when
rtx.conf does not set it (the package's classic layer, else the runtime's default), which leaving the
weather to Remix puts back (R3-009).
[`tools/weather_presets.py`](../../../../tools/weather_presets.py.md) writes it from the fork's
`rtx_weather.h`. The sky ([`nativeloader_sky.lua`](../autorun/nativeloader_sky.lua.md)) blends
between the presets and gives the values to Remix
([ADR 0031](../../../../docs/decisions/0031-physical-sky-time-and-weather.md)).

Fields that every preset leaves alike are not here: the runtime leaves them to the configuration too.
When the fork's presets change, run the tool again; its `--check` (and the tool tests) tell when the
table is out of date.
