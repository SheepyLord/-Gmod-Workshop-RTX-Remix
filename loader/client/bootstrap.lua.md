# bootstrap.lua

Private client initializer embedded in gmsv_nlrtxclient_win64.dll (menu-side, never a server initializer). It receives only an immutable,
hash-verified RTX script catalog from native code. It executes shared/client autoruns and local
RTX entity definitions with scoped include/require/file helpers. All unrelated operations fall
back to the original engine APIs; sv_allowcslua and server state are not changed. Arbitrary-source
developer automation is excluded. Native API callbacks accept catalog keys only, never source.
Status and errors are local. No files, clipboard or network changes are made by the loader itself.

The scoped net adapter drops a bundled tool's message when the server has not registered its
channel. Write/send/abort calls for that message do nothing and BytesWritten returns 0, 0; the
next Start resets that state. Registered channels delegate normally. All verified scripts share
this adapter, including included helpers. The original global net functions remain untouched.
Missing channel names are recorded in NATIVELOADER_CLIENT_PAYLOAD.missing_server_channels;
server-side tool features still require their matching server component.

It returns without finishing while the realm is not ready (no GAMEMODE or no valid local player),
so the module tries again later; it finishes at once, and is not run again, when the realm lacks
hook or CompileString and in single-player. The packaged cl_rtx.lua sets the global
NATIVELOADER_RTX_NORMAL_LOAD when normal loading ran it; a second run would register its hooks,
convar callbacks and entities again. On a listen host or an sv_allowcslua 1 server, where every
local add-on loads normally, the initializer then finishes without running anything. On another
server, which delivered its own copy of that add-on, only the add-on holding autorun/cl_rtx.lua is
left out (its autoruns and entities, and cross-owner includes of its files, which the engine then
serves) and listed in NATIVELOADER_CLIENT_PAYLOAD.normally_loaded
([ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md)). An entity class the server
already delivered (scripted_ents.GetStored) keeps its definition; the owned copy is not run and the
class is listed in NATIVELOADER_CLIENT_PAYLOAD.server_entities. Whether the server delivered other
individual files is not detectable reliably on the client, so autoruns are not filtered one by one.

Owned OnGamemodeLoaded, PostGamemodeLoaded, Initialize and InitPostEntity registrations made while
the payload loads are tracked and, if still registered with the same function, replayed once each
in that order (those events happened before this late initialization). Registrations of other code
are never replayed.
