#include "internal.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <system_error>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <wincodec.h>
#endif

namespace advmat::rtx_bridge::detail {
namespace {

constexpr std::array<std::uint8_t, 4> kDdsMagic{'D', 'D', 'S', ' '};
// Far more distinct maps than a session uses; past it the memory starts over.
constexpr std::size_t kMaximumRememberedSources = 4096;

std::string Lowercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

bool ReadFile(const std::filesystem::path& path, std::uintmax_t maximum,
              std::vector<std::uint8_t>& bytes, std::string& error) {
    std::error_code ec;
    const auto size = std::filesystem::file_size(path, ec);
    if (ec) {
        error = "cannot determine texture size: " + ec.message();
        return false;
    }
    if (size == 0 || size > maximum || size > static_cast<std::uintmax_t>(
            std::numeric_limits<std::streamsize>::max())) {
        error = "texture size is empty or exceeds the configured safety limit";
        return false;
    }
    bytes.resize(static_cast<std::size_t>(size));
    std::ifstream stream(path, std::ios::binary);
    if (!stream || !stream.read(reinterpret_cast<char*>(bytes.data()),
                                static_cast<std::streamsize>(bytes.size()))) {
        error = "cannot read texture source";
        return false;
    }
    return true;
}

std::uint32_t ReadU32(const std::uint8_t* bytes, std::size_t offset) {
    return static_cast<std::uint32_t>(bytes[offset]) |
        (static_cast<std::uint32_t>(bytes[offset + 1]) << 8u) |
        (static_cast<std::uint32_t>(bytes[offset + 2]) << 16u) |
        (static_cast<std::uint32_t>(bytes[offset + 3]) << 24u);
}

// A DDS is copied as it is and the RTX Remix runtime reads it at mod load, so
// its header is checked against the file itself: a format whose storage is
// known, a mip count the dimensions allow, sane faces and array layers, and
// every byte the header describes present in the file. A header-only check
// let a 128-byte file, or a cached copy cut down to its header, through.
constexpr std::size_t kDdsHeaderBytes = 128;      // "DDS " and the 124-byte DDS_HEADER
constexpr std::size_t kDdsDx10HeaderBytes = 20;   // DDS_HEADER_DXT10, for FourCC "DX10"
// The runtime records the sizes of at most 16 levels per texture.
constexpr std::uint32_t kMaximumDdsMipLevels = 16;
constexpr std::uint32_t kMaximumDdsArraySize = 2048;

constexpr std::uint32_t kDdsFlagDepth = 0x800000u;      // DDSD_DEPTH
constexpr std::uint32_t kDdsPixelFourCc = 0x4u;         // DDPF_FOURCC
constexpr std::uint32_t kDdsPixelData = 0x2u | 0x40u | 0x200u | 0x20000u | 0x80000u;
                                                        // ALPHA, RGB, YUV, LUMINANCE, BUMPDUDV
constexpr std::uint32_t kDdsCaps2Cubemap = 0x200u;
constexpr std::uint32_t kDdsCaps2CubeFaces = 0xFC00u;
constexpr std::uint32_t kDdsCaps2Volume = 0x200000u;
constexpr std::uint32_t kDxgiMiscTextureCube = 0x4u;

constexpr std::uint32_t FourCc(char a, char b, char c, char d) {
    return static_cast<std::uint32_t>(static_cast<std::uint8_t>(a)) |
        (static_cast<std::uint32_t>(static_cast<std::uint8_t>(b)) << 8u) |
        (static_cast<std::uint32_t>(static_cast<std::uint8_t>(c)) << 16u) |
        (static_cast<std::uint32_t>(static_cast<std::uint8_t>(d)) << 24u);
}

// How a format stores a level: whole pixels of bitsPerPixel, 4x4 blocks of
// bytesPerUnit, or pairs of pixels in bytesPerUnit (packed 4:2:2).
struct DdsStorage {
    enum class Kind { Pixels, Blocks, Pairs };
    Kind kind = Kind::Pixels;
    std::uint32_t bitsPerPixel = 0;
    std::uint32_t bytesPerUnit = 0;
};

DdsStorage PixelStorage(std::uint32_t bitsPerPixel) {
    DdsStorage storage;
    storage.bitsPerPixel = bitsPerPixel;
    return storage;
}

DdsStorage BlockStorage(DdsStorage::Kind kind, std::uint32_t bytesPerUnit) {
    DdsStorage storage;
    storage.kind = kind;
    storage.bytesPerUnit = bytesPerUnit;
    return storage;
}

// DXGI_FORMAT values with a fixed storage. Video and planar formats and
// unknown values have none and are refused.
std::optional<DdsStorage> DxgiStorage(std::uint32_t format) {
    using Kind = DdsStorage::Kind;
    if (format >= 1 && format <= 4) return PixelStorage(128);
    if (format >= 5 && format <= 8) return PixelStorage(96);
    if (format >= 9 && format <= 22) return PixelStorage(64);
    if (format >= 23 && format <= 47) return PixelStorage(32);
    if (format >= 48 && format <= 59) return PixelStorage(16);
    if (format >= 60 && format <= 65) return PixelStorage(8);
    if (format == 66) return PixelStorage(1);                        // R1_UNORM
    if (format == 67) return PixelStorage(32);                       // R9G9B9E5_SHAREDEXP
    if (format == 68 || format == 69) return BlockStorage(Kind::Pairs, 4);
    if ((format >= 70 && format <= 72) || (format >= 79 && format <= 81)) {
        return BlockStorage(Kind::Blocks, 8);                        // BC1, BC4
    }
    if ((format >= 73 && format <= 78) || (format >= 82 && format <= 84) ||
        (format >= 94 && format <= 99)) {
        return BlockStorage(Kind::Blocks, 16);                       // BC2, BC3, BC5, BC6H, BC7
    }
    if (format == 85 || format == 86 || format == 115) return PixelStorage(16);
    if (format >= 87 && format <= 93) return PixelStorage(32);
    return std::nullopt;
}

// A header without the DX10 extension: a FourCC code, or uncompressed pixels.
std::optional<DdsStorage> LegacyStorage(std::uint32_t pixelFlags, std::uint32_t fourCc,
                                        std::uint32_t rgbBitCount) {
    using Kind = DdsStorage::Kind;
    if (pixelFlags & kDdsPixelFourCc) {
        switch (fourCc) {
        case FourCc('D', 'X', 'T', '1'): case FourCc('A', 'T', 'I', '1'):
        case FourCc('B', 'C', '4', 'U'): case FourCc('B', 'C', '4', 'S'):
            return BlockStorage(Kind::Blocks, 8);
        case FourCc('D', 'X', 'T', '2'): case FourCc('D', 'X', 'T', '3'):
        case FourCc('D', 'X', 'T', '4'): case FourCc('D', 'X', 'T', '5'):
        case FourCc('A', 'T', 'I', '2'): case FourCc('B', 'C', '5', 'U'):
        case FourCc('B', 'C', '5', 'S'):
            return BlockStorage(Kind::Blocks, 16);
        case FourCc('R', 'G', 'B', 'G'): case FourCc('G', 'R', 'G', 'B'):
        case FourCc('Y', 'U', 'Y', '2'): case FourCc('U', 'Y', 'V', 'Y'):
            return BlockStorage(Kind::Pairs, 4);
        // D3DFORMAT values written as a FourCC.
        case 36: case 110: case 113: case 115: return PixelStorage(64);
        case 111: case 117: return PixelStorage(16);
        case 112: case 114: return PixelStorage(32);
        case 116: return PixelStorage(128);
        default: return std::nullopt;
        }
    }
    if ((pixelFlags & kDdsPixelData) && rgbBitCount >= 8 && rgbBitCount <= 128 &&
        rgbBitCount % 8 == 0) {
        return PixelStorage(rgbBitCount);
    }
    return std::nullopt;
}

bool CheckedMultiply(std::uint64_t left, std::uint64_t right, std::uint64_t& result) {
    if (left != 0 && right > std::numeric_limits<std::uint64_t>::max() / left) return false;
    result = left * right;
    return true;
}

bool CheckedAdd(std::uint64_t left, std::uint64_t right, std::uint64_t& result) {
    if (right > std::numeric_limits<std::uint64_t>::max() - left) return false;
    result = left + right;
    return true;
}

std::uint32_t CountBits(std::uint32_t value) {
    std::uint32_t count = 0;
    for (; value != 0; value &= value - 1) ++count;
    return count;
}

// `bytes` holds the first `available` bytes of a DDS file of `fileSize` bytes:
// the 128-byte header at least, and the DX10 header when there is one.
bool ValidateDdsLayout(const std::uint8_t* bytes, std::size_t available,
                       std::uintmax_t fileSize, std::uint32_t maximumDimension,
                       std::string& error) {
    if (available < kDdsHeaderBytes || fileSize < kDdsHeaderBytes ||
        !std::equal(kDdsMagic.begin(), kDdsMagic.end(), bytes)) {
        error = "DDS source has no valid DDS magic/header";
        return false;
    }
    const auto headerSize = ReadU32(bytes, 4);
    const auto flags = ReadU32(bytes, 8);
    const auto height = ReadU32(bytes, 12);
    const auto width = ReadU32(bytes, 16);
    const auto rawDepth = ReadU32(bytes, 24);
    const auto rawMipCount = ReadU32(bytes, 28);
    const auto pixelFormatSize = ReadU32(bytes, 76);
    const auto pixelFlags = ReadU32(bytes, 80);
    const auto fourCc = ReadU32(bytes, 84);
    const auto rgbBitCount = ReadU32(bytes, 88);
    const auto caps2 = ReadU32(bytes, 112);
    if (headerSize != 124 || pixelFormatSize != 32 || width == 0 || height == 0 ||
        width > maximumDimension || height > maximumDimension) {
        error = "DDS header or dimensions are invalid";
        return false;
    }

    std::uint64_t headerBytes = kDdsHeaderBytes;
    std::optional<DdsStorage> storage;
    std::uint32_t depth = 1;
    std::uint64_t layers = 1;  // array elements times cube faces
    if ((pixelFlags & kDdsPixelFourCc) && fourCc == FourCc('D', 'X', '1', '0')) {
        headerBytes += kDdsDx10HeaderBytes;
        if (available < headerBytes || fileSize < headerBytes) {
            error = "DDS file is shorter than its DX10 header";
            return false;
        }
        const auto format = ReadU32(bytes, 128);
        const auto dimension = ReadU32(bytes, 132);
        const auto miscFlag = ReadU32(bytes, 136);
        const auto arraySize = ReadU32(bytes, 140);
        storage = DxgiStorage(format);
        if (arraySize == 0 || arraySize > kMaximumDdsArraySize) {
            error = "DDS array size is invalid";
            return false;
        }
        layers = arraySize;
        if (dimension == 4) {  // TEXTURE3D
            if (arraySize != 1 || (miscFlag & kDxgiMiscTextureCube)) {
                error = "DDS volume texture layout is invalid";
                return false;
            }
            depth = std::max<std::uint32_t>(1u, rawDepth);
        } else if (dimension == 2 || dimension == 3) {  // TEXTURE1D, TEXTURE2D
            if (miscFlag & kDxgiMiscTextureCube) layers *= 6;
        } else {
            error = "DDS resource dimension is invalid";
            return false;
        }
    } else {
        storage = LegacyStorage(pixelFlags, fourCc, rgbBitCount);
        const bool volume = (flags & kDdsFlagDepth) || (caps2 & kDdsCaps2Volume);
        if (caps2 & kDdsCaps2Cubemap) {
            layers = CountBits(caps2 & kDdsCaps2CubeFaces);
            if (layers == 0 || volume) {
                error = "DDS cube map layout is invalid";
                return false;
            }
        }
        if (volume) depth = std::max<std::uint32_t>(1u, rawDepth);
    }
    if (!storage) {
        error = "DDS pixel format is not supported";
        return false;
    }
    if (depth > maximumDimension) {
        error = "DDS header or dimensions are invalid";
        return false;
    }

    // A level per halving down to 1x1x1 at most, and never more than the
    // runtime can record.
    const std::uint32_t levels = std::max<std::uint32_t>(1u, rawMipCount);
    std::uint32_t largest = std::max({width, height, depth});
    std::uint32_t possibleLevels = 1;
    while (largest > 1) {
        largest >>= 1u;
        ++possibleLevels;
    }
    if (levels > kMaximumDdsMipLevels || levels > possibleLevels) {
        error = "DDS mip count " + std::to_string(rawMipCount) +
            " is invalid for a " + std::to_string(width) + " x " + std::to_string(height) +
            " texture";
        return false;
    }

    std::uint64_t required = 0;
    bool fits = true;
    for (std::uint32_t level = 0; level < levels && fits; ++level) {
        const std::uint64_t levelWidth = std::max<std::uint32_t>(1u, width >> level);
        const std::uint64_t levelHeight = std::max<std::uint32_t>(1u, height >> level);
        const std::uint64_t levelDepth = std::max<std::uint32_t>(1u, depth >> level);
        std::uint64_t rowBytes = 0;
        std::uint64_t rows = levelHeight;
        switch (storage->kind) {
        case DdsStorage::Kind::Blocks:
            rowBytes = (levelWidth + 3) / 4 * storage->bytesPerUnit;
            rows = (levelHeight + 3) / 4;
            break;
        case DdsStorage::Kind::Pairs:
            rowBytes = (levelWidth + 1) / 2 * storage->bytesPerUnit;
            break;
        case DdsStorage::Kind::Pixels:
            rowBytes = (levelWidth * storage->bitsPerPixel + 7) / 8;
            break;
        }
        std::uint64_t levelBytes = 0;
        fits = CheckedMultiply(rowBytes, rows, levelBytes) &&
            CheckedMultiply(levelBytes, levelDepth, levelBytes) &&
            CheckedAdd(required, levelBytes, required);
    }
    if (!fits || !CheckedMultiply(required, layers, required) ||
        required > fileSize - headerBytes) {
        error = "DDS file is shorter than the data its header describes";
        return false;
    }
    return true;
}

bool ValidateDds(const std::vector<std::uint8_t>& bytes, std::uint32_t maximumDimension,
                 std::string& error) {
    return ValidateDdsLayout(bytes.data(), bytes.size(), bytes.size(), maximumDimension, error);
}

// A copy this writer made earlier gets the same full check before it is used
// again; only the headers are read, and the file's size stands for its data.
bool ValidateDdsFile(const std::filesystem::path& path, std::uintmax_t maximumBytes,
                     std::uint32_t maximumDimension) {
    std::error_code ec;
    const auto size = std::filesystem::file_size(path, ec);
    if (ec || size < kDdsHeaderBytes || size > maximumBytes) {
        return false;
    }
    std::array<std::uint8_t, kDdsHeaderBytes + kDdsDx10HeaderBytes> header{};
    const auto wanted = static_cast<std::size_t>(
        std::min<std::uintmax_t>(size, static_cast<std::uintmax_t>(header.size())));
    std::ifstream stream(path, std::ios::binary);
    if (!stream || !stream.read(reinterpret_cast<char*>(header.data()),
                                static_cast<std::streamsize>(wanted))) {
        return false;
    }
    std::string ignored;
    return ValidateDdsLayout(header.data(), wanted, size, maximumDimension, ignored);
}

bool IsWicExtension(const std::string& extension) {
    static constexpr std::array<const char*, 7> supported{
        ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".gif"};
    return std::find(supported.begin(), supported.end(), extension) != supported.end();
}

// RTX Remix loads every folder in rtx-remix/mods, and a mod kept elsewhere is
// often linked in (a gm_poolrooms_rtx junction to a folder outside the game).
// A source reached through such a link may resolve anywhere inside that
// link's own target, but nowhere else. ~gmod_topbr and this writer's own
// folder never qualify.
bool InsideLinkedModFolder(const TextureImportConfig& config,
                           const std::filesystem::path& source,
                           const std::filesystem::path& canonicalSource) {
    if (!source.is_absolute()) return false;
    const auto lexical = source.lexically_normal();
    const auto mods = (config.gameRoot / "rtx-remix" / "mods").lexically_normal();
    if (!IsDescendantOrSame(lexical, mods)) return false;
    // The link itself must still lie below a configured import root.
    const bool belowAllowedRoot = std::any_of(
        config.allowedRoots.begin(), config.allowedRoots.end(),
        [&lexical](const std::filesystem::path& root) {
            return IsDescendantOrSame(lexical, root);
        });
    if (!belowAllowedRoot) return false;

    auto component = lexical.begin();
    for (auto modsComponent = mods.begin(); modsComponent != mods.end(); ++modsComponent) {
        ++component;
    }
    if (component == lexical.end()) return false;
    const auto folder = mods / *component;
    // The source must be inside the folder, not the folder entry itself.
    if (++component == lexical.end()) return false;
    if (IsDescendantOrSame(folder, mods / "~gmod_topbr") ||
        IsDescendantOrSame(folder, config.modDirectory) || !IsLinkEntry(folder)) {
        return false;
    }
    std::error_code ec;
    const auto target = std::filesystem::canonical(folder, ec);
    if (ec || !std::filesystem::is_directory(target, ec)) return false;
    return IsDescendantOrSame(canonicalSource, target);
}

void Fnv1aAdd(std::uint64_t& hash, const void* data, std::size_t size) {
    const auto* cursor = static_cast<const std::uint8_t*>(data);
    for (std::size_t index = 0; index < size; ++index) {
        hash ^= cursor[index];
        hash *= 1099511628211ull;
    }
}

// A texture's name hashes its source bytes and then its bake operations in one
// FNV-1a stream. The two halves are split so the byte half can be remembered;
// the names they produce are unchanged.
std::uint64_t Fnv1aBytes(const std::vector<std::uint8_t>& bytes) {
    std::uint64_t hash = 14695981039346656037ull;
    Fnv1aAdd(hash, bytes.data(), bytes.size());
    return hash;
}

std::uint64_t Fnv1aOperations(std::uint64_t hash,
                              const std::vector<TextureOperation>& operations) {
    for (const auto& operation : operations) {
        const auto kind = static_cast<std::uint8_t>(operation.kind);
        Fnv1aAdd(hash, &kind, sizeof(kind));
        Fnv1aAdd(hash, &operation.color, sizeof(operation.color));
        Fnv1aAdd(hash, &operation.strength, sizeof(operation.strength));
        const auto channel = static_cast<std::uint8_t>(operation.channel);
        Fnv1aAdd(hash, &channel, sizeof(channel));
    }
    return hash;
}

std::string Hex(std::uint64_t value) {
    std::ostringstream output;
    output << std::uppercase << std::hex << std::setfill('0') << std::setw(16) << value;
    return output.str();
}

std::string TextureFileName(TextureRole role, std::uint64_t digest) {
    return std::string(TextureRoleName(role)) + "_" + Hex(digest) + ".dds";
}

// The copy a source with this content hash was imported as, while it is still
// present and valid. Creates and writes nothing.
bool FindUnchangedImport(const TextureImportConfig& config, const std::string& profileId,
                         const TextureInput& input, std::uint64_t contentHash,
                         std::uintmax_t maxBytes, std::uint32_t maxDimension,
                         ImportedTexture& output) {
    const auto filename = TextureFileName(
        input.role, Fnv1aOperations(contentHash, input.operations));
    const auto destination = config.modDirectory / "textures" / profileId / filename;
    std::string error;
    bool exists = false;
    if (!IsDescendantOrSame(destination, config.modDirectory) ||
        !ValidatePlainDirectoryTree(config.gameRoot, destination.parent_path(), error) ||
        !InspectPlainPath(destination, false, exists, error) || !exists ||
        !ValidateDdsFile(destination, maxBytes, maxDimension)) {
        return false;
    }
    output.role = input.role;
    output.absolutePath = destination;
    output.layerAssetPath = "../textures/" + profileId + "/" + filename;
    output.changed = false;
    return true;
}

#ifdef _WIN32
struct Image {
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::vector<std::uint8_t> bgra;
};

void ApplyOperations(Image& image, const std::vector<TextureOperation>& operations) {
    for (const auto& operation : operations) {
        if (operation.kind == TextureOperationKind::Invert) {
            for (std::size_t offset = 0; offset < image.bgra.size(); offset += 4) {
                image.bgra[offset + 0] = static_cast<std::uint8_t>(255 - image.bgra[offset + 0]);
                image.bgra[offset + 1] = static_cast<std::uint8_t>(255 - image.bgra[offset + 1]);
                image.bgra[offset + 2] = static_cast<std::uint8_t>(255 - image.bgra[offset + 2]);
            }
        } else if (operation.kind == TextureOperationKind::Multiply) {
            for (std::size_t offset = 0; offset < image.bgra.size(); offset += 4) {
                image.bgra[offset + 0] = static_cast<std::uint8_t>(std::clamp(
                    image.bgra[offset + 0] * operation.color.z, 0.0f, 255.0f));
                image.bgra[offset + 1] = static_cast<std::uint8_t>(std::clamp(
                    image.bgra[offset + 1] * operation.color.y, 0.0f, 255.0f));
                image.bgra[offset + 2] = static_cast<std::uint8_t>(std::clamp(
                    image.bgra[offset + 2] * operation.color.x, 0.0f, 255.0f));
            }
        } else if (operation.kind == TextureOperationKind::NormalFromHeight) {
            const auto source = image.bgra;
            const auto heightSample = [&source, &image, &operation](int x, int y) {
                x = std::clamp(x, 0, static_cast<int>(image.width) - 1);
                y = std::clamp(y, 0, static_cast<int>(image.height) - 1);
                const auto offset = (static_cast<std::size_t>(y) * image.width +
                                     static_cast<std::size_t>(x)) * 4;
                switch (operation.channel) {
                case HeightChannel::Red: return source[offset + 2] / 255.0f;
                case HeightChannel::Green: return source[offset + 1] / 255.0f;
                case HeightChannel::Blue: return source[offset + 0] / 255.0f;
                case HeightChannel::Alpha: return source[offset + 3] / 255.0f;
                case HeightChannel::Luminance:
                default:
                    return (source[offset + 2] * 0.2126f + source[offset + 1] * 0.7152f +
                            source[offset + 0] * 0.0722f) / 255.0f;
                }
            };
            for (std::uint32_t y = 0; y < image.height; ++y) {
                for (std::uint32_t x = 0; x < image.width; ++x) {
                    const int ix = static_cast<int>(x);
                    const int iy = static_cast<int>(y);
                    const float gx =
                        -heightSample(ix - 1, iy - 1) - 2.0f * heightSample(ix - 1, iy) -
                        heightSample(ix - 1, iy + 1) + heightSample(ix + 1, iy - 1) +
                        2.0f * heightSample(ix + 1, iy) + heightSample(ix + 1, iy + 1);
                    const float gy =
                        -heightSample(ix - 1, iy - 1) - 2.0f * heightSample(ix, iy - 1) -
                        heightSample(ix + 1, iy - 1) + heightSample(ix - 1, iy + 1) +
                        2.0f * heightSample(ix, iy + 1) + heightSample(ix + 1, iy + 1);
                    float nx = -gx * operation.strength;
                    float ny = -gy * operation.strength;
                    float nz = 1.0f;
                    const float inverseLength = 1.0f / std::sqrt(nx * nx + ny * ny + nz * nz);
                    nx *= inverseLength;
                    ny *= inverseLength;
                    nz *= inverseLength;
                    const auto offset = (static_cast<std::size_t>(y) * image.width + x) * 4;
                    image.bgra[offset + 0] = static_cast<std::uint8_t>((nz * 0.5f + 0.5f) * 255.0f);
                    image.bgra[offset + 1] = static_cast<std::uint8_t>((ny * 0.5f + 0.5f) * 255.0f);
                    image.bgra[offset + 2] = static_cast<std::uint8_t>((nx * 0.5f + 0.5f) * 255.0f);
                    image.bgra[offset + 3] = 255;
                }
            }
        }
    }
}

#pragma pack(push, 1)
struct DdsPixelFormat {
    std::uint32_t size;
    std::uint32_t flags;
    std::uint32_t fourCc;
    std::uint32_t rgbBitCount;
    std::uint32_t redMask;
    std::uint32_t greenMask;
    std::uint32_t blueMask;
    std::uint32_t alphaMask;
};

struct DdsHeader {
    std::uint32_t size;
    std::uint32_t flags;
    std::uint32_t height;
    std::uint32_t width;
    std::uint32_t pitch;
    std::uint32_t depth;
    std::uint32_t mipMapCount;
    std::uint32_t reserved[11];
    DdsPixelFormat pixelFormat;
    std::uint32_t caps;
    std::uint32_t caps2;
    std::uint32_t caps3;
    std::uint32_t caps4;
    std::uint32_t reserved2;
};
#pragma pack(pop)

static_assert(sizeof(DdsHeader) == 124, "DDS header layout must be 124 bytes");

std::vector<std::uint8_t> EncodeDds(Image image, bool normalizeNormalMips) {
    std::uint32_t mipCount = 1;
    for (auto dimension = std::max(image.width, image.height); dimension > 1; dimension /= 2) {
        ++mipCount;
    }

    DdsHeader header{};
    header.size = 124;
    header.flags = 0x1u | 0x2u | 0x4u | 0x8u | 0x1000u | 0x20000u;
    header.height = image.height;
    header.width = image.width;
    header.pitch = image.width * 4u;
    header.depth = 1;
    header.mipMapCount = mipCount;
    header.pixelFormat = {32, 0x1u | 0x40u, 0, 32,
                          0x00ff0000u, 0x0000ff00u, 0x000000ffu, 0xff000000u};
    header.caps = 0x1000u | 0x8u | 0x400000u;

    std::vector<std::uint8_t> output;
    output.reserve(128 + image.bgra.size() * 4 / 3 + 64);
    output.insert(output.end(), kDdsMagic.begin(), kDdsMagic.end());
    const auto* headerBytes = reinterpret_cast<const std::uint8_t*>(&header);
    output.insert(output.end(), headerBytes, headerBytes + sizeof(header));

    auto current = std::move(image.bgra);
    auto width = image.width;
    auto height = image.height;
    output.insert(output.end(), current.begin(), current.end());
    while (width > 1 || height > 1) {
        const auto nextWidth = std::max(1u, width / 2u);
        const auto nextHeight = std::max(1u, height / 2u);
        std::vector<std::uint8_t> next(static_cast<std::size_t>(nextWidth) * nextHeight * 4u);
        for (std::uint32_t y = 0; y < nextHeight; ++y) {
            for (std::uint32_t x = 0; x < nextWidth; ++x) {
                std::uint32_t sums[4]{};
                std::uint32_t samples = 0;
                for (std::uint32_t dy = 0; dy < 2 && y * 2 + dy < height; ++dy) {
                    for (std::uint32_t dx = 0; dx < 2 && x * 2 + dx < width; ++dx) {
                        const auto sourceOffset =
                            (static_cast<std::size_t>(y * 2 + dy) * width + x * 2 + dx) * 4;
                        for (int channel = 0; channel < 4; ++channel) {
                            sums[channel] += current[sourceOffset + channel];
                        }
                        ++samples;
                    }
                }
                const auto destinationOffset =
                    (static_cast<std::size_t>(y) * nextWidth + x) * 4;
                for (int channel = 0; channel < 4; ++channel) {
                    next[destinationOffset + channel] =
                        static_cast<std::uint8_t>(sums[channel] / samples);
                }
                if (normalizeNormalMips) {
                    float nx = next[destinationOffset + 2] / 127.5f - 1.0f;
                    float ny = next[destinationOffset + 1] / 127.5f - 1.0f;
                    float nz = next[destinationOffset + 0] / 127.5f - 1.0f;
                    const float lengthSquared = nx * nx + ny * ny + nz * nz;
                    if (lengthSquared > 1.0e-12f) {
                        const float inverseLength = 1.0f / std::sqrt(lengthSquared);
                        nx *= inverseLength;
                        ny *= inverseLength;
                        nz *= inverseLength;
                    } else {
                        nx = 0.0f;
                        ny = 0.0f;
                        nz = 1.0f;
                    }
                    const auto encodeComponent = [](float value) {
                        const float encoded = std::clamp(
                            (value * 0.5f + 0.5f) * 255.0f, 0.0f, 255.0f);
                        return static_cast<std::uint8_t>(encoded + 0.5f);
                    };
                    next[destinationOffset + 0] = encodeComponent(nz);
                    next[destinationOffset + 1] = encodeComponent(ny);
                    next[destinationOffset + 2] = encodeComponent(nx);
                }
            }
        }
        output.insert(output.end(), next.begin(), next.end());
        current = std::move(next);
        width = nextWidth;
        height = nextHeight;
    }
    return output;
}

template <typename T>
class ComObject {
public:
    ~ComObject() { if (value_) value_->Release(); }
    T** Put() { return &value_; }
    T* Get() const { return value_; }
    T* operator->() const { return value_; }
private:
    T* value_ = nullptr;
};

class ComApartment {
public:
    ComApartment() : result_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)),
                     owns_(result_ == S_OK || result_ == S_FALSE) {}
    ~ComApartment() { if (owns_) CoUninitialize(); }
    HRESULT Result() const { return result_; }
private:
    HRESULT result_;
    bool owns_;
};

