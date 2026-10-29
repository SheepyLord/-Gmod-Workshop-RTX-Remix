# classic_defaults.py

Writes the companion's table of classic RTX settings,
[`companion/nativeloader/lua/nativeloader/classic_defaults.lua`](../companion/nativeloader/lua/nativeloader/classic_defaults.lua.md).
The values are what the user's classic RTX install (`GarrysMod_RTX_c`) saved for the RTX add-ons'
console variables. The companion applies them once as first-run defaults
([ADR 0020](../docs/decisions/0020-classic-rtx-settings-as-defaults.md)).

```powershell
python tools\classic_defaults.py            # regenerate from GarrysMod_RTX_c
python tools\classic_defaults.py --check    # exit 1 when the table is out of date
python tools\classic_defaults.py --version 2  # a new table version: players get the values once more
```

## Inputs

- `--reference` (default `H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c`): its
  `garrysmod\cfg\client.vdf` and `server.vdf`, where GMod x64 keeps the values of Lua console
  variables. Read only.
- Which variables: names starting `rtx_` (the RTX fixes), `mhrtx_` (the Model Hotloader's RTX options),
  `brrtx_` (gm_br_rtx), `r_hwskin`, `r_eyes_hwskin` and `r_forcehw` (the fixes' skinning options).
  Debug switches are left out.

## Output

The Lua table (`return { version = N, client = {...}, server = {...} }`), sorted by name, with a
header naming the source and date. It is rewritten only when its content changes (the date line is
not compared). Prints the path and the counts.

## Exit codes

0 on success (and with `--check` when up to date); 1 when a reference file is missing, or with
`--check` when the table differs.
