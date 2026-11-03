// GPL-2.0. DDS layouts and the BC4/BC5 block encoder for generated maps (R13-M).
// Standard C++ only: production and the SDK-free native regressions share this code.
#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <istream>
#include <optional>
#include <ostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace MaterialPipeline { namespace ToPBR { namespace DDS {
// RGBA8 is the pre-R13 uncompressed layout: a 32-bit legacy header with B8G8R8A8 masks.
// BC4/BC5 use a DX10 header with DXGI_FORMAT_BC4_UNORM (80) / DXGI_FORMAT_BC5_UNORM (83).
enum class Format : uint32_t { RGBA8 = 0, BC4 = 80, BC5 = 83 };
inline const char* Name(Format format) {
    return format == Format::BC4 ? "BC4" : format == Format::BC5 ? "BC5" : "RGBA8";
}
// Encoder identity. Change it whenever encoded bytes can change: it is part of the game-map recipe.
constexpr const char* EncoderId = "bc4-minmax-ls2-align4-bounded-1";

constexpr uint32_t Magic = 0x20534444, FourCCDX10 = 0x30315844;
constexpr uint32_t FlagCaps = 0x1, FlagHeight = 0x2, FlagWidth = 0x4, FlagPixelFormat = 0x1000,
                   FlagMipCount = 0x20000, FlagLinearSize = 0x80000;
constexpr uint32_t PixelAlpha = 0x1, PixelFourCC = 0x4, PixelRGB = 0x40;
constexpr uint32_t CapsTexture = 0x1000, CapsMipmap = 0x400000, CapsComplex = 0x8;
constexpr uint32_t Caps2Cubemap = 0x200, Caps2Volume = 0x200000, MiscTextureCube = 0x4;

struct Info { uint32_t width = 0, height = 0, levels = 0; Format format = Format::RGBA8; uint64_t bytes = 0; };
struct Level { uint32_t width = 0, height = 0; std::vector<uint8_t> rgba; }; // straight RGBA8 texels

inline uint32_t LevelCount(uint32_t w, uint32_t h) {
    uint32_t levels = 1;
    while (w > 1 || h > 1) { w = (std::max)(1u, w / 2); h = (std::max)(1u, h / 2); ++levels; }
    return levels;
}
inline uint64_t LevelBytes(uint32_t w, uint32_t h, Format format) {
    if (format == Format::RGBA8) return uint64_t(w) * h * 4;
    return uint64_t((w + 3) / 4) * ((h + 3) / 4) * (format == Format::BC4 ? 8 : 16);
}
inline uint64_t HeaderBytes(Format format) { return format == Format::RGBA8 ? 128 : 148; }
inline uint64_t FileBytes(uint32_t w, uint32_t h, Format format) {
    uint64_t bytes = HeaderBytes(format);
    for (;;) {
        bytes += LevelBytes(w, h, format);
        if (w == 1 && h == 1) return bytes;
        w = (std::max)(1u, w / 2); h = (std::max)(1u, h / 2);
    }
}
// Block-compressed maps are written only for a base whose sides are multiples of four, so every
// reader (gli, DXVK/Vulkan) sees whole blocks at the top level. Other sizes keep the legacy layout.
inline bool BlockAligned(uint32_t w, uint32_t h) { return w && h && w % 4 == 0 && h % 4 == 0; }