bool DecodeWithWic(const std::filesystem::path& path, std::uint32_t maximumDimension,
                   std::uintmax_t maximumBytes,
                   Image& image, std::string& error) {
    ComApartment apartment;
    if (FAILED(apartment.Result()) && apartment.Result() != RPC_E_CHANGED_MODE) {
        error = "COM initialization failed";
        return false;
    }

    ComObject<IWICImagingFactory> factory;
    HRESULT result = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.Put()));
    ComObject<IWICBitmapDecoder> decoder;
    ComObject<IWICBitmapFrameDecode> frame;
    ComObject<IWICFormatConverter> converter;
    if (SUCCEEDED(result)) {
        result = factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ,
            WICDecodeMetadataCacheOnLoad, decoder.Put());
    }
    if (SUCCEEDED(result)) result = decoder->GetFrame(0, frame.Put());
    if (SUCCEEDED(result)) result = factory->CreateFormatConverter(converter.Put());
    if (SUCCEEDED(result)) {
        result = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
            WICBitmapDitherTypeNone, nullptr, 0.0, WICBitmapPaletteTypeCustom);
    }
    UINT width = 0;
    UINT height = 0;
    if (SUCCEEDED(result)) result = converter->GetSize(&width, &height);
    std::uintmax_t encodedBytes = 128;
    if (SUCCEEDED(result) && (width == 0 || height == 0 || width > maximumDimension ||
                              height > maximumDimension)) {
        result = E_INVALIDARG;
        error = "decoded texture dimensions exceed the configured safety limit";
    }
    if (SUCCEEDED(result)) {
        auto mipWidth = static_cast<std::uintmax_t>(width);
        auto mipHeight = static_cast<std::uintmax_t>(height);
        while (true) {
            const auto rowBytes = mipWidth * 4u;
            if (encodedBytes > maximumBytes || rowBytes > maximumBytes ||
                mipHeight > (maximumBytes - encodedBytes) / rowBytes) {
                result = E_INVALIDARG;
                error = "decoded texture mip chain exceeds the configured safety limit";
                break;
            }
            encodedBytes += rowBytes * mipHeight;
            if (mipWidth == 1 && mipHeight == 1) break;
            mipWidth = std::max<std::uintmax_t>(1, mipWidth / 2);
            mipHeight = std::max<std::uintmax_t>(1, mipHeight / 2);
        }
    }
    if (SUCCEEDED(result)) {
        const auto rowBytes = static_cast<std::uintmax_t>(width) * 4u;
        const auto baseBytes = rowBytes * height;
        if (rowBytes > std::numeric_limits<UINT>::max() ||
            baseBytes > std::numeric_limits<UINT>::max()) {
            result = E_INVALIDARG;
            error = "decoded texture exceeds the Windows decoder buffer limit";
        }
    }
    if (SUCCEEDED(result)) {
        image.width = width;
        image.height = height;
        image.bgra.resize(static_cast<std::size_t>(width) * height * 4u);
        result = converter->CopyPixels(nullptr, width * 4u,
            static_cast<UINT>(image.bgra.size()), image.bgra.data());
    }
    if (FAILED(result)) {
        if (error.empty()) {
            error = "Windows Imaging Component could not decode the texture (HRESULT " +
                std::to_string(static_cast<unsigned long>(result)) + ")";
        }
        return false;
    }
    return true;
}
#endif

} // namespace

