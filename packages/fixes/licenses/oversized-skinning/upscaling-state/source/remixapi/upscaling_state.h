// GPL-2.0, as part of RTXFixesBinary. See ../../../../COPYING.
#pragma once
#include <cstdint>
#include <string_view>

namespace RemixAPI::UpscalingReadback {
inline constexpr const char* Key = "rtx.runtime.upscalingState";
struct State {
    bool ready = false;
    unsigned upscaler = 0;
    unsigned frameGeneration = 0;
    bool dlss = false;
    bool dlfg = false;
    bool fsrfg = false;
};

// Version 1: seven single-digit fields, exactly one space between them.
inline bool Parse(std::string_view value, State& out) {
    if (value.size() != 13 || value[0] != '1') return false;
    for (unsigned i = 1; i < 13; i += 2) {
        if (value[i] != ' ') return false;
    }
    for (unsigned i : {2u, 8u, 10u, 12u}) {
        if (value[i] != '0' && value[i] != '1') return false;
    }
    if (value[4] < '0' || value[4] > '5' || value[6] < '0' || value[6] > '2') return false;
    out = {value[2] == '1', unsigned(value[4] - '0'), unsigned(value[6] - '0'),
           value[8] == '1', value[10] == '1', value[12] == '1'};
    return true;
}

template<class Read>
bool ReadState(Read read, State& out) {
    char value[64] = {};
    uint32_t actual = 0;
    if (!read(Key, value, uint32_t(sizeof(value)), &actual)
        || actual != 14 || value[13] != '\0') return false;
    return Parse(std::string_view(value, 13), out);
}
} // namespace RemixAPI::UpscalingReadback
