#include "advmat_rtx_bridge/bridge.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <initializer_list>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <winioctl.h>
#endif

using namespace advmat::rtx_bridge;

namespace {

std::string ReadText(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

void PutU32(std::vector<std::uint8_t>& bytes, std::size_t offset, std::uint32_t value) {
    bytes[offset + 0] = static_cast<std::uint8_t>(value);
    bytes[offset + 1] = static_cast<std::uint8_t>(value >> 8u);
    bytes[offset + 2] = static_cast<std::uint8_t>(value >> 16u);
    bytes[offset + 3] = static_cast<std::uint8_t>(value >> 24u);
}

// A DDS file's header fields, and how many data bytes follow the headers.
// The defaults describe one level of 32-bit BGRA pixels.
struct DdsFixture {
    std::uint32_t width = 1;
    std::uint32_t height = 1;
    std::uint32_t depth = 0;
    std::uint32_t mipCount = 0;
    std::uint32_t flags = 0x1u | 0x2u | 0x4u | 0x1000u;  // CAPS, HEIGHT, WIDTH, PIXELFORMAT
    std::uint32_t pixelFlags = 0x1u | 0x40u;            // ALPHAPIXELS, RGB
    std::uint32_t fourCc = 0;
    std::uint32_t bitCount = 32;
    std::uint32_t caps2 = 0;
    bool dx10 = false;
    std::uint32_t dxgiFormat = 0;
    std::uint32_t dimension = 3;                        // TEXTURE2D
    std::uint32_t miscFlag = 0;
    std::uint32_t arraySize = 1;
    std::size_t dataBytes = 0;
};

constexpr std::uint32_t TestFourCc(char a, char b, char c, char d) {
    return static_cast<std::uint32_t>(static_cast<std::uint8_t>(a)) |
        (static_cast<std::uint32_t>(static_cast<std::uint8_t>(b)) << 8u) |
        (static_cast<std::uint32_t>(static_cast<std::uint8_t>(c)) << 16u) |
        (static_cast<std::uint32_t>(static_cast<std::uint8_t>(d)) << 24u);
}

void WriteDds(const std::filesystem::path& path, const DdsFixture& fixture) {
    const std::size_t headers = 128u + (fixture.dx10 ? 20u : 0u);
    std::vector<std::uint8_t> bytes(headers + fixture.dataBytes, 0);
    bytes[0] = 'D'; bytes[1] = 'D'; bytes[2] = 'S'; bytes[3] = ' ';
    PutU32(bytes, 4, 124);
    PutU32(bytes, 8, fixture.flags);
    PutU32(bytes, 12, fixture.height);
    PutU32(bytes, 16, fixture.width);
    PutU32(bytes, 24, fixture.depth);
    PutU32(bytes, 28, fixture.mipCount);
    PutU32(bytes, 76, 32);
    PutU32(bytes, 80, fixture.pixelFlags);
    PutU32(bytes, 84, fixture.fourCc);
    PutU32(bytes, 88, fixture.bitCount);
    if (fixture.bitCount == 32 && !(fixture.pixelFlags & 0x4u)) {
        PutU32(bytes, 92, 0x00ff0000u);
        PutU32(bytes, 96, 0x0000ff00u);
        PutU32(bytes, 100, 0x000000ffu);
        PutU32(bytes, 104, 0xff000000u);
    }
    PutU32(bytes, 108, 0x1000u);  // DDSCAPS_TEXTURE
    PutU32(bytes, 112, fixture.caps2);
    if (fixture.dx10) {
        PutU32(bytes, 128, fixture.dxgiFormat);
        PutU32(bytes, 132, fixture.dimension);
        PutU32(bytes, 136, fixture.miscFlag);
        PutU32(bytes, 140, fixture.arraySize);
    }
    for (std::size_t offset = headers; offset + 3 < bytes.size(); offset += 4) {
        bytes[offset + 0] = 0x10;
        bytes[offset + 1] = 0x20;
        bytes[offset + 2] = 0x30;
        bytes[offset + 3] = 0xff;
    }
    std::filesystem::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
}

void WriteMinimalDds(const std::filesystem::path& path,
                     std::uint32_t width = 1, std::uint32_t height = 1) {
    DdsFixture fixture;
    fixture.width = width;
    fixture.height = height;
    fixture.dataBytes = static_cast<std::size_t>(width) * height * 4u;
    WriteDds(path, fixture);
}

#ifdef _WIN32
void PutU16(std::vector<std::uint8_t>& bytes, std::size_t offset, std::uint16_t value) {
    bytes[offset + 0] = static_cast<std::uint8_t>(value);
    bytes[offset + 1] = static_cast<std::uint8_t>(value >> 8u);
}

void WriteNormalMipFixture(const std::filesystem::path& path) {
    // A 2x2 BGRA BMP containing two +X and two +Z normals. Their raw box
    // average is length ~0.71; the generated 1x1 mip must be renormalized.
    std::vector<std::uint8_t> bytes(70, 0);
    bytes[0] = 'B';
    bytes[1] = 'M';
    PutU32(bytes, 2, static_cast<std::uint32_t>(bytes.size()));
    PutU32(bytes, 10, 54);
    PutU32(bytes, 14, 40);
    PutU32(bytes, 18, 2);
    PutU32(bytes, 22, 2);
    PutU16(bytes, 26, 1);
    PutU16(bytes, 28, 32);
    PutU32(bytes, 34, 16);
    const std::uint8_t pixels[]{
        128, 128, 255, 255, 255, 128, 128, 255,
        128, 128, 255, 255, 255, 128, 128, 255,
    };
    std::copy(std::begin(pixels), std::end(pixels), bytes.begin() + 54);
    std::filesystem::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
}

void WriteBmp(const std::filesystem::path& path, std::uint32_t width, std::uint32_t height) {
    const auto pixelBytes = static_cast<std::size_t>(width) * height * 4u;
    std::vector<std::uint8_t> bytes(54 + pixelBytes, 0x80);
    std::fill(bytes.begin(), bytes.begin() + 54, std::uint8_t{0});
    bytes[0] = 'B';
    bytes[1] = 'M';
    PutU32(bytes, 2, static_cast<std::uint32_t>(bytes.size()));
    PutU32(bytes, 10, 54);
    PutU32(bytes, 14, 40);
    PutU32(bytes, 18, width);
    PutU32(bytes, 22, height);
    PutU16(bytes, 26, 1);
    PutU16(bytes, 28, 32);
    PutU32(bytes, 34, static_cast<std::uint32_t>(pixelBytes));
    std::filesystem::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
}
#endif

// Links a directory the way users link a mod kept elsewhere into
// rtx-remix/mods. On Windows this is a junction (mklink /J), which unlike a
// symbolic link needs neither elevation nor Developer Mode.
bool CreateDirectoryLink(const std::filesystem::path& target,
                         const std::filesystem::path& link) {
#ifdef _WIN32
    std::error_code ec;
    if (!std::filesystem::create_directory(link, ec) || ec) return false;
    const HANDLE handle = CreateFileW(link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        std::filesystem::remove(link, ec);
        return false;
    }
    // REPARSE_DATA_BUFFER's mount-point form: tag, data length, reserved,
    // then substitute/print name offsets and lengths and both NUL-ended names.
    const std::wstring printName = std::filesystem::absolute(target).wstring();
    const std::wstring substituteName = L"\\??\\" + printName;
    const auto substituteBytes = substituteName.size() * sizeof(wchar_t);
    const auto printBytes = printName.size() * sizeof(wchar_t);
    std::vector<std::uint8_t> buffer(16 + substituteBytes + 2 + printBytes + 2, 0);
    PutU32(buffer, 0, static_cast<std::uint32_t>(IO_REPARSE_TAG_MOUNT_POINT));
    PutU16(buffer, 4, static_cast<std::uint16_t>(buffer.size() - 8));
    PutU16(buffer, 8, 0);
    PutU16(buffer, 10, static_cast<std::uint16_t>(substituteBytes));
    PutU16(buffer, 12, static_cast<std::uint16_t>(substituteBytes + 2));
    PutU16(buffer, 14, static_cast<std::uint16_t>(printBytes));
    std::memcpy(buffer.data() + 16, substituteName.data(), substituteBytes);
    std::memcpy(buffer.data() + 16 + substituteBytes + 2, printName.data(), printBytes);
    DWORD returned = 0;
    const bool linked = DeviceIoControl(handle, FSCTL_SET_REPARSE_POINT, buffer.data(),
        static_cast<DWORD>(buffer.size()), nullptr, 0, &returned, nullptr) != FALSE;
    CloseHandle(handle);
    if (!linked) std::filesystem::remove(link, ec);
    return linked;
#else
    std::error_code ec;
    std::filesystem::create_directory_symlink(target, link, ec);
    return !ec;
#endif
}

void WriteText(const std::filesystem::path& path, const std::string& contents) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output << contents;
}

std::string LegacyLayer(const std::vector<std::string>& hashes) {
    std::string output = "#usda 1.0\n(\n    upAxis = \"Z\"\n)\n\n"
                         "over \"RootNode\"\n{\n    over \"Looks\"\n    {\n";
    for (const auto& hash : hashes) {
        output += "        over \"mat_" + hash + "\"\n"
                  "        {\n            over \"Shader\"\n            {\n"
                  "                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@\n"
                  "                float inputs:reflection_roughness_constant = 0.5\n"
                  "            }\n        }\n\n";
    }
    output += "    }\n}\n";
    return output;
}

std::string ModLayer(const std::vector<std::string>& profileIds) {
    std::string output = "#usda 1.0\n(\n"
                         "    customLayerData = {\n"
                         "        string lightspeed_game_name = \"Garry's Mod (x64)\"\n"
                         "        string lightspeed_layer_type = \"replacement\"\n"
                         "    }\n"
                         "    metersPerUnit = 0.01\n"
                         "    subLayers = [\n";
    for (std::size_t index = 0; index < profileIds.size(); ++index) {
        output += "        @./profiles/" + profileIds[index] + ".usda@";
        if (index + 1 < profileIds.size()) output += ',';
        output += '\n';
    }
    output += "    ]\n"
              "    timeCodesPerSecond = 24\n"
              "    upAxis = \"Z\"\n"
              ")\n";
    return output;
}

bool RootReferences(const std::string& rootContents,
                    const std::filesystem::path& layerPath) {
    return rootContents.find("./profiles/" + layerPath.filename().string()) !=
        std::string::npos;
}

bool HasTextureInput(const std::string& layerContents, const std::string& input,
                     const std::string& colorSpace) {
    const auto inputPosition = layerContents.find("asset inputs:" + input + " = @");
    if (inputPosition == std::string::npos) return false;
    const auto inputEnd = layerContents.find("                )", inputPosition);
    if (inputEnd == std::string::npos) return false;
    const auto colorPosition = layerContents.find(
        "colorSpace = \"" + colorSpace + "\"", inputPosition);
    return colorPosition != std::string::npos && colorPosition < inputEnd;
}

bool IsVersionedHashLayer(const std::filesystem::path& path,
                          std::string_view hash) {
    const auto filename = path.filename().string();
    const std::string prefix = "hash_" + std::string(hash) + "_";
    constexpr std::string_view suffix = ".usda";
    return filename.size() == prefix.size() + 16 + suffix.size() &&
        filename.compare(0, prefix.size(), prefix) == 0 &&
        filename.compare(filename.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::vector<std::filesystem::path> FindVersionedHashLayers(
    const std::filesystem::path& profiles, std::string_view hash) {
    std::vector<std::filesystem::path> found;
    std::error_code ec;
    if (!std::filesystem::is_directory(profiles, ec) || ec) return found;
    for (std::filesystem::directory_iterator iterator(profiles, ec), end;
         !ec && iterator != end; iterator.increment(ec)) {
        if (iterator->is_regular_file(ec) && !ec &&
            IsVersionedHashLayer(iterator->path(), hash)) {
            found.push_back(iterator->path());
        }
    }
    assert(!ec);
    std::sort(found.begin(), found.end());
    return found;
}

std::size_t CountRegularFiles(const std::filesystem::path& directory) {
    std::error_code ec;
    if (!std::filesystem::is_directory(directory, ec) || ec) return 0;
    std::size_t count = 0;
    for (std::filesystem::directory_iterator iterator(directory, ec), end;
         !ec && iterator != end; iterator.increment(ec)) {
        if (iterator->is_regular_file(ec) && !ec) ++count;
    }
    assert(!ec);
    return count;
}

std::string HexHash(std::uint64_t value) {
    std::ostringstream output;
    output << std::uppercase << std::hex << std::setfill('0') <<
        std::setw(16) << value;
    return output.str();
}

} // namespace

int main() {
    std::string error;
    std::string canonical;
    assert(ValidateProfileId("material_0123", error));
    assert(!ValidateProfileId("../escape", error));
    assert(CanonicalizeHash("0xabc", canonical, error));
    assert(canonical == "0000000000000ABC");
    assert(!CanonicalizeHash("0x0", canonical, error));
    assert(!CanonicalizeHash("xyz", canonical, error));
    BridgeOperation operation = BridgeOperation::Preview;
    assert(ParseBridgeOperation("", operation, error));
    assert(operation == BridgeOperation::Commit);
    assert(ParseBridgeOperation("PREVIEW", operation, error));
    assert(operation == BridgeOperation::Preview);
    assert(ParseBridgeOperation("restore", operation, error));
    assert(operation == BridgeOperation::Restore);
    assert(ParseBridgeOperation("clear", operation, error));
    assert(operation == BridgeOperation::Clear);
    assert(!ParseBridgeOperation("temporary", operation, error));

    Config defaults;
    assert(defaults.maxTextureBytes == 32ull * 1024ull * 1024ull);
    assert(defaults.maxTextureDimension == 2048);
    // A DDS is copied, never decoded: rpai's 4096 px maps and an 11059 x 8847
    // sheet (130 MB as BC7) must fit as they are.
    assert(defaults.maxDdsTextureBytes == 512ull * 1024ull * 1024ull);
    assert(defaults.maxDdsTextureDimension == 16384);
    assert(kMaxTextureOperations == 4);

    const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto temporaryRoot = std::filesystem::temp_directory_path() /
        ("advmat_rtx_writer_test_" + std::to_string(nonce));
    std::filesystem::create_directories(temporaryRoot / "garrysmod" / "data");
    std::filesystem::create_directories(temporaryRoot / "rtx-remix" / "mods");
    // The bridge canonicalizes its game root, and %TEMP% may be an 8.3 short
    // path (C:\Users\NAME~1\...). Spell every expected path the same way.
    const auto root = std::filesystem::canonical(temporaryRoot);
    const auto nestedExecutable = root / "bin" / "win64" / "gmod.exe";
    WriteText(nestedExecutable, "test executable placeholder");
    const auto discoveredRoot = FindGameRootFromExecutable(nestedExecutable);
    assert(discoveredRoot && *discoveredRoot == root.lexically_normal());
    assert(!FindGameRootFromExecutable("bin/win64/gmod.exe"));

    auto tooDeepDirectory = root;
    for (std::size_t index = 0; index < kMaxGameRootAncestorDepth + 1; ++index) {
        tooDeepDirectory /= "nested";
    }
    const auto tooDeepExecutable = tooDeepDirectory / "gmod.exe";
    WriteText(tooDeepExecutable, "test executable placeholder");
    assert(!FindGameRootFromExecutable(tooDeepExecutable));

    const auto source = root / "garrysmod" / "data" / "source.dds";
    WriteMinimalDds(source);

    Config config;
    config.gameRoot = root;
    Bridge bridge(std::move(config));
    const auto capabilities = bridge.GetCapabilities();
    assert(capabilities.available);
    assert(capabilities.livePreview && capabilities.reversiblePreview);
    assert(capabilities.authoritativeReset);
    assert(capabilities.synchronous);
    assert(capabilities.maxTextureBytes == kDefaultMaxTextureBytes);
    assert(capabilities.maxTextureDimension == kDefaultMaxTextureDimension);
    assert(capabilities.maxDdsTextureBytes == kDefaultMaxDdsTextureBytes);
    assert(capabilities.maxDdsTextureDimension == kDefaultMaxDdsTextureDimension);
    assert(capabilities.maxTextureOperations == kMaxTextureOperations);
    ApplyRequest request;
    request.profileId = "material_0123456789ABCDEF";
    request.hashes = {"0x0123456789abcdef", "0123456789ABCDF0"};
    request.material.albedo = Vec3{0.8f, 0.7f, 0.6f};
    request.material.roughness = 0.25f;
    request.material.metallic = 0.75f;
    request.material.spriteSheetRows = 2;
    request.material.spriteSheetColumns = 3;
    request.material.spriteSheetFps = 4;
    request.material.filterMode = 1;
    request.material.wrapModeU = 1;
    request.material.wrapModeV = 2;
    request.material.blendType = 8;
    request.material.alphaTestType = 7;
    request.material.alphaReferenceValue = 0.5f;
    request.material.textures.push_back({TextureRole::Albedo, source, {}});

    const auto expectedMod = root / "rtx-remix" / "mods" / "!advanced_material_editor";

    // Destination containment is physical, not merely lexical. Exercise both
    // a junction/symlink present during construction and components planted
    // after provider discovery. Windows may require Developer Mode for test
    // symlink creation, so each attack case is conditional on host support.
    const auto linkedRoot = root / "linked_game";
    const auto linkedExternal = root / "linked_external";
    std::filesystem::create_directories(linkedRoot / "garrysmod" / "data");
    std::filesystem::create_directories(linkedRoot / "rtx-remix");
    WriteText(linkedExternal / "keep.txt", "outside constructor sentinel");
    std::error_code linkError;
    std::filesystem::create_directory_symlink(
        linkedExternal, linkedRoot / "rtx-remix" / "mods", linkError);
    if (!linkError) {
        Config linkedConfig;
        linkedConfig.gameRoot = linkedRoot;
        Bridge linkedBridge(std::move(linkedConfig));
        assert(!linkedBridge.GetCapabilities().available);
        assert(ReadText(linkedExternal / "keep.txt") == "outside constructor sentinel");
    }

    const auto redirectedRoot = root / "redirected_game";
    const auto redirectedExternal = root / "redirected_external";
    const auto redirectedSource = redirectedRoot / "garrysmod" / "data" / "source.dds";
    std::filesystem::create_directories(redirectedRoot / "garrysmod" / "data");
    std::filesystem::create_directories(redirectedRoot / "rtx-remix" / "mods");
    WriteMinimalDds(redirectedSource);
    WriteText(redirectedExternal / "keep.txt", "outside runtime sentinel");
    Config redirectedConfig;
    redirectedConfig.gameRoot = redirectedRoot;
    Bridge redirectedBridge(std::move(redirectedConfig));
    assert(redirectedBridge.GetCapabilities().available);
    ApplyRequest redirectedRequest = request;
    redirectedRequest.material.textures.front().source = redirectedSource;
    const auto redirectedMods = redirectedRoot / "rtx-remix" / "mods";
    const auto redirectedMod = redirectedMods / "!advanced_material_editor";

    linkError.clear();
    std::filesystem::remove(redirectedMods, linkError);
    assert(!linkError);
    std::filesystem::create_directory_symlink(redirectedExternal, redirectedMods, linkError);
    if (!linkError) {
        const auto redirectedAncestor = redirectedBridge.ApplyLegacyMaterial(redirectedRequest);
        assert(!redirectedAncestor.ok);
        assert(ReadText(redirectedExternal / "keep.txt") == "outside runtime sentinel");
        assert(!std::filesystem::exists(redirectedExternal / "!advanced_material_editor"));
        std::filesystem::remove(redirectedMods, linkError);
        assert(!linkError);
    } else {
        linkError.clear();
    }
    std::filesystem::create_directories(redirectedMod);

    linkError.clear();
    std::filesystem::create_directory_symlink(
        redirectedExternal, redirectedMod / "textures", linkError);
    if (!linkError) {
        const auto redirectedTexture = redirectedBridge.ApplyLegacyMaterial(redirectedRequest);
        assert(!redirectedTexture.ok);
        assert(ReadText(redirectedExternal / "keep.txt") == "outside runtime sentinel");
        std::filesystem::remove(redirectedMod / "textures", linkError);
        assert(!linkError);
    } else {
        linkError.clear();
    }

    const auto redirectedTextureDirectory = redirectedMod / "textures";
    std::filesystem::create_directories(redirectedTextureDirectory);
    const auto redirectedNestedTexture = redirectedTextureDirectory / "nested_reparse";
    linkError.clear();
    std::filesystem::create_directory_symlink(
        redirectedExternal, redirectedNestedTexture, linkError);
    if (!linkError) {
        const auto redirectedNested =
            redirectedBridge.ApplyLegacyMaterial(redirectedRequest);
        assert(!redirectedNested.ok);
        assert(ReadText(redirectedExternal / "keep.txt") == "outside runtime sentinel");
        std::filesystem::remove(redirectedNestedTexture, linkError);
        assert(!linkError);
    } else {
        linkError.clear();
    }
    std::filesystem::remove(redirectedTextureDirectory, linkError);
    assert(!linkError);

    linkError.clear();
    std::filesystem::create_directory_symlink(
        redirectedExternal, redirectedMod / "profiles", linkError);
    if (!linkError) {
        auto redirectedProfileRequest = redirectedRequest;
        redirectedProfileRequest.material.textures.clear();
        const auto redirectedProfile =
            redirectedBridge.ApplyLegacyMaterial(redirectedProfileRequest);
        assert(!redirectedProfile.ok);
        assert(ReadText(redirectedExternal / "keep.txt") == "outside runtime sentinel");
        std::filesystem::remove(redirectedMod / "profiles", linkError);
        assert(!linkError);
    } else {
        linkError.clear();
    }

    const auto redirectedExternalRoot = redirectedExternal / "external_mod.usda";
    WriteText(redirectedExternalRoot, "outside root sentinel");
    linkError.clear();
    std::filesystem::create_symlink(
        redirectedExternalRoot, redirectedMod / "mod.usda", linkError);
    if (!linkError) {
        const auto redirectedRootLayer =
            redirectedBridge.ApplyLegacyMaterial(redirectedRequest);
        assert(!redirectedRootLayer.ok);
        assert(ReadText(redirectedExternalRoot) == "outside root sentinel");
        std::filesystem::remove(redirectedMod / "mod.usda", linkError);
        assert(!linkError);
    }

    auto invalidSpriteSheet = request;
    invalidSpriteSheet.material.spriteSheetRows = 0;
    const auto invalidRows = bridge.ApplyLegacyMaterial(invalidSpriteSheet);
    assert(!invalidRows.ok && invalidRows.code == "invalid_material");
    invalidSpriteSheet = request;
    invalidSpriteSheet.material.spriteSheetColumns = 0;
    const auto invalidColumns = bridge.ApplyLegacyMaterial(invalidSpriteSheet);
    assert(!invalidColumns.ok && invalidColumns.code == "invalid_material");
    assert(!std::filesystem::exists(expectedMod));

    request.operation = BridgeOperation::Preview;
    const auto preview = bridge.ApplyLegacyMaterial(request);
    assert(preview.ok);
    assert(ReadText(expectedMod / "mod.usda").find("advmat-preview-base-begin") != std::string::npos);
    assert(bridge.RestorePreview(request.profileId).ok);
    assert(ReadText(expectedMod / "mod.usda") == ModLayer({}));
    request.operation = BridgeOperation::Commit;

    const auto applied = bridge.ApplyLegacyMaterial(request);
    if (!applied.ok) {
        std::cerr << applied.code << ": " << applied.message << '\n';
        return 1;
    }
    assert(bridge.ModDirectory() == expectedMod);
    assert(std::filesystem::is_regular_file(applied.layerPath));
    assert(applied.layerPaths.size() == 2);
    assert(IsVersionedHashLayer(applied.layerPaths[0], "0123456789ABCDEF"));
    assert(IsVersionedHashLayer(applied.layerPaths[1], "0123456789ABCDF0"));
    assert(applied.importedTextures.size() == 1);
    assert(std::filesystem::is_regular_file(applied.importedTextures.front()));

    const auto firstProfileText = ReadText(applied.layerPaths[0]);
    const auto secondProfileText = ReadText(applied.layerPaths[1]);
    assert(firstProfileText.find("mat_0123456789ABCDEF") != std::string::npos);
    assert(firstProfileText.find("mat_0123456789ABCDF0") == std::string::npos);
    assert(secondProfileText.find("mat_0123456789ABCDF0") != std::string::npos);
    assert(secondProfileText.find("mat_0123456789ABCDEF") == std::string::npos);
    assert(firstProfileText.find("AperturePBR_Opacity.mdl") != std::string::npos);
    assert(firstProfileText.find("subIdentifier = \"AperturePBR_Opacity\"") !=
        std::string::npos);
    assert(firstProfileText.find("reflection_roughness_constant = 0.25") != std::string::npos);
    assert(firstProfileText.find("metallic_constant = 0.75") != std::string::npos);
    assert(firstProfileText.find("diffuse_texture") != std::string::npos);
    assert(firstProfileText.find("int inputs:sprite_sheet_rows = 2") != std::string::npos);
    assert(firstProfileText.find("int inputs:sprite_sheet_cols = 3") != std::string::npos);
    assert(firstProfileText.find("int inputs:sprite_sheet_fps = 4") != std::string::npos);
    assert(firstProfileText.find("int inputs:filter_mode = 1") != std::string::npos);
    assert(firstProfileText.find("int inputs:wrap_mode_u = 1") != std::string::npos);
    assert(firstProfileText.find("int inputs:wrap_mode_v = 2") != std::string::npos);
    assert(firstProfileText.find("bool inputs:blend_enabled = 1") != std::string::npos);
    assert(firstProfileText.find("int inputs:blend_type = 8") != std::string::npos);
    assert(firstProfileText.find("int inputs:alpha_test_type = 7") != std::string::npos);
    assert(firstProfileText.find("float inputs:alpha_test_reference_value = 0.5") !=
        std::string::npos);
    assert(firstProfileText.find("uchar inputs:") == std::string::npos);

    const auto modText = ReadText(expectedMod / "mod.usda");
    assert(RootReferences(modText, applied.layerPaths[0]));
    assert(RootReferences(modText, applied.layerPaths[1]));
    assert(modText.find("./profiles/material_0123456789ABCDEF.usda") == std::string::npos);
    assert(modText.find("~gmod_topbr") == std::string::npos);

    // Reapplying an unchanged profile must reuse the content-addressed DDS and
    // avoid touching either USDA layer. This is important because calls are
    // synchronous on the game's client thread.
    const auto oldTime = std::filesystem::file_time_type::clock::now() -
        std::chrono::hours(24);
    std::filesystem::last_write_time(applied.layerPath, oldTime);
    std::filesystem::last_write_time(applied.layerPaths[1], oldTime);
    std::filesystem::last_write_time(expectedMod / "mod.usda", oldTime);
    std::filesystem::last_write_time(applied.importedTextures.front(), oldTime);
    const auto oldProfileTime = std::filesystem::last_write_time(applied.layerPath);
    const auto oldSecondProfileTime = std::filesystem::last_write_time(applied.layerPaths[1]);
    const auto oldModTime = std::filesystem::last_write_time(expectedMod / "mod.usda");
    const auto oldTextureTime = std::filesystem::last_write_time(applied.importedTextures.front());
    const auto reapplied = bridge.ApplyLegacyMaterial(request);
    assert(reapplied.ok);
    assert(reapplied.layerPaths == applied.layerPaths);
    assert(std::filesystem::last_write_time(applied.layerPath) == oldProfileTime);
    assert(std::filesystem::last_write_time(applied.layerPaths[1]) == oldSecondProfileTime);
    assert(std::filesystem::last_write_time(expectedMod / "mod.usda") == oldModTime);
    assert(std::filesystem::last_write_time(applied.importedTextures.front()) == oldTextureTime);

    const auto previewAfterCommit = [&]() {
        auto previewRequest = request;
        previewRequest.operation = BridgeOperation::Preview;
        return bridge.ApplyLegacyMaterial(previewRequest);
    }();
    assert(previewAfterCommit.ok);
    assert(bridge.RestorePreview(request.profileId).ok);
    assert(std::filesystem::last_write_time(applied.layerPath) == oldProfileTime);
    assert(std::filesystem::last_write_time(applied.layerPaths[1]) == oldSecondProfileTime);
    assert(ReadText(expectedMod / "mod.usda") == ModLayer({
        applied.layerPaths[0].stem().string(), applied.layerPaths[1].stem().string()}));
    assert(std::filesystem::last_write_time(applied.importedTextures.front()) == oldTextureTime);

    // A multi-hash update is staged into new immutable revisions. Failure after
    // the first staged layer must leave both previously active revisions and
    // the root activation ledger byte-for-byte intact.
    const auto committedRootText = ReadText(expectedMod / "mod.usda");
    int stagedLayerCount = 0;
    Config midStageFailureConfig;
    midStageFailureConfig.gameRoot = root;
    midStageFailureConfig.failureInjector = [&stagedLayerCount](std::string_view point) {
        if (point != "apply_after_stage_layer") return false;
        ++stagedLayerCount;
        return stagedLayerCount == 1;
    };
    Bridge midStageFailureBridge(std::move(midStageFailureConfig));
    ApplyRequest changedRequest = request;
    changedRequest.material.roughness = 0.9f;
    const auto midStageFailure = midStageFailureBridge.ApplyLegacyMaterial(changedRequest);
    assert(!midStageFailure.ok && midStageFailure.code == "injected_failure");
    assert(stagedLayerCount == 1);
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);
    assert(ReadText(applied.layerPaths[0]) == firstProfileText);
    assert(ReadText(applied.layerPaths[1]) == secondProfileText);
    assert(RootReferences(ReadText(expectedMod / "mod.usda"), applied.layerPaths[0]));
    assert(RootReferences(ReadText(expectedMod / "mod.usda"), applied.layerPaths[1]));
    assert(FindVersionedHashLayers(expectedMod / "profiles",
        "0123456789ABCDEF").size() == 1);
    assert(FindVersionedHashLayers(expectedMod / "profiles",
        "0123456789ABCDF0").size() == 1);

    // Failure after every new revision is durable but before publication has
    // the same all-old result; active-ledger cleanup removes the inert staged
    // files before the failure is returned.
    bool reachedPrePublish = false;
    Config prePublishFailureConfig;
    prePublishFailureConfig.gameRoot = root;
    prePublishFailureConfig.failureInjector = [&reachedPrePublish](std::string_view point) {
        if (point != "apply_before_root_publish") return false;
        reachedPrePublish = true;
        return true;
    };
    Bridge prePublishFailureBridge(std::move(prePublishFailureConfig));
    changedRequest.material.roughness = 0.8f;
    const auto prePublishFailure =
        prePublishFailureBridge.ApplyLegacyMaterial(changedRequest);
    assert(!prePublishFailure.ok && prePublishFailure.code == "injected_failure");
    assert(reachedPrePublish);
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);
    assert(ReadText(applied.layerPaths[0]) == firstProfileText);
    assert(ReadText(applied.layerPaths[1]) == secondProfileText);
    assert(FindVersionedHashLayers(expectedMod / "profiles",
        "0123456789ABCDEF").size() == 1);
    assert(FindVersionedHashLayers(expectedMod / "profiles",
        "0123456789ABCDF0").size() == 1);

