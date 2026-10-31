#include "transport.h"

#include "../debug_context.h"

#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/Lua/Interface.h>
#include <icvar.h>
#include <tier0/dbg.h>
#include <tier1/convar.h>

#include <cctype>
#include <string>

namespace {

ICvar* g_cvar = nullptr;
ConCommand* g_requestCommand = nullptr;

bool ValidId(const char* id) {
    if (!id || !*id) return false;
    size_t length = 0;
    for (const unsigned char* it = reinterpret_cast<const unsigned char*>(id); *it; ++it) {
        if (++length > 64) return false;
        if (!std::isalnum(*it) && *it != '_' && *it != '-') return false;
    }
    return true;
}

void RequestCommand(const CCommand& args) {
    if (!RTXDebug::IsMainThread()) {
        Warning("[RTXDebug] Request rejected off the game thread\n");
        return;
    }
    if (args.ArgC() != 2 || !ValidId(args.Arg(1))) {
        Warning("[RTXDebug] Usage: rtx_debug_request <alphanumeric-id>\n");
        return;
    }

    GarrysMod::Lua::ILuaBase* lua = RTXDebug::Lua();
    if (!lua) return;
    const int top = lua->Top();
    lua->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    lua->GetField(-1, "RTXDebug");
    if (!lua->IsType(-1, GarrysMod::Lua::Type::Table)) {
        Warning("[RTXDebug] Lua API is unavailable\n");
        lua->Pop(lua->Top() - top);
        return;
    }
    lua->GetField(-1, "DispatchRequest");
    if (!lua->IsType(-1, GarrysMod::Lua::Type::Function)) {
        Warning("[RTXDebug] Companion Lua addon is unavailable; cannot dispatch %s\n", args.Arg(1));
        lua->Pop(lua->Top() - top);
        return;
    }
    lua->PushString(args.Arg(1));
    if (lua->PCall(1, 0, 0) != 0) {
        const char* error = lua->GetString(-1);
        Warning("[RTXDebug] Request %s failed: %s\n", args.Arg(1), error ? error : "unknown error");
    }
    lua->Pop(lua->Top() - top);
}

} // namespace

namespace RTXDebug::Transport {

bool Initialize(GarrysMod::Lua::ILuaBase* lua) {
    if (!lua || g_requestCommand) return false;
    static SourceSDK::FactoryLoader loader("vstdlib");
    g_cvar = loader.GetInterface<ICvar>(CVAR_INTERFACE_VERSION);
    if (!g_cvar || g_cvar->FindCommandBase("rtx_debug_request")) return false;
    g_requestCommand = new ConCommand(
        "rtx_debug_request", RequestCommand,
        "Execute a request from data/rtx_debug/requests/<id>.json");
    g_cvar->RegisterConCommand(g_requestCommand);
    return true;
}

void Shutdown() {
    if (g_cvar && g_requestCommand) {
        g_cvar->UnregisterConCommand(g_requestCommand);
        delete g_requestCommand;
    }
    g_requestCommand = nullptr;
    g_cvar = nullptr;
}

} // namespace RTXDebug::Transport
