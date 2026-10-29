# nativeloader_i18n.lua

Shared autorun file. On the server it sends the companion's translations to clients:
`AddCSLuaFile("nativeloader/i18n.lua")`, and `nativeloader/i18n_data.lua` when the add-on has it (the
RTX package's build writes it, [`tools/companion_i18n.py`](../../../../tools/companion_i18n.py.md)).
Files under `lua/autorun/client` reach clients by themselves; the module they include does not, so
without this a client joining a server would run the tab and guide without their translations.

On the client it does nothing. See [`../nativeloader/i18n.lua.md`](../nativeloader/i18n.lua.md) and
[ADR 0029](../../../../docs/decisions/0029-companion-translations.md).