    // Failure after creating a new map and profile revision removes both
    // transaction-owned orphans while the old root remains active.
    ApplyRequest failedGeneration = request;
    failedGeneration.profileId = "failed_transaction";
    failedGeneration.hashes = {"00000000FA11ED01"};
    failedGeneration.material.textures.clear();
    failedGeneration.material.textures.push_back(
        {TextureRole::Anisotropy, source, {}});
    const auto failedGenerationResult =
        prePublishFailureBridge.ApplyLegacyMaterial(failedGeneration);
    assert(!failedGenerationResult.ok &&
        failedGenerationResult.code == "injected_failure");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);
    assert(!std::filesystem::exists(expectedMod / "textures" / "failed_transaction"));
    assert(FindVersionedHashLayers(expectedMod / "profiles",
        "00000000FA11ED01").empty());

    ApplyRequest tooManyOperations = request;
    tooManyOperations.profileId = "operation_limit";
    tooManyOperations.material.textures.front().operations.assign(
        kMaxTextureOperations + 1, TextureOperation{});
    const auto operationLimit = bridge.ApplyLegacyMaterial(tooManyOperations);
    assert(!operationLimit.ok && operationLimit.code == "invalid_material");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    ApplyRequest invalidBlend = request;
    invalidBlend.material.blendType = 9;
    const auto blendLimit = bridge.ApplyLegacyMaterial(invalidBlend);
    assert(!blendLimit.ok && blendLimit.code == "invalid_material");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    ApplyRequest invalidFilter = request;
    invalidFilter.material.filterMode = 2;
    const auto filterLimit = bridge.ApplyLegacyMaterial(invalidFilter);
    assert(!filterLimit.ok && filterLimit.code == "invalid_material");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    ApplyRequest invalidWrap = request;
    invalidWrap.material.wrapModeU = 4;
    const auto wrapLimit = bridge.ApplyLegacyMaterial(invalidWrap);
    assert(!wrapLimit.ok && wrapLimit.code == "invalid_material");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    for (const int invalidAlphaTest : {-1, 8}) {
        ApplyRequest invalidAlpha = request;
        invalidAlpha.material.alphaTestType = invalidAlphaTest;
        const auto alphaLimit = bridge.ApplyLegacyMaterial(invalidAlpha);
        assert(!alphaLimit.ok && alphaLimit.code == "invalid_material");
        assert(ReadText(expectedMod / "mod.usda") == committedRootText);
    }

    const auto oversizedDimensionSource = root / "garrysmod" / "data" / "too_wide.dds";
    WriteMinimalDds(oversizedDimensionSource, kDefaultMaxDdsTextureDimension + 1, 1);
    ApplyRequest oversizedDimension = request;
    oversizedDimension.profileId = "dimension_limit";
    oversizedDimension.material.textures.front().source = oversizedDimensionSource;
    const auto dimensionLimit = bridge.ApplyLegacyMaterial(oversizedDimension);
    assert(!dimensionLimit.ok && dimensionLimit.code == "invalid_dds");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    ApplyRequest partialTextureFailure = request;
    partialTextureFailure.profileId = "partial_texture_failure";
    partialTextureFailure.material.textures.clear();
    partialTextureFailure.material.textures.push_back(
        {TextureRole::Anisotropy, source, {}});
    partialTextureFailure.material.textures.push_back(
        {TextureRole::Normal, oversizedDimensionSource, {}});
    const auto partialTextureResult = bridge.ApplyLegacyMaterial(partialTextureFailure);
    assert(!partialTextureResult.ok && partialTextureResult.code == "invalid_dds");
    assert(!std::filesystem::exists(
        expectedMod / "textures" / "partial_texture_failure"));
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    const auto protectedSource =
        root / "rtx-remix" / "mods" / "~gmod_topbr" / "protected.dds";
    WriteMinimalDds(protectedSource);
    ApplyRequest protectedInput = request;
    protectedInput.profileId = "protected_input";
    protectedInput.material.textures.front().source = protectedSource;
    const auto protectedResult = bridge.ApplyLegacyMaterial(protectedInput);
    assert(!protectedResult.ok && protectedResult.code == "protected_texture_path");
    assert(ReadText(expectedMod / "mod.usda") == committedRootText);

    assert(!bridge.ClearLegacyMaterial({request.profileId, {}}).ok);
    const auto cleared = bridge.ClearLegacyMaterial(
        {request.profileId, {"0x0123456789ABCDEF"}});
    assert(cleared.ok);
    // The just-disabled revision remains as the single previous generation.
    // Only the atomically published root decides which revisions are active.
    assert(std::filesystem::is_regular_file(applied.layerPaths[0]));
    assert(std::filesystem::is_regular_file(applied.layerPaths[1]));
    assert(std::filesystem::is_regular_file(cleared.layerPath));
    const auto clearedModText = ReadText(expectedMod / "mod.usda");
    assert(!RootReferences(clearedModText, applied.layerPaths[0]));
    assert(RootReferences(clearedModText, applied.layerPaths[1]));
    // An exact-hash clear is deliberately idempotent and cannot touch the
    // surviving hash layer for the same Source material.
    std::filesystem::last_write_time(cleared.layerPath, oldTime);
    std::filesystem::last_write_time(applied.layerPaths[1], oldTime);
    std::filesystem::last_write_time(expectedMod / "mod.usda", oldTime);
    const auto survivingTime = std::filesystem::last_write_time(applied.layerPaths[1]);
    const auto oldClearedModTime = std::filesystem::last_write_time(expectedMod / "mod.usda");
    assert(bridge.ClearLegacyMaterial(
        {request.profileId, {"0x0123456789ABCDEF"}}).ok);
    assert(!std::filesystem::exists(cleared.layerPath));
    assert(std::filesystem::last_write_time(applied.layerPaths[1]) == survivingTime);
    assert(std::filesystem::last_write_time(expectedMod / "mod.usda") == oldClearedModTime);

    assert(bridge.ClearLegacyMaterial(
        {request.profileId, {"0x0123456789ABCDF0"}}).ok);
    assert(std::filesystem::is_regular_file(applied.layerPaths[1]));
    const auto fullyClearedModText = ReadText(expectedMod / "mod.usda");
    assert(fullyClearedModText.find("hash_0123456789ABCDEF") == std::string::npos);
    assert(fullyClearedModText.find("hash_0123456789ABCDF0") == std::string::npos);

    // Migrate an aggregate material_<id> layer from the pre-hash layout, then
    // clear only one hash. The other raw shader block must survive in its own
    // layer, and retrying the retired hash must remain harmless.
    const std::string legacyHash1 = "000000000000AAA1";
    const std::string legacyHash2 = "000000000000AAA2";
    const std::string legacyProfile = "material_legacy_migration";
    const auto legacyPath = expectedMod / "profiles" / (legacyProfile + ".usda");
    const auto legacyContents = LegacyLayer({legacyHash1, legacyHash2});
    WriteText(legacyPath, legacyContents);
    WriteText(expectedMod / "mod.usda", ModLayer({legacyProfile}));
    const auto migratedClear = bridge.ClearLegacyMaterial(
        {legacyProfile, {legacyHash1}});
    assert(migratedClear.ok);
    const auto migratedHash1Layers = FindVersionedHashLayers(
        expectedMod / "profiles", legacyHash1);
    const auto migratedHash2Layers = FindVersionedHashLayers(
        expectedMod / "profiles", legacyHash2);
    assert(migratedHash1Layers.size() == 1);
    assert(migratedHash2Layers.size() == 1);
    const auto& migratedHash1 = migratedHash1Layers.front();
    const auto& migratedHash2 = migratedHash2Layers.front();
    assert(std::filesystem::is_regular_file(migratedHash1));
    assert(std::filesystem::is_regular_file(migratedHash2));
    assert(std::filesystem::is_regular_file(legacyPath));
    assert(ReadText(legacyPath) == legacyContents);
    const auto migratedModText = ReadText(expectedMod / "mod.usda");
    assert(!RootReferences(migratedModText, legacyPath));
    assert(!RootReferences(migratedModText, migratedHash1));
    assert(RootReferences(migratedModText, migratedHash2));
    const auto migratedHash2Text = ReadText(migratedHash2);
    assert(migratedHash2Text.find("mat_" + legacyHash2) != std::string::npos);
    const auto migratedRootBeforeRetry = ReadText(expectedMod / "mod.usda");
    assert(bridge.ClearLegacyMaterial({legacyProfile, {legacyHash1}}).ok);
    assert(!std::filesystem::exists(legacyPath));
    assert(!std::filesystem::exists(migratedHash1));
    assert(std::filesystem::is_regular_file(migratedHash2));
    assert(ReadText(expectedMod / "mod.usda") == migratedRootBeforeRetry);
    assert(bridge.ClearLegacyMaterial({legacyProfile, {legacyHash2}}).ok);
    assert(std::filesystem::is_regular_file(migratedHash2));
    assert(ReadText(expectedMod / "mod.usda").find("hash_") == std::string::npos);

    // Every edit begins by pruning files not referenced by the current root,
    // then leaves at most the just-superseded generation for watcher safety.
    // Repeated successful edits therefore stay bounded within one session.
    const std::string churnHash = "00000000C0FFEE01";
    ApplyRequest churnRequest = request;
    churnRequest.profileId = "bounded_churn";
    churnRequest.hashes = {churnHash};
    for (std::uint32_t revision = 1; revision <= 12; ++revision) {
        const auto churnSource = root / "garrysmod" / "data" /
            ("churn_" + std::to_string(revision) + ".dds");
        WriteMinimalDds(churnSource, revision, 1);
        churnRequest.material.roughness = revision / 16.0f;
        churnRequest.material.textures.clear();
        churnRequest.material.textures.push_back(
            {TextureRole::Albedo, churnSource, {}});
        const auto churnApply = bridge.ApplyLegacyMaterial(churnRequest);
        assert(churnApply.ok && churnApply.layerPaths.size() == 1);
    }
    const auto churnLayers = FindVersionedHashLayers(
        expectedMod / "profiles", churnHash);
    assert(churnLayers.size() == 2);
    assert(CountRegularFiles(expectedMod / "textures" / "bounded_churn") == 2);
    assert(bridge.ClearLegacyMaterial({"bounded_churn", {churnHash}}).ok);

    // Populate a larger active generation. ClearAllOwned must deactivate the
    // entire set with one root publication, then retire the profile and texture
    // generations with fixed directory renames independent of layer count.
    ApplyRequest scaleRequest = request;
    scaleRequest.profileId = "material_authoritative_reset_scale";
    scaleRequest.hashes.clear();
    for (std::uint64_t index = 0; index < 64; ++index) {
        scaleRequest.hashes.push_back(HexHash(0x1000u + index));
    }
    const auto resetApply = bridge.ApplyLegacyMaterial(scaleRequest);
    assert(resetApply.ok && resetApply.layerPaths.size() == 64);
    const std::string resetLegacyProfile = "material_authoritative_reset";
    const auto resetLegacyPath = expectedMod / "profiles" /
        (resetLegacyProfile + ".usda");
    WriteText(resetLegacyPath, LegacyLayer({legacyHash1}));
    std::vector<std::string> resetActiveIds;
    resetActiveIds.reserve(resetApply.layerPaths.size() + 1);
    for (const auto& path : resetApply.layerPaths) {
        resetActiveIds.push_back(path.stem().string());
    }
    resetActiveIds.push_back(resetLegacyProfile);
    WriteText(expectedMod / "mod.usda", ModLayer(resetActiveIds));
    const auto retainedTexture = resetApply.importedTextures.front();
    assert(std::filesystem::is_regular_file(retainedTexture));

    // A failure before the empty-root commit cannot change activation.
    const auto activeRootBeforeReset = ReadText(expectedMod / "mod.usda");
    Config resetBeforeConfig;
    resetBeforeConfig.gameRoot = root;
    resetBeforeConfig.failureInjector = [](std::string_view point) {
        return point == "reset_before_root_publish";
    };
    Bridge resetBeforeBridge(std::move(resetBeforeConfig));
    const auto resetBeforeFailure = resetBeforeBridge.ClearAllOwned();
    assert(!resetBeforeFailure.ok && resetBeforeFailure.code == "injected_failure");
    assert(ReadText(expectedMod / "mod.usda") == activeRootBeforeReset);
    assert(std::filesystem::is_directory(expectedMod / "profiles"));

    // A simulated crash immediately after the empty-root commit leaves every
    // old layer on disk but none active. A retry may then retire the directory
    // without risking reactivation.
    Config resetAfterConfig;
    resetAfterConfig.gameRoot = root;
    resetAfterConfig.failureInjector = [](std::string_view point) {
        return point == "reset_after_root_publish";
    };
    Bridge resetAfterBridge(std::move(resetAfterConfig));
    const auto resetAfterFailure = resetAfterBridge.ClearAllOwned();
    assert(!resetAfterFailure.ok &&
        resetAfterFailure.code == "injected_failure_after_commit");
    const auto emptyRootText = ReadText(expectedMod / "mod.usda");
    assert(emptyRootText == ModLayer({}));
    assert(std::filesystem::is_directory(expectedMod / "profiles"));
    for (const auto& path : resetApply.layerPaths) {
        assert(std::filesystem::is_regular_file(path));
        assert(!RootReferences(emptyRootText, path));
    }

    // A failure between the two retirement renames is already past the empty
    // root commit. Profiles may be quarantined while textures remain in their
    // active cache path; retry must still rotate textures even though profiles/
    // no longer exists.
    Config resetBetweenConfig;
    resetBetweenConfig.gameRoot = root;
    resetBetweenConfig.failureInjector = [](std::string_view point) {
        return point == "reset_after_profile_retire";
    };
    Bridge resetBetweenBridge(std::move(resetBetweenConfig));
    const auto resetBetweenFailure = resetBetweenBridge.ClearAllOwned();
    assert(!resetBetweenFailure.ok &&
        resetBetweenFailure.code == "injected_failure_after_commit");
    const auto retiredProfiles = expectedMod / "profiles.retired";
    const auto retiredTextures = expectedMod / "textures.retired";
    assert(std::filesystem::is_directory(retiredProfiles));
    assert(!std::filesystem::exists(expectedMod / "profiles"));
    assert(std::filesystem::is_directory(expectedMod / "textures"));
    assert(!std::filesystem::exists(retiredTextures));
    for (const auto& path : resetApply.layerPaths) {
        assert(std::filesystem::is_regular_file(retiredProfiles / path.filename()));
    }
    assert(std::filesystem::is_regular_file(retiredProfiles / resetLegacyPath.filename()));
    assert(std::filesystem::is_regular_file(retainedTexture));

    const auto reset = bridge.ClearAllOwned();
    assert(reset.ok && reset.layerPaths.empty());
    const auto retainedTextureRelative = retainedTexture.lexically_relative(
        expectedMod / "textures");
    assert(!retainedTextureRelative.empty());
    assert(!std::filesystem::exists(expectedMod / "textures"));
    assert(std::filesystem::is_regular_file(
        retiredTextures / retainedTextureRelative));
    const auto resetModText = ReadText(expectedMod / "mod.usda");
    assert(resetModText == ModLayer({}));

    // Authoritative reset is idempotent and avoids needless watcher reloads.
    std::filesystem::last_write_time(expectedMod / "mod.usda", oldTime);
    const auto resetModTime = std::filesystem::last_write_time(expectedMod / "mod.usda");
    const auto repeatedReset = bridge.ClearAllOwned();
    assert(repeatedReset.ok && repeatedReset.layerPaths.empty());
    assert(std::filesystem::last_write_time(expectedMod / "mod.usda") == resetModTime);
    assert(std::filesystem::is_directory(retiredProfiles));
    assert(std::filesystem::is_directory(retiredTextures));
    assert(std::filesystem::is_regular_file(
        retiredTextures / retainedTextureRelative));

    // A later generation creates a fresh profiles/ directory. The retired
    // generation remains outside the sole root ledger and cannot reactivate.
    ApplyRequest postResetRequest = request;
    postResetRequest.hashes = {"00000000FEEDFACE"};
    const auto postResetApply = bridge.ApplyLegacyMaterial(postResetRequest);
    assert(postResetApply.ok && postResetApply.layerPaths.size() == 1);
    assert(postResetApply.importedTextures.size() == 1);
    const auto postResetTexture = postResetApply.importedTextures.front();
    assert(std::filesystem::is_regular_file(postResetTexture));
    const auto postResetRoot = ReadText(expectedMod / "mod.usda");
    assert(RootReferences(postResetRoot, postResetApply.layerPaths.front()));
    assert(postResetRoot.find(retiredProfiles.filename().string()) == std::string::npos);
    assert(std::filesystem::is_directory(retiredProfiles));

    // A second populated reset replaces both fixed quarantines instead of
    // creating per-session directories. A sentinel in the older texture cache
    // proves that replacement happened rather than another generation being
    // accumulated beside it.
    WriteText(retiredTextures / "old_generation.marker", "old texture generation");
    const auto rotatedReset = bridge.ClearAllOwned();
    assert(rotatedReset.ok && rotatedReset.layerPaths.size() == 1);
    assert(rotatedReset.layerPaths.front() == retiredProfiles);
    assert(std::filesystem::is_regular_file(
        retiredProfiles / postResetApply.layerPaths.front().filename()));
    assert(!std::filesystem::exists(
        retiredProfiles / resetApply.layerPaths.front().filename()));
    assert(!std::filesystem::exists(retiredTextures / "old_generation.marker"));
    const auto postResetTextureRelative = postResetTexture.lexically_relative(
        expectedMod / "textures");
    assert(!postResetTextureRelative.empty());
    assert(!std::filesystem::exists(expectedMod / "textures"));
    assert(std::filesystem::is_regular_file(
        retiredTextures / postResetTextureRelative));
    std::size_t profileRetirementDirectories = 0;
    std::size_t textureRetirementDirectories = 0;
    for (const auto& entry : std::filesystem::directory_iterator(expectedMod)) {
        const auto name = entry.path().filename().string();
        if (name == "profiles.retired" || name.rfind("profiles.tmp.", 0) == 0) {
            ++profileRetirementDirectories;
        }
        if (name == "textures.retired" || name.rfind("textures.tmp.", 0) == 0) {
            ++textureRetirementDirectories;
        }
    }
    assert(profileRetirementDirectories == 1);
    assert(textureRetirementDirectories == 1);

    // Refuse planted quarantine symlinks/junctions rather than allowing
    // recursive cleanup to cross the fixed mod boundary. Cover both a nested
    // entry and the exact quarantine root. Symlink creation may require
    // Developer Mode on Windows, so each assertion is conditional on support.
    const auto reparseApply = bridge.ApplyLegacyMaterial(postResetRequest);
    assert(reparseApply.ok && reparseApply.importedTextures.size() == 1);
    const auto externalTextureDirectory = root / "external_texture_sentinel";
    const auto externalTextureSentinel = externalTextureDirectory / "keep.txt";
    WriteText(externalTextureSentinel, "outside texture sentinel");
    std::error_code reparseError;
    const auto nestedReparse = retiredTextures / "planted_reparse";
    std::filesystem::create_directory_symlink(
        externalTextureDirectory, nestedReparse, reparseError);
    if (!reparseError) {
        const auto unsafeNestedRetirement = bridge.ClearAllOwned();
        assert(!unsafeNestedRetirement.ok &&
            unsafeNestedRetirement.code == "authoritative_reset_retire_failed_after_commit");
        assert(ReadText(expectedMod / "mod.usda") == ModLayer({}));
        assert(ReadText(externalTextureSentinel) == "outside texture sentinel");
        assert(std::filesystem::is_directory(expectedMod / "textures"));
        std::filesystem::remove(nestedReparse, reparseError);
        assert(!reparseError);
        const auto recoveredNestedRetirement = bridge.ClearAllOwned();
        assert(recoveredNestedRetirement.ok);
        assert(ReadText(externalTextureSentinel) == "outside texture sentinel");
    } else {
        reparseError.clear();
        const auto ordinaryNestedRetirement = bridge.ClearAllOwned();
        assert(ordinaryNestedRetirement.ok);
        assert(ReadText(externalTextureSentinel) == "outside texture sentinel");
    }

    const auto rootReparseApply = bridge.ApplyLegacyMaterial(postResetRequest);
    assert(rootReparseApply.ok && rootReparseApply.importedTextures.size() == 1);
    reparseError.clear();
    std::filesystem::remove_all(retiredTextures, reparseError);
    assert(!reparseError);
    reparseError.clear();
    std::filesystem::create_directory_symlink(
        externalTextureDirectory, retiredTextures, reparseError);
    if (!reparseError) {
        const auto unsafeRetirement = bridge.ClearAllOwned();
        assert(!unsafeRetirement.ok &&
            unsafeRetirement.code == "authoritative_reset_retire_failed_after_commit");
        assert(ReadText(expectedMod / "mod.usda") == ModLayer({}));
        assert(ReadText(externalTextureSentinel) == "outside texture sentinel");
        assert(std::filesystem::is_directory(expectedMod / "textures"));
        std::filesystem::remove(retiredTextures, reparseError);
        assert(!reparseError);
        const auto recoveredRetirement = bridge.ClearAllOwned();
        assert(recoveredRetirement.ok);
        assert(ReadText(externalTextureSentinel) == "outside texture sentinel");
        assert(!std::filesystem::exists(expectedMod / "textures"));
        assert(std::filesystem::is_directory(retiredTextures));
    } else {
        reparseError.clear();
        const auto ordinaryRetirement = bridge.ClearAllOwned();
        assert(ordinaryRetirement.ok);
        assert(ReadText(externalTextureSentinel) == "outside texture sentinel");
    }

    ApplyRequest unsafe = request;
    unsafe.profileId = "../outside";
    assert(!bridge.ApplyLegacyMaterial(unsafe).ok);
    unsafe = request;
    unsafe.hashes = {"not-a-hash"};
    assert(!bridge.ApplyLegacyMaterial(unsafe).ok);

    // The active ledger parser never accepts paths outside the fixed profiles
    // namespace. Authoritative reset can still recover from a malformed root,
    // and its retirement cannot touch the referenced outside file.
    const auto outsideSentinel = expectedMod.parent_path() / "outside.usda";
    WriteText(outsideSentinel, "outside sentinel");
    WriteText(expectedMod / "mod.usda",
        "#usda 1.0\n(\n    subLayers = [\n"
        "        @../outside.usda@\n    ]\n)\n");
    const auto unsafeRootApply = bridge.ApplyLegacyMaterial(postResetRequest);
    assert(!unsafeRootApply.ok && unsafeRootApply.code == "mod_index_read_failed");
    assert(ReadText(outsideSentinel) == "outside sentinel");
    const auto recoveredReset = bridge.ClearAllOwned();
    assert(recoveredReset.ok);
    assert(ReadText(expectedMod / "mod.usda") == ModLayer({}));
    assert(ReadText(outsideSentinel) == "outside sentinel");

    // AperturePBR exposes an anisotropy map. It has no tangent_texture input,
    // so the native role, content-addressed name, and USDA token must agree.
    assert(std::string(TextureRoleName(TextureRole::Anisotropy)) == "anisotropy");
    ApplyRequest anisotropyRequest = request;
    anisotropyRequest.profileId = "anisotropy_contract";
    anisotropyRequest.hashes = {"00000000A11507F1"};
    anisotropyRequest.material.textures.clear();
    anisotropyRequest.material.textures.push_back(
        {TextureRole::Anisotropy, source, {}});
    const auto anisotropyApply = bridge.ApplyLegacyMaterial(anisotropyRequest);
    assert(anisotropyApply.ok && anisotropyApply.layerPaths.size() == 1);
    assert(anisotropyApply.importedTextures.size() == 1);
    assert(anisotropyApply.importedTextures.front().filename().string().rfind(
        "anisotropy_", 0) == 0);
    const auto anisotropyLayer = ReadText(anisotropyApply.layerPaths.front());
    assert(anisotropyLayer.find("asset inputs:anisotropy_texture") != std::string::npos);
    assert(anisotropyLayer.find("tangent_texture") == std::string::npos);

    // RTX Remix 1.5.2's AperturePBR_Opacity contract. Exercise every texture
    // role and subsurface constant together so the unique-role bound, USDA
    // input names, and MDL-declared colour spaces cannot drift independently.
    assert(kTextureRoleCount == 11);
    assert(std::string(TextureRoleName(TextureRole::SubsurfaceTransmittance)) ==
           "subsurface_transmittance");
    assert(std::string(TextureRoleName(TextureRole::SubsurfaceThickness)) ==
           "subsurface_thickness");
    assert(std::string(TextureRoleName(TextureRole::SubsurfaceScattering)) ==
           "subsurface_scattering");
    assert(std::string(TextureRoleName(TextureRole::SubsurfaceRadius)) ==
           "subsurface_radius");

    ApplyRequest aperture152Request = request;
    aperture152Request.profileId = "aperture_152_contract";
    aperture152Request.hashes = {"0000000015200001"};
    aperture152Request.material.textures.clear();
    for (std::size_t role = 0; role < kTextureRoleCount; ++role) {
        aperture152Request.material.textures.push_back(
            {static_cast<TextureRole>(role), source, {}});
    }
    aperture152Request.material.subsurfaceTransmittanceColor =
        Vec3{0.1f, 0.2f, 0.3f};
    aperture152Request.material.subsurfaceMeasurementDistance = 16.0f;
    aperture152Request.material.subsurfaceSingleScatteringAlbedo =
        Vec3{0.4f, 0.5f, 0.6f};
    aperture152Request.material.subsurfaceVolumetricAnisotropy = -0.99f;
    aperture152Request.material.subsurfaceRadius = Vec3{0.7f, 0.8f, 0.9f};
    aperture152Request.material.subsurfaceRadiusScale = 1000.0f;
    aperture152Request.material.subsurfaceMaxSampleRadius = 65504.0f;
    aperture152Request.material.normalEncoding = 1;
    // Explicit false must win over every legacy inference trigger below.
    aperture152Request.material.enableThinFilm = false;
    aperture152Request.material.thinFilmThickness = 200.0f;
    aperture152Request.material.alphaIsThinFilmThickness = true;
    aperture152Request.material.enableEmission = false;
    aperture152Request.material.emissiveIntensity = 40.0f;
    aperture152Request.material.preloadTextures = false;
    aperture152Request.material.ignoreMaterial = true;
    aperture152Request.material.blendEnabled = false;
    aperture152Request.material.blendType = 8;
    aperture152Request.material.subsurfaceDiffusionProfile = true;
    aperture152Request.material.wrapModeU = 3;
    aperture152Request.material.alphaTestType = 6;

    const auto aperture152Apply = bridge.ApplyLegacyMaterial(aperture152Request);
    assert(aperture152Apply.ok && aperture152Apply.layerPaths.size() == 1);
    assert(aperture152Apply.importedTextures.size() == kTextureRoleCount);
    const auto aperture152Layer = ReadText(aperture152Apply.layerPaths.front());
    assert(HasTextureInput(aperture152Layer, "diffuse_texture", "sRGB"));
    assert(HasTextureInput(aperture152Layer, "normalmap_texture", "raw"));
    assert(HasTextureInput(aperture152Layer, "anisotropy_texture", "raw"));
    assert(HasTextureInput(aperture152Layer, "reflectionroughness_texture", "raw"));
    assert(HasTextureInput(aperture152Layer, "metallic_texture", "raw"));
    assert(HasTextureInput(aperture152Layer, "height_texture", "raw"));
    assert(HasTextureInput(aperture152Layer, "emissive_mask_texture", "sRGB"));
    assert(HasTextureInput(aperture152Layer,
                           "subsurface_transmittance_texture", "sRGB"));
    assert(HasTextureInput(aperture152Layer,
                           "subsurface_thickness_texture", "raw"));
    assert(HasTextureInput(aperture152Layer,
                           "subsurface_single_scattering_texture", "sRGB"));
    assert(HasTextureInput(aperture152Layer,
                           "subsurface_radius_texture", "raw"));
    assert(aperture152Layer.find(
        "color3f inputs:subsurface_transmittance_color = (0.100000001, 0.200000003, 0.300000012)") !=
        std::string::npos);
    assert(aperture152Layer.find(
        "float inputs:subsurface_measurement_distance = 16") != std::string::npos);
    assert(aperture152Layer.find(
        "color3f inputs:subsurface_single_scattering_albedo = (0.400000006, 0.5, 0.600000024)") !=
        std::string::npos);
    assert(aperture152Layer.find(
        "float inputs:subsurface_volumetric_anisotropy = -0.99000001") !=
        std::string::npos);
    assert(aperture152Layer.find(
        "color3f inputs:subsurface_radius = (0.699999988, 0.800000012, 0.899999976)") !=
        std::string::npos);
    assert(aperture152Layer.find(
        "float inputs:subsurface_radius_scale = 1000") != std::string::npos);
    assert(aperture152Layer.find(
        "float inputs:subsurface_max_sample_radius = 65504") != std::string::npos);
    assert(aperture152Layer.find("int inputs:encoding = 1") != std::string::npos);
    assert(aperture152Layer.find("bool inputs:enable_thin_film = 0") !=
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:enable_thin_film = 1") ==
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:enable_emission = 0") !=
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:enable_emission = 1") ==
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:preload_textures = 0") !=
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:preload_textures = 1") ==
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:ignore_material = 1") !=
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:blend_enabled = 0") !=
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:blend_enabled = 1") ==
        std::string::npos);
    assert(aperture152Layer.find("bool inputs:subsurface_diffusion_profile = 1") !=
        std::string::npos);
    assert(aperture152Layer.find("int inputs:wrap_mode_u = 3") != std::string::npos);
    assert(aperture152Layer.find("int inputs:alpha_test_type = 6") !=
        std::string::npos);

    // Every AlphaTestType and normal-map encoding value declared by the MDLs
    // is accepted, while values immediately outside each enum remain invalid.
    ApplyRequest enumRequest = aperture152Request;
    enumRequest.profileId = "aperture_152_enums";
    enumRequest.hashes = {"0000000015200002"};
    enumRequest.material.textures.clear();
    for (int alphaTest = 0; alphaTest <= 7; ++alphaTest) {
        enumRequest.material.alphaTestType = alphaTest;
        const auto enumApply = bridge.ApplyLegacyMaterial(enumRequest);
        assert(enumApply.ok);
    }
    for (int encoding = 0; encoding <= 2; ++encoding) {
        enumRequest.material.normalEncoding = encoding;
        const auto enumApply = bridge.ApplyLegacyMaterial(enumRequest);
        assert(enumApply.ok);
    }
    for (const int invalidEncoding : {-1, 3}) {
        enumRequest.material.normalEncoding = invalidEncoding;
        const auto enumApply = bridge.ApplyLegacyMaterial(enumRequest);
        assert(!enumApply.ok && enumApply.code == "invalid_material");
    }

    // Check every new hard range just beyond the 1.5.2 MDL boundary.
    auto invalid152 = aperture152Request;
    invalid152.material.subsurfaceTransmittanceColor = Vec3{1.01f, 0.0f, 0.0f};
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);
    invalid152 = aperture152Request;
    invalid152.material.subsurfaceMeasurementDistance = 16.01f;
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);
    invalid152 = aperture152Request;
    invalid152.material.subsurfaceSingleScatteringAlbedo = Vec3{0.0f, -0.01f, 0.0f};
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);
    invalid152 = aperture152Request;
    invalid152.material.subsurfaceVolumetricAnisotropy = 1.0f;
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);
    invalid152 = aperture152Request;
    invalid152.material.subsurfaceRadius = Vec3{0.0f, 0.0f, 1.01f};
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);
    invalid152 = aperture152Request;
    invalid152.material.subsurfaceRadiusScale = 1000.01f;
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);
    invalid152 = aperture152Request;
    invalid152.material.subsurfaceMaxSampleRadius = 65504.01f;
    assert(!bridge.ApplyLegacyMaterial(invalid152).ok);

    // Protocol-1 requests without explicit flags retain their prior inferred
    // writer behaviour. New requests can override every one of these above.
    ApplyRequest legacyInference = request;
    legacyInference.profileId = "legacy_flag_inference";
    legacyInference.hashes = {"0000000015200003"};
    legacyInference.material.textures.clear();
    legacyInference.material.textures.push_back({TextureRole::Normal, source, {}});
    legacyInference.material.emissiveIntensity = 1.0f;
    legacyInference.material.thinFilmThickness = 100.0f;
    const auto legacyInferenceApply = bridge.ApplyLegacyMaterial(legacyInference);
    assert(legacyInferenceApply.ok);
    const auto legacyInferenceLayer = ReadText(legacyInferenceApply.layerPaths.front());
    assert(legacyInferenceLayer.find("bool inputs:preload_textures = 1") !=
        std::string::npos);
    assert(legacyInferenceLayer.find("int inputs:encoding = 2") != std::string::npos);
    assert(legacyInferenceLayer.find("bool inputs:enable_emission = 1") !=
        std::string::npos);
    assert(legacyInferenceLayer.find("bool inputs:enable_thin_film = 1") !=
        std::string::npos);
    assert(legacyInferenceLayer.find("bool inputs:blend_enabled = 1") !=
        std::string::npos);

