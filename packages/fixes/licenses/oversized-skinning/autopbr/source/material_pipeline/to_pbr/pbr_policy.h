// GPL-2.0. Shared by the production converter and its offline regressions.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <vector>
#include <string>
#include <cctype>

namespace MaterialPipeline { namespace ToPBR { namespace Policy {
inline bool IsImportedMaterialName(std::string name) {
    if (!name.empty() && name.front()=='!') name.erase(0,1);
    for (auto& c:name) { if(c=='\\')c='/';else if(uint8_t(c)<128)c=char(std::tolower(uint8_t(c))); }
    return name.compare(0,4,"mmd/")==0 || name.compare(0,12,"mmdhl_soft_v")==0;
}
inline bool ValidImage(uint32_t w, uint32_t h) {
    return w && h && w <= 4096 && h <= 4096 && uint64_t(w) * h <= 16 * 1024 * 1024;
}
inline float PhongRoughness(float n) {
    if (!std::isfinite(n) || n <= 0) return 0.7f;
    return std::clamp(std::pow(2.0f / (std::clamp(n, 1.0f, 512.0f) + 2.0f), 0.25f), 0.12f, 0.9f);
}
inline float ReflectionRoughness(float mask) {
    if (!std::isfinite(mask)) return 0.7f;
    return 0.22f + 0.68f * std::pow(1.0f - std::clamp(mask, 0.0f, 1.0f), 1.5f);
}
inline bool SameFile(const std::filesystem::path& a, const std::filesystem::path& b) {
    std::ifstream x(a, std::ios::binary), y(b, std::ios::binary);
    if (!x || !y) return false;
    char xb[65536], yb[65536];
    do {
        x.read(xb, sizeof(xb)); y.read(yb, sizeof(yb));
        if (x.gcount() != y.gcount() || !std::equal(xb, xb + x.gcount(), yb)) return false;
    } while (x.gcount());
    return !x.bad() && !y.bad();
}
inline bool ValidDDS(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return false;
    auto size = file.tellg(); file.seekg(0);
    uint32_t header[32]{};
    if (!file.read(reinterpret_cast<char*>(header), sizeof(header))) return false;
    if (header[0] != 0x20534444 || header[1] != 124 || header[19] != 32 ||
        header[21] != 0 || header[22] != 32 || !ValidImage(header[4], header[3])) return false;
    uint64_t expected = 128;
    uint32_t w = header[4], h = header[3], levels = 0;
    do {
        expected += uint64_t(w) * h * 4; ++levels;
        if (w == 1 && h == 1) break;
        w = (std::max)(1u, w / 2); h = (std::max)(1u, h / 2);
    } while (true);
    return header[7] == levels && uint64_t(size) == expected;
}
}}}
