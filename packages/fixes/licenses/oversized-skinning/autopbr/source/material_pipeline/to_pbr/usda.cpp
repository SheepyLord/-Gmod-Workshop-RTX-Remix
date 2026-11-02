// =========================================================================
// usda.cpp - USD/USDA file generation implementation
// =========================================================================
// Implementation of USD file generation for RTX Remix mods
// =========================================================================

#ifdef _WIN64

#include "usda.h"
#include "to_pbr.h"
#include <tier0/dbg.h>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <Windows.h>
#include <algorithm>
#include <vector>
#include <mutex>
#include <cmath>
#include <filesystem>
#include "pbr_policy.h"

namespace MaterialPipeline {
namespace ToPBR {
namespace USDA {

// =========================================================================
// ProcessedMaterialInfo Definition (needed for complete type)
// =========================================================================

// Note: ProcessedMaterialInfo is defined in the TextureProcessor class
// We need to reference it from the header

// =========================================================================
// Utility Functions
// =========================================================================

std::string GetRelativeTexturePath(const std::string& absolutePath, const std::string& outputDir) {
    const auto mod = std::filesystem::u8path(GetModDirectory(outputDir));
    const auto relative = std::filesystem::u8path(absolutePath).lexically_relative(mod);
    if (!relative.empty()) return "./" + relative.generic_u8string();
    return "./textures/" + std::filesystem::u8path(absolutePath).filename().u8string();
}

std::string GetModDirectory(const std::string& outputDirectory) {
    const auto path=std::filesystem::u8path(outputDirectory).lexically_normal();
    return path.filename() == "textures" ? path.parent_path().u8string() : path.u8string();
}

// =========================================================================
// USDA Generation
// =========================================================================

bool CheckExistingMaterials(const std::string& materialsUsdaPath,
                            const std::unordered_map<uint64_t, TextureProcessor::ProcessedMaterialInfo>& materialInfo,
                            std::unordered_set<uint64_t>& existingHashes,
                            int& newMaterialCount,
                            bool debugOutput) {
    existingHashes.clear();
    newMaterialCount = 0;
    
    // Read existing materials.usda to find which hashes are already defined
    std::ifstream existingFile(materialsUsdaPath);
    if (existingFile.is_open()) {
        std::string line;
        while (std::getline(existingFile, line)) {
            // Look for lines like: over "mat_HASH"
            size_t matPos = line.find("over \"mat_");
            if (matPos != std::string::npos) {
                size_t hashStart = matPos + 10; // Length of 'over "mat_'
                size_t hashEnd = line.find("\"", hashStart);
                if (hashEnd != std::string::npos) {
                    std::string hashStr = line.substr(hashStart, hashEnd - hashStart);
                    uint64_t hash = 0;
                    if (sscanf(hashStr.c_str(), "%llX", (unsigned long long*)&hash) == 1) {
                        existingHashes.insert(hash);
                    }
                }
            }
        }
        existingFile.close();
        
        if (debugOutput && !existingHashes.empty()) {
            Msg("[USDA] Found %d existing material entries\n", (int)existingHashes.size());
        }
    }
    
    // Count new materials
    for (const auto& pair : materialInfo) {
        if (existingHashes.find(pair.first) == existingHashes.end()) {
            newMaterialCount++;
        }
    }
    
    return true;
}

bool LoadExistingHashes(const std::string& materialsUsdaPath,
                        std::unordered_set<uint64_t>& existingHashes,
                        bool debugOutput) {
    existingHashes.clear();
    
    // Read existing materials.usda to find which hashes are already defined
    std::ifstream existingFile(materialsUsdaPath);
    if (!existingFile.is_open()) {
        // File doesn't exist - that's OK, just means no existing hashes
        if (debugOutput) {
            Msg("[USDA] No existing materials.usda found at %s\n", materialsUsdaPath.c_str());
        }
        return true;
    }
    
    std::string line;
    while (std::getline(existingFile, line)) {
        // Look for lines like: over "mat_HASH"
        size_t matPos = line.find("over \"mat_");
        if (matPos != std::string::npos) {
            size_t hashStart = matPos + 10; // Length of 'over "mat_'
            size_t hashEnd = line.find("\"", hashStart);
            if (hashEnd != std::string::npos) {
                std::string hashStr = line.substr(hashStart, hashEnd - hashStart);
                uint64_t hash = 0;
                if (sscanf(hashStr.c_str(), "%llX", (unsigned long long*)&hash) == 1) {
                    existingHashes.insert(hash);
                }
            }
        }
    }
    existingFile.close();
    
    if (debugOutput) {
        Msg("[USDA] Loaded %zu existing material hashes from %s\n", 
            existingHashes.size(), materialsUsdaPath.c_str());
    }
    
    return true;
}

bool PublishStagedFile(const std::string& stagingPath, const std::string& finalPath) {
    // Only generated USD snapshots are mutable. Preserve pre-existing or subsequently
    // edited text before replacing it; byte comparison distinguishes our own last write.
    static std::mutex ownershipMutex;
    static std::unordered_map<std::string, std::string> lastPublished;
    std::lock_guard<std::mutex> lock(ownershipMutex);
    const bool usd = finalPath.size() >= 5 && finalPath.substr(finalPath.size()-5) == ".usda";
    std::string next;
    if (usd) {
        auto read = [](const std::string& path, std::string& result) {
            std::ifstream f(std::filesystem::u8path(path), std::ios::binary | std::ios::ate);
            if (!f) return false;
            const auto n=f.tellg();
            if (n < 0 || n > 16*1024*1024) return false;
            result.resize(size_t(n)); f.seekg(0);
            return bool(f.read(result.data(), std::streamsize(result.size())));
        };
        if (!read(stagingPath, next)) return false;
        if (GetFileAttributesW(std::filesystem::u8path(finalPath).c_str()) != INVALID_FILE_ATTRIBUTES) {
            std::string previous;
            if (!read(finalPath, previous)) return false;
            const auto owned=lastPublished.find(finalPath);
            if (previous != next && (owned == lastPublished.end() || previous != owned->second)) {
                uint64_t hash=14695981039346656037ull;
                for (unsigned char c:previous) { hash^=c; hash*=1099511628211ull; }
                char suffix[64]; snprintf(suffix,sizeof(suffix),".before-r11-%016llX.bak",(unsigned long long)hash);
                const auto backup=std::filesystem::u8path(finalPath+suffix);
                const auto original=std::filesystem::u8path(finalPath);
                if (!CopyFileW(original.c_str(),backup.c_str(),TRUE) &&
                    !Policy::SameFile(original,backup)) return false;
                // A concurrent edit must also be preserved before publication.
                if (!Policy::SameFile(original,backup)) return false;
            }
        }
    }
    if (MoveFileExW(std::filesystem::u8path(stagingPath).c_str(), std::filesystem::u8path(finalPath).c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        if (usd) lastPublished[finalPath]=std::move(next);
        return true;
    }
    Warning("[USDA] Failed to publish %s (error %lu)\n", finalPath.c_str(), GetLastError());
    std::remove(stagingPath.c_str());
    return false;
}

bool WriteModUSDAFile(const std::string& modDir) {
    std::string modUsdaPath = modDir + "/mod.usda";

    // Write USDA header
    std::ostringstream content;
    content << "#usda 1.0\n";
    content << "(\n";
    content << "    customLayerData = {\n";
    content << "        string lightspeed_game_name = \"Garry's Mod (x64)\"\n";
    content << "        string lightspeed_layer_type = \"replacement\"\n";
    content << "    }\n";
    content << "    metersPerUnit = 0.01\n";
    content << "    subLayers = [\n";
    content << "        @./materials.usda@\n";
    content << "    ]\n";
    content << "    timeCodesPerSecond = 24\n";
    content << "    upAxis = \"Z\"\n";
    content << ")\n\n";

    // Called on every batch publication: leave an up-to-date layer alone, and never
    // truncate the live file Remix watches (stage it and swap instead).
    {
        std::ifstream existing(modUsdaPath);
        std::ostringstream current;
        if (existing && (current << existing.rdbuf()) && current.str() == content.str()) {
            return true;
        }
    }

    const std::string stagingPath = modUsdaPath + ".tmp";
    {
        std::ofstream modUsda(stagingPath, std::ios::trunc);
        if (!modUsda.is_open()) {
            Warning("[USDA] Failed to create mod.usda at %s\n", stagingPath.c_str());
            return false;
        }
        modUsda << content.str();
        modUsda.close();
        if (!modUsda) {
            Warning("[USDA] Failed to write %s\n", stagingPath.c_str());
            std::remove(stagingPath.c_str());
            return false;
        }
    }
    return PublishStagedFile(stagingPath, modUsdaPath);
}

void WriteGlassMaterial(std::ostream& stream,
                        uint64_t hash,
                        const TextureProcessor::ProcessedMaterialInfo& info,
                        const std::string& outputDirectory) {
    char hashStr[32];
    snprintf(hashStr, sizeof(hashStr), "%llX", (unsigned long long)hash);
    
    stream << "        over \"mat_" << hashStr << "\"\n";
    stream << "        {\n";
    stream << "            over \"Shader\"\n";
    stream << "            {\n";
    
    // Glass materials use AperturePBR_Translucent shader
    stream << "                uniform asset info:mdl:sourceAsset = @AperturePBR_Translucent.mdl@\n";
    stream << "                uniform token info:mdl:sourceAsset:subIdentifier = \"AperturePBR_Translucent\"\n";
    
    // Glass-specific properties
    stream << "                float inputs:ior_constant = " << info.ior << "\n";
    stream << "                bool inputs:thin_walled = " << (info.thinWalled ? 1 : 0) << "\n";
    if (info.hasVolumeTransmittance) {
        stream << "                color3f inputs:transmittance_color = ("
               << info.transmittanceColor[0] << ", "
               << info.transmittanceColor[1] << ", "
               << info.transmittanceColor[2] << ")\n";
        stream << "                float inputs:transmittance_measurement_distance = "
               << info.transmittanceMeasurementDistance << "\n";
    }
    // Translucent replacement textures do not participate in Remix's sampler
    // feedback path. Force their full mip chain to be resident instead of
    // leaving a newly-loaded glass texture at its single smallest mip.
    stream << "                bool inputs:preload_textures = 1\n";
    
    // Roughness
    if (!info.roughnessPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.roughnessPath, outputDirectory);
        stream << "                asset inputs:reflectionroughness_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"raw\"\n";
        stream << "                )\n";
    } else {
        float glassRoughness = (info.roughnessConstant >= 0.99f) ? 0.05f : info.roughnessConstant;
        stream << "                float inputs:reflection_roughness_constant = " << glassRoughness << "\n";
    }
    
    // Transmittance texture for colored/tinted glass
    if (!info.transmittancePath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.transmittancePath, outputDirectory);
        stream << "                asset inputs:transmittance_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"srgb\"\n";
        stream << "                )\n";
        stream << "                bool inputs:use_diffuse_layer = 1\n";
        if (info.enableTransmissionMask) {
            stream << "                bool inputs:enable_transmission_mask = 1\n";
        }
        
        // For Refract shaders: reduce diffuse opacity
        if (info.isRefractShader) {
            stream << "                float inputs:diffuse_color_constant_opacity = 0.3\n";
        }
    }
    
