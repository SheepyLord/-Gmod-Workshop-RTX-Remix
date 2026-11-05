#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace advmat::rtx_bridge {

inline constexpr int kApiVersion = 1;
// An image the writer decodes (WIC), bakes and mips itself on the game thread.
inline constexpr std::uintmax_t kDefaultMaxTextureBytes = 32ull * 1024ull * 1024ull;
inline constexpr std::uint32_t kDefaultMaxTextureDimension = 2048;
// A DDS is validated and copied as it is, never decoded, so RTX Remix
// enhancement maps (4096 px BC7, an 11059 x 8847 sheet of 130 MB) fit.
inline constexpr std::uintmax_t kDefaultMaxDdsTextureBytes = 512ull * 1024ull * 1024ull;
inline constexpr std::uint32_t kDefaultMaxDdsTextureDimension = 16384;
inline constexpr std::size_t kMaxTextureOperations = 4;
inline constexpr std::size_t kMaxGameRootAncestorDepth = 6;

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

enum class TextureRole {
    Albedo,
    Normal,
    Anisotropy,
    Roughness,
    Metallic,
    Height,
    Emissive,
    SubsurfaceTransmittance,
    SubsurfaceThickness,
    SubsurfaceScattering,
    SubsurfaceRadius,
};

inline constexpr std::size_t kTextureRoleCount = 11;

enum class TextureOperationKind {
    Invert,
    Multiply,
    NormalFromHeight,
};

enum class HeightChannel {
    Luminance,
    Red,
    Green,
    Blue,
    Alpha,
};

// Preview is an optional protocol-1 extension, paired with RestorePreview.
enum class BridgeOperation {
    Commit,
    Preview,
    Restore,
    Clear,
};

struct TextureOperation {
    TextureOperationKind kind = TextureOperationKind::Invert;
    Vec3 color{1.0f, 1.0f, 1.0f};
    float strength = 1.0f;
    HeightChannel channel = HeightChannel::Luminance;
};

struct TextureInput {
    TextureRole role = TextureRole::Albedo;
    std::filesystem::path source;
    std::vector<TextureOperation> operations;
};

// Mirrors the fields accepted by RemixMaterial.CreateOpaqueMaterial. Every
// value is optional so the generated layer only authors values the editor owns.
struct MaterialParameters {
    std::vector<TextureInput> textures;

    std::optional<Vec3> albedo;
    std::optional<float> opacity;
    std::optional<float> roughness;
    std::optional<float> metallic;
    std::optional<Vec3> emissiveColor;
    std::optional<float> emissiveIntensity;
    std::optional<float> anisotropy;
    std::optional<float> thinFilmThickness;
    std::optional<float> displaceIn;
    std::optional<float> displaceOut;
    std::optional<Vec3> subsurfaceTransmittanceColor;
    std::optional<float> subsurfaceMeasurementDistance;
    std::optional<Vec3> subsurfaceSingleScatteringAlbedo;
    std::optional<float> subsurfaceVolumetricAnisotropy;
    std::optional<Vec3> subsurfaceRadius;
    std::optional<float> subsurfaceRadiusScale;
    std::optional<float> subsurfaceMaxSampleRadius;

    std::optional<int> spriteSheetRows;
    std::optional<int> spriteSheetColumns;
    std::optional<int> spriteSheetFps;
    std::optional<int> filterMode;
    std::optional<int> wrapModeU;
    std::optional<int> wrapModeV;
    std::optional<int> normalEncoding;
    std::optional<bool> enableThinFilm;
    std::optional<bool> enableEmission;
    std::optional<bool> preloadTextures;
    std::optional<bool> ignoreMaterial;
    std::optional<bool> alphaIsThinFilmThickness;
    std::optional<bool> useDrawCallAlphaState;
    std::optional<bool> blendEnabled;
    std::optional<bool> invertedBlend;
    std::optional<bool> subsurfaceDiffusionProfile;
    std::optional<int> blendType;
    std::optional<int> alphaTestType;
    // AperturePBR expects a normalized floating-point threshold. The legacy
    // RemixMaterial compatibility table may still supply a byte, which the Lua
    // binding normalizes before it reaches this writer-owned representation.
    std::optional<float> alphaReferenceValue;
};

struct ApplyRequest {
    BridgeOperation operation = BridgeOperation::Commit;
    // Stable material-derived identity used for the imported-texture folder
    // and one-time migration of the older aggregate layer format.
    std::string profileId;
    // Persistent layers themselves are keyed one-per-canonical captured hash.
    std::vector<std::string> hashes;
    MaterialParameters material;
};

