#include "detours.h"

#include "../debug_context.h"
#include "../lua_util.h"

#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/Types.h>
#include <cdll_int.h>
#include <detouring/hook.hpp>
#include <tier0/dbg.h>
#include <Windows.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>

namespace RTXDebug::Detours {

namespace {

constexpr const char* kClientCmdHookName = "client_cmd";
constexpr size_t kEventCapacity = 128;
constexpr size_t kCommandCapacity = 256;
// IVEngineClient013 starts with GetIntersectingSurfaces at slot 0.
constexpr size_t kClientCmdVtableSlot = 7;

struct Event {
    uint64_t sequence = 0;
    uint64_t tickMs = 0;
    DWORD threadId = 0;
    char command[kCommandCapacity]{};
};

// Callbacks running on this thread, so a thread never waits for itself.
thread_local uint32_t t_activeCalls = 0;

struct ActiveCall {
    explicit ActiveCall(std::atomic<uint32_t>& count) : active(count) {
        active.fetch_add(1, std::memory_order_acq_rel);
        ++t_activeCalls;
    }
    ~ActiveCall() {
        --t_activeCalls;
        active.fetch_sub(1, std::memory_order_acq_rel);
    }
    std::atomic<uint32_t>& active;
};

using ClientCmdFunction = void (__fastcall*)(void*, const char*);

Detouring::Hook g_clientCmdHook;
std::atomic<uint32_t> g_activeCalls{0};
std::atomic<bool> g_recording{false};
SRWLOCK g_eventLock = SRWLOCK_INIT;
std::array<Event, kEventCapacity> g_events{};
uint64_t g_eventSequence = 0;

void CopyCommand(const char* source, char (&destination)[kCommandCapacity]) {
    if (!source) {
        strcpy_s(destination, "<null>");
        return;
    }

    // The engine supplies the command pointer. A malformed pointer must not
    // crash the trace path before the original engine function sees it.
    __try {
        size_t i = 0;
        for (; i + 1 < kCommandCapacity; ++i) {
            const char c = source[i];
            destination[i] = c;
            if (c == '\0') return;
        }
        destination[i] = '\0';
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        strcpy_s(destination, "<unreadable>");
    }
}

void __fastcall CaptureClientCmd(void* engine, const char* command) {
    ActiveCall call(g_activeCalls);
    if (g_recording.load(std::memory_order_acquire)) {
        Event event{};
        event.tickMs = GetTickCount64();
        event.threadId = GetCurrentThreadId();
        CopyCommand(command, event.command);

        AcquireSRWLockExclusive(&g_eventLock);
        event.sequence = ++g_eventSequence;
        g_events[(event.sequence - 1) % kEventCapacity] = event;
        ReleaseSRWLockExclusive(&g_eventLock);
    }

    auto original = g_clientCmdHook.GetTrampoline<ClientCmdFunction>();
    if (original) original(engine, command);
}

bool IsExecutable(void* address) {
    MEMORY_BASIC_INFORMATION info{};
    if (!address || !VirtualQuery(address, &info, sizeof(info))
        || info.State != MEM_COMMIT || (info.Protect & PAGE_GUARD)) {
        return false;
    }
    const HMODULE engineModule = GetModuleHandleA("engine.dll");
    if (!engineModule || info.AllocationBase != engineModule) return false;
    const DWORD protection = info.Protect & 0xff;
    return protection == PAGE_EXECUTE || protection == PAGE_EXECUTE_READ
        || protection == PAGE_EXECUTE_READWRITE
        || protection == PAGE_EXECUTE_WRITECOPY;
}

bool EnsureHookCreated(std::string& error) {
    if (g_clientCmdHook.IsValid()) return true;

    static SourceSDK::FactoryLoader engineLoader("engine");
    IVEngineClient* engine = engineLoader.GetInterface<IVEngineClient>(
        VENGINE_CLIENT_INTERFACE_VERSION);
    if (!engine) {
        error = "VEngineClient015 is unavailable";
        return false;
    }

    void** vtable = *reinterpret_cast<void***>(engine);
    void* target = vtable ? vtable[kClientCmdVtableSlot] : nullptr;
    if (!IsExecutable(target)) {
        error = "ClientCmd vtable target is not executable in engine.dll";
        return false;
    }
    if (!g_clientCmdHook.Create(Detouring::Hook::Target(target),
        reinterpret_cast<void*>(&CaptureClientCmd))) {
        error = "Failed to create ClientCmd detour";
        return false;
    }
    return true;
}

void WaitForCallbacks() {
    // A thread may have reached the detour entry just as MinHook removed the
    // jump. Require a short quiet interval before releasing its trampoline.
    // Callbacks further up this thread's own stack are not waited for.
    const uint32_t own = t_activeCalls;
    for (;;) {
        if (g_activeCalls.load(std::memory_order_acquire) <= own) {
            Sleep(10);
            if (g_activeCalls.load(std::memory_order_acquire) <= own) return;
        }
        Sleep(1);
    }
}

// Stops recording, removes the jump and waits for running callbacks.
bool DisableClientCmd() {
    g_recording.store(false, std::memory_order_release);
    if (g_clientCmdHook.IsEnabled() && !g_clientCmdHook.Disable()) return false;
    WaitForCallbacks();
    return true;
}

bool HookNameIsValid(GarrysMod::Lua::ILuaBase* lua) {
    return lua->IsType(1, GarrysMod::Lua::Type::String)
        && std::strcmp(lua->GetString(1), kClientCmdHookName) == 0;
}

LUA_FUNCTION_STATIC(DetoursList) {
    if (!IsMainThread()) return PushError(LUA, "Detours.List requires the game thread");
    LUA->CreateTable();
    LUA->PushNumber(1);
    LUA->CreateTable();
    LUA->PushString(kClientCmdHookName);
    LUA->SetField(-2, "name");
    LUA->PushString("IVEngineClient::ClientCmd");
    LUA->SetField(-2, "target");
    LUA->PushBool(g_clientCmdHook.IsEnabled());
    LUA->SetField(-2, "enabled");
    AcquireSRWLockShared(&g_eventLock);
    const uint64_t captured = g_eventSequence;
    ReleaseSRWLockShared(&g_eventLock);
    LUA->PushNumber(static_cast<double>(captured));
    LUA->SetField(-2, "captured");
    LUA->SetTable(-3);
    return 1;
}

LUA_FUNCTION_STATIC(DetoursEnable) {
    if (!HookNameIsValid(LUA)) return PushError(LUA, "Unknown detour name");
    if (!CanMutate()) {
        return PushError(LUA,
            "Detours.Enable requires local single-player, sv_cheats 1, -insecure, and the game thread");
    }
    std::string error;
    if (!EnsureHookCreated(error)) return PushError(LUA, error.c_str());
    if (!g_clientCmdHook.IsEnabled() && !g_clientCmdHook.Enable()) {
        return PushError(LUA, "Failed to enable ClientCmd detour");
    }
    g_recording.store(true, std::memory_order_release);
    Msg("[RTXDebug] Enabled %s detour\n", kClientCmdHookName);
    LUA->PushBool(true);
    return 1;
}

// Disabling only undoes this module's own detour, so it needs no mutation gate.
LUA_FUNCTION_STATIC(DetoursDisable) {
    if (!HookNameIsValid(LUA)) return PushError(LUA, "Unknown detour name");
    if (!IsMainThread()) return PushError(LUA, "Detours.Disable requires the game thread");
    if (!DisableClientCmd()) return PushError(LUA, "Failed to disable ClientCmd detour");
    Msg("[RTXDebug] Disabled %s detour\n", kClientCmdHookName);
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION_STATIC(DetoursEvents) {
    if (!IsMainThread()) return PushError(LUA, "Detours.Events requires the game thread");
    size_t limit = kEventCapacity;
    if (LUA->IsType(1, GarrysMod::Lua::Type::Number)) {
        const double requested = LUA->GetNumber(1);
        if (!std::isfinite(requested) || std::trunc(requested) != requested
            || requested < 1 || requested > kEventCapacity) {
            return PushError(LUA, "Events limit must be an integer from 1 to 128");
        }
        limit = static_cast<size_t>(requested);
    }

    std::array<Event, kEventCapacity> snapshot{};
    size_t count = 0;
    AcquireSRWLockShared(&g_eventLock);
    const uint64_t available = (std::min)(g_eventSequence,
        static_cast<uint64_t>(kEventCapacity));
    count = (std::min)(limit, static_cast<size_t>(available));
    const uint64_t first = g_eventSequence - count + 1;
    for (size_t i = 0; i < count; ++i) {
        const uint64_t sequence = first + i;
        snapshot[i] = g_events[(sequence - 1) % kEventCapacity];
    }
    ReleaseSRWLockShared(&g_eventLock);

    LUA->CreateTable();
    for (size_t i = 0; i < count; ++i) {
        LUA->PushNumber(static_cast<double>(i + 1));
        LUA->CreateTable();
        LUA->PushNumber(static_cast<double>(snapshot[i].sequence));
        LUA->SetField(-2, "sequence");
        LUA->PushNumber(static_cast<double>(snapshot[i].tickMs));
        LUA->SetField(-2, "tick_ms");
        LUA->PushNumber(static_cast<double>(snapshot[i].threadId));
        LUA->SetField(-2, "thread_id");
        LUA->PushString(snapshot[i].command);
        LUA->SetField(-2, "command");
        LUA->SetTable(-3);
    }
    return 1;
}

} // namespace

void Register(GarrysMod::Lua::ILuaBase* lua) {
    if (!lua || !lua->IsType(-1, GarrysMod::Lua::Type::Table)) return;
    lua->CreateTable();
    lua->PushCFunction(DetoursList);
    lua->SetField(-2, "List");
    lua->PushCFunction(DetoursEnable);
    lua->SetField(-2, "Enable");
    lua->PushCFunction(DetoursDisable);
    lua->SetField(-2, "Disable");
    lua->PushCFunction(DetoursEvents);
    lua->SetField(-2, "Events");
    lua->SetField(-2, "Detours");
}

size_t ActiveDetours() {
    return g_clientCmdHook.IsEnabled() ? 1 : 0;
}

int DisableAll(std::vector<std::string>& failures) {
    if (!g_clientCmdHook.IsEnabled()) {
        g_recording.store(false, std::memory_order_release);
        return 0;
    }
    if (!DisableClientCmd()) {
        failures.push_back(std::string("detour ") + kClientCmdHookName + " could not be disabled");
        return 0;
    }
    Msg("[RTXDebug] Disabled %s detour\n", kClientCmdHookName);
    return 1;
}

void Shutdown() {
    if (!DisableClientCmd()) {
        Warning("[RTXDebug] Failed to disable %s detour during shutdown\n",
            kClientCmdHookName);
        WaitForCallbacks();
    }
    if (g_clientCmdHook.IsValid() && !g_clientCmdHook.Destroy()) {
        Warning("[RTXDebug] Failed to destroy %s detour during shutdown\n",
            kClientCmdHookName);
    }
    AcquireSRWLockExclusive(&g_eventLock);
    g_eventSequence = 0;
    g_events = {};
    ReleaseSRWLockExclusive(&g_eventLock);
}

} // namespace RTXDebug::Detours
