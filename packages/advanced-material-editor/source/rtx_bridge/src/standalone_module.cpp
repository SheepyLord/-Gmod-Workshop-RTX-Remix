#include "advmat_rtx_bridge/lua_bindings.h"
#include "advmat_rtx_bridge/bridge.h"

#include <GarrysMod/Lua/Interface.h>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#endif

#include <filesystem>
#include <optional>

using namespace GarrysMod::Lua;

namespace {

std::optional<std::filesystem::path> DiscoverExecutablePath() {
#ifdef _WIN32
    std::wstring buffer(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                            static_cast<DWORD>(buffer.size()));
    if (length > 0 && length < buffer.size()) {
        buffer.resize(length);
        return std::filesystem::path(buffer);
    }
#endif
    return std::nullopt;
}

} // namespace

GMOD_MODULE_OPEN() {
    const auto executable = DiscoverExecutablePath();
    const auto gameRoot = executable ?
        advmat::rtx_bridge::FindGameRootFromExecutable(*executable) : std::nullopt;
    // Register an unavailable provider when discovery fails. Lua can inspect
    // capabilities and fall back safely, without trusting the process CWD.
    advmat::rtx_bridge::RegisterLua(LUA,
        gameRoot.value_or(std::filesystem::path{}));
    return 0;
}

GMOD_MODULE_CLOSE() {
    advmat::rtx_bridge::UnregisterLua(LUA);
    return 0;
}