    // Normal map support for frosted/textured glass
    if (!info.normalPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.normalPath, outputDirectory);
        stream << "                int inputs:encoding = 0\n";  // octahedral
        stream << "                asset inputs:normalmap_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"raw\"\n";
        stream << "                )\n";
    }
    
    stream << "            }\n";  // Close Shader
    stream << "        }\n\n";  // Close material
}

void WriteOpaqueMaterial(std::ostream& stream,
                         uint64_t hash,
                         const TextureProcessor::ProcessedMaterialInfo& info,
                         const std::string& outputDirectory) {
    char hashStr[32];
    snprintf(hashStr, sizeof(hashStr), "%llX", (unsigned long long)hash);
    
    stream << "        over \"mat_" << hashStr << "\"\n";
    stream << "        {\n";
    stream << "            over \"Shader\"\n";
    stream << "            {\n";
    
    // Standard opaque materials use Remix's AperturePBR_Opacity shader (an earlier
    // "AperturePBR_Opaque" name matched no MDL; the runtime only fell back to opaque)
    stream << "                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@\n";
    stream << "                uniform token info:mdl:sourceAsset:subIdentifier = \"AperturePBR_Opacity\"\n";

    // Remix associates auxiliary opaque textures with the replacement
    // albedo's sampler-feedback stamp. Most ToPBR materials intentionally
    // preserve Source's original albedo, leaving generated normal maps with
    // no replacement stamp to inherit. Preload those materials so the normal
    // map cannot remain at its initially loaded smallest mip.
    if (!info.normalPath.empty() && info.albedoPath.empty()) {
        stream << "                bool inputs:preload_textures = 1\n";
    }
    
    // Albedo/Diffuse texture override (e.g., BFT metallic albedo reconstruction)
    if (!info.albedoPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.albedoPath, outputDirectory);
        stream << "                asset inputs:diffuse_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"srgb\"\n";
        stream << "                )\n";
    }
    
