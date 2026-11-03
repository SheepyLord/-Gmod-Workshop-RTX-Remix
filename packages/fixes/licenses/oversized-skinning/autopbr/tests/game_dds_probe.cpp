// GPL-2.0. R13-M evidence probe: runs production game-map conversion on real PMX folders and
// reports, per map, its compact format, bytes before and after, and the BC error of every block
// against the uncompressed map. With a read-only folder of earlier outputs, it also checks that
// the earlier generators' keys find their finished families, that those families' stored base
// levels equal today's conversion, and that today's uncompressed writer reproduces their bytes.
// Usage: game_dds_probe <descriptor: UTF-8 lines "pmx path" then "base", repeated> <scratch folder> [<earlier outputs folder>]
#include "../source/material_pipeline/to_pbr/game_pbr.h"
#include "../source/material_pipeline/to_pbr/vtf.h"
#include <cassert>
#include <chrono>
#include <cmath>
#include <iostream>
using namespace MaterialPipeline::ToPBR;
namespace fs = std::filesystem;

static std::string Bytes(const fs::path& p) { std::ifstream f(p, std::ios::binary); return {std::istreambuf_iterator<char>(f), {}}; }
struct Error { double worst = 0, sum2 = 0; uint64_t count = 0; bool bounded = true; };
static void Measure(const std::vector<DDS::Level>& chain, DDS::Format format, Error& error) {
    if (format == DDS::Format::RGBA8) return;
    const auto bytes = DDS::Encode(chain, format);
    size_t at = size_t(DDS::HeaderBytes(format));
    const int channels = format == DDS::Format::BC4 ? 1 : 2;
    for (const auto& level : chain)
        for (uint32_t by = 0; by < level.height; by += 4) for (uint32_t bx = 0; bx < level.width; bx += 4)
            for (int c = 0; c < channels; ++c, at += 8) {
                int decoded[16]; DDS::DecodeBC4(bytes.data() + at, decoded);
                int lo = 255, hi = 0, worst35 = 0;
                for (uint32_t y = 0; y < 4 && by + y < level.height; ++y) for (uint32_t x = 0; x < 4 && bx + x < level.width; ++x) {
                    const int v = level.rgba[(size_t(by + y) * level.width + bx + x) * 4 + c];
                    lo = (std::min)(lo, v); hi = (std::max)(hi, v);
                    const int e35 = std::abs(35 * v - decoded[y * 4 + x]);
                    worst35 = (std::max)(worst35, e35);
                    error.sum2 += (e35 / 35.0) * (e35 / 35.0); ++error.count;
                }
                if (2 * worst35 > 5 * (hi - lo)) error.bounded = false;
                error.worst = (std::max)(error.worst, worst35 / 35.0);
            }
}
int wmain(int argc, wchar_t** argv) {
    if (argc != 3 && argc != 4) { std::cerr << "usage: game_dds_probe <descriptor> <scratch> [<earlier outputs>]\n"; return 2; }
    std::cout.setf(std::ios::unitbuf);
    const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const fs::path scratch = fs::absolute(argv[2]); fs::create_directories(scratch);
    const fs::path earlier = argc == 4 ? fs::path(argv[3]) : fs::path();
    std::ifstream input(fs::path(argv[1]), std::ios::binary);
    std::string pmx, base;
    bool allBounded = true; uint64_t families = 0, before = 0, after = 0, loadedBefore = 0, loadedAfter = 0;
    static const char* suffix[4]{"_normal", "_roughness", "_metallic", "_emission"};
    while (std::getline(input, pmx) && std::getline(input, base)) {
        if (!pmx.empty() && pmx.back() == '\r') pmx.pop_back();
        if (!base.empty() && base.back() == '\r') base.pop_back();
        try {
            const auto source = fs::u8path(pmx);
            const auto maps = GamePBR::Discover(source.parent_path(), base);
            if (!maps.recognized) { std::cout << "ABSTAIN " << base << "\n"; continue; }
            std::array<std::vector<uint8_t>, 3> inputs; std::array<bool, 3> present{};
            { size_t i = 0; for (const auto& p : {maps.normal, maps.packed, maps.emission}) { present[i] = !p.empty(); if (present[i]) inputs[i] = GamePBR::Read(p); ++i; } }
            const auto keys = GamePBR::ContentKeys(GamePBR::Read(source, 256 * 1024 * 1024), GamePBR::Read(source.parent_path() / fs::u8path(base)), inputs, present, base, maps.layout);
            std::map<std::string, std::pair<std::vector<DDS::Level>, DDS::Format>> written;
            const auto out = scratch / "compact";
            fs::create_directories(out);
            const auto started = std::chrono::steady_clock::now();
            const auto result = GamePBR::Convert(pmx, base, out.u8string(),
                [&](const std::vector<DDS::Level>& levels, const std::string& path, DDS::Format format) {
                    written[fs::u8path(path).filename().u8string()] = {levels, format};
                    DDS::Publish(fs::u8path(path), levels, format);
                    return true;
                }, [](ConvertedTexture& t) { VTF::ConvertNormalMapToOctahedral(t); });
            if (result.normal.empty() && result.roughness.empty()) { std::cout << "NOMAPS " << base << "\n"; continue; }
            const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
            ++families;
            const std::array<std::string, 4> paths{result.normal, result.roughness, result.metallic, result.emission};
            uint64_t familyBefore = 0, familyAfter = 0;
            for (size_t role = 0; role < 4; ++role) {
                if (paths[role].empty()) continue;
                const auto name = fs::u8path(paths[role]).filename().u8string();
                DDS::Info info; DDS::Probe(fs::u8path(paths[role]), info);
                const auto legacy = DDS::FileBytes(info.width, info.height, DDS::Format::RGBA8);
                Error e;
                if (written.count(name)) Measure(written[name].first, written[name].second, e);
                allBounded &= e.bounded;
                familyBefore += legacy; familyAfter += info.bytes;
                loadedBefore += legacy; loadedAfter += info.bytes;
                std::cout << "MAP " << base << " " << suffix[role] + 1 << " " << info.width << "x" << info.height << " " << DDS::Name(info.format)
                          << " bytes=" << info.bytes << " uncompressed=" << legacy;
                if (e.count) std::cout << " max=" << e.worst << " rms=" << std::sqrt(e.sum2 / double(e.count)) << " bounded=" << e.bounded;
                std::cout << "\n";
            }
            if (present[1]) { DDS::Info info; DDS::Probe(fs::u8path(paths[1]), info); familyBefore += DDS::FileBytes(info.width, info.height, DDS::Format::RGBA8); } // the AO map stored before R13
            before += familyBefore; after += familyAfter;
            std::cout << "FAMILY " << base << " layout=" << int(maps.layout) << " id=" << GamePBR::Id(keys.current) << " via=" << result.via
                      << " disk-before=" << familyBefore << " disk-after=" << familyAfter << " seconds=" << seconds << "\n";
            if (earlier.empty()) continue;
            struct Old { const char* marker; uint64_t key; };
            for (const Old& old : {Old{"r12-game-v7", keys.v7}, Old{"r12-game-v6", keys.v6}, Old{"r11-game-v5", keys.v5}}) {
                const auto marker = earlier / (GamePBR::Id(old.key) + "_complete.txt");
                std::ifstream m(marker, std::ios::binary); std::string version; int glow = -1; m >> version >> glow;
                if (!m) { std::cout << "EARLIER " << base << " " << old.marker << " " << GamePBR::Id(old.key) << " absent\n"; continue; }
                std::cout << "EARLIER " << base << " " << old.marker << " " << GamePBR::Id(old.key) << " found marker=" << version << " glow=" << glow;
                bool sameBase = true, sameBytes = true; size_t compared = 0;
                for (size_t role = 0; role < (glow ? 4u : 3u); ++role) {
                    const auto file = earlier / (GamePBR::Id(old.key) + suffix[role] + ".dds");
                    DDS::Info info;
                    if (!DDS::Probe(file, info) || info.format != DDS::Format::RGBA8) { sameBase = false; continue; }
                    const auto chain = DDS::Read(file, info);
                    const auto mine = written.find(GamePBR::Id(keys.current) + suffix[role] + ".dds");
                    if (mine != written.end()) sameBase &= mine->second.first[0].rgba == chain[0].rgba;
                    const auto reencoded = DDS::Encode(DDS::Chain(info.width, info.height, chain[0].rgba), DDS::Format::RGBA8);
                    sameBytes &= std::string(reencoded.begin(), reencoded.end()) == Bytes(file);
                    ++compared;
                }
                std::cout << " maps=" << compared << " base-level-equals-today=" << sameBase << " shipped-writer-bytes-reproduced=" << sameBytes << "\n";
            }
        } catch (const std::exception& e) { std::cout << "REJECT " << base << " " << e.what() << "\n"; }
    }
    std::cout << "TOTAL families=" << families << " disk-before=" << before << " disk-after=" << after
              << " loaded-before=" << loadedBefore << " loaded-after=" << loadedAfter << " all-blocks-bounded=" << allBounded << "\n";
    if (SUCCEEDED(com)) CoUninitialize();
    return allBounded ? 0 : 1;
}
