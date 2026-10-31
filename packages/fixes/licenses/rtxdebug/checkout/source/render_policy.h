#pragma once

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

} // namespace RTXDebug::Policy
