# classic_defaults.py

Writes the companion's table of classic RTX settings,
[`companion/nativeloader/lua/nativeloader/classic_defaults.lua`](../companion/nativeloader/lua/nativeloader/classic_defaults.lua.md).
The values are what a classic RTX install saved for the RTX add-ons' console variables; the table in
the repository holds those of the user's classic install (`GarrysMod_RTX_c`, read on 2026-10-28). The
companion applies them once as first-run defaults
([ADR 0020](../docs/decisions/0020-classic-rtx-settings-as-defaults.md)).

`GarrysMod_RTX_c` holds this project's implementation since 2026-10-30 (AGENTS.md rule 1): it is no
longer a classic install, and reading it would take this project's own settings for the classic ones.
So there is no default reference. The checked-in table is the record; regenerate it only from a
preserved copy of a classic install (its `garrysmod\cfg`), for example a legacy fixture prepared under
`out\`.

```powershell
python tools\classic_defaults.py --reference <classic install>              # regenerate the table
python tools\classic_defaults.py --reference <classic install> --check      # exit 1 when the table is out of date
python tools\classic_defaults.py --reference <classic install> --version 4  # a new table version: players get the values once more
```

## Inputs

- `--reference` (required): a classic install; its `garrysmod\cfg\client.vdf` and `server.vdf`, where
  GMod x64 keeps the values of Lua console variables. Read only.
- Which variables: names starting `rtx_` (the RTX fixes), `mhrtx_` (the Model Hotloader's RTX options),
  `brrtx_` (gm_br_rtx), `r_hwskin`, `r_eyes_hwskin` and `r_forcehw` (the fixes' skinning options).
  Debug switches are left out.

## Output

The Lua table (`return { version = N, client = {...}, server = {...} }`), sorted by name, with a
header naming the source and date. It is rewritten only when its content changes (the date line is
not compared). Prints the path and the counts.

A name saved in both files goes in the client table only. In single-player the client and the server
share one variable of each name, and the client's saved value is applied last, so the client's value
is the one the classic install plays with. Its `server.vdf` keeps stale copies of three: `rtx_pseudoplayer`,
`rtx_pseudoweapon` and `rtx_disablevertexlighting` are `1` there and `0` in `client.vdf`. Applying
them from the server table (version 2, through `nativeloader_rtx_defaults_server`) brought the pseudo
player back: the player's own model drawn in first person. Version 3 leaves them out of the server
table and applies the corrected values once more.

## Exit codes

0 on success (and with `--check` when up to date); 1 without `--reference`, when a reference file is
missing, or with `--check` when the table differs.
