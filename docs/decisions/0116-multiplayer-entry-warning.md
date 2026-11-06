# 0116: Warn before entering the RTX server browser

- Status: Accepted 2026-11-06
- Decided by: the user's R20 item 50

The RTX client bootstrap supports multiplayer rendering but cannot establish a server's policy,
ensure its map has PBR content, or guarantee performance/stability. Show those limits before the
server browser opens, in both the main and pause menus.

Loader 0.15.0 registers an Angular `$locationChangeStart` listener in the decorated stock menu.
It intercepts the `/servers` route and its descendants, including navigation from code, alternate
links, history and the home link. A localized modal states the kick/ban risk, checking server rules,
the map's PBR resources, uncertain performance/stability, and use at the player's own risk with no
developer responsibility. Continue permits the pending route once; Back returns home. The checkbox
is saved only on Continue, never on Back.

The remembered choice is the stock menu cookie `nativeloader.multiplayer-warning-dismissed`, read
and written through the stock menu Lua bridge using fixed snippets. It survives restarts in local
mn.db (the stock menu File object has no Write method, so file.Write is unavailable) and is
separate from cloud config.cfg, loader config.json and Remix user.conf. A broken bridge, changed menu
or failed modal creation permits navigation. The listener cancels only after a modal exists, so a
failed warning never traps the player. It is installed only for an active RTX session; the independent
verified multiplayer bootstrap trigger and its changed-menu fallback retain their existing behavior.

This is a local entry warning, not a server-policy check or an anti-cheat compatibility claim.