// Parses exactly the two layouts this module writes. The uncompressed rule is the pre-R13
// validator's (magic, header sizes, no FourCC, 32 bits, full chain), so every existing record and
// cache entry keeps validating. Dimension bounds and the file size are checked by the caller.
inline bool Probe(std::istream& file, Info& info) {
    uint32_t h[32]{};
    if (!file.read(reinterpret_cast<char*>(h), sizeof(h))) return false;
    if (h[0] != Magic || h[1] != 124 || h[19] != 32 || !h[3] || !h[4]) return false;
    info.width = h[4]; info.height = h[3]; info.levels = h[7];
    if (h[21] == 0) {
        if (h[22] != 32) return false;
        info.format = Format::RGBA8;
    } else if (h[21] == FourCCDX10 && (h[20] & PixelFourCC)) {
        uint32_t dx[5]{};
        if (!file.read(reinterpret_cast<char*>(dx), sizeof(dx))) return false;
        if ((dx[0] != uint32_t(Format::BC4) && dx[0] != uint32_t(Format::BC5)) || dx[1] != 3 ||
            (dx[2] & MiscTextureCube) || dx[3] != 1 || (h[28] & (Caps2Cubemap | Caps2Volume)) ||
            !(h[2] & FlagMipCount) || !BlockAligned(info.width, info.height)) return false;
        info.format = Format(dx[0]);
    } else return false;
    if (info.levels != LevelCount(info.width, info.height)) return false;
    info.bytes = FileBytes(info.width, info.height, info.format);
    return true;
}
// Header and exact file size. Callers add their own dimension bound (Policy::ValidImage).
inline bool Probe(const std::filesystem::path& path, Info& info) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return false;
    const auto size = file.tellg();
    if (size < 0) return false;
    file.seekg(0);
    return Probe(file, info) && uint64_t(size) == info.bytes;
}

// The legacy writer's box filter, exactly: per channel, the floor of the mean of the texels a
// 2x2 footprint covers inside the previous level. Transcoded legacy mips therefore equal the
// mips a fresh conversion generates from the same base level.
inline std::vector<Level> Chain(uint32_t w, uint32_t h, std::vector<uint8_t> rgba) {
    if (!w || !h || rgba.size() != size_t(w) * h * 4) throw std::runtime_error("image data size does not match its dimensions");
    std::vector<Level> chain;
    chain.push_back({w, h, std::move(rgba)});
    while (w > 1 || h > 1) {
        const auto& old = chain.back();
        const uint32_t nw = (std::max)(1u, w / 2), nh = (std::max)(1u, h / 2);
        Level next{nw, nh, std::vector<uint8_t>(size_t(nw) * nh * 4)};
        for (uint32_t y = 0; y < nh; ++y) for (uint32_t x = 0; x < nw; ++x) {
            uint32_t sum[4]{}, count = 0;
            for (uint32_t dy = 0; dy < 2 && y * 2 + dy < h; ++dy)
                for (uint32_t dx = 0; dx < 2 && x * 2 + dx < w; ++dx) {
                    const size_t at = (size_t(y * 2 + dy) * w + x * 2 + dx) * 4;
                    for (int c = 0; c < 4; ++c) sum[c] += old.rgba[at + c];
                    ++count;
                }
            for (int c = 0; c < 4; ++c) next.rgba[(size_t(y) * nw + x) * 4 + c] = uint8_t(sum[c] / count);
        }
        chain.push_back(std::move(next));
        w = nw; h = nh;
    }
    return chain;
}