#ifdef _WIN32
    const auto normalMipSource = root / "garrysmod" / "data" / "normal_mips.bmp";
    WriteNormalMipFixture(normalMipSource);
    ApplyRequest normalMipRequest = request;
    normalMipRequest.profileId = "normal_mip_contract";
    normalMipRequest.hashes = {"00000000A11CE001"};
    normalMipRequest.material.textures.clear();
    normalMipRequest.material.textures.push_back(
        {TextureRole::Normal, normalMipSource, {}});
    const auto normalMipApply = bridge.ApplyLegacyMaterial(normalMipRequest);
    assert(normalMipApply.ok && normalMipApply.importedTextures.size() == 1);
    std::ifstream normalDds(normalMipApply.importedTextures.front(), std::ios::binary);
    normalDds.seekg(128 + 2 * 2 * 4);
    std::uint8_t normalMip[4]{};
    normalDds.read(reinterpret_cast<char*>(normalMip),
                   static_cast<std::streamsize>(sizeof(normalMip)));
    assert(normalDds);
    const float mipX = normalMip[2] / 127.5f - 1.0f;
    const float mipY = normalMip[1] / 127.5f - 1.0f;
    const float mipZ = normalMip[0] / 127.5f - 1.0f;
    const float mipLength = std::sqrt(mipX * mipX + mipY * mipY + mipZ * mipZ);
    assert(mipLength > 0.98f && mipLength < 1.02f);
    assert(normalMip[0] > 210 && normalMip[2] > 210);
