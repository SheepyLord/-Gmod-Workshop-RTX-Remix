// =========================================================================
// format_source.cpp - Standard Source Engine Format Handler
// =========================================================================
// Handles standard Source Engine materials using traditional phong/envmap:
//   - VertexLitGeneric
//   - LightmappedGeneric
//   - Other standard shaders
//
// This is the fallback handler when no community PBR format is detected.
//
// Roughness derivation (priority order):
//   PHONG MATERIALS:
//     1. $phongexponenttexture (per-pixel, best quality)
//     2. $basemapalphaphongmask (base alpha as mask)
//     3. $normalmapalphaenvmapmask (normal alpha as mask)
//     4. Normal map alpha (default phong behavior)
//     5. $phongexponent constant
//
//   NON-PHONG MATERIALS:
//     1. $envmapmask texture
//     2. $basealphaenvmapmask
//     3. Auto-discovered _mask/_spec textures
//     4. Explicit/implicit envmap alpha masks
//     5. Matte constant (1.0) when no reflective data is declared
//
// Metallic extraction:
//   In Source Engine, envmap on a perfectly black texture creates a metallic
//   appearance (pure environment reflection). This is equivalent to white albedo
//   + metallic=1 in PBR. We extract metallic information by combining:
//   - $envmapmask: identifies reflective areas
//   - Base texture brightness: dark areas with reflections = metallic
//   
//   For proper PBR rendering, we also modify the albedo:
//   - Dark metallic areas need brightened albedo (toward white)
//   - This ensures reflections look correct (metals tint reflections by albedo)
//   - Without this, dark metallic areas would show dark/muddy reflections
// =========================================================================

#ifdef _WIN64

#include "formats.h"
#include "pbr_policy.h"
#include <tier0/dbg.h>
#include <algorithm>
#include <cmath>

