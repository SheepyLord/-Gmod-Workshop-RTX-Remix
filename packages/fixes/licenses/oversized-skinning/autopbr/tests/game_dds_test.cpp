// GPL-2.0. SDK-free regressions for R13-M: compact game maps (BC4/BC5), their validation and
// publication, refusals, recipe keys, reuse across versions and the legacy-map migration.
// Usage: game_dds_test <fresh fixture from make_game_pbr_fixtures.py> [bulk | bump-prepare | bump-check]
#include "game_pbr_types.h"
#include "../source/material_pipeline/to_pbr/game_pbr.h"
#include "../source/material_pipeline/to_pbr/game_registry.h"
#include "../source/material_pipeline/to_pbr/game_overrides.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <random>
using namespace MaterialPipeline::ToPBR;
namespace fs = std::filesystem;

static std::string Bytes(const fs::path& p) { std::ifstream f(p, std::ios::binary); return {std::istreambuf_iterator<char>(f), {}}; }
static std::vector<uint8_t> Data(const fs::path& p) { const auto s = Bytes(p); return {s.begin(), s.end()}; }
static void Put(const fs::path& p, const std::string& s) { std::ofstream f(p, std::ios::binary | std::ios::trunc); f << s; }
static uint64_t Fnv(const std::vector<uint8_t>& b, uint64_t seed = 14695981039346656037ull) {
    for (auto x : b) { seed ^= x; seed *= 1099511628211ull; }
    return seed;
}
static bool Throws(const std::function<void()>& f, std::string* what = nullptr) {
    try { f(); } catch (const std::exception& e) { if (what) *what = e.what(); return true; }
    return false;
}

// The header TextureProcessor::WriteDDSHeader wrote before R13, from its own constants.
static std::vector<uint8_t> ShippedHeader(uint32_t w, uint32_t h, uint32_t levels) {
    uint32_t hd[32]{};
    hd[0] = 0x20534444; hd[1] = 124; hd[2] = 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000 | 0x20000; hd[3] = h; hd[4] = w;
    hd[5] = w * h * 4; hd[6] = 1; hd[7] = levels; hd[19] = 32; hd[20] = 0x40 | 0x1; hd[22] = 32;
    hd[23] = 0x00FF0000; hd[24] = 0x0000FF00; hd[25] = 0x000000FF; hd[26] = 0xFF000000; hd[27] = 0x1000 | 0x400000 | 0x8;
    std::vector<uint8_t> out(128);
    memcpy(out.data(), hd, 128);
    return out;
}
// The shipped writer's mip loop, transcribed: BGRA, 2x2 box, integer floor of the mean.
static std::vector<uint8_t> ShippedFile(uint32_t width, uint32_t height, const std::vector<uint8_t>& rgba) {
    uint32_t mipCount = 1;
    for (uint32_t size = (std::max)(width, height); size > 1; size /= 2) ++mipCount;
    auto out = ShippedHeader(width, height, mipCount);
    std::vector<uint8_t> current(rgba.size());
    for (size_t i = 0; i < rgba.size(); i += 4) { current[i] = rgba[i + 2]; current[i + 1] = rgba[i + 1]; current[i + 2] = rgba[i]; current[i + 3] = rgba[i + 3]; }
    out.insert(out.end(), current.begin(), current.end());
    uint32_t mipWidth = width, mipHeight = height;
    for (uint32_t mip = 1; mip < mipCount; mip++) {
        const uint32_t newWidth = (std::max)(1u, mipWidth / 2), newHeight = (std::max)(1u, mipHeight / 2);
        std::vector<uint8_t> next(size_t(newWidth) * newHeight * 4);
        for (uint32_t y = 0; y < newHeight; y++) for (uint32_t x = 0; x < newWidth; x++) {
            uint32_t r = 0, g = 0, b = 0, a = 0; int count = 0;
            for (uint32_t dy = 0; dy < 2 && (y * 2 + dy) < mipHeight; dy++)
                for (uint32_t dx = 0; dx < 2 && (x * 2 + dx) < mipWidth; dx++) {
                    const size_t at = (size_t(y * 2 + dy) * mipWidth + (x * 2 + dx)) * 4;
                    b += current[at]; g += current[at + 1]; r += current[at + 2]; a += current[at + 3]; count++;
                }
            const size_t at = (size_t(y) * newWidth + x) * 4;
            next[at] = uint8_t(b / count); next[at + 1] = uint8_t(g / count); next[at + 2] = uint8_t(r / count); next[at + 3] = uint8_t(a / count);
        }
        out.insert(out.end(), next.begin(), next.end());
        current = std::move(next); mipWidth = newWidth; mipHeight = newHeight;
    }
    return out;
}
// The shipped content-key formulas, transcribed: 6e33b90 (v5), e223e4e (v6), 026708a (v7).
static uint64_t ShippedKey(unsigned version, const fs::path& pmx, const std::string& base, const GamePBR::Maps& maps) {
    uint64_t key = Fnv(Data(pmx.parent_path() / fs::u8path(base)), Fnv(Data(pmx)));
    unsigned role = 0;
    for (const auto& path : {maps.normal, maps.packed, maps.emission}) {
        if (version != 5) key = Fnv(std::vector<uint8_t>{uint8_t(++role), uint8_t(!path.empty())}, key);
        if (!path.empty()) key = Fnv(Data(path), key);
    }
    key = Fnv(std::vector<uint8_t>(base.begin(), base.end()), key);
    if (version == 5) return key ^ 0x52313147414d4505ull;
    return key ^ (version == 6 ? 0x52313247414d4506ull : 0x52313247414d4507ull) ^ uint64_t(maps.layout);
}
static void PNG(const fs::path& path, uint32_t w, uint32_t h, uint8_t value) {
    GamePBR::ComPtr<IWICImagingFactory> factory; GamePBR::ComPtr<IWICStream> stream;
    GamePBR::ComPtr<IWICBitmapEncoder> encoder; GamePBR::ComPtr<IWICBitmapFrameEncode> frame;
    auto check = [](HRESULT hr) { assert(SUCCEEDED(hr)); (void)hr; };
    check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)));
    check(factory->CreateStream(&stream)); check(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE));
    check(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)); check(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache));
    check(encoder->CreateNewFrame(&frame, nullptr)); check(frame->Initialize(nullptr)); check(frame->SetSize(w, h));
    auto format = GUID_WICPixelFormat32bppBGRA; check(frame->SetPixelFormat(&format));
    std::vector<uint8_t> pixels(size_t(w) * h * 4, value);
    check(frame->WritePixels(h, w * 4, UINT(pixels.size()), pixels.data()));
    check(frame->Commit()); check(encoder->Commit());
}

