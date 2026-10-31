#include "debug_context.h"
#include "detours/detours.h"
#include "engine/engine.h"
#include "lua_bridge/lua_bridge.h"
#include "lua_util.h"
#include "render_policy.h"
#include "memory/memory_debug.h"
#include "remix/remix_debug.h"
#include "transport/transport.h"

#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/Lua/Interface.h>
#include <icvar.h>
#include <tier0/dbg.h>
#include <tier0/icommandline.h>
#include <tier1/convar.h>
#include <Windows.h>

#include <exception>
#include <string>
#include <vector>

namespace {

constexpr const char* kVersion = "0.2.0";
constexpr const char* kRemixApiVersion = "0.1000.1";

GarrysMod::Lua::ILuaBase* g_lua = nullptr;
DWORD g_mainThread = 0;
bool g_open = false;
bool g_closing = false;
ICvar* g_cvar = nullptr;

ICvar* ResolveCvar() {
    if (g_cvar) return g_cvar;
    static SourceSDK::FactoryLoader loader("vstdlib");
    g_cvar = loader.GetInterface<ICvar>(CVAR_INTERFACE_VERSION);
    return g_cvar;
}

// RTXFixesBinary registers RemixConfig; the Remix functions forward to it.
bool RemixLuaApiPresent(GarrysMod::Lua::ILuaBase* lua) {
    lua->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    lua->GetField(-1, "RemixConfig");
    const bool present = lua->IsType(-1, GarrysMod::Lua::Type::Table);
    lua->Pop(2);
    return present;
}

LUA_FUNCTION_STATIC(RTXDebug_Status) {
    LUA->CreateTable();
    RTXDebug::SetString(LUA, "version", kVersion);
    RTXDebug::SetString(LUA, "remix_api", kRemixApiVersion);
    RTXDebug::SetBool(LUA, "main_thread", RTXDebug::IsMainThread());
    RTXDebug::SetBool(LUA, "single_player", RTXDebug::IsSinglePlayer());
    RTXDebug::SetBool(LUA, "insecure_launch", RTXDebug::IsInsecureLaunch());
    RTXDebug::SetBool(LUA, "sv_cheats", RTXDebug::CheatsEnabled());
    RTXDebug::SetBool(LUA, "can_mutate", RTXDebug::CanMutate());
    RTXDebug::SetBool(LUA, "can_configure_rendering", RTXDebug::CanConfigureRendering());
    RTXDebug::SetNumber(LUA, "process_id", GetCurrentProcessId());
    RTXDebug::SetBool(LUA, "remix_lua_api", RemixLuaApiPresent(LUA));
    // Changes this module will undo on RestoreAll or unload.
    LUA->CreateTable();
    RTXDebug::SetNumber(LUA, "convars", static_cast<double>(RTXDebug::Engine::ActiveOverrides()));
    RTXDebug::SetNumber(LUA, "remix", static_cast<double>(RTXDebug::Remix::ActiveOverrides()));
    RTXDebug::SetNumber(LUA, "memory", static_cast<double>(RTXDebug::Memory::ActiveMutations()));
    RTXDebug::SetNumber(LUA, "detours", static_cast<double>(RTXDebug::Detours::ActiveDetours()));
    LUA->SetField(-2, "active");
    return 1;
}

// Undoes every change this module owns and keeps it loaded. The companion
// addon calls this from the ShutDown hook, while RTXFixesBinary is still open.
LUA_FUNCTION_STATIC(RTXDebug_RestoreAll) {
    if (!RTXDebug::IsMainThread()) return RTXDebug::PushError(LUA, "RestoreAll requires the game thread");
    std::vector<std::string> failures;
    const int detours = RTXDebug::Detours::DisableAll(failures);
    const int remix = RTXDebug::Remix::RestoreAll(LUA, failures);
    const int convars = RTXDebug::Engine::RestoreConVars(failures);
    const int memory = RTXDebug::Memory::RestoreAll(failures);
    LUA->CreateTable();
    RTXDebug::SetNumber(LUA, "detours", detours);
    RTXDebug::SetNumber(LUA, "remix", remix);
    RTXDebug::SetNumber(LUA, "convars", convars);
    RTXDebug::SetNumber(LUA, "memory", memory);
    LUA->CreateTable();
    for (size_t i = 0; i < failures.size(); ++i) {
        Warning("[RTXDebug] RestoreAll: %s\n", failures[i].c_str());
        LUA->PushString(failures[i].c_str());
        RTXDebug::SetArrayValue(LUA, static_cast<int>(i + 1));
    }
    LUA->SetField(-2, "failures");
    RTXDebug::SetBool(LUA, "complete", failures.empty());
    return 1;
}

void RemoveLuaGlobal(GarrysMod::Lua::ILuaBase* lua) {
    if (!lua) return;
    lua->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    lua->PushNil();
    lua->SetField(-2, "RTXDebug");
    lua->Pop();
}

void Shutdown(GarrysMod::Lua::ILuaBase* lua) {
    if (g_closing) return;
    g_closing = true;
    RTXDebug::Transport::Shutdown();
    RTXDebug::Detours::Shutdown();
    RTXDebug::Remix::Shutdown(lua);
    RTXDebug::Engine::Shutdown();
    RTXDebug::LuaBridge::Shutdown();
    RTXDebug::Memory::Shutdown();
    RemoveLuaGlobal(lua);
    g_lua = nullptr;
    g_cvar = nullptr;
    g_mainThread = 0;
    g_open = false;
}

} // namespace

