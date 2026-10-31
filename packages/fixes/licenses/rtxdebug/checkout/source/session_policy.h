#pragma once

namespace RTXDebug::Policy {

// What the engine client reports about its connection. The module reads every field
// natively (IVEngineClient and the client's INetChannelInfo), never from a Lua state:
// client scripts that a remote server sends can replace any Lua function, including
// game.SinglePlayer, and the server replicates sv_cheats.
struct SessionFacts {
    bool connected = false;    // IVEngineClient::IsConnected
    bool netChannel = false;   // IVEngineClient::GetNetChannelInfo returned a channel
    bool loopback = false;     // INetChannelInfo::IsLoopback: the engine's in-process loopback
    bool demoPlayback = false; // IVEngineClient::IsPlayingDemo
    int maxClients = 0;        // IVEngineClient::GetMaxClients
};

// Local single-player: the client is joined, through the in-process loopback channel, to
// the server this process runs, and that server has one player slot. A remote server
// cannot make the client's channel loopback. The player count comes from the server's
// own ServerInfo message, so it counts only together with loopback.
inline bool IsLocalSinglePlayer(const SessionFacts& facts) {
    return facts.connected && facts.netChannel && facts.loopback && !facts.demoPlayback
        && facts.maxClients == 1;
}

// The developer mutation gate (Lua.Eval, convar writes and console commands, memory,
// detours, and Remix options outside rtx.*): the game thread of an open module, the
// -insecure launch option on the process command line, local single-player as above, and
// sv_cheats 1.
inline bool CanMutate(bool mainThread, bool closing, bool insecureLaunch,
                      bool localSinglePlayer, bool cheats) {
    return mainThread && !closing && insecureLaunch && localSinglePlayer && cheats;
}

} // namespace RTXDebug::Policy