    // Normal map
    if (!info.normalPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.normalPath, outputDirectory);
        stream << "                int inputs:encoding = 0\n";  // octahedral
        stream << "                asset inputs:normalmap_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"raw\"\n";
        stream << "                )\n";
    }
    
    // Roughness
    if (!info.roughnessPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.roughnessPath, outputDirectory);
        stream << "                asset inputs:reflectionroughness_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"raw\"\n";
        stream << "                )\n";
    } else {
        stream << "                float inputs:reflection_roughness_constant = " << info.roughnessConstant << "\n";
    }
    
    // Metallic
    if (!info.metallicPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.metallicPath, outputDirectory);
        stream << "                asset inputs:metallic_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"raw\"\n";
        stream << "                )\n";
    } else {
        stream << "                float inputs:metallic_constant = " << info.metallicConstant << "\n";
    }
    
    // Height/Displacement map
    if (!info.heightPath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.heightPath, outputDirectory);
        stream << "                asset inputs:height_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"raw\"\n";
        stream << "                )\n";
        float displaceIn = info.heightScale * 0.5f;
        stream << "                float inputs:displace_in = " << displaceIn << "\n";
    }
    
    // Emissive/Self-illumination
    if (!info.emissivePath.empty()) {
        std::string relPath = GetRelativeTexturePath(info.emissivePath, outputDirectory);
        stream << "                asset inputs:emissive_mask_texture = @" << relPath << "@ (\n";
        stream << "                    colorSpace = \"srgb\"\n";
        stream << "                )\n";
        float emitIntensity = std::isfinite(info.emissionIntensity) ? (std::max)(0.0f, info.emissionIntensity) : 0.0f;
        stream << "                float inputs:emissive_intensity = " << emitIntensity << "\n";
    }
    
    stream << "            }\n";  // Close Shader
    stream << "        }\n\n";  // Close material
}

