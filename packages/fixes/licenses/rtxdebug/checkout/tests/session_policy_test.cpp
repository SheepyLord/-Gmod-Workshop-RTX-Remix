#include "../source/session_policy.h"

#include <iostream>

namespace {

using RTXDebug::Policy::CanMutate;
using RTXDebug::Policy::IsLocalSinglePlayer;
using RTXDebug::Policy::SessionFacts;

int g_failures = 0;

void Expect(bool condition, const char* what) {
    if (condition) return;
    std::cout << "FAIL: " << what << "\n";
    ++g_failures;
}

// What the engine reports while the player is in a game they started themselves.
SessionFacts LocalGame() {
    SessionFacts facts;
    facts.connected = true;
    facts.netChannel = true;
    facts.loopback = true;
    facts.demoPlayback = false;
    facts.maxClients = 1;
    return facts;
}

} // namespace

int main() {
    Expect(IsLocalSinglePlayer(LocalGame()), "a local one-slot game over loopback is single-player");
    Expect(!IsLocalSinglePlayer(SessionFacts{}), "the main menu (no connection) is not single-player");

    // A remote server decides what it sends (its player count, sv_cheats, every client
    // Lua function) but not the client's own net channel, which is never loopback.
    SessionFacts remote = LocalGame();
    remote.loopback = false;
    Expect(!IsLocalSinglePlayer(remote), "a remote server that reports one player slot is not single-player");

    SessionFacts facts = LocalGame();
    facts.connected = false;
    Expect(!IsLocalSinglePlayer(facts), "a client that is not connected is not single-player");
    facts = LocalGame();
    facts.netChannel = false;
    Expect(!IsLocalSinglePlayer(facts), "a connection without a net channel is not single-player");
    facts = LocalGame();
    facts.demoPlayback = true;
    Expect(!IsLocalSinglePlayer(facts), "demo playback is not single-player");
    for (int slots : {0, 2, 8, 128, -1}) {
        facts = LocalGame();
        facts.maxClients = slots;
        Expect(!IsLocalSinglePlayer(facts), "a loopback game without exactly one player slot is not single-player");
    }

    // The gate opens only when every part holds.
    for (int mask = 0; mask < 32; ++mask) {
        const bool mainThread = (mask & 1) != 0;
        const bool closing = (mask & 2) != 0;
        const bool insecure = (mask & 4) != 0;
        const bool singlePlayer = (mask & 8) != 0;
        const bool cheats = (mask & 16) != 0;
        const bool expected = mainThread && !closing && insecure && singlePlayer && cheats;
        Expect(CanMutate(mainThread, closing, insecure, singlePlayer, cheats) == expected,
            "CanMutate requires the game thread, an open module, -insecure, single-player and sv_cheats");
    }

    // The reviewed case: the player launched with -insecure, the remote server replicates
    // sv_cheats 1 and its scripts replace game.SinglePlayer. The engine facts still say remote.
    Expect(!CanMutate(true, false, true, IsLocalSinglePlayer(remote), true),
        "a remote insecure server with sv_cheats 1 cannot open the mutation gate");
    Expect(CanMutate(true, false, true, IsLocalSinglePlayer(LocalGame()), true),
        "local single-player with -insecure and sv_cheats 1 opens the mutation gate");

    if (g_failures) return 1;
    std::cout << "Session policy tests passed\n";
    return 0;
}
