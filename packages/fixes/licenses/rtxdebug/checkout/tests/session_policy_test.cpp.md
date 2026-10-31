# session_policy_test.cpp

Standalone CPU check of the actual session_policy.h functions. Single-player needs a connected
client, a loopback net channel, no demo playback and exactly one player slot; a remote server that
reports one slot, a listen server with more slots, the main menu and demo playback are refused. The
mutation gate's full truth table is checked, including the case of a remote insecure server with
sv_cheats 1. Compile with a C++17 compiler and run it; exit 0 when every check passes, 1 otherwise.
No game, GPU, file or network access.