namespace RTXDebug {

bool IsMainThread() {
    return g_mainThread != 0 && GetCurrentThreadId() == g_mainThread;
}

GarrysMod::Lua::ILuaBase* Lua() {
    return g_lua;
}

bool IsSinglePlayer() {
    if (!IsMainThread() || !g_lua) return false;
    const int top = g_lua->Top();
    g_lua->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    g_lua->GetField(-1, "game");
    if (!g_lua->IsType(-1, GarrysMod::Lua::Type::Table)) {
        g_lua->Pop(g_lua->Top() - top);
        return false;
    }
    g_lua->GetField(-1, "SinglePlayer");
    if (!g_lua->IsType(-1, GarrysMod::Lua::Type::Function)) {
        g_lua->Pop(g_lua->Top() - top);
        return false;
    }
    const bool called = g_lua->PCall(0, 1, 0) == 0;
    const bool result = called && g_lua->GetBool(-1);
    g_lua->Pop(g_lua->Top() - top);
    return result;
}

bool IsInsecureLaunch() {
    const ICommandLine* commandLine = CommandLine();
    return commandLine && commandLine->FindParm("-insecure") != 0;
}

bool CheatsEnabled() {
    if (!IsMainThread()) return false;
    ICvar* cv = ResolveCvar();
    ConVar* cheats = cv ? cv->FindVar("sv_cheats") : nullptr;
    return cheats && cheats->GetBool();
}

bool CanMutate() {
    return !g_closing && IsMainThread() && IsInsecureLaunch() && IsSinglePlayer() && CheatsEnabled();
}

bool CanConfigureRendering() {
    if (!IsMainThread() || !g_lua) return false;
    const int top = g_lua->Top();
    const auto flag = [&](const char* name) {
        g_lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, name);
        const bool value = g_lua->IsType(-1, GarrysMod::Lua::Type::Bool) && g_lua->GetBool(-1);
        g_lua->Pop();
        return value;
    };
    const bool client = flag("CLIENT_DLL") && !flag("SERVER") && !flag("MENU_DLL");
    g_lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, "RemixConfig");
    bool api = false;
    if (g_lua->IsType(-1, GarrysMod::Lua::Type::Table)) {
        g_lua->GetField(-1, "SetConfigVariable");
        api = g_lua->IsType(-1, GarrysMod::Lua::Type::Function);
        g_lua->Pop();
    }
    g_lua->Pop();
    g_lua->Pop(g_lua->Top() - top);
    return Policy::CanConfigureRendering(true, g_closing, client, api);
}

} // namespace RTXDebug

GMOD_MODULE_OPEN() {
    if (g_open) return 0;
    g_lua = LUA;
    g_mainThread = GetCurrentThreadId();
    g_closing = false;
    const int top = LUA->Top();
    LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    LUA->GetField(-1, "RTXDebug");
    const bool globalExists = !LUA->IsType(-1, GarrysMod::Lua::Type::Nil);
    LUA->Pop(2);
    if (globalExists) {
        g_lua = nullptr;
        g_mainThread = 0;
        LUA->ThrowError("[RTXDebug] RTXDebug global already exists");
        return 0;
    }

    // Lua errors are raised only after the try block, so they never unwind
    // through a C++ handler.
    const char* failure = nullptr;
    try {
        LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
        LUA->CreateTable();
        RTXDebug::AddFunction(LUA, "Status", RTXDebug_Status);
        RTXDebug::AddFunction(LUA, "RestoreAll", RTXDebug_RestoreAll);
        RTXDebug::Engine::Register(LUA);
        RTXDebug::LuaBridge::Register(LUA);
        RTXDebug::Memory::RegisterLua(LUA, RTXDebug::CanMutate);
        if (RTXDebug::Remix::Register(LUA)) {
            RTXDebug::Detours::Register(LUA);
            LUA->SetField(-2, "RTXDebug");
        } else {
            failure = "[RTXDebug] Failed to register Remix bindings";
        }
        while (LUA->Top() > top) LUA->Pop();
        if (!failure && !RTXDebug::Transport::Initialize(LUA))
            failure = "[RTXDebug] Failed to register rtx_debug_request";
    } catch (const std::exception& error) {
        while (LUA->Top() > top) LUA->Pop();
        Warning("[RTXDebug] Module open failed: %s\n", error.what());
        failure = "[RTXDebug] Module open failed";
    } catch (...) {
        while (LUA->Top() > top) LUA->Pop();
        Warning("[RTXDebug] Module open failed with an unknown exception\n");
        failure = "[RTXDebug] Module open failed";
    }
    if (failure) {
        Shutdown(LUA);
        LUA->ThrowError(failure);
        return 0;
    }
    g_open = true;
    Msg("[RTXDebug] Module loaded (Remix API %s)\n", kRemixApiVersion);
    return 0;
}

GMOD_MODULE_CLOSE() {
    Shutdown(LUA);
    Msg("[RTXDebug] Module unloaded\n");
    return 0;
}