// Every texel's exact decoded error (GPU precision) against its source, per block and overall.
struct Error { double worst = 0, worstBase = 0, sum2 = 0; uint64_t count = 0, blocks = 0; bool bounded = true; };
static void Measure(const std::vector<DDS::Level>& chain, DDS::Format format, Error& error) {
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
                // Proven bound: endpoints at the extremes put every texel within (max-min)/14.
                if (2 * worst35 > 5 * (hi - lo)) error.bounded = false;
                if (hi - lo <= 0 && worst35) error.bounded = false;
                error.worst = (std::max)(error.worst, worst35 / 35.0); ++error.blocks;
                if (&level == &chain[0]) error.worstBase = (std::max)(error.worstBase, worst35 / 35.0);
            }
    assert(at == bytes.size());
}
static std::vector<DDS::Level> Pattern(uint32_t w, uint32_t h, const std::function<uint8_t(uint32_t, uint32_t, int)>& f) {
    std::vector<uint8_t> rgba(size_t(w) * h * 4);
    for (uint32_t y = 0; y < h; ++y) for (uint32_t x = 0; x < w; ++x) for (int c = 0; c < 4; ++c) rgba[(size_t(y) * w + x) * 4 + c] = f(x, y, c);
    return DDS::Chain(w, h, rgba);
}