// BC4: two 8-bit endpoints and sixteen 3-bit indices. r0 > r1 interpolates six values between
// them; r0 <= r1 interpolates four and adds exact 0 and 255. Palettes are exact rationals: in
// units of 1/35 both modes compare without rounding, as the GPU decodes them.
inline void Palette35(uint8_t r0, uint8_t r1, int out[8]) {
    out[0] = 35 * r0; out[1] = 35 * r1;
    if (r0 > r1) { for (int i = 1; i <= 6; ++i) out[i + 1] = 5 * ((7 - i) * r0 + i * r1); }
    else { for (int i = 1; i <= 4; ++i) out[i + 1] = 7 * ((5 - i) * r0 + i * r1); out[6] = 0; out[7] = 35 * 255; }
}
struct BlockFit { std::array<uint8_t, 8> block{}; uint64_t error = 0; int worst = 0; }; // squared/worst error, 1/35 units
inline BlockFit FitBC4(const uint8_t v[16], uint8_t r0, uint8_t r1) {
    int palette[8]; Palette35(r0, r1, palette);
    BlockFit fit; uint64_t bits = 0;
    for (int i = 0; i < 16; ++i) {
        const int x = 35 * v[i];
        int pick = 0, best = std::abs(x - palette[0]);
        for (int k = 1; k < 8; ++k) { const int e = std::abs(x - palette[k]); if (e < best) { best = e; pick = k; } }
        bits |= uint64_t(pick) << (3 * i);
        fit.error += uint64_t(best) * uint64_t(best);
        fit.worst = (std::max)(fit.worst, best);
    }
    fit.block[0] = r0; fit.block[1] = r1;
    for (int i = 0; i < 6; ++i) fit.block[2 + i] = uint8_t(bits >> (8 * i));
    return fit;
}
inline int64_t RoundDiv(int64_t num, int64_t den) { // den > 0, round half up, exact for negatives
    const int64_t q = (2 * num + den) / (2 * den), r = (2 * num + den) % (2 * den);
    return r < 0 ? q - 1 : q;
}
// Endpoints at the block's extremes bound every texel's error by (max - min) / 14. Two
// least-squares refinements, the exact-0/255 mode and (for blocks of at most four levels, such as
// quantized roughness) endpoints that put the minimum and maximum on two palette positions may
// replace them only with a lower squared error and no worse texel, so that bound always holds.
// Integer arithmetic: deterministic bytes.
inline std::array<uint8_t, 8> EncodeBC4(const uint8_t v[16]) {
    uint8_t lo = 255, hi = 0;
    for (int i = 0; i < 16; ++i) { lo = (std::min)(lo, v[i]); hi = (std::max)(hi, v[i]); }
    BlockFit best = FitBC4(v, hi, lo);
    if (!best.error) return best.block;
    const int bound = best.worst;
    auto consider = [&](const BlockFit& fit) { if (fit.error < best.error && fit.worst <= bound) best = fit; };
    auto pair = [&](int64_t r0, int64_t r1) { if (r0 >= 0 && r0 <= 255 && r1 >= 0 && r1 <= 255) consider(FitBC4(v, uint8_t(r0), uint8_t(r1))); };
    uint8_t ilo = 255, ihi = 0; bool extremes = false, inner = false;
    for (int i = 0; i < 16; ++i) {
        if (v[i] == 0 || v[i] == 255) { extremes = true; continue; }
        inner = true; ilo = (std::min)(ilo, v[i]); ihi = (std::max)(ihi, v[i]);
    }
    if (extremes && inner) consider(FitBC4(v, ilo, ihi));
    for (int pass = 0; pass < 2 && best.block[0] > best.block[1]; ++pass) {
        // Weight of r0 in sevenths for each index: 0 -> 7, 1 -> 0, k >= 2 -> 8 - k.
        uint64_t bits = 0;
        for (int i = 0; i < 6; ++i) bits |= uint64_t(best.block[2 + i]) << (8 * i);
        int64_t a = 0, b = 0, c = 0, e = 0, f = 0;
        for (int i = 0; i < 16; ++i) {
            const int k = int((bits >> (3 * i)) & 7), s = k == 0 ? 7 : k == 1 ? 0 : 8 - k;
            a += s * s; b += s * (7 - s); c += (7 - s) * (7 - s);
            e += 7 * s * v[i]; f += 7 * (7 - s) * v[i];
        }
        const int64_t det = a * c - b * b;
        if (det <= 0) break;
        const int64_t r0 = std::clamp<int64_t>(RoundDiv(e * c - b * f, det), 0, 255);
        const int64_t r1 = std::clamp<int64_t>(RoundDiv(a * f - b * e, det), 0, 255);
        if (r0 <= r1) break;
        const auto fit = FitBC4(v, uint8_t(r0), uint8_t(r1));
        if (!(fit.error < best.error && fit.worst <= bound)) break;
        best = fit;
    }
    uint64_t seen[4]{}; int levels = 0;
    for (int i = 0; i < 16; ++i) { const uint64_t bit = 1ull << (v[i] & 63); if (!(seen[v[i] >> 6] & bit)) { seen[v[i] >> 6] |= bit; ++levels; } }
    if (best.error && levels <= 4) {
        // Eight values: s/7 of r0, s = 0..7, with r0 > r1; the minimum sits at s0 < s1 of the maximum.
        for (int s0 = 0; s0 < 8; ++s0) for (int s1 = s0 + 1; s1 < 8; ++s1) {
            const int64_t d = RoundDiv(7 * int64_t(hi - lo), s1 - s0), r1 = RoundDiv(7 * int64_t(lo) - s0 * d, 7);
            if (d > 0) pair(r1 + d, r1);
        }
        // Six values: s/5 of r0, s = 0..5, with r0 <= r1; the minimum sits at s0 > s1 of the maximum.
        for (int s1 = 0; s1 < 6; ++s1) for (int s0 = s1 + 1; s0 < 6; ++s0) {
            const int64_t d = RoundDiv(5 * int64_t(hi - lo), s0 - s1), r0 = RoundDiv(5 * int64_t(lo) - (5 - s0) * d, 5);
            if (d > 0) pair(r0, r0 + d);
        }
    }
    return best.block;
}
// Exact decode in 1/35 units (GPU precision); Decode8 rounds to the nearest 8-bit value.
inline void DecodeBC4(const uint8_t* block, int out35[16]) {
    int palette[8]; Palette35(block[0], block[1], palette);
    uint64_t bits = 0;
    for (int i = 0; i < 6; ++i) bits |= uint64_t(block[2 + i]) << (8 * i);
    for (int i = 0; i < 16; ++i) out35[i] = palette[(bits >> (3 * i)) & 7];
}
inline uint8_t Decode8(int value35) { return uint8_t((value35 + 17) / 35); }

