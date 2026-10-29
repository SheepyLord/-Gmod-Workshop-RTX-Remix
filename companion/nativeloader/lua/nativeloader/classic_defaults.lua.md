# classic_defaults.lua

Generated data, not code to edit: the values the user's classic RTX install saved for the RTX
add-ons' console variables, as `return { version = N, client = {...}, server = {...} }`.
[`tools/classic_defaults.py`](../../../../tools/classic_defaults.py.md) writes it;
[`nativeloader_defaults.lua`](../autorun/nativeloader_defaults.lua.md) applies it
([ADR 0020](../../../../docs/decisions/0020-classic-rtx-settings-as-defaults.md)).

`version` goes up when the table changes, so each player gets the new values once more (only for
settings still at their add-on's default).