static void Codec(const fs::path& root) {
    // Uncompressed files are byte-identical to the shipped writer: header, BGRA order and mips.
    for (auto size : {std::pair<uint32_t, uint32_t>{1, 1}, {13, 7}, {64, 64}, {2048, 1024}, {1500, 1500}}) {
        std::mt19937 random(size.first * 31 + size.second);
        std::vector<uint8_t> rgba(size_t(size.first) * size.second * 4);
        for (auto& v : rgba) v = uint8_t(random());
        const auto shipped = ShippedFile(size.first, size.second, rgba);
        const auto ours = DDS::Encode(DDS::Chain(size.first, size.second, rgba), DDS::Format::RGBA8);
        assert(ours == shipped && ours.size() == DDS::FileBytes(size.first, size.second, DDS::Format::RGBA8));
        Put(root / "shipped.dds", std::string(shipped.begin(), shipped.end()));
        DDS::Info info;
        const auto back = DDS::Read(root / "shipped.dds", info);
        assert(info.format == DDS::Format::RGBA8 && back[0].rgba == rgba && Policy::ValidDDS(root / "shipped.dds", DDS::Format::RGBA8));
    }
    const uint64_t rgba8 = DDS::FileBytes(2048, 2048, DDS::Format::RGBA8), bc4 = DDS::FileBytes(2048, 2048, DDS::Format::BC4),
                   bc5 = DDS::FileBytes(2048, 2048, DDS::Format::BC5);
    assert(rgba8 == 22369748 && bc4 == 2796364 && bc5 == 5592580);
    std::cout << "SIZE 2048x2048 full chain: RGBA8=" << rgba8 << " BC4=" << bc4 << " BC5=" << bc5 << "\n";
    std::cout << "SIZE family before (normal+roughness+metallic+ao, RGBA8)=" << 4 * rgba8 << " after (BC5+2xBC4)=" << bc5 + 2 * bc4
              << " emission (RGBA8, unchanged)=" << rgba8 << " loaded by Remix before=" << 3 * rgba8 << " after=" << bc5 + 2 * bc4 << "\n";
    // Layout validation: complete DX10 BC4/BC5 accepted, anything else this module never writes refused.
    const auto chain = Pattern(16, 8, [](uint32_t x, uint32_t y, int c) { return uint8_t(c == 0 ? x * 16 : c == 1 ? y * 32 : 255); });
    for (auto format : {DDS::Format::BC4, DDS::Format::BC5}) {
        const auto bytes = DDS::Encode(chain, format);
        const auto good = std::string(bytes.begin(), bytes.end());
        const auto p = root / "layout.dds";
        Put(p, good); assert(Policy::ValidDDS(p, format) && !Policy::ValidDDS(p, DDS::Format::RGBA8));
        Put(p, good + "x"); assert(!Policy::ValidDDS(p));
        Put(p, good.substr(0, good.size() - 1)); assert(!Policy::ValidDDS(p));
        auto patch = [&](size_t offset, uint32_t value) { auto s = good; memcpy(s.data() + offset, &value, 4); Put(p, s); return Policy::ValidDDS(p); };
        assert(!patch(28, 3));          // wrong mip count
        assert(!patch(112, 0x200));     // cube map caps
        assert(!patch(128, 71));        // BC1: not a layout this module writes
        assert(!patch(140, 2));         // array of two
        assert(!patch(132, 4));         // 3D texture
        assert(!patch(80, 0));          // FourCC flag missing
        assert(patch(128, uint32_t(format)));
    }
    {
        auto s = DDS::Encode(Pattern(8, 8, [](uint32_t, uint32_t, int) { return uint8_t(7); }), DDS::Format::BC4);
        const uint32_t six = 6; memcpy(s.data() + 12, &six, 4); memcpy(s.data() + 16, &six, 4);
        Put(root / "unaligned.dds", std::string(s.begin(), s.end()));
        assert(!Policy::ValidDDS(root / "unaligned.dds"));
        assert(Throws([] { DDS::Encode(Pattern(6, 6, [](uint32_t, uint32_t, int) { return uint8_t(1); }), DDS::Format::BC5); }));
    }
    // Every two-valued block is exact, in both modes and every arrangement tested.
    for (unsigned a = 0; a < 256; ++a) for (unsigned b = 0; b < 256; ++b) for (unsigned pattern = 0; pattern < 3; ++pattern) {
        uint8_t v[16];
        for (unsigned i = 0; i < 16; ++i) v[i] = uint8_t((pattern == 0 ? i % 2 : pattern == 1 ? i < 3 : (i * 7) % 5 == 0) ? a : b);
        int decoded[16]; const auto block = DDS::EncodeBC4(v); DDS::DecodeBC4(block.data(), decoded);
        for (unsigned i = 0; i < 16; ++i) assert(decoded[i] == 35 * v[i]);
    }
    // Real quantized roughness blocks (field maps): a few evenly spaced levels lie exactly on a
    // palette whose endpoint extends past the data, in eight- or six-value mode.
    for (const std::array<uint8_t, 16>& v : {
             std::array<uint8_t, 16>{170, 170, 118, 65, 118, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 118},
             std::array<uint8_t, 16>{66, 51, 36, 36, 81, 66, 51, 36, 81, 66, 51, 36, 81, 81, 66, 51},
             std::array<uint8_t, 16>{177, 211, 211, 211, 143, 143, 143, 177, 109, 109, 143, 143, 109, 109, 109, 109},
             std::array<uint8_t, 16>{40, 40, 40, 40, 40, 40, 40, 81, 40, 40, 81, 121, 40, 81, 121, 121}}) {
        int decoded[16]; const auto block = DDS::EncodeBC4(v.data()); DDS::DecodeBC4(block.data(), decoded);
        int worst = 0; for (unsigned i = 0; i < 16; ++i) worst = (std::max)(worst, std::abs(decoded[i] - 35 * v[i]));
        assert(worst <= 35); // within one level (exact where the levels are exactly evenly spaced)
    }
    // Generated gradients, edges and noise: the per-block bound holds; report the error.
    struct Case { const char* name; std::function<uint8_t(uint32_t, uint32_t, int)> f; };
    std::mt19937 noise(7);
    const std::vector<Case> cases{
        {"horizontal-gradient", [](uint32_t x, uint32_t, int) { return uint8_t(x * 255 / 255); }},
        {"diagonal-gradient", [](uint32_t x, uint32_t y, int c) { return uint8_t(c ? (x * 3 + y) / 4 : (x + y) / 2); }},
        {"hard-edges", [](uint32_t x, uint32_t y, int c) { return uint8_t(((x / 3 + y / 5 + c) % 2) ? 255 : 0); }},
        {"edge-plus-gradient", [](uint32_t x, uint32_t y, int) { return uint8_t(x < 128 ? y : 255 - (x + y) % 64); }},
        {"anti-aliased-mask", [](uint32_t x, uint32_t y, int) { const int d = int(x) - int(y); return uint8_t(d < -2 ? 0 : d > 2 ? 255 : 128 + 60 * d); }},
        {"noise", [&](uint32_t, uint32_t, int) { return uint8_t(noise()); }},
    };
    for (const auto& c : cases) for (auto format : {DDS::Format::BC4, DDS::Format::BC5}) {
        Error e; Measure(Pattern(256, 256, c.f), format, e);
        assert(e.bounded);
        std::cout << "ERROR " << c.name << " " << DDS::Name(format) << " max=" << e.worst << " base-level max=" << e.worstBase
                  << " rms=" << std::sqrt(e.sum2 / double(e.count)) << " texels=" << e.count << " blocks=" << e.blocks << "\n";
        // A smooth gradient (a few levels per 4x4 block) is reproduced within one level at full size.
        if (std::string(c.name).find("gradient") != std::string::npos && std::string(c.name) != "edge-plus-gradient") assert(e.worstBase <= 1.0);
    }
    std::cout << "PASS codec: shipped uncompressed bytes, DX10 BC4/BC5 layouts and refusals, exact two-value blocks, (max-min)/14 bound\n";
}