inline void Put(std::vector<uint8_t>& out, uint32_t value) {
    for (int i = 0; i < 4; ++i) out.push_back(uint8_t(value >> (8 * i)));
}
inline std::vector<uint8_t> Header(uint32_t w, uint32_t h, uint32_t levels, Format format) {
    uint32_t hd[32]{};
    hd[0] = Magic; hd[1] = 124; hd[3] = h; hd[4] = w; hd[6] = 1; hd[7] = levels; hd[19] = 32;
    hd[27] = CapsTexture | CapsMipmap | CapsComplex;
    hd[2] = FlagCaps | FlagHeight | FlagWidth | FlagPixelFormat | FlagLinearSize | FlagMipCount;
    if (format == Format::RGBA8) {
        // Field-for-field the header TextureProcessor::WriteDDSHeader wrote before R13.
        hd[5] = w * h * 4; hd[20] = PixelRGB | PixelAlpha; hd[22] = 32;
        hd[23] = 0x00ff0000; hd[24] = 0x0000ff00; hd[25] = 0x000000ff; hd[26] = 0xff000000;
    } else {
        hd[5] = uint32_t(LevelBytes(w, h, format)); hd[20] = PixelFourCC; hd[21] = FourCCDX10;
    }
    std::vector<uint8_t> out;
    out.reserve(size_t(HeaderBytes(format)));
    for (auto value : hd) Put(out, value);
    if (format != Format::RGBA8) { Put(out, uint32_t(format)); Put(out, 3); Put(out, 0); Put(out, 1); Put(out, 0); }
    return out;
}
// A whole file in memory. Levels must form the full chain of the base level.
inline std::vector<uint8_t> Encode(const std::vector<Level>& chain, Format format) {
    if (chain.empty()) throw std::runtime_error("no image levels");
    const uint32_t w = chain[0].width, h = chain[0].height;
    if (chain.size() != LevelCount(w, h)) throw std::runtime_error("incomplete mip chain");
    if (format != Format::RGBA8 && !BlockAligned(w, h)) throw std::runtime_error("block-compressed map needs sides that are multiples of 4");
    auto out = Header(w, h, uint32_t(chain.size()), format);
    out.reserve(size_t(FileBytes(w, h, format)));
    uint32_t lw = w, lh = h;
    for (const auto& level : chain) {
        if (level.width != lw || level.height != lh || level.rgba.size() != size_t(lw) * lh * 4)
            throw std::runtime_error("mip level size does not match its chain");
        if (format == Format::RGBA8) {
            for (size_t i = 0; i < level.rgba.size(); i += 4) {
                out.push_back(level.rgba[i + 2]); out.push_back(level.rgba[i + 1]);
                out.push_back(level.rgba[i]); out.push_back(level.rgba[i + 3]);
            }
        } else {
            const int channels = format == Format::BC4 ? 1 : 2;
            for (uint32_t by = 0; by < lh; by += 4) for (uint32_t bx = 0; bx < lw; bx += 4)
                for (int c = 0; c < channels; ++c) {
                    uint8_t v[16];
                    // Texels past a small level's edge repeat its last row/column.
                    for (uint32_t y = 0; y < 4; ++y) for (uint32_t x = 0; x < 4; ++x)
                        v[y * 4 + x] = level.rgba[(size_t((std::min)(by + y, lh - 1)) * lw + (std::min)(bx + x, lw - 1)) * 4 + c];
                    const auto block = EncodeBC4(v);
                    out.insert(out.end(), block.begin(), block.end());
                }
        }
        lw = (std::max)(1u, lw / 2); lh = (std::max)(1u, lh / 2);
    }
    return out;
}
// Reads every level as straight RGBA8. Uncompressed files return their stored texels; BC4
// returns the value in R, G and B (alpha 255), BC5 returns R and G with B 0 and alpha 255:
// the channel layouts the uncompressed roughness/metallic and octahedral normal maps use.
inline std::vector<Level> Read(const std::filesystem::path& path, Info& info) {
    if (!Probe(path, info)) throw std::runtime_error("not a valid generated DDS: " + path.filename().u8string());
    std::ifstream file(path, std::ios::binary);
    file.seekg(std::streamoff(HeaderBytes(info.format)));
    std::vector<Level> chain;
    uint32_t w = info.width, h = info.height;
    for (uint32_t i = 0; i < info.levels; ++i) {
        std::vector<uint8_t> data(size_t(LevelBytes(w, h, info.format)));
        if (!file.read(reinterpret_cast<char*>(data.data()), std::streamsize(data.size()))) throw std::runtime_error("truncated DDS: " + path.filename().u8string());
        Level level{w, h, std::vector<uint8_t>(size_t(w) * h * 4)};
        if (info.format == Format::RGBA8) {
            for (size_t p = 0; p < data.size(); p += 4) {
                level.rgba[p] = data[p + 2]; level.rgba[p + 1] = data[p + 1];
                level.rgba[p + 2] = data[p]; level.rgba[p + 3] = data[p + 3];
            }
        } else {
            const int channels = info.format == Format::BC4 ? 1 : 2;
            size_t at = 0;
            for (uint32_t by = 0; by < h; by += 4) for (uint32_t bx = 0; bx < w; bx += 4)
                for (int c = 0; c < channels; ++c, at += 8) {
                    int values[16]; DecodeBC4(data.data() + at, values);
                    for (uint32_t y = 0; y < 4 && by + y < h; ++y) for (uint32_t x = 0; x < 4 && bx + x < w; ++x) {
                        auto* texel = level.rgba.data() + (size_t(by + y) * w + bx + x) * 4;
                        const uint8_t value = Decode8(values[y * 4 + x]);
                        if (channels == 1) { texel[0] = texel[1] = texel[2] = value; }
                        else texel[c] = value;
                        texel[3] = 255;
                    }
                }
        }
        chain.push_back(std::move(level));
        w = (std::max)(1u, w / 2); h = (std::max)(1u, h / 2);
    }
    return chain;
}
}}}
