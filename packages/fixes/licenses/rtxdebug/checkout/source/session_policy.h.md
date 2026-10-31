# session_policy.h

Pure developer mutation gate. `IsLocalSinglePlayer` decides single-player from facts the module
reads natively from the engine client (`IsConnected`, `GetNetChannelInfo()->IsLoopback()`,
`GetMaxClients`, `IsPlayingDemo`), never from a Lua state, which a remote server's client scripts
can change. `CanMutate` combines it with the game thread, an open module, `-insecure` from the
process command line and `sv_cheats`. Tested by tests/session_policy_test.cpp.
