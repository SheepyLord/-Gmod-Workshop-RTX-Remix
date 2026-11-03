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
#include <optional>
#include "dds_codec.h"

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
// The layout of a complete generated DDS: the legacy uncompressed one, or (R13-M) DX10 BC4/BC5,
// each with a full mip chain, an exact file size and the module's image bound.
inline std::optional<DDS::Format> DDSFormat(const std::filesystem::path& path) {
    DDS::Info info;
    if (!DDS::Probe(path, info) || !ValidImage(info.width, info.height)) return {};
    return info.format;
}
inline bool ValidDDS(const std::filesystem::path& path) { return DDSFormat(path).has_value(); }
inline bool ValidDDS(const std::filesystem::path& path, DDS::Format format) {
    const auto found = DDSFormat(path);
    return found && *found == format;
}

// One clear line per refusal, naming the limit and its numbers (R13-M). The imported game PBR
// panel shows the same text.
constexpr uint64_t WorldMapBudget = 1024ull * 1024 * 1024, DiskHeadroom = 64ull * 1024 * 1024;
inline std::string ImageRefusal(uint32_t w, uint32_t h, const std::string& what = "map") {
    return "image bounds exceeded: " + what + " is " + std::to_string(w) + "x" + std::to_string(h) + " (" +
        std::to_string(uint64_t(w) * h) + " pixels); the limit is 4096x4096 and 16777216 pixels";
}
inline std::string BudgetRefusal(uint64_t used, uint64_t requested) {
    return "session budget used up: " + std::to_string(used) + " of " + std::to_string(WorldMapBudget) +
        " bytes of world maps written this session, " + std::to_string(requested) +
        " more requested; restart the game to convert more world materials (imported game maps are not limited)";
}
inline std::string DiskRefusal(std::optional<uint64_t> available, uint64_t requested, const std::string& folder) {
    const auto mib = [](uint64_t bytes) { return std::to_string(bytes / (1024 * 1024)); };
    return "free disk space limit: " + (available ? mib(*available) + " MiB free" : std::string("free space unknown")) +
        " in " + folder + ", " + mib(requested + DiskHeadroom) + " MiB needed (" + std::to_string(requested) +
        " bytes for this map plus 64 MiB kept free)";
}
}}}
