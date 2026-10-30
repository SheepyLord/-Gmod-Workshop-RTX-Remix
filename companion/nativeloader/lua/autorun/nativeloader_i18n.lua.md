# nativeloader_i18n.lua

Shared autorun file. On the server it sends the companion's translations to clients:
`AddCSLuaFile("nativeloader/i18n.lua")`, and `nativeloader/i18n_data.lua` when the add-on has it (the
RTX package's build writes it, [`tools/companion_i18n.py`](../../../../tools/companion_i18n.py.md)).
Files under `lua/autorun/client` reach clients by themselves; the module they include does not, so
without this a client joining a server would run the tab and guide without their translations.

On the client it does nothing. See [`../nativeloader/i18n.lua.md`](../nativeloader/i18n.lua.md) and
[ADR 0029](../../../../docs/decisions/0029-companion-translations.md).

The server registers `nativeloader_localized_chat` and exposes `NATIVELOADER_LOCALIZED_CHAT(player,
format, arguments)` for bundled glass notices. It sends only a format string and argument table to
that player. The client translates and formats the notice with `pcall` before showing local chat
text. It never executes received text, writes a file, or sends a message from the client.