static void Publication(const fs::path& root, bool bulk) {
    const auto folder = root / "publish"; fs::create_directories(folder);
    const auto chain = Pattern(64, 32, [](uint32_t x, uint32_t y, int c) { return uint8_t(c == 3 ? 255 : (x * 4 + y * c) % 256); });
    const auto target = folder / "map_bc5.dds";
    DDS::Publish(target, chain, DDS::Format::BC5);
    assert(Policy::ValidDDS(target, DDS::Format::BC5) && fs::file_size(target) == DDS::FileBytes(64, 32, DDS::Format::BC5));
    assert(!fs::exists(target.wstring() + L".tmp"));
    // An invalid existing file is kept aside byte for byte, never overwritten.
    Put(target, "damaged generated map");
    DDS::Publish(target, chain, DDS::Format::BC5);
    bool kept = false;
    for (const auto& f : fs::directory_iterator(folder)) if (f.path().filename().u8string().find("map_bc5.dds.rejected-") == 0 && Bytes(f.path()) == "damaged generated map") kept = true;
    assert(kept && Policy::ValidDDS(target, DDS::Format::BC5));
    // Refusals: one line naming the limit and its numbers. Nothing is written.
    std::string what;
    const auto expected = DDS::FileBytes(64, 32, DDS::Format::BC4);
    assert(Throws([&] { DDS::Publish(folder / "full.dds", chain, DDS::Format::BC4, [&](const fs::path&) { return std::optional<uint64_t>(expected + Policy::DiskHeadroom - 1); }); }, &what));
    assert(what.find("free disk space limit: 64 MiB free in ") == 0 && what.find("(" + std::to_string(expected) + " bytes for this map plus 64 MiB kept free)") != std::string::npos);
    assert(!fs::exists(folder / "full.dds") && !fs::exists(folder / "full.dds.tmp"));
    std::cout << "REFUSAL " << what << "\n";
    assert(Throws([&] { DDS::Publish(folder / "unknown.dds", chain, DDS::Format::BC4, [](const fs::path&) { return std::optional<uint64_t>(); }); }, &what));
    assert(what.find("free disk space limit: free space unknown in ") == 0);
    std::vector<DDS::Level> wide{{4097, 1, std::vector<uint8_t>(4097 * 4, 1)}};
    assert(Throws([&] { DDS::Publish(folder / "wide.dds", wide, DDS::Format::RGBA8); }, &what));
    assert(what == "image bounds exceeded: wide.dds is 4097x1 (4097 pixels); the limit is 4096x4096 and 16777216 pixels");
    std::cout << "REFUSAL " << what << "\n";
    PNG(root / "wide.png", 4097, 1, 9);
    assert(Throws([&] { GamePBR::Decode(root / "wide.png"); }, &what));
    assert(what == "image bounds exceeded: wide.png is 4097x1 (4097 pixels); the limit is 4096x4096 and 16777216 pixels");
    what = Policy::BudgetRefusal(Policy::WorldMapBudget, 22369748);
    assert(what == "session budget used up: 1073741824 of 1073741824 bytes of world maps written this session, 22369748 more requested; restart the game to convert more world materials (imported game maps are not limited)");
    std::cout << "REFUSAL " << what << "\n";
    // Imported game maps carry no session budget: more than 1 GiB in one session publishes.
    if (bulk) {
        const auto big = DDS::Chain(2048, 2048, std::vector<uint8_t>(size_t(2048) * 2048 * 4, 127));
        uint64_t total = 0;
        for (unsigned i = 0; i < 49; ++i) {
            const auto p = folder / ("bulk_" + std::to_string(i % 2) + ".dds");
            if (fs::exists(p)) fs::remove(p);
            DDS::Publish(p, big, DDS::Format::RGBA8);
            total += fs::file_size(p);
        }
        assert(total > Policy::WorldMapBudget);
        std::cout << "PASS game maps past 1 GiB: " << total << " bytes in 49 publications, none refused\n";
    }
    std::cout << "PASS publication: atomic, invalid files kept aside, disk/bounds/budget refusal lines\n";
}

