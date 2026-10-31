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