namespace MaterialPipeline {
namespace ToPBR {
namespace SourceEngine {

// Constants
constexpr float MAX_PHONG_EXPONENT = 150.0f;

// Forward declarations
float CalculateRoughness(const MaterialPBRProperties& props);
float EstimateMetallic(const MaterialPBRProperties& props, bool enabled);

// =========================================================================
// Property Extraction
// =========================================================================

void ExtractProperties(const VMTParseResult& vmt, MaterialPBRProperties& props) {
    // Copy basic properties from VMT parse
    props.hasPhong = vmt.hasPhong;
    props.phongExponent = vmt.phongExponent;
    props.phongBoost = vmt.phongBoost;
    props.hasEnvMap = vmt.hasEnvMap;
    props.isSSBump = vmt.isSSBump;
    props.isTranslucent = vmt.isTranslucent;
    props.isSelfIllum = vmt.isSelfIllum;
    
    // Copy texture paths
    if (!vmt.baseTexture.empty()) {
        props.baseTexturePath = vmt.baseTexture;
    }
    if (!vmt.bumpMap.empty()) {
        props.bumpMapPath = vmt.bumpMap;
        props.hasBumpMap = true;
    }
    if (!vmt.envMapMask.empty()) {
        props.envMapMaskPath = vmt.envMapMask;
        props.hasEnvMapMask = true;
    }
    if (!vmt.phongExponentTexture.empty()) {
        props.phongExponentTexturePath = vmt.phongExponentTexture;
        props.hasPhongExponentTexture = true;
    }
    
    // Fresnel ranges
    if (vmt.hasPhongFresnelRanges) {
        props.phongFresnelRanges[0] = vmt.phongFresnelRanges[0];
        props.phongFresnelRanges[1] = vmt.phongFresnelRanges[1];
        props.phongFresnelRanges[2] = vmt.phongFresnelRanges[2];
        props.hasPhongFresnelRanges = true;
    }
    
    // Envmap tint
    if (vmt.hasEnvMapTint) {
        props.envMapTint[0] = vmt.envMapTint[0];
        props.envMapTint[1] = vmt.envMapTint[1];
        props.envMapTint[2] = vmt.envMapTint[2];
        props.hasEnvMapTint = true;
    }
    
    // Surface prop
    props.surfaceProp = vmt.surfaceProp;
    
    // Calculate roughness and metallic estimates
    props.roughness = CalculateRoughness(props);
    props.metallic = EstimateMetallic(props, false);  // Conservative default
}

// =========================================================================
// Roughness Calculation
// =========================================================================

static float PhongToRoughness(float exponent, float = MAX_PHONG_EXPONENT) {
    return Policy::PhongRoughness(exponent);
}

float CalculateRoughness(const MaterialPBRProperties& props) {
    float roughness = 0.7f;
    
    if (props.hasPhong) {
        if (props.phongExponent > 0) {
            roughness = PhongToRoughness(props.phongExponent);
        }
        
        // Boost and Fresnel ranges affect intensity/angular response, not the
        // Phong lobe width. Folding them into roughness makes the PBR result
        // glossier than the material's exponent requests.
    } else if (props.hasEnvMap) {
        if (props.hasEnvMapTint) {
            float brightness = (props.envMapTint[0] + props.envMapTint[1] + props.envMapTint[2]) / 3.0f;
            roughness = Policy::ReflectionRoughness(brightness);
        } else {
            roughness = 0.4f;
        }
    }
    
    if (roughness < 0.04f) roughness = 0.04f;
    if (roughness > 1.0f) roughness = 1.0f;
    
    return roughness;
}

// =========================================================================
// Metallic Estimation
// =========================================================================

float EstimateMetallic(const MaterialPBRProperties&, bool) {
    return 0.0f; // Only explicit community metallic data or unmasked chrome prove metal.
}

// =========================================================================
// Helper: Check if alpha channel has meaningful variation
// =========================================================================
static bool HasAlphaVariation(const std::vector<uint8_t>& pixelData) {
    if (pixelData.size() < 4) return false;
    
    uint8_t firstAlpha = pixelData[3];
    // Check all alpha values starting at index 7 (second pixel's alpha)
    for (size_t i = 7; i < pixelData.size(); i += 4) {
        if (pixelData[i] != firstAlpha) {
            return true;
        }
    }
    return false;
}

// =========================================================================
// Helper: Generate roughness texture from source data
// =========================================================================
static bool GenerateRoughnessFromSource(
    const ConvertedTexture& sourceTex,
    bool useAlphaChannel,
    bool isPhongExponentTexture,
    bool isInvertedMask,
    bool isPhongMask,
    bool isSSBumpEnvMapMask,
    float constantPhongRoughness,
    const std::string& sourcePath,
    const std::string& outputSuffix,
    const ProcessingContext& ctx,
    ProcessedMaterial& result) {
    
    // If using alpha channel, check for meaningful variation
    if (useAlphaChannel && !HasAlphaVariation(sourceTex.pixelData)) {
        if (ctx.debugOutput) {
            Msg("[Source] Alpha channel has no variation, skipping roughness texture\n");
        }
        return false;
    }
    
    ConvertedTexture roughTex;
    roughTex.width = sourceTex.width;
    roughTex.height = sourceTex.height;
    roughTex.mipLevels = 1;
    roughTex.format = REMIXAPI_FORMAT_R8G8B8A8_UNORM;
    roughTex.isNormalMap = false;
    roughTex.pixelData.resize(sourceTex.width * sourceTex.height * 4);
    
    // Debug: Track min/max/avg values
    uint8_t minSource = 255, maxSource = 0;
    uint8_t minRough = 255, maxRough = 0;
    uint32_t totalSource = 0, totalRough = 0;
    
    for (uint32_t i = 0; i < sourceTex.width * sourceTex.height; i++) {
        uint8_t sourceValue;
        
        if (useAlphaChannel) {
            sourceValue = sourceTex.pixelData[i * 4 + 3];  // Alpha channel
        } else {
            sourceValue = sourceTex.pixelData[i * 4 + 0];  // Red channel
        }
        
        // Track stats
        if (sourceValue < minSource) minSource = sourceValue;
        if (sourceValue > maxSource) maxSource = sourceValue;
        totalSource += sourceValue;
        
        uint8_t roughness;
        if (isPhongExponentTexture) {
            // $phongexponenttexture: value is phong exponent (0-255)
            // Higher = shinier = LOWER roughness
            float exp = static_cast<float>(sourceValue);
            float rough = PhongToRoughness(exp * MAX_PHONG_EXPONENT / 255.0f);
            roughness = static_cast<uint8_t>(rough * 255.0f);
        } else if (isPhongMask) {
            // Phong mask (bumpmap alpha): modulates Phong highlight strength.
            // In Source Engine, this is typically painted as a fairly binary mask:
            //   Black (0) = no phong (matte areas like pores, wrinkles)
            //   White (255) = full phong (shiny areas like skin highlights)
            float maskStrength = static_cast<float>(sourceValue) / 255.0f;
            float rough = 1.0f - maskStrength * (1.0f - constantPhongRoughness);
            
            roughness = static_cast<uint8_t>(rough * 255.0f + 0.5f);
            
            // Debug: Log first few pixels
            if (ctx.debugOutput && i < 10) {
                Msg("[Source] Pixel %d: alpha=%d, maskStr=%.3f, phongRough=%.3f, finalRough=%.3f (byte=%d)\n",
                    i, sourceValue, maskStrength, constantPhongRoughness, rough, roughness);
            }
        } else if (isSSBumpEnvMapMask) {
            // $normalmapalphaenvmapmask controls cubemap intensity in Source,
            // not the width of the reflected lobe. A linear inversion makes
            // partially reflective SSBumps much too diffuse in PBR. Treat the
            // mask more like reflection presence: retain a polished lobe where
            // the mask is present, while mask values near zero still become
            // rough enough to suppress reflections.
            constexpr float kReflectiveRoughness = 0.25f;
            constexpr float kMaskFalloffPower = 3.0f;
            float maskStrength = static_cast<float>(sourceValue) / 255.0f;
            float falloff = std::pow(1.0f - maskStrength, kMaskFalloffPower);
            float rough = kReflectiveRoughness +
                (1.0f - kReflectiveRoughness) * falloff;
            roughness = static_cast<uint8_t>(rough * 255.0f + 0.5f);
        } else if (isInvertedMask) {
            // $basealphaenvmapmask: white = masked (matte), black = reflective (shiny)
            // So we DON'T invert - high value = high roughness
            roughness = uint8_t(255.0f * Policy::ReflectionRoughness(1.0f - sourceValue / 255.0f) + 0.5f);
        } else {
            // Standard envmap mask: bright = reflective = low roughness
            roughness = uint8_t(255.0f * Policy::ReflectionRoughness(sourceValue / 255.0f) + 0.5f);
        }
        
        // Track roughness stats
        if (roughness < minRough) minRough = roughness;
        if (roughness > maxRough) maxRough = roughness;
        totalRough += roughness;
        
        roughTex.pixelData[i * 4 + 0] = roughness;
        roughTex.pixelData[i * 4 + 1] = roughness;
        roughTex.pixelData[i * 4 + 2] = roughness;
        roughTex.pixelData[i * 4 + 3] = 255;
    }
    
    // Log statistics
    if (ctx.debugOutput) {
        uint32_t pixelCount = sourceTex.width * sourceTex.height;
        float avgSource = static_cast<float>(totalSource) / pixelCount;
        float avgRough = static_cast<float>(totalRough) / pixelCount;
        Msg("[Source] Roughness texture stats:\n");
        Msg("[Source]   Source values: min=%d, max=%d, avg=%.1f\n", minSource, maxSource, avgSource);
        Msg("[Source]   Roughness values: min=%d, max=%d, avg=%.1f\n", minRough, maxRough, avgRough);
        Msg("[Source]   Full Phong roughness=%.3f\n", constantPhongRoughness);
    }
    
    std::string path = ctx.generateOutputPath(sourcePath, outputSuffix);
    
    if (ctx.fileExists(path)) {
        result.roughnessPath = path;
        result.skippedCount++;
        return true;
    } else if (ctx.writeDDS(roughTex, path)) {
        result.roughnessPath = path;
        if (ctx.materialsWithRoughness) (*ctx.materialsWithRoughness)++;
        return true;
    }
    
    return false;
}

// =========================================================================
// Texture Processing - Full implementation matching original behavior
// =========================================================================

ProcessedMaterial ProcessTextures(const MaterialPBRProperties& props,
                                   uint64_t textureHash,
                                   const ProcessingContext& ctx) {
    ProcessedMaterial result;
    
    if (ctx.debugOutput) {
        Msg("[Source] Processing material: %s\n", props.materialName.c_str());
        Msg("[Source]   hasPhong=%d, hasPhongExpTex=%d, normMapAlpha=%d, hasBaseMapAlphaPhong=%d\n",
            props.hasPhong, props.hasPhongExponentTexture, props.normalMapAlphaEnvMapMask, props.hasBaseMapAlphaPhongMask);
        Msg("[Source]   hasBump=%d, hasEnvMapMask=%d, hasBaseAlphaEnvMapMask=%d, hasEnvMap=%d\n",
            props.hasBumpMap, props.hasEnvMapMask, props.hasBaseAlphaEnvMapMask, props.hasEnvMap);
        Msg("[Source]   hasDiscoveredMask=%d (%s)\n", props.hasDiscoveredMask, props.discoveredMaskPath.c_str());
    }
    
    // Process normal map
    if (props.hasBumpMap && !props.bumpMapPath.empty()) {
        std::vector<uint8_t> fileData;
        if (ctx.readVTFFile(props.bumpMapPath, fileData)) {
            VTFFileHeader header;
            if (ctx.parseVTFHeader(fileData, header)) {
                // Check if output file already exists BEFORE expensive decompression
                const char* normalSuffix = props.isSSBump
                    ? "_ssbump_normal_v7"
                    : "_normal";
                std::string path = ctx.generateOutputPath(props.bumpMapPath, normalSuffix);
                
                if (ctx.fileExists(path)) {
                    // File already exists - skip all processing
                    result.normalPath = path;
                    result.skippedCount++;
                    if (ctx.debugOutput) {
                        Msg("[Source] Normal map already exists (skipped): %s\n", path.c_str());
                    }
                } else {
                    // File doesn't exist - do the expensive work
                    ConvertedTexture normalTex;
                    normalTex.isNormalMap = true;
                    
                    if (ctx.extractPixelData(fileData, header, normalTex, false)) {
                        // Handle SSBump conversion
                        if (props.isSSBump) {
                            ctx.convertSSBumpToNormal(normalTex);
                        }
                        
                        ctx.convertToOctahedral(normalTex);
                        
                        if (ctx.writeDDS(normalTex, path)) {
                            result.normalPath = path;
                            if (ctx.materialsWithNormals) (*ctx.materialsWithNormals)++;
                            if (ctx.debugOutput) Msg("[Source] Wrote normal: %s\n", path.c_str());
                        }
                    }
                }
            }
        }
    }
    
    // $envmapsphere + $envmapmode: unmasked spherical reflection, i.e. chrome.
    // Keep the normal map for surface detail but force full metal, mirror-like
    // roughness instead of running per-pixel roughness/metallic estimation.
    if (props.isEnvmapSphereChrome) {
        constexpr float kChromeRoughness = 0.05f;
        result.roughnessConstant = kChromeRoughness;
        result.metallicConstant = 1.0f;
        result.success = true;
        if (ctx.debugOutput) {
            Msg("[Source] %s: chrome material -> metallic=1.0, roughness=%.2f\n",
                props.materialName.c_str(), kChromeRoughness);
        }
        return result;
    }
    
    // =========================================================================
    // Roughness texture generation - comprehensive priority system
    // =========================================================================
    bool hasRoughnessTexture = false;
    std::string vtfPath;
    bool useAlphaChannel = false;
    bool isPhongExponentTexture = false;
    bool isInvertedMask = false;
    bool isPhongMask = false;
    bool isSSBumpEnvMapMask = false;
    
    // =========================================================================
    // PHONG MATERIAL PATH - prioritize phong-specific properties
    // Default Source Engine behavior: phong uses $bumpmap alpha as mask
    // Override with $basemapalphaphongmask to use $basetexture alpha instead
    // =========================================================================
    if (props.hasPhong) {
        // Priority 1: $phongexponenttexture (best quality - dedicated roughness data)
        if (props.hasPhongExponentTexture && !props.phongExponentTexturePath.empty()) {
            vtfPath = props.phongExponentTexturePath;
            useAlphaChannel = false;
            isPhongExponentTexture = true;
            if (ctx.debugOutput) Msg("[Source] [PHONG] Using $phongexponenttexture (best quality)\n");
        }
        // Priority 2: $basemapalphaphongmask - OVERRIDE to use base texture alpha as phong mask
        else if (props.hasBaseMapAlphaPhongMask && !props.baseTexturePath.empty()) {
            vtfPath = props.baseTexturePath;
            useAlphaChannel = true;
            isPhongMask = true;
            if (ctx.debugOutput) Msg("[Source] [PHONG] Using base texture alpha ($basemapalphaphongmask)\n");
        }
        // Priority 3: $normalmapalphaenvmapmask - explicit normal map alpha mask parameter
        else if (props.normalMapAlphaEnvMapMask && props.hasBumpMap && !props.bumpMapPath.empty()) {
            vtfPath = props.bumpMapPath;
            useAlphaChannel = true;
            isPhongMask = true;
            if (ctx.debugOutput) Msg("[Source] [PHONG] Using normal map alpha ($normalmapalphaenvmapmask)\n");
        }
        // Priority 4: DEFAULT Source Engine behavior - phong + bumpmap = bumpmap alpha is phong mask
        else if (props.hasBumpMap && !props.bumpMapPath.empty()) {
            vtfPath = props.bumpMapPath;
            useAlphaChannel = true;
            isPhongMask = true;
            if (ctx.debugOutput) Msg("[Source] [PHONG] Using bumpmap alpha (default phong behavior)\n");
        }
        // Priority 5: No bumpmap available - use constant $phongexponent
        else {
            if (ctx.debugOutput) Msg("[Source] [PHONG] No bumpmap found, using constant $phongexponent\n");
        }
    }
    
    // =========================================================================
    // NON-PHONG / FALLBACK PATH - use envmap-based properties
    // Only use these fallbacks if the material doesn't have phong enabled
    // If phong is enabled but no mask texture was found, use the constant phong exponent
    // =========================================================================
    if (vtfPath.empty() && !props.hasPhong) {
        // Priority 5: $envmapmask - separate envmap mask texture
        if (props.hasEnvMapMask && !props.envMapMaskPath.empty()) {
            vtfPath = props.envMapMaskPath;
            useAlphaChannel = false;
            if (ctx.debugOutput) Msg("[Source] Using $envmapmask for roughness\n");
        }
        // Priority 6: $basealphaenvmapmask - base texture alpha as envmap mask (INVERTED!)
        else if (props.hasBaseAlphaEnvMapMask && !props.baseTexturePath.empty()) {
            vtfPath = props.baseTexturePath;
            useAlphaChannel = true;
            isInvertedMask = true;
            if (ctx.debugOutput) Msg("[Source] Using base texture alpha ($basealphaenvmapmask - INVERTED)\n");
        }
        // Priority 7: Auto-discovered _mask/_spec textures
        else if (props.hasDiscoveredMask && !props.discoveredMaskPath.empty()) {
            vtfPath = props.discoveredMaskPath;
            useAlphaChannel = false;
            if (ctx.debugOutput) Msg("[Source] Using auto-discovered mask: %s\n", props.discoveredMaskPath.c_str());
        }
        // Priority 8: $normalmapalphaenvmapmask (non-phong path)
        else if (props.normalMapAlphaEnvMapMask && props.hasBumpMap && !props.bumpMapPath.empty()) {
            vtfPath = props.bumpMapPath;
            useAlphaChannel = true;
            isSSBumpEnvMapMask = props.isSSBump;
            if (ctx.debugOutput) Msg("[Source] Using normal map alpha ($normalmapalphaenvmapmask - non-phong)\n");
        }
        // Priority 9: $envmap + normal map alpha (implicit $normalmapalphaenvmapmask)
        else if ((props.hasEnvMap || props.hasEnvMapTint) && props.hasBumpMap && !props.bumpMapPath.empty()) {
            vtfPath = props.bumpMapPath;
            useAlphaChannel = true;
            isSSBumpEnvMapMask = props.isSSBump;
            if (ctx.debugOutput) Msg("[Source] Trying normal map alpha (implicit envmap roughness)\n");
        }
        // Priority 10: $envmap + base texture alpha (implicit $basealphaenvmapmask)
        else if ((props.hasEnvMap || props.hasEnvMapTint) && !props.baseTexturePath.empty()) {
            vtfPath = props.baseTexturePath;
            useAlphaChannel = true;
            isInvertedMask = true;
            if (ctx.debugOutput) Msg("[Source] Trying base texture alpha (implicit envmap - INVERTED)\n");
        }
    }
    
    // Try to generate roughness texture from found source
    if (!vtfPath.empty()) {
        std::vector<uint8_t> fileData;
        if (ctx.readVTFFile(vtfPath, fileData)) {
            VTFFileHeader header;
            if (ctx.parseVTFHeader(fileData, header)) {
                // Check if output file already exists BEFORE expensive decompression
                std::string roughnessSuffix;
                if (isSSBumpEnvMapMask) {
                    roughnessSuffix = "_ssbump_roughness_v2";
                } else if (isPhongExponentTexture) {
                    roughnessSuffix = "_phongexp_roughness_v2";
                } else if (isPhongMask) {
                    // A shared mask texture can be referenced by materials with
                    // different exponents. Include the resulting full-Phong
                    // roughness so one material cannot reuse another's map.
                    int roughnessKey = static_cast<int>(props.roughness * 1000.0f + 0.5f);
                    roughnessSuffix = "_phongmask_roughness_v2_r" + std::to_string(roughnessKey);
                } else {
                    roughnessSuffix = "_roughness";
                }
                std::string path = ctx.generateOutputPath(vtfPath, roughnessSuffix);
                
                if (ctx.fileExists(path)) {
                    // File already exists - skip all processing
                    result.roughnessPath = path;
                    result.skippedCount++;
                    hasRoughnessTexture = true;
                    if (ctx.debugOutput) {
                        Msg("[Source] Roughness texture already exists (skipped): %s\n", path.c_str());
                    }
                } else {
                    // File doesn't exist - do the expensive work
                    ConvertedTexture sourceTex;
                    if (ctx.extractPixelData(fileData, header, sourceTex, false)) {
                        hasRoughnessTexture = GenerateRoughnessFromSource(
                            sourceTex, useAlphaChannel, isPhongExponentTexture, isInvertedMask, isPhongMask,
                            isSSBumpEnvMapMask, props.roughness, vtfPath, roughnessSuffix, ctx, result);
                        
                        if (hasRoughnessTexture && ctx.debugOutput) {
                            Msg("[Source] Generated roughness texture from: %s\n", vtfPath.c_str());
                        } else if (ctx.debugOutput) {
                            Msg("[Source] Failed to generate roughness texture (no variation or error)\n");
                        }
                    }
                }
            }
        }
    }
    
    // For phong materials that failed to generate a texture, ensure we use the constant
    if (!hasRoughnessTexture && props.hasPhong && ctx.debugOutput) {
        Msg("[Source] [PHONG] Using constant roughness from $phongexponent: %.2f\n", props.roughness);
    }
    
    // Set constants for materials without textures
    if (!hasRoughnessTexture) {
        result.roughnessConstant = props.roughness;
        if (ctx.debugOutput) {
            Msg("[Source] No roughness texture generated, using constant: %.2f\n", props.roughness);
        }
    }
    result.metallicConstant = props.metallic;
    
    // =========================================================================
    // Height map processing
    // =========================================================================
    std::string heightMapPath;
    if (props.hasParallaxMap && !props.parallaxMapPath.empty()) {
        heightMapPath = props.parallaxMapPath;
    } else if (props.hasDiscoveredHeight && !props.discoveredHeightPath.empty()) {
        heightMapPath = props.discoveredHeightPath;
    }
    
    if (!heightMapPath.empty()) {
        std::vector<uint8_t> fileData;
        if (ctx.readVTFFile(heightMapPath, fileData)) {
            VTFFileHeader header;
            if (ctx.parseVTFHeader(fileData, header)) {
                // Check if output file already exists BEFORE expensive decompression
                std::string path = ctx.generateOutputPath(heightMapPath, "_height");
                
                if (ctx.fileExists(path)) {
                    // File already exists - skip all processing
                    result.heightPath = path;
                    result.heightScale = props.hasParallaxMapScale ? props.parallaxMapScale : 0.025f;
                    result.skippedCount++;
                    if (ctx.debugOutput) {
                        Msg("[Source] Height map already exists (skipped): %s\n", path.c_str());
                    }
                } else {
                    // File doesn't exist - do the expensive work
                    ConvertedTexture heightTex;
                    if (ctx.extractPixelData(fileData, header, heightTex, false)) {
                        if (ctx.writeDDS(heightTex, path)) {
                            result.heightPath = path;
                            result.heightScale = props.hasParallaxMapScale ? props.parallaxMapScale : 0.025f;
                            if (ctx.debugOutput) Msg("[Source] Wrote height: %s\n", path.c_str());
                        }
                    }
                }
            }
        }
    }
    
    result.success = true;
    if (ctx.debugOutput) {
        Msg("[Source] Complete: %s (skipped %d existing)\n", props.materialName.c_str(), result.skippedCount);
    }
    
    return result;
}

} // namespace SourceEngine
} // namespace ToPBR
} // namespace MaterialPipeline

#endif // _WIN64