struct Run { unsigned oct = 0, writes = 0; };
static Run run;
static void Oct(ConvertedTexture& t) {
    ++run.oct; // Deterministic stand-in for the octahedral encoder: the converted bytes are compared, not its math.
    for (size_t i = 0; i < t.pixelData.size(); i += 4) { t.pixelData[i + 2] = 0; t.pixelData[i + 3] = 255; }
}
static std::map<std::string, DDS::Level> captured;
static bool Write(const std::vector<DDS::Level>& levels, const std::string& path, DDS::Format format) {
    ++run.writes; captured[fs::u8path(path).filename().u8string()] = levels[0];
    DDS::Publish(fs::u8path(path), levels, format);
    return true;
}
static const char* Suffix(size_t role) { static const char* s[4]{"_normal", "_roughness", "_metallic", "_emission"}; return s[role]; }
// A finished family as an earlier generator stored it: uncompressed files and its marker line.
static std::array<fs::path, 4> Legacy(const fs::path& out, uint64_t key, const char* marker, const std::array<DDS::Level, 4>& base, bool glow = true) {
    std::array<fs::path, 4> paths;
    for (size_t role = 0; role < (glow ? 4u : 3u); ++role) {
        paths[role] = out / (GamePBR::Id(key) + Suffix(role) + ".dds");
        const auto bytes = ShippedFile(base[role].width, base[role].height, base[role].rgba);
        Put(paths[role], std::string(bytes.begin(), bytes.end()));
    }
    Put(out / (GamePBR::Id(key) + "_ao.dds"), Bytes(paths[1]));
    Put(out / (GamePBR::Id(key) + "_complete.txt"), std::string(marker) + " " + (glow ? "1" : "0") + "\n");
    return paths;
}

