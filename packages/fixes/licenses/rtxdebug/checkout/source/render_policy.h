#pragma once

#include <cstddef>
#include <string_view>

namespace RTXDebug::Policy {

// This boundary grants only the existing client Remix option API. Engine/gameplay,
// arbitrary Lua, memory and detour operations retain the separate mutation gate.
inline bool IsRenderingOption(std::string_view key) {
    if (key.size() <= 4 || key.size() > 256 || key.substr(0, 4) != "rtx.") return false;
    for (char c : key) {
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == '_' || c == '.')) return false;
    }
    return true;
}

inline bool CanConfigureRendering(bool mainThread, bool closing, bool clientRealm, bool remixApi) {
    return mainThread && !closing && clientRealm && remixApi;
}

inline bool CanSetConfig(bool fullMutation, bool rendering, std::string_view key) {
    return fullMutation || (rendering && IsRenderingOption(key));
}

// Convar names that RTXDebug.Engine.GetConVar may read outside local single-player. Outside a
// local game a remote server's client scripts can reach this module, so there GetConVar is limited
// to the rendering surface a multiplayer RTX session inspects; every other convar is refused, and
// ListConsole (which would enumerate them all) is refused outright. The list is deliberately short
// and matched case-insensitively by prefix. Names with unexpected characters never match.
inline bool IsRenderingConVar(std::string_view name) {
    if (name.empty() || name.size() > 128) return false;
    for (char c : name) {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == '_' || c == '.';
        if (!ok) return false;
    }
    static constexpr std::string_view kPrefixes[] = {"r_", "mat_", "rtx", "cl_draw"};
    for (std::string_view prefix : kPrefixes) {
        if (name.size() < prefix.size()) continue;
        bool match = true;
        for (std::size_t i = 0; i < prefix.size(); ++i) {
            char a = name[i];
            if (a >= 'A' && a <= 'Z') a = static_cast<char>(a - 'A' + 'a');
            if (a != prefix[i]) { match = false; break; }
        }
        if (match) return true;
    }
    return false;
}

} // namespace RTXDebug::Policy