// Helper function to write fresh USDA content
static void WriteFreshUSDAContent(std::ostream& stream,
                                  const std::unordered_map<uint64_t, TextureProcessor::ProcessedMaterialInfo>& materialInfo,
                                  const std::string& outputDirectory) {
    stream << "#usda 1.0\n";
    stream << "(\n";
    stream << "    upAxis = \"Z\"\n";
    stream << ")\n\n";
    
    stream << "over \"RootNode\"\n";
    stream << "{\n";
    stream << "    over \"Looks\"\n";
    stream << "    {\n";
    
    std::vector<uint64_t> hashes;
    for (const auto& pair : materialInfo) hashes.push_back(pair.first);
    std::sort(hashes.begin(), hashes.end());
    for (uint64_t hash : hashes) {
        const auto& info = materialInfo.at(hash);

        if (info.isGlass) {
            WriteGlassMaterial(stream, hash, info, outputDirectory);
        } else {
            WriteOpaqueMaterial(stream, hash, info, outputDirectory);
        }
    }
    
    stream << "    }\n";  // Close Looks
    stream << "}\n";  // Close RootNode
}

bool WriteMaterialsUSDAFile(const std::string& modDir,
                            const std::string& outputDirectory,
                            const std::unordered_map<uint64_t, TextureProcessor::ProcessedMaterialInfo>& materialInfo,
                            bool debugOutput,
                            const std::string& overridePath) {
    const std::string path = overridePath.empty() ? modDir + "/materials.usda" : overridePath;
    std::ofstream file(path, std::ios::trunc);
    if (!file) return false;
    WriteFreshUSDAContent(file, materialInfo, outputDirectory);
    file.close();
    return bool(file);
}

} // namespace USDA
} // namespace ToPBR
} // namespace MaterialPipeline

#endif // _WIN64
