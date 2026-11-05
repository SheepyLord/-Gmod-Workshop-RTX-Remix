// GPL-2.0, like the rest of the RTX fixes. R19 (the native loader's ADR 0112): what RTXWaterNative
// takes from Lua, which any server's client Lua reaches. Standard C++ only, so
// test/lua_input_test.cpp compiles it alone.
#pragma once

#include <cctype>
#include <cmath>
#include <string>
#include <vector>

namespace rtxwater_input {

// A surface polygon is flat {x1, y1, x2, y2, ...}: an even count of at least six finite numbers.
// SetSurface reads the coordinates in pairs, and a non-finite one has no extent to tile.
inline bool UsablePolygon(const std::vector<float>& poly) {
    if (poly.size() < 6 || poly.size() % 2 != 0) return false;
    for (float value : poly)
        if (!std::isfinite(value)) return false;
    return true;
}

// A segment that Win32 reads as a device whatever its folder or extension.
inline bool DeviceName(const std::string& segment) {
    std::string base;
    for (char c : segment) {
        if (c == '.') break;
        base += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    while (!base.empty() && base.back() == ' ') base.pop_back();
    if (base == "con" || base == "prn" || base == "aux" || base == "nul" || base == "conin$" || base == "conout$")
        return true;
    return base.size() == 4 && (base.compare(0, 3, "com") == 0 || base.compare(0, 3, "lpt") == 0) &&
           std::isdigit(static_cast<unsigned char>(base[3]));
}

// A texture path that SetMaterial puts below the game folder: no root, drive, UNC or "\\?\" path,
// no ':', no ".." segment, no shortened or device segment, no control character.
inline bool GameRelativePath(const std::string& path) {
    if (path.empty() || path.size() > 1024 || path.front() == '/' || path.front() == '\\') return false;
    for (char c : path) {
        const auto byte = static_cast<unsigned char>(c);
        if (byte < 0x20 || byte == 0x7F || c == ':') return false;
    }
    size_t start = 0;
    while (start <= path.size()) {
        const size_t end = path.find_first_of("/\\", start);
        const std::string segment = path.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (segment == "..") return false;
        if (!segment.empty() && segment != "." &&
            (segment.back() == '.' || segment.back() == ' ' || DeviceName(segment)))
            return false;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return true;
}

}  // namespace rtxwater_input
