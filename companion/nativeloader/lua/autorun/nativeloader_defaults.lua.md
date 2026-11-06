# nativeloader_defaults.lua

R20-B additionally migrates the sky defaults independently of the classic table's version. On
the client it registers `NativeLoaderSkyDefaults`; the sky autorun calls it immediately after
creating its ConVars, before callbacks or clock startup. If both current values are numerically
`nativeloader_sky_time_passes = 0` and `nativeloader_sky_day_minutes = 30`, immediate `ConVar:SetString`
writes `1` and `20`. A changed value in either preserves both. The DATA marker
`nativeloader_companion/sky_defaults_client_v1.txt` records migration or preservation; future choices
are never migrated again. Missing ConVars leave the marker absent. This does not run server-side,
reapply other classic settings or count as a deliberate takeover of a map add-on's sky. See
[ADR 0117](../../../../docs/decisions/0117-startup-upscaling-hint-and-sky-defaults.md). Inputs are the
two client ConVars and marker; outputs are those two values and marker. No exit code (game Lua).

The companion's first-run defaults for the RTX add-ons' settings
([ADR 0020](../../../../docs/decisions/0020-classic-rtx-settings-as-defaults.md)). Shared: it runs
on the server and on the client.

- **When:** 5 s after the session is up (`Initialize` on the server, `InitPostEntity` on the client),
  once per table version and realm.
- **What:** for each setting in [`classic_defaults.lua`](../nativeloader/classic_defaults.lua.md) that
  exists in this session, a value still at its add-on's own default (`ConVar:GetDefault()`) is set to
  the classic install's value. A value the player chose is never changed.
- **Marker:** `garrysmod/data/nativeloader_companion/classic_defaults_<realm>_v<version>.txt`, written
  only when the RTX add-ons' settings exist. Without RTX those add-ons are left out of the session
  (ADR 0013), so the next RTX session tries again.
- **Commands:** `nativeloader_rtx_defaults` (client) sets every classic value, also the changed ones,
  and runs `nativeloader_rtx_defaults_server`, which does the same for the server settings (in
  single-player, or for a superadmin).
- **One realm per name.** In single-player the client and the server share one variable of each name.
  The table therefore has a name in the client table or the server table, never both, so the order in
  which the realms apply cannot change the result (table version 3; version 2 had the classic install's
  stale server copies of `rtx_pseudoplayer`, `rtx_pseudoweapon` and `rtx_disablevertexlighting`).

Console output: one line per realm on the first run, `[nativeloader] client: 7 of 176 RTX settings
set to the classic RTX install's values (first run)`.