bool SupportsWicConversion() noexcept {
#ifdef _WIN32
    return true;
#else
    return false;
#endif
}

bool SupportsTextureOperations() noexcept {
    return SupportsWicConversion();
}

Result ImportTexture(const TextureImportConfig& config,
                     const std::string& profileId,
                     const TextureInput& input,
                     ImportedTexture& output) {
    std::error_code ec;
    std::filesystem::path source = input.source;
    if (source.is_relative()) {
        // The Lua file API commonly reports paths relative to garrysmod/ or
        // garrysmod/data/. Resolve only these well-known in-install locations.
        const auto& gameRoot = config.gameRoot;
        const std::filesystem::path candidates[]{
            gameRoot / source,
            gameRoot / "garrysmod" / source,
            gameRoot / "garrysmod" / "data" / source,
        };
        for (const auto& candidate : candidates) {
            if (std::filesystem::is_regular_file(candidate, ec)) {
                source = candidate;
                break;
            }
            ec.clear();
        }
    }
    const auto canonicalSource = std::filesystem::canonical(source, ec);
    if (ec || !std::filesystem::is_regular_file(canonicalSource, ec)) {
        return Result::Failure("invalid_texture_path", "texture source is not a readable regular file");
    }

    bool allowed = false;
    for (const auto& root : config.allowedRoots) {
        if (IsDescendantOrSame(canonicalSource, root)) {
            allowed = true;
            break;
        }
    }
    if (!allowed) allowed = InsideLinkedModFolder(config, source, canonicalSource);
    if (!allowed) {
        return Result::Failure("texture_path_outside_allowed_roots",
            "texture source resolves outside the configured import roots");
    }

    // ~gmod_topbr belongs to the client's ToPBR pipeline.  Even though it is
    // below the broad default game-root import boundary, never let this addon
    // read or derive assets from another writer's managed output tree.
    std::error_code protectedEc;
    const auto protectedRoot = std::filesystem::canonical(
        config.gameRoot / "rtx-remix" / "mods" / "~gmod_topbr", protectedEc);
    if (!protectedEc && IsDescendantOrSame(canonicalSource, protectedRoot)) {
        return Result::Failure("protected_texture_path",
            "texture source is inside the protected ~gmod_topbr output tree");
    }

    const auto extension = Lowercase(canonicalSource.extension().string());
    const bool isDds = extension == ".dds";
    if (!isDds && !IsWicExtension(extension)) {
        return Result::Failure("unsupported_texture_format",
            "only DDS and Windows Imaging Component formats are accepted");
    }
#ifndef _WIN32
    if (!isDds) {
        return Result::Failure("texture_conversion_unavailable",
            "this build can only import existing DDS files");
    }
#endif
    // A DDS is only validated and copied, so it is held to its own, far larger
    // limits than an image this writer decodes, bakes and mips itself.
    const auto maxBytes = isDds ? config.maxDdsBytes : config.maxBytes;
    const auto maxDimension = isDds ? config.maxDdsDimension : config.maxDimension;
    if (isDds && !input.operations.empty()) {
        return Result::Failure("dds_bake_unsupported",
            "bake operations require a WIC-decodable source such as PNG; compressed DDS editing is not supported");
    }

    // Every preview re-sends each map. A source with the size and write time
    // it had when it was last read still has the content hash read then, so
    // while its copy exists it is neither read nor hashed again; a 130 MB
    // enhancement map would otherwise cost a full read on every call.
    std::error_code stampEc;
    SourceDigest stamp;
    stamp.size = std::filesystem::file_size(canonicalSource, stampEc);
    if (!stampEc) stamp.writeTime = std::filesystem::last_write_time(canonicalSource, stampEc);
    const bool stamped = !stampEc && config.digests != nullptr;
    if (stamped) {
        const auto known = config.digests->find(canonicalSource);
        if (known != config.digests->end() && known->second.size == stamp.size &&
            known->second.writeTime == stamp.writeTime &&
            FindUnchangedImport(config, profileId, input, known->second.contentHash,
                                maxBytes, maxDimension, output)) {
            return Result::Success(profileId);
        }
    }

    std::vector<std::uint8_t> sourceBytes;
    std::string error;
    if (!ReadFile(canonicalSource, maxBytes, sourceBytes, error)) {
        return Result::Failure("texture_read_failed", error);
    }
    if (isDds && !ValidateDds(sourceBytes, maxDimension, error)) {
        return Result::Failure("invalid_dds", error);
    }
    stamp.contentHash = Fnv1aBytes(sourceBytes);
    if (stamped) {
        if (config.digests->size() >= kMaximumRememberedSources) config.digests->clear();
        (*config.digests)[canonicalSource] = stamp;
    }

    // Derive and validate the content-addressed destination before decoding.
    // An unchanged generated image read here therefore costs one bounded
    // source read and hash, but no WIC decode, bake pass, mip generation, or
    // file rewrite.
    const auto filename = TextureFileName(
        input.role, Fnv1aOperations(stamp.contentHash, input.operations));
    const auto destination = config.modDirectory / "textures" / profileId / filename;
    if (!IsDescendantOrSame(destination, config.modDirectory)) {
        return Result::Failure("unsafe_texture_destination", "computed texture destination escaped the mod directory");
    }
    bool runtimeExists = false;
    if (!InspectPlainPath(config.gameRoot / "rtx-remix", true,
                          runtimeExists, error) || !runtimeExists) {
        if (error.empty()) error = "rtx-remix runtime directory is missing";
        return Result::Failure("unsafe_texture_destination", error);
    }
    const auto destinationDirectory = destination.parent_path();
    if (!EnsurePlainDirectoryTree(config.gameRoot, destinationDirectory, error)) {
        return Result::Failure("unsafe_texture_destination", error);
    }
    bool destinationExists = false;
    if (!InspectPlainPath(destination, false, destinationExists, error)) {
        return Result::Failure("unsafe_texture_destination", error);
    }
    output.role = input.role;
    output.absolutePath = destination;
    output.layerAssetPath = "../textures/" + profileId + "/" + filename;
    if (destinationExists && ValidateDdsFile(destination, maxBytes, maxDimension)) {
        output.changed = false;
        return Result::Success(profileId);
    }

    std::vector<std::uint8_t> ddsBytes;
    if (isDds) {
        ddsBytes = std::move(sourceBytes);
    } else {
#ifdef _WIN32
        Image image;
        if (!DecodeWithWic(canonicalSource, config.maxDimension, config.maxBytes, image, error)) {
            return Result::Failure("texture_decode_failed", error);
        }
        ApplyOperations(image, input.operations);
        ddsBytes = EncodeDds(std::move(image), input.role == TextureRole::Normal);
#else
        return Result::Failure("texture_conversion_unavailable", "unreachable conversion path");
#endif
    }

    if (!ValidatePlainDirectoryTree(config.gameRoot, destinationDirectory, error) ||
        !InspectPlainPath(destination, false, destinationExists, error)) {
        return Result::Failure("unsafe_texture_destination", error);
    }
    if (!AtomicWriteBytes(destination, ddsBytes, error)) {
        return Result::Failure("texture_write_failed", error);
    }
    output.changed = true;
    return Result::Success(profileId);
}

} // namespace advmat::rtx_bridge::detail