static void Conversion(const fs::path& root) {
    const auto pmx = root / "test.pmx";
    const std::string base = "tex/T_actor_test_cloth_D.png";
    const auto maps = GamePBR::Discover(root, base);
    assert(maps.recognized && maps.layout == GamePBR::Maps::Endfield && !maps.emission.empty());
    // Production keys reproduce the shipped formulas for these inputs.
    std::array<std::vector<uint8_t>, 3> inputs{Data(maps.normal), Data(maps.packed), Data(maps.emission)};
    const auto keys = GamePBR::ContentKeys(Data(pmx), Data(root / base), inputs, {true, true, true}, base, maps.layout);
    assert(keys.v7 == ShippedKey(7, pmx, base, maps) && keys.v6 == ShippedKey(6, pmx, base, maps) && keys.v5 == ShippedKey(5, pmx, base, maps));
    assert(keys.current != keys.v7 && keys.current != keys.v6 && keys.current != keys.v5);
    const auto fresh = root / "fresh"; fs::create_directories(fresh);
    auto convert = [&](const fs::path& out, const GamePBR::Maps* selected = nullptr) {
        return GamePBR::Convert(pmx.u8string(), base, out.u8string(), Write, Oct, nullptr, selected);
    };
    run = {};
    auto first = convert(fresh);
    assert(first.via == "converted" && first.written == 4 && run.oct == 1 && run.writes == 4);
    assert(Policy::ValidDDS(fs::u8path(first.normal), DDS::Format::BC5) && Policy::ValidDDS(fs::u8path(first.roughness), DDS::Format::BC4) &&
           Policy::ValidDDS(fs::u8path(first.metallic), DDS::Format::BC4) && Policy::ValidDDS(fs::u8path(first.emission), DDS::Format::RGBA8));
    for (const auto& f : fs::directory_iterator(fresh)) assert(f.path().filename().u8string().find("_ao") == std::string::npos);
    const auto marker = fresh / (GamePBR::Id(keys.current) + "_complete.txt");
    assert(Bytes(marker) == GamePBR::Recipe() + " 1\norigin converted\n");
    std::cout << "RECIPE " << GamePBR::Recipe() << "\n";
    std::array<DDS::Level, 4> base4;
    for (size_t role = 0; role < 4; ++role) base4[role] = captured.at(GamePBR::Id(keys.current) + Suffix(role) + ".dds");
    std::array<std::string, 4> freshBytes{Bytes(fs::u8path(first.normal)), Bytes(fs::u8path(first.roughness)), Bytes(fs::u8path(first.metallic)), Bytes(fs::u8path(first.emission))};
    // Cached: nothing decoded, converted or written.
    run = {};
    auto again = convert(fresh);
    assert(again.via == "cached" && again.written == 0 && run.oct == 0 && run.writes == 0 && again.normal == first.normal);
    // A family stopped halfway completes on its next pass, keeping the maps it already stored.
    const auto normalTime = fs::last_write_time(fs::u8path(first.normal));
    fs::remove(fs::u8path(first.roughness)); fs::remove(fs::u8path(first.metallic)); fs::remove(marker);
    run = {};
    auto resumed = convert(fresh);
    assert(resumed.via == "converted" && resumed.written == 2 && run.writes == 2 && fs::last_write_time(fs::u8path(first.normal)) == normalTime);
    assert(Bytes(fs::u8path(first.roughness)) == freshBytes[1] && Bytes(marker) == GamePBR::Recipe() + " 1\norigin converted\n");
    // A forced refusal mid-family: the exact refusal line propagates (log and panel), the maps
    // written before it stay, and the next pass completes the rest.
    fs::remove(fs::u8path(first.metallic)); fs::remove(fs::u8path(first.emission)); fs::remove(marker);
    std::string what;
    unsigned attempts = 0;
    run = {};
    assert(Throws([&] {
        GamePBR::Convert(pmx.u8string(), base, fresh.u8string(), [&](const std::vector<DDS::Level>& levels, const std::string& path, DDS::Format format) {
            if (++attempts == 2) DDS::Publish(fs::u8path(path), levels, format, [](const fs::path&) { return std::optional<uint64_t>(1024); });
            return Write(levels, path, format);
        }, Oct);
    }, &what));
    assert(what.find("free disk space limit: 0 MiB free in ") == 0 && attempts == 2 && Policy::ValidDDS(fs::u8path(first.metallic)));
    assert(!Policy::ValidDDS(fs::u8path(first.emission)) && !fs::exists(marker));
    run = {};
    auto completed = convert(fresh);
    assert(completed.via == "converted" && completed.written == 1 && run.writes == 1);
    for (size_t role = 0; role < 4; ++role) assert(Bytes(fs::u8path(role == 0 ? first.normal : role == 1 ? first.roughness : role == 2 ? first.metallic : first.emission)) == freshBytes[role]);

    // Format migration with the source present: a finished v7 family is re-encoded, never
    // converted again, and the result is byte-identical to a fresh conversion.
    auto expectTranscode = [&](const fs::path& out, const char* marker7, const GamePBR::Maps* selected) {
        run = {};
        const auto result = convert(out, selected);
        assert(result.via == std::string("transcoded from ") + marker7 && run.oct == 0 && run.writes == 4 && result.written == 4);
        const std::array<std::string, 4> paths{result.normal, result.roughness, result.metallic, result.emission};
        for (size_t role = 0; role < 4; ++role) assert(Bytes(fs::u8path(paths[role])) == freshBytes[role]);
        assert(Bytes(fs::u8path(paths[0]).parent_path() / (GamePBR::Id(keys.current) + "_complete.txt")).find(std::string("origin transcoded ") + marker7) != std::string::npos);
        // The migrated family is then simply current.
        run = {};
        assert(convert(out, selected).via == "cached" && run.writes == 0);
    };
    for (auto version : {7u, 6u, 5u}) {
        const auto out = root / ("legacy-v" + std::to_string(version)); fs::create_directories(out);
        const char* name = version == 7 ? "r12-game-v7" : version == 6 ? "r12-game-v6" : "r11-game-v5";
        const auto old = Legacy(out, ShippedKey(version, pmx, base, maps), name, base4);
        const auto oldBytes = Bytes(old[0]);
        expectTranscode(out, name, nullptr);
        assert(Bytes(old[0]) == oldBytes); // the earlier family is left as it was
    }
    // A half-finished earlier family (no marker) converts normally.
    {
        const auto out = root / "legacy-partial"; fs::create_directories(out);
        Legacy(out, keys.v7, "r12-game-v7", base4);
        fs::remove(out / (GamePBR::Id(keys.v7) + "_complete.txt"));
        run = {};
        assert(convert(out).via == "converted" && run.oct == 1);
    }
    // v5 keys carry no layout: v5 chose Silver whenever any *_MRA was in the folder, so such a
    // folder's Endfield family converts again. Manual choices never use v5 families.
    {
        const auto out = root / "legacy-v5-mra"; fs::create_directories(out);
        Legacy(out, keys.v5, "r11-game-v5", base4);
        fs::copy_file(root / "tex/T_actor_test_cloth_N.png", root / "tex/T_other_family_MRA.png");
        run = {};
        assert(convert(out).via == "converted" && run.oct == 1);
        fs::remove(root / "tex/T_other_family_MRA.png");
        const auto manual = root / "legacy-v5-manual"; fs::create_directories(manual);
        Legacy(manual, keys.v5, "r11-game-v5", base4);
        run = {};
        assert(convert(manual, &maps).via == "converted" && run.oct == 1);
    }
    // A v5/v6 output whose packed map was resized came from the premultiplying WIC decode: it is
    // converted again from its readable source. The same v7 output is transcoded.
    {
        GamePBR::Maps resized = maps; resized.packed = root / "straight-packed.png"; // 16x16 packed beside an 8x8 normal
        run = {};
        const auto reference = root / "resized-fresh"; fs::create_directories(reference);
        auto fresh16 = convert(reference, &resized);
        assert(fresh16.via == "converted" && run.oct == 1);
        std::array<DDS::Level, 4> resizedBase;
        const auto resizedKeys = GamePBR::ContentKeys(Data(pmx), Data(root / base), {Data(resized.normal), Data(resized.packed), Data(resized.emission)}, {true, true, true}, base, resized.layout);
        for (size_t role = 0; role < 4; ++role) resizedBase[role] = captured.at(GamePBR::Id(resizedKeys.current) + Suffix(role) + ".dds");
        const auto v6 = root / "legacy-v6-resized"; fs::create_directories(v6);
        Legacy(v6, ShippedKey(6, pmx, base, resized), "r12-game-v6", resizedBase);
        run = {};
        assert(convert(v6, &resized).via == "converted" && run.oct == 1);
        const auto v7 = root / "legacy-v7-resized"; fs::create_directories(v7);
        Legacy(v7, ShippedKey(7, pmx, base, resized), "r12-game-v7", resizedBase);
        run = {};
        assert(convert(v7, &resized).via == "transcoded from r12-game-v7" && run.oct == 0);
    }
    std::cout << "PASS conversion: compact formats without AO, recipe marker, cache, half-family completion, refusal mid-family, "
                 "v7/v6/v5 transcoding byte-identical to fresh conversion, resized v6 and v5-MRA and manual cases convert again\n";

    // Source-less migration of stored records (R11-B registry, R12-B manual choices).
    const auto textures = root / "registry" / "textures"; fs::create_directories(textures);
    const auto v7 = Legacy(textures, keys.v7, "r12-game-v7", base4);
    GameRegistry::Registry registry(textures);
    assert(registry.Load());
    const std::string identity = "mmd/t/0123456789abcdef";
    GameRegistry::Record legacy; legacy.identity = identity; legacy.hashes = {0x11}; legacy.generator = 7;
    assert(registry.Capture(legacy, {v7[0].u8string(), v7[1].u8string(), v7[2].u8string(), v7[3].u8string()}));
    assert(registry.ValidateRecord(legacy)); // uncompressed records stay valid
    assert(registry.Resolve(identity, {0x11}, true, true, [&] { return std::optional<GameRegistry::Record>(legacy); }) && registry.Save());
    fs::rename(pmx, root / "test.pmx.hidden"); fs::rename(root / "tex", root / "tex.hidden");
    unsigned transcodes = 0;
    auto transcode = [&](const fs::path& from, const fs::path& to, DDS::Format format) { ++transcodes; DDS::Transcode(from, to, format); };
    auto absent = []() -> std::optional<GameRegistry::Record> { assert(false); return {}; };
    const auto before = Bytes(registry.Path());
    assert(registry.Compact(identity, transcode) == 3 && transcodes == 3);
    assert(Bytes(registry.Path()) != before);
    {
        GameRegistry::Registry reloaded(textures);
        assert(reloaded.Load() && reloaded.Size() == 1);
        const auto record = reloaded.Resolve(identity, {0x22}, true, false, absent);
        assert(record && record->generator == 7 && record->hashes == std::vector<uint64_t>{0x22});
        assert(record->textures[0].file == GamePBR::Id(keys.v7) + "_normal_bc5.dds" && record->textures[1].file == GamePBR::Id(keys.v7) + "_roughness_bc4.dds" &&
               record->textures[2].file == GamePBR::Id(keys.v7) + "_metallic_bc4.dds" && record->textures[3].file == legacy.textures[3].file);
        assert(record->textures[3].digest == legacy.textures[3].digest && record->textures[0].bytes == DDS::FileBytes(8, 8, DDS::Format::BC5));
        for (size_t role = 0; role < 3; ++role) assert(Bytes(fs::u8path(reloaded.TexturePath(record->textures[role]))) == freshBytes[role]);
        assert(reloaded.Compact(identity, transcode) == 0 && transcodes == 3);
    }
    // A failed registry save keeps the previous record, in memory and on disk.
    {
        const auto other = root / "registry-locked" / "textures"; fs::create_directories(other);
        const auto files = Legacy(other, keys.v7, "r12-game-v7", base4);
        GameRegistry::Registry locked(other); assert(locked.Load());
        GameRegistry::Record r = legacy;
        assert(locked.Capture(r, {files[0].u8string(), files[1].u8string(), files[2].u8string(), files[3].u8string()}));
        assert(locked.Resolve(identity, {0x11}, true, true, [&] { return std::optional<GameRegistry::Record>(r); }) && locked.Save());
        const auto saved = Bytes(locked.Path());
        fs::create_directory(locked.Path().wstring() + L".tmp");
        assert(Throws([&] { locked.Compact(identity, transcode); }, &what) && what == "registry could not be saved; cached maps stay uncompressed");
        assert(Bytes(locked.Path()) == saved && locked.Resolve(identity, {0x33}, true, false, absent)->textures[0].file == r.textures[0].file);
        fs::remove(locked.Path().wstring() + L".tmp");
        const auto count = transcodes;
        assert(locked.Compact(identity, transcode) == 3 && transcodes == count); // already-valid compact files are reused
    }
    // Manual choices migrate the same way, atomically through the store.
    {
        GameOverrides::Store store(textures); assert(store.Load());
        GameOverrides::Choice choice; choice.mode = "maps"; choice.source = "E:/gone/model.pmx"; choice.base = base; choice.packed = "tex/T_actor_test_cloth_P.png"; choice.layout = 1;
        choice.record = legacy; choice.record.identity = "mmd/t/1123456789abcdef";
        assert(store.Set(choice.record.identity, choice));
        assert(store.Compact(choice.record.identity, transcode) == 3 && transcodes >= 3);
        GameOverrides::Store reloaded(textures); assert(reloaded.Load());
        const auto restored = reloaded.Resolve(choice.record.identity, {0x44});
        assert(restored && restored->textures[0].file == GamePBR::Id(keys.v7) + "_normal_bc5.dds" && restored->textures[3].file == legacy.textures[3].file);
        assert(reloaded.Compact(choice.record.identity, transcode) == 0);
    }
    // Role formats: each role accepts its compact format or the uncompressed one, nothing else.
    {
        const auto bc4 = textures / (GamePBR::Id(keys.v7) + "_roughness_bc4.dds"), bc5 = textures / (GamePBR::Id(keys.v7) + "_normal_bc5.dds");
        assert(GameRegistry::Inspect(bc5, false, 0) && !GameRegistry::Inspect(bc5, false, 1) && !GameRegistry::Inspect(bc5, false, 3));
        assert(GameRegistry::Inspect(bc4, false, 1) && GameRegistry::Inspect(bc4, false, 2) && !GameRegistry::Inspect(bc4, false, 0) && !GameRegistry::Inspect(bc4, false, 3));
        assert(GameRegistry::Inspect(v7[3], false, 3) && GameRegistry::Inspect(v7[0], false, 0));
        GameRegistry::Record swapped = legacy;
        swapped.textures[0] = *GameRegistry::Inspect(bc4, true);
        assert(!registry.ValidateRecord(swapped));
    }
    fs::rename(root / "test.pmx.hidden", pmx); fs::rename(root / "tex.hidden", root / "tex");
    std::cout << "PASS migration without source: registry and manual choices transcoded and saved atomically, failed save keeps the "
                 "previous record, compact files reused, role formats enforced, uncompressed records still valid\n";
}