#endif

    // Preview rollback is independent of profile persistence and retains both
    // the saved and displayed dependencies throughout repeated cache pruning.
    {
        const auto previewRoot = root / "preview_game";
        std::filesystem::create_directories(previewRoot / "rtx-remix");
        Config previewConfig;
        previewConfig.gameRoot = previewRoot;
        bool failPublish = false;
        bool failRestore = false;
        previewConfig.failureInjector = [&](std::string_view point) {
            return (failPublish && point == "apply_before_root_publish") ||
                   (failRestore && point == "preview_before_restore");
        };
        const auto mod = previewRoot / "rtx-remix/mods/!advanced_material_editor/mod.usda";
        ApplyRequest saved;
        saved.profileId = "material_preview";
        saved.hashes = {"AA", "BB"};
        saved.material.roughness = 0.2f;
        const auto savedSource = previewRoot / "garrysmod/data/saved.dds";
        WriteMinimalDds(savedSource);
        saved.material.textures.push_back({TextureRole::Albedo, savedSource, {}});
        std::string interruptedRoot;
        std::string latestRoot;
        {
            Bridge writer(previewConfig);
            const auto original = writer.ApplyLegacyMaterial(saved);
            assert(original.ok);
            const auto originalRoot = ReadText(mod);
            auto draft = saved;
            draft.operation = BridgeOperation::Preview;
            draft.hashes = {"AA"};
            draft.material.textures.clear();
            for (int i = 0; i < 12; ++i) {
                draft.material.roughness = 0.4f + i * 0.01f;
                assert(writer.ApplyLegacyMaterial(draft).ok);
            }
            assert(std::filesystem::exists(original.layerPaths[0]));
            assert(std::filesystem::exists(original.importedTextures[0]));
            assert(writer.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod) == originalRoot);
            assert(writer.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod) == originalRoot);

            assert(writer.ApplyLegacyMaterial(draft).ok);
            const auto visible = ReadText(mod);
            failPublish = true;
            draft.material.roughness = 0.99f;
            assert(!writer.ApplyLegacyMaterial(draft).ok);
            assert(ReadText(mod) == visible);
            failPublish = false;
            failRestore = true;
            assert(!writer.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod) == visible);
            failRestore = false;

            // A simultaneous commit updates the rollback baseline, without
            // overwriting the draft which the user is currently inspecting.
            saved.material.roughness = 0.1f;
            const auto latest = writer.ApplyLegacyMaterial(saved);
            assert(latest.ok);
            latestRoot = ModLayer({latest.layerPaths[0].stem().string(),
                                   latest.layerPaths[1].stem().string()});
            interruptedRoot = ReadText(mod);
            assert(interruptedRoot != latestRoot);
            assert(writer.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod) == latestRoot);

            auto other = draft;
            other.profileId = "material_other";
            other.hashes = {"CC"};
            assert(writer.ApplyLegacyMaterial(draft).ok);
            const auto otherResult = writer.ApplyLegacyMaterial(other);
            assert(otherResult.ok);
            assert(writer.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod).find(otherResult.layerPath.stem().string()) != std::string::npos);
            assert(writer.RestorePreview(other.profileId).ok);
            assert(ReadText(mod) == latestRoot);

            // Normal unload drops unsaved overlays, even without a Lua close.
            assert(writer.ApplyLegacyMaterial(draft).ok);
        }
        assert(ReadText(mod) == latestRoot);
        // Simulate process termination: the atomic root alone must contain
        // enough rollback information for the next provider to recover.
        WriteText(mod, interruptedRoot);
        {
            Bridge recovered(previewConfig);
            assert(recovered.GetCapabilities().available);
            assert(ReadText(mod) == latestRoot);
            auto draft = saved;
            draft.operation = BridgeOperation::Preview;
            assert(recovered.ApplyLegacyMaterial(draft).ok);
            assert(recovered.ClearLegacyMaterial({saved.profileId, {"AA"}}).ok);
            assert(recovered.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod).find("hash_00000000000000AA_") == std::string::npos);
            assert(recovered.ApplyLegacyMaterial(draft).ok);
            assert(recovered.ClearAllOwned().ok);
            assert(recovered.RestorePreview(saved.profileId).ok);
            assert(ReadText(mod) == ModLayer({}));
        }
        assert(ReadText(mod) == ModLayer({}));
    }

    // A DDS is validated and copied, never decoded, so it has limits of its
    // own: far larger by default, and independent of the decode/bake limits.
    {
        const auto limitRoot = root / "dds_limit_game";
        const auto data = limitRoot / "garrysmod" / "data";
        std::filesystem::create_directories(data);
        std::filesystem::create_directories(limitRoot / "rtx-remix");

        // With the defaults, a map twice the decode limit goes in as it is.
        Config wideConfig;
        wideConfig.gameRoot = limitRoot;
        Bridge wideBridge(std::move(wideConfig));
        const auto wideSource = data / "wide.dds";
        WriteMinimalDds(wideSource, kDefaultMaxTextureDimension * 2, 4);
        ApplyRequest wide;
        wide.profileId = "material_dds_limits";
        wide.hashes = {"00000000DD500001"};
        wide.material.textures.push_back({TextureRole::Albedo, wideSource, {}});
        const auto wideApply = wideBridge.ApplyLegacyMaterial(wide);
        assert(wideApply.ok && wideApply.importedTextures.size() == 1);
        assert(ReadText(wideApply.importedTextures.front()) == ReadText(wideSource));
        assert(wideBridge.ClearAllOwned().ok);

        Config limitConfig;
        limitConfig.gameRoot = limitRoot;
        limitConfig.maxTextureBytes = 4096;
        limitConfig.maxTextureDimension = 8;
        limitConfig.maxDdsTextureBytes = 128 + 64 * 64 * 4;
        limitConfig.maxDdsTextureDimension = 64;
        Bridge limitBridge(std::move(limitConfig));
        const auto limitCapabilities = limitBridge.GetCapabilities();
        assert(limitCapabilities.available);
        assert(limitCapabilities.maxTextureBytes == 4096);
        assert(limitCapabilities.maxTextureDimension == 8);
        assert(limitCapabilities.maxDdsTextureBytes == 128 + 64 * 64 * 4);
        assert(limitCapabilities.maxDdsTextureDimension == 64);

        // Exactly at both DDS limits, and well over both decode limits.
        const auto atLimit = data / "at_limit.dds";
        WriteMinimalDds(atLimit, 64, 64);
        ApplyRequest limited;
        limited.profileId = "material_dds_limits";
        limited.hashes = {"00000000DD500002"};
        limited.material.textures.push_back({TextureRole::Albedo, atLimit, {}});
        const auto atLimitApply = limitBridge.ApplyLegacyMaterial(limited);
        assert(atLimitApply.ok && atLimitApply.importedTextures.size() == 1);
        assert(ReadText(atLimitApply.importedTextures.front()) == ReadText(atLimit));
        const auto limitedMod =
            limitRoot / "rtx-remix" / "mods" / "!advanced_material_editor" / "mod.usda";
        const auto limitedRoot = ReadText(limitedMod);

        ApplyRequest overLimit = limited;
        overLimit.hashes = {"00000000DD500003"};
        WriteMinimalDds(data / "too_wide.dds", 65, 1);
        overLimit.material.textures.front().source = data / "too_wide.dds";
        const auto tooWide = limitBridge.ApplyLegacyMaterial(overLimit);
        assert(!tooWide.ok && tooWide.code == "invalid_dds");

        const auto tooHeavy = data / "too_heavy.dds";
        WriteMinimalDds(tooHeavy, 64, 64);
        {
            std::ofstream append(tooHeavy, std::ios::binary | std::ios::app);
            append.put('\0');
        }
        overLimit.material.textures.front().source = tooHeavy;
        const auto heavy = limitBridge.ApplyLegacyMaterial(overLimit);
        assert(!heavy.ok && heavy.code == "texture_read_failed");

        // Bake operations still need a decoded image, whatever the DDS size.
        overLimit.material.textures.front().source = atLimit;
        overLimit.material.textures.front().operations = {TextureOperation{}};
        const auto baked = limitBridge.ApplyLegacyMaterial(overLimit);
        assert(!baked.ok && baked.code == "dds_bake_unsupported");
        assert(ReadText(limitedMod) == limitedRoot);

#ifdef _WIN32
        // An image the writer decodes keeps the conservative limits.
        overLimit.material.textures.front().operations.clear();
        WriteBmp(data / "decoded_wide.bmp", 16, 16);
        overLimit.material.textures.front().source = data / "decoded_wide.bmp";
        const auto decodedWide = limitBridge.ApplyLegacyMaterial(overLimit);
        assert(!decodedWide.ok && decodedWide.code == "texture_decode_failed");
        assert(ReadText(limitedMod) == limitedRoot);
        WriteBmp(data / "decoded.bmp", 8, 8);
        overLimit.material.textures.front().source = data / "decoded.bmp";
        assert(limitBridge.ApplyLegacyMaterial(overLimit).ok);
#endif
    }

    // A DDS is checked against its own size before it is copied: a known
    // format, a mip count its dimensions allow (16 at most, all the runtime
    // records), sane faces and array layers, and every byte the header
    // describes present. A copy made earlier gets the same check before it is
    // used again (R19, BR-03).
    {
        const auto layoutRoot = root / "dds_layout_game";
        const auto data = layoutRoot / "garrysmod" / "data";
        std::filesystem::create_directories(data);
        std::filesystem::create_directories(layoutRoot / "rtx-remix");
        Config layoutConfig;
        layoutConfig.gameRoot = layoutRoot;
        Bridge layoutBridge(std::move(layoutConfig));
        std::uint64_t nextHash = 0xD0000001ull;
        const auto apply = [&](const std::filesystem::path& source) {
            ApplyRequest dds;
            dds.profileId = "material_dds_layout";
            std::ostringstream hash;
            hash << std::uppercase << std::hex << std::setw(16) << std::setfill('0') << nextHash++;
            dds.hashes = {hash.str()};
            dds.material.textures.push_back({TextureRole::Albedo, source, {}});
            return layoutBridge.ApplyLegacyMaterial(dds);
        };
        const auto refused = [&](const char* name, const DdsFixture& fixture) {
            WriteDds(data / name, fixture);
            const auto result = apply(data / name);
            return !result.ok && result.code == "invalid_dds";
        };

        // Accepted: full mip chains of 32-bit pixels, BC1 and BC7 (DX10).
        DdsFixture pixels;
        pixels.width = 8;
        pixels.height = 4;
        pixels.mipCount = 4;
        pixels.flags |= 0x20000u;  // MIPMAPCOUNT
        pixels.dataBytes = (8 * 4 + 4 * 2 + 2 * 1 + 1 * 1) * 4;
        WriteDds(data / "pixels.dds", pixels);
        const auto pixelsApply = apply(data / "pixels.dds");
        assert(pixelsApply.ok && pixelsApply.importedTextures.size() == 1);

        DdsFixture bc1;
        bc1.width = 16;
        bc1.height = 16;
        bc1.mipCount = 5;
        bc1.flags |= 0x20000u;
        bc1.pixelFlags = 0x4u;  // FOURCC
        bc1.fourCc = TestFourCc('D', 'X', 'T', '1');
        bc1.bitCount = 0;
        bc1.dataBytes = (16 + 4 + 1 + 1 + 1) * 8;
        WriteDds(data / "bc1.dds", bc1);
        assert(apply(data / "bc1.dds").ok);

        DdsFixture bc7;
        bc7.width = 8;
        bc7.height = 8;
        bc7.mipCount = 4;
        bc7.flags |= 0x20000u;
        bc7.pixelFlags = 0x4u;
        bc7.fourCc = TestFourCc('D', 'X', '1', '0');
        bc7.bitCount = 0;
        bc7.dx10 = true;
        bc7.dxgiFormat = 98;  // BC7_UNORM
        bc7.dataBytes = (4 + 1 + 1 + 1) * 16;
        WriteDds(data / "bc7.dds", bc7);
        assert(apply(data / "bc7.dds").ok);

        // More mips than the runtime records, or than the dimensions allow.
        for (const std::uint32_t mips : {17u, 18u, 0x80000000u}) {
            DdsFixture many = pixels;
            many.mipCount = mips;
            many.dataBytes = 64 * 1024;
            assert(refused("too_many_mips.dds", many));
        }
        DdsFixture deep = pixels;
        deep.mipCount = 5;  // an 8 x 4 texture has 4 levels
        deep.dataBytes = 64 * 1024;
        assert(refused("deep_mips.dds", deep));

        // Headers whose data is missing: none at all, one byte short, or a
        // DX10 header cut off.
        DdsFixture headerOnly;
        headerOnly.width = 4;
        headerOnly.height = 4;
        assert(refused("header_only.dds", headerOnly));
        DdsFixture shortData = headerOnly;
        shortData.dataBytes = 4 * 4 * 4 - 1;
        assert(refused("short_data.dds", shortData));
        DdsFixture shortChain = pixels;
        shortChain.dataBytes -= 4;
        assert(refused("short_chain.dds", shortChain));
        DdsFixture cutDx10 = bc7;
        cutDx10.dx10 = false;  // the FourCC says DX10; its header is not there
        cutDx10.dataBytes = 0;
        assert(refused("cut_dx10.dds", cutDx10));

        // Array sizes, dimensions and formats the header cannot have.
        for (const std::uint32_t layers : {0u, 2049u, 0xFFFFFFFFu}) {
            DdsFixture array = bc7;
            array.arraySize = layers;
            assert(refused("array.dds", array));
        }
        DdsFixture bigArray = bc7;
        bigArray.arraySize = 2048;  // allowed, but the data for one layer is not enough
        assert(refused("big_array.dds", bigArray));
        DdsFixture badDimension = bc7;
        badDimension.dimension = 5;
        assert(refused("bad_dimension.dds", badDimension));
        DdsFixture planar = bc7;
        planar.dxgiFormat = 103;  // NV12
        assert(refused("planar.dds", planar));
        DdsFixture unknown = bc1;
        unknown.fourCc = TestFourCc('A', 'B', 'C', 'D');
        assert(refused("unknown.dds", unknown));
        DdsFixture noFormat = headerOnly;  // the header-only test fixture of old
        noFormat.pixelFlags = 0;
        noFormat.bitCount = 0;
        noFormat.dataBytes = 4 * 4 * 4;
        assert(refused("no_format.dds", noFormat));
        DdsFixture faceless = headerOnly;
        faceless.caps2 = 0x200u;  // a cube map without faces
        faceless.dataBytes = 4 * 4 * 4 * 6;
        assert(refused("faceless.dds", faceless));
        DdsFixture volume = headerOnly;
        volume.flags |= 0x800000u;  // DEPTH
        volume.depth = 0x80000000u;
        volume.dataBytes = 4 * 4 * 4;
        assert(refused("volume.dds", volume));

#ifdef _WIN32
        // A cached copy cut down to its header is not used again: with the
        // source held open without sharing, the apply has to read it and fails;
        // once readable, the copy is written whole again.
        const auto cached = pixelsApply.importedTextures.front();
        std::filesystem::resize_file(cached, 128);
        ApplyRequest again;
        again.profileId = "material_dds_layout";
        again.hashes = {"00000000D0000001"};
        again.material.textures.push_back({TextureRole::Albedo, data / "pixels.dds", {}});
        {
            const HANDLE lock = CreateFileW((data / "pixels.dds").c_str(), GENERIC_READ, 0,
                nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            assert(lock != INVALID_HANDLE_VALUE);
            const auto locked = layoutBridge.ApplyLegacyMaterial(again);
            CloseHandle(lock);
            assert(!locked.ok && locked.code == "texture_read_failed");
        }
        const auto restored = layoutBridge.ApplyLegacyMaterial(again);
        assert(restored.ok && restored.importedTextures.size() == 1);
        assert(restored.importedTextures.front() == cached);
        assert(ReadText(cached) == ReadText(data / "pixels.dds"));
#endif
        assert(layoutBridge.ClearAllOwned().ok);
    }

    // A texture source that leaves this computer is refused from its spelling,
    // before any filesystem call: probing a UNC path makes Windows open an SMB
    // session to the host the caller named and offer the player's credentials
    // (R19, the class of the review's H3). 192.0.2.1 is TEST-NET-1, never
    // routable. The refusal reason is the spelling check's own; a probe that
    // failed would report invalid_texture_path, and an SMB attempt to that host
    // would take many seconds instead of none.
    {
        const auto remoteRoot = root / "remote_source_game";
        const auto data = remoteRoot / "garrysmod" / "data";
        std::filesystem::create_directories(data);
        std::filesystem::create_directories(remoteRoot / "rtx-remix");
        Config remoteConfig;
        remoteConfig.gameRoot = remoteRoot;
        Bridge remoteBridge(std::move(remoteConfig));
        const auto apply = [&](const std::filesystem::path& source, const char* hash) {
            ApplyRequest remote;
            remote.profileId = "material_remote_source";
            remote.hashes = {hash};
            remote.material.textures.push_back({TextureRole::Albedo, source, {}});
            return remoteBridge.ApplyLegacyMaterial(remote);
        };
        const auto refusedFromSpelling = [&](const wchar_t* spelling) {
            const auto result = apply(std::filesystem::path(spelling), "00000000AE000001");
            return !result.ok && result.code == "texture_path_outside_allowed_roots" &&
                result.message.find("must be a path on this computer") != std::string::npos;
        };
        const wchar_t* const remoteSpellings[]{
            LR"(\\192.0.2.1\share\x.png)",           // UNC
            L"//192.0.2.1/share/x.png",              // UNC with forward slashes
            LR"(\/192.0.2.1/share\x.png)",           // separators mixed
            LR"(\\?\UNC\192.0.2.1\share\x.png)",     // the long-path UNC form
            LR"(\\?\C:\x.png)",                      // device paths
            LR"(\\.\C:\x.png)",
            LR"(\\192.0.2.1\share\..\..\x.png)",
        };
        const auto started = std::chrono::steady_clock::now();
        for (const auto* spelling : remoteSpellings) assert(refusedFromSpelling(spelling));
#ifdef _WIN32
        // Other root names, and a drive letter without a root directory.
        assert(refusedFromSpelling(LR"(\??\C:\x.png)"));
        assert(refusedFromSpelling(LR"(\??\UNC\192.0.2.1\share\x.png)"));
        assert(refusedFromSpelling(L"C:x.png"));
        assert(refusedFromSpelling(L"C:"));
#endif
        assert(std::chrono::steady_clock::now() - started < std::chrono::seconds(5));

        // Local spellings work as before: an absolute path, and a path relative
        // to the game, to garrysmod/ and to garrysmod/data/.
        WriteMinimalDds(data / "local.dds");
        assert(apply(data / "local.dds", "00000000AE000002").ok);
        assert(apply("garrysmod/data/local.dds", "00000000AE000003").ok);
        assert(apply("data/local.dds", "00000000AE000004").ok);
        assert(apply("local.dds", "00000000AE000005").ok);
        // A root-relative "\dir\x.dds" has no drive, so Windows would resolve it
        // against the game root's current drive, not inside the game folder. It
        // is now refused as outside the roots, before any probe of that drive.
        const auto rooted = apply(L"\\no_such_folder_advmat\\x.dds", "00000000AE000006");
        assert(!rooted.ok && rooted.code == "texture_path_outside_allowed_roots");
        assert(remoteBridge.ClearAllOwned().ok);
    }

    // A source outside every allowed root is refused the same way whether or not
    // the file exists, decided before canonical(): a server's client Lua must
    // not learn from the error code whether a file is present on the player's PC
    // (R19 follow-up). A file inside the game folder may still be told apart.
    {
        const auto outsideRoot = root / "outside_roots_game";
        const auto data = outsideRoot / "garrysmod" / "data";
        std::filesystem::create_directories(data);
        std::filesystem::create_directories(outsideRoot / "rtx-remix");
        Config outsideConfig;
        outsideConfig.gameRoot = outsideRoot;
        Bridge outsideBridge(std::move(outsideConfig));
        std::uint64_t nextHash = 0xA0000001ull;
        const auto applyOutside = [&](const std::filesystem::path& source) {
            ApplyRequest outside;
            outside.profileId = "material_outside_roots";
            std::ostringstream hash;
            hash << std::uppercase << std::hex << std::setw(16) << std::setfill('0') << nextHash++;
            outside.hashes = {hash.str()};
            outside.material.textures.push_back({TextureRole::Albedo, source, {}});
            return outsideBridge.ApplyLegacyMaterial(outside);
        };

        // Two absolute paths outside the game folder: one real, one missing.
        // `root` is the parent of outsideRoot, so a file directly under it is
        // outside the only allowed root.
        const auto presentOutside = root / "present_outside.dds";
        WriteMinimalDds(presentOutside);
        const auto missingOutside = root / "missing_outside.dds";
        assert(!std::filesystem::exists(missingOutside));
        const auto present = applyOutside(presentOutside);
        const auto missing = applyOutside(missingOutside);
        assert(!present.ok && !missing.ok);
        assert(present.code == "texture_path_outside_allowed_roots");
        assert(missing.code == present.code && missing.message == present.message);

        // The same for a root-relative path, present or not, before any probe.
        const auto rootedPresent = applyOutside(L"\\present_outside.dds");
        const auto rootedMissing = applyOutside(L"\\missing_outside.dds");
        assert(rootedPresent.code == "texture_path_outside_allowed_roots");
        assert(rootedMissing.code == rootedPresent.code &&
               rootedMissing.message == rootedPresent.message);

        // A file in the game folder is still told apart: inside and allowed.
        WriteMinimalDds(data / "inside.dds");
        assert(applyOutside(data / "inside.dds").ok);
        const auto insideMissing = applyOutside(data / "gone.dds");
        assert(!insideMissing.ok && insideMissing.code == "invalid_texture_path");
        assert(outsideBridge.ClearAllOwned().ok);
    }

    // A folder in rtx-remix/mods may be a link to a mod kept elsewhere
    // (gm_poolrooms_rtx -> another drive). Its maps are read through the link,
    // must stay inside that link's own target, and are copied into this
    // writer's folder; nothing is written into the linked mod.
    {
        const auto linkedGame = root / "linked_mod_game";
        const auto store = root / "linked_mod_store";
        const auto mods = linkedGame / "rtx-remix" / "mods";
        std::filesystem::create_directories(linkedGame / "garrysmod" / "data");
        std::filesystem::create_directories(mods);
        const auto linkedTarget = store / "gm_linked_rtx";
        const auto linkedMap = linkedTarget / "textures" / "floor.a.rtex.dds";
        WriteMinimalDds(linkedMap, kDefaultMaxTextureDimension * 2, 4);
        WriteMinimalDds(store / "elsewhere" / "secret.dds");
        WriteMinimalDds(store / "topbr" / "protected.dds");
        const auto linkedFolder = mods / "gm_linked_rtx";
        assert(CreateDirectoryLink(linkedTarget, linkedFolder));

        Config linkedConfig;
        linkedConfig.gameRoot = linkedGame;
        Bridge linkedBridge(std::move(linkedConfig));
        assert(linkedBridge.GetCapabilities().available);
        const auto linkedOwnMod = mods / "!advanced_material_editor";

        // AME names an enhancement's map relative to the game folder.
        ApplyRequest enhancement;
        enhancement.profileId = "material_linked_mod";
        enhancement.hashes = {"000000001111C0DE"};
        enhancement.material.textures.push_back(
            {TextureRole::Albedo, "rtx-remix/mods/gm_linked_rtx/textures/floor.a.rtex.dds", {}});
        const auto linkedApply = linkedBridge.ApplyLegacyMaterial(enhancement);
        if (!linkedApply.ok) {
            std::cerr << linkedApply.code << ": " << linkedApply.message << '\n';
            return 1;
        }
        assert(linkedApply.importedTextures.size() == 1);
        assert(linkedApply.importedTextures.front().parent_path() ==
               linkedOwnMod / "textures" / "material_linked_mod");
        assert(ReadText(linkedApply.importedTextures.front()) == ReadText(linkedMap));
        assert(CountRegularFiles(linkedTarget) == 0);
        assert(CountRegularFiles(linkedTarget / "textures") == 1);

        // The same file by its absolute path through the link.
        auto through = enhancement;
        through.material.textures.front().source =
            linkedFolder / "textures" / "floor.a.rtex.dds";
        assert(linkedBridge.ApplyLegacyMaterial(through).ok);
        const auto linkedModRoot = ReadText(linkedOwnMod / "mod.usda");

        const auto refused = [&](const std::filesystem::path& source) {
            auto attempt = enhancement;
            attempt.hashes = {"000000002222C0DE"};
            attempt.material.textures.front().source = source;
            const auto result = linkedBridge.ApplyLegacyMaterial(attempt);
            return !result.ok && result.code == "texture_path_outside_allowed_roots" &&
                ReadText(linkedOwnMod / "mod.usda") == linkedModRoot;
        };

        // The link's target named directly is still outside the game folder.
        assert(refused(linkedMap));

        // A link nested inside the linked mod may not leave its target.
        assert(CreateDirectoryLink(store / "elsewhere", linkedTarget / "escape"));
        assert(refused("rtx-remix/mods/gm_linked_rtx/escape/secret.dds"));

        // A plain mod folder gets no exception for a link nested inside it.
        std::filesystem::create_directories(mods / "plain_mod");
        assert(CreateDirectoryLink(store / "elsewhere", mods / "plain_mod" / "textures"));
        assert(refused("rtx-remix/mods/plain_mod/textures/secret.dds"));

        // ~gmod_topbr stays protected even when it is a link to elsewhere.
        assert(CreateDirectoryLink(store / "topbr", mods / "~gmod_topbr"));
        assert(refused("rtx-remix/mods/~gmod_topbr/protected.dds"));

        // Restricting the import roots also restricts linked mod folders.
        Config restrictedConfig;
        restrictedConfig.gameRoot = linkedGame;
        restrictedConfig.allowedTextureRoots = {linkedGame / "garrysmod" / "data"};
        Bridge restrictedBridge(std::move(restrictedConfig));
        assert(restrictedBridge.GetCapabilities().available);
        const auto restricted = restrictedBridge.ApplyLegacyMaterial(enhancement);
        assert(!restricted.ok && restricted.code == "texture_path_outside_allowed_roots");
        assert(ReadText(linkedOwnMod / "mod.usda") == linkedModRoot);

        // A symbolic link works like a junction; creating one may need
        // Developer Mode or elevation on Windows, so this case is conditional.
        std::error_code symlinkError;
        std::filesystem::create_directory_symlink(
            linkedTarget, mods / "gm_symlinked_rtx", symlinkError);
        if (!symlinkError) {
            auto symlinked = enhancement;
            symlinked.material.textures.front().source =
                "rtx-remix/mods/gm_symlinked_rtx/textures/floor.a.rtex.dds";
            assert(linkedBridge.ApplyLegacyMaterial(symlinked).ok);
            std::filesystem::remove(mods / "gm_symlinked_rtx", symlinkError);
            assert(!symlinkError);
        }

        // This writer's own folder can never be a link: the bridge refuses
        // to start, and the link's target is left alone.
        const auto ownLinkedGame = root / "own_linked_game";
        std::filesystem::create_directories(ownLinkedGame / "garrysmod" / "data");
        std::filesystem::create_directories(ownLinkedGame / "rtx-remix" / "mods");
        WriteText(store / "own" / "keep.txt", "outside own-folder sentinel");
        const auto ownLink = ownLinkedGame / "rtx-remix" / "mods" / "!advanced_material_editor";
        assert(CreateDirectoryLink(store / "own", ownLink));
        {
            Config ownConfig;
            ownConfig.gameRoot = ownLinkedGame;
            Bridge ownBridge(std::move(ownConfig));
            assert(!ownBridge.GetCapabilities().available);
            assert(!ownBridge.ClearAllOwned().ok);
        }
        assert(ReadText(store / "own" / "keep.txt") == "outside own-folder sentinel");

        assert(linkedBridge.ClearAllOwned().ok);
        assert(CountRegularFiles(linkedTarget / "textures") == 1);
        std::error_code unlinkError;
        for (const auto& link : {ownLink, mods / "~gmod_topbr", mods / "plain_mod" / "textures",
                                 linkedTarget / "escape", linkedFolder}) {
            std::filesystem::remove(link, unlinkError);
            assert(!unlinkError);
        }
        assert(std::filesystem::is_regular_file(linkedMap));
        assert(std::filesystem::is_regular_file(store / "elsewhere" / "secret.dds"));
    }

#ifdef _WIN32
    // Every preview re-sends each map, and an unchanged one is not read again:
    // the content hash read last time still names its copy. Holding the file
    // open without sharing makes any read fail, so each apply below shows
    // whether it read the source.
    {
        const auto digestRoot = root / "digest_game";
        std::filesystem::create_directories(digestRoot / "garrysmod" / "data");
        std::filesystem::create_directories(digestRoot / "rtx-remix" / "mods");
        const auto map = digestRoot / "rtx-remix" / "mods" / "ai_pbr" / "map.a.rtex.dds";
        WriteMinimalDds(map, 64, 64);
        Config digestConfig;
        digestConfig.gameRoot = digestRoot;
        Bridge digestBridge(std::move(digestConfig));
        ApplyRequest edit;
        edit.profileId = "material_digest";
        edit.hashes = {"00000000D16E5701"};
        edit.material.roughness = 0.5f;
        edit.material.textures.push_back({TextureRole::Albedo, map, {}});
        const auto first = digestBridge.ApplyLegacyMaterial(edit);
        assert(first.ok && first.importedTextures.size() == 1);

        const auto applyWhileLocked = [&](float roughness) {
            const HANDLE lock = CreateFileW(map.c_str(), GENERIC_READ, 0, nullptr,
                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            assert(lock != INVALID_HANDLE_VALUE);
            edit.material.roughness = roughness;
            const auto result = digestBridge.ApplyLegacyMaterial(edit);
            CloseHandle(lock);
            return result;
        };

        // A slider move: same map, copy present. Nothing reads the source.
        const auto unchanged = applyWhileLocked(0.25f);
        assert(unchanged.ok && unchanged.importedTextures == first.importedTextures);

        // Once its copy is gone (reset retires the cache) the map is read again.
        assert(digestBridge.ClearAllOwned().ok);
        const auto retired = applyWhileLocked(0.3f);
        assert(!retired.ok && retired.code == "texture_read_failed");
        const auto recopied = digestBridge.ApplyLegacyMaterial(edit);
        assert(recopied.ok && recopied.importedTextures == first.importedTextures);
        assert(ReadText(recopied.importedTextures.front()) == ReadText(map));

        // A new write time means the map may have changed, so it is read.
        std::filesystem::last_write_time(map,
            std::filesystem::last_write_time(map) + std::chrono::seconds(10));
        const auto touched = applyWhileLocked(0.35f);
        assert(!touched.ok && touched.code == "texture_read_failed");

        // A rewritten map gets a new content-addressed copy.
        WriteMinimalDds(map, 32, 32);
        const auto rewritten = digestBridge.ApplyLegacyMaterial(edit);
        assert(rewritten.ok && rewritten.importedTextures.size() == 1);
        assert(rewritten.importedTextures.front() != first.importedTextures.front());
        assert(ReadText(rewritten.importedTextures.front()) == ReadText(map));
    }
#endif

    std::error_code cleanupError;
    std::filesystem::remove_all(root, cleanupError);
    std::cout << "advmat RTX writer tests passed\n";
    return 0;
}