struct ClearRequest {
    std::string profileId;
    // Required exact hashes. Broad material-derived clear is intentionally not
    // supported because a delayed tombstone must not remove a newer hash.
    std::vector<std::string> hashes;
};

struct Result {
    bool ok = false;
    std::string code;
    std::string message;
    std::string profileId;
    std::filesystem::path layerPath;
    std::vector<std::filesystem::path> layerPaths;
    std::vector<std::filesystem::path> importedTextures;

    static Result Success(std::string profileId = {});
    static Result Failure(std::string code, std::string message);
};

struct Capabilities {
    int apiVersion = kApiVersion;
    bool available = true;
    bool legacyUsdaWriter = true;
    bool livePreview = false;
    bool reversiblePreview = false;
    bool authoritativeReset = true;
    bool atomicProfileLayers = true;
    bool ddsImport = true;
    bool wicImageConversion = false;
    bool textureOperations = false;
    bool synchronous = true;
    std::uintmax_t maxTextureBytes = kDefaultMaxTextureBytes;
    std::uint32_t maxTextureDimension = kDefaultMaxTextureDimension;
    std::uintmax_t maxDdsTextureBytes = kDefaultMaxDdsTextureBytes;
    std::uint32_t maxDdsTextureDimension = kDefaultMaxDdsTextureDimension;
    std::size_t maxTextureOperations = kMaxTextureOperations;
    std::filesystem::path modDirectory;
};

struct Config {
    // Garry's Mod installation root (the directory containing hl2.exe and
    // rtx-remix). The mod destination is deliberately not configurable.
    std::filesystem::path gameRoot;

    // Texture sources must resolve below one of these roots. When empty, the
    // canonical game root is the sole import root. The one exception is a
    // folder in rtx-remix/mods that is itself a link: a source reached through
    // it may resolve anywhere inside that link's own target.
    std::vector<std::filesystem::path> allowedTextureRoots;

    // Native calls run synchronously on the caller (normally Garry's Mod's
    // client/game thread). Keep defaults deliberately conservative.
    // maxTexture* bound an image the writer decodes, bakes and mips itself;
    // maxDdsTexture* bound a DDS, which is only validated and copied.
    std::uintmax_t maxTextureBytes = kDefaultMaxTextureBytes;
    std::uint32_t maxTextureDimension = kDefaultMaxTextureDimension;
    std::uintmax_t maxDdsTextureBytes = kDefaultMaxDdsTextureBytes;
    std::uint32_t maxDdsTextureDimension = kDefaultMaxDdsTextureDimension;

    // Test-only deterministic failure injection. Production integrations must
    // leave this empty. A true result aborts at the named pre/post-commit point.
    std::function<bool(std::string_view)> failureInjector;
};

class Bridge {
public:
    explicit Bridge(Config config);

    Capabilities GetCapabilities() const;
    Result ApplyLegacyMaterial(const ApplyRequest& request);
    Result ClearLegacyMaterial(const ClearRequest& request);
    // Remove only this material's session overlay, preserving current commits.
    Result RestorePreview(const std::string& profileId);
    // Disables every active layer in the bridge's fixed owned namespace. No
    // caller-provided filesystem path participates in this operation.
    Result ClearAllOwned();

    const std::filesystem::path& ModDirectory() const noexcept;

private:
    struct Impl;
    Impl* impl_;

public:
    ~Bridge();
    Bridge(const Bridge&) = delete;
    Bridge& operator=(const Bridge&) = delete;
    Bridge(Bridge&&) noexcept;
    Bridge& operator=(Bridge&&) noexcept;
};

// Strict helpers are public so the writer contract can be tested without Lua.
bool ValidateProfileId(const std::string& value, std::string& error);
bool CanonicalizeHash(const std::string& value, std::string& canonical, std::string& error);
bool ParseBridgeOperation(const std::string& value, BridgeOperation& operation,
                          std::string& error);
// Starting at the executable's directory, checks a bounded ancestor chain for
// a directory containing both garrysmod/ and rtx-remix/. Relative paths and
// unvalidated current-directory fallbacks are intentionally rejected.
std::optional<std::filesystem::path> FindGameRootFromExecutable(
    const std::filesystem::path& executablePath);
const char* TextureRoleName(TextureRole role) noexcept;

} // namespace advmat::rtx_bridge