// An unrelated version bump: a build with another generator number converts nothing.
static void Bump(const fs::path& root, bool prepare) {
    const auto out = root / "bump"; fs::create_directories(out);
    run = {};
    const auto result = GamePBR::Convert((root / "test.pmx").u8string(), "tex/T_actor_test_cloth_D.png", out.u8string(), Write, Oct);
    if (prepare) {
        assert(result.via == "converted" && run.oct == 1 && GamePBR::GeneratorVersion != 999);
        std::cout << "PASS bump-prepare: converted with generator " << GamePBR::GeneratorVersion << "\n";
    } else {
        assert(GamePBR::GeneratorVersion == 999 && result.via == "cached" && run.oct == 0 && run.writes == 0);
        std::cout << "PASS bump-check: generator " << GamePBR::GeneratorVersion << " reused every map (0 conversions, 0 writes)\n";
    }
}

int wmain(int argc, wchar_t** argv) {
    assert(argc == 2 || argc == 3);
    const fs::path root = fs::absolute(argv[1]);
    const std::wstring mode = argc == 3 ? argv[2] : L"";
    std::cout.setf(std::ios::unitbuf); // keep every line before a failed assertion
    const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (mode == L"bump-prepare" || mode == L"bump-check") Bump(root, mode == L"bump-prepare");
    else {
        Codec(root);
        Publication(root, mode == L"bulk");
        Conversion(root);
    }
    if (SUCCEEDED(com)) CoUninitialize();
    return 0;
}
