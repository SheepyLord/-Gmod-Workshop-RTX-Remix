# weather_presets.py

Writes the companion's table of weather presets,
[`companion/nativeloader/lua/nativeloader/weather_presets.lua`](../companion/nativeloader/lua/nativeloader/weather_presets.lua.md),
from the user's Remix fork. The runtime has twelve weather presets (clear, partly cloudy, overcast,
hazy, foggy, drizzle, rainstorm, thunderstorm, snow, blizzard, sandstorm, smoggy), each 63 values for
clouds, the atmosphere, the night sky, volumetric fog and precipitation, and a blender that crossfades
between them. A game picks one with `remixapi_SetGameValue("__weather.target", ...)`, which the RTX
fixes give Lua no way to, so the companion's sky ([`nativeloader_sky.lua`](../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md))
blends between the same values itself, through `RemixConfig.SetConfigVariable`
([ADR 0031](../docs/decisions/0031-physical-sky-time-and-weather.md)).

```powershell
python tools\weather_presets.py            # regenerate from the fork
python tools\weather_presets.py --check    # exit 1 when the table is out of date
```

## Inputs

`--fork` (default `H:\BACKUP_20260815\Modding\dxvk-remix-gmod`), read only:

- `src\dxvk\rtx_render\rtx_weather.h`:
  - `WEATHER_PRESET_FIELD_LIST`: each field's type, name and kind;
  - `WEATHER_PRESET_VALUES_<preset>`: the values;
  - `DECLARE_ALL_WEATHER_PRESETS`: the order.
- `rtx_weather.cpp`: the fields listed in `FALLBACK_IF_INVARIANT(...)`. While a weather is set, the
  runtime takes such a field over only if the presets disagree on it. The other fields it always takes
  over.
- `rtx_atmosphere.h`, `rtx_global_volumetrics.h`, `rtx_precipitation.h`: the `RTX_OPTION`
  declarations. Every field's option must be declared there. The declared type says whether the option
  takes a whole number.

## What each field sets

The option the runtime's `snapshotRenderer` reads for the field:

| Field | Option |
|---|---|
| `precipitation<Name>` | `rtx.weather.precipitation.<name>` |
| `volumetricAnisotropy` | `rtx.volumetrics.anisotropy` |
| other fields of the group "Volumetric Fog" | `rtx.volumetrics.<field>` |
| everything else (clouds, atmosphere, sky and moon) | `rtx.atmosphere.<field>` |

The blend kinds come from the runtime's (`WK_*`), and the companion interpolates them the same way:

- `scalar`: linear;
- `angle`: the short way round;
- `extinction`: in 1/distance;
- `color`, `vec3`: per channel;
- `step`: switches at the midpoint.

The two kinds the runtime shows in other units (km/s as m/s, 1/km as km) blend linearly on the stored
value, as in the runtime.

## Output

A Lua table: `order` (the twelve names), `fields` (`name`, `option`, `kind`, `integer` for a
whole-number option) and `presets` (name to field to value; colours as `{ r, g, b }`).

- Fields that every preset leaves alike and that the runtime leaves to the configuration (27 of the 63
  as of 2026-10-29) are left out, and the header names them.
- The header also names the fork's commit and the first 16 digits of the SHA-256 of `rtx_weather.h`.
- The file is rewritten only when the presets change; the commit line is not compared.
- Prints the path and the counts: 12 presets, 36 of 63 fields.

## Exit codes

- 0 on success, and with `--check` when the table is up to date.
- 1 when a source file is missing or does not read as expected, or with `--check` when the table
  differs. An expected macro that is missing, a field without a value in a preset and an option that is
  not declared are all refused. The message names what was wrong.

Tests: [tests/test_weather_presets.py](tests/test_weather_presets.py.md).
