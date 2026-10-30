# test_weather_presets.py

Tests [`weather_presets.py`](../weather_presets.py.md) on a small fork it writes under `out\tmp`. The
fork has eight fields, one of each blend kind, and twelve presets.

- **Each field's option and kind.** A cloud field sets `rtx.atmosphere.*`, `volumetricAnisotropy` sets
  `rtx.volumetrics.anisotropy`, and a precipitation field sets `rtx.weather.precipitation.*`.
- **Fields the runtime takes over only when presets disagree.**
  - The fog-remap switch differs in one preset, so it is in the table.
  - The noise octaves are the same in all twelve, so they are left out and named in the header.
  - The octaves' option is a `uint32_t`, so the field is marked `integer`.
- **The written table.** It shows colours as `{ r, g, b }` and switches as `true`/`false`.
- **`--check`.** It fails before the table exists and after a value in it is edited. It passes once
  the table is written.
- **Refused sources.** An option the fork does not declare is refused, and so is a preset without a
  value for a field.
- **The committed table against the user's fork.** When the fork is on this machine, `--check` must
  pass on the committed `weather_presets.lua`; the test is skipped otherwise.

Run with the other tool tests: `python -m unittest discover -s tests` from `tools\` (as
`tools\test.ps1` does). Exit 0 when the tests pass.

- `test_what_each_option_goes_back_to` (R3-009): the defaults of every option the weather sets, the layer's
  value winning over the runtime's, as option text; a default that is not a literal stops the run.
