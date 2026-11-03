-- RTX Remix ToPBR Material Converter
-- Automatically converts Source Engine material properties to PBR materials in RTX Remix.
--
-- This module uses MaterialPipeline.ToPBR C++ module to:
-- - Read VTF texture files from Source Engine filesystem
-- - Extract pixel data and convert to Remix-compatible format
-- - Upload textures via RemixAPI CreateTexture
-- - Create PBR materials with proper roughness/metallic values
--
-- Console Commands:
-- - rtx_topbr_process - Process all tracked materials
-- - rtx_topbr_inspect <material> - Inspect a material's PBR properties
-- - rtx_topbr_stats - Show conversion statistics
-- - rtx_topbr_clear - Clear conversion cache
-- - rtx_topbr_debug <0/1> - Enable debug output
-- - rtx_topbr_help - Show help

if SERVER then return end

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end

-- ConVars for configuration
-- NOTE: Material discovery is handled by RTXMaterialPipeline. ToPBR only processes individual materials.
CreateClientConVar("rtx_topbr_enabled", "0", true, false, "Enable ToPBR conversion stage")
CreateClientConVar("rtx_topbr_debug", "0", true, false, "Enable debug output")
CreateClientConVar("rtx_topbr_metallic", "0", true, false, "Compatibility flag; metallic comes only from authored maps or unmasked chrome")
CreateClientConVar("rtx_topbr_autodiscover", "1", true, false, "Auto-discover companion textures (_normal, _mask, _spec) not explicitly referenced in VMT")
CreateClientConVar("rtx_topbr_parse_commented_properties", "0", true, false, "Parse commented-out VMT properties (e.g., //$envmap) - useful for maps where they were disabled for vanilla Source")

-- Module table
RTXToPBR = RTXToPBR or {}

-- Initialization state
local isInitialized = false

--[[
    Safe ConVar access helpers
]]--
local function GetConVarBoolSafe(name, default)
    local cv = GetConVar(name)
    if cv then return cv:GetBool() end
    return default or false
end

local function GetConVarFloatSafe(name, default)
    local cv = GetConVar(name)
    if cv then return cv:GetFloat() end
    return default or 0
end

--[[
    Debug print helper
]]--
local function DebugPrint(...)
    if GetConVarBoolSafe("rtx_topbr_debug", false) then
        MsgC(Color(200, 200, 255), "[RTX ToPBR] ", Color(255, 255, 255), ...)
        MsgC(Color(255, 255, 255), "\n")
    end
end

--[[
    Initialize the MaterialPipeline.ToPBR C++ module
]]--
function RTXToPBR.Initialize()
    if isInitialized then
        return true
    end
    
    -- Check if MaterialPipeline.ToPBR is available (from C++ module)
    local processor = MaterialPipeline and MaterialPipeline.ToPBR
    if not processor then
        MsgC(Color(255, 100, 100), "[RTX ToPBR] MaterialPipeline.ToPBR not available - C++ module not loaded\n")
        return false
    end
    
    -- Helper to sync all ConVars to C++
    local function SyncConVarsToProcessor()
        if processor.SetEnabled then
            processor.SetEnabled(GetConVarBoolSafe("rtx_topbr_enabled", false))
        end
        processor.SetDebugOutput(GetConVarBoolSafe("rtx_topbr_debug", false))
        if processor.SetMetallicGeneration then
            processor.SetMetallicGeneration(GetConVarBoolSafe("rtx_topbr_metallic", false))
        end
        if processor.SetAutoDiscover then
            processor.SetAutoDiscover(GetConVarBoolSafe("rtx_topbr_autodiscover", true))
        end
        if processor.SetParseCommentedProperties then
            processor.SetParseCommentedProperties(GetConVarBoolSafe("rtx_topbr_parse_commented_properties", false))
        end
    end
    
    -- Check if already initialized by C++ (during RemixAPI init)
    if processor.IsInitialized and processor.IsInitialized() then
        isInitialized = true
        MsgC(Color(100, 255, 100), "[RTX ToPBR] MaterialPipeline.ToPBR already initialized by C++\n")
        SyncConVarsToProcessor()
        return true
    end
    
    -- Initialize the C++ converter (fallback if not already done)
    local success = processor.Initialize()
    if not success then
        MsgC(Color(255, 100, 100), "[RTX ToPBR] Failed to initialize MaterialPipeline.ToPBR\n")
        return false
    end
    
    SyncConVarsToProcessor()
    
    isInitialized = true
    MsgC(Color(100, 255, 100), "[RTX ToPBR] Initialized successfully\n")
    return true
end

-- Helper to get the processor (MaterialPipeline.ToPBR)
local function GetProcessor()
    return MaterialPipeline and MaterialPipeline.ToPBR
end

-- NOTE: Material discovery and continuous processing is handled by RTXMaterialPipeline.
-- ToPBR only provides ProcessMaterial(name) for the pipeline to call.
-- The functions below are utilities for inspection and configuration.

--[[
    Get material from what the player is looking at (trace)
]]--
function RTXToPBR.GetMaterialFromTrace()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil, nil end
    
    local tr = ply:GetEyeTrace()
    if not tr.Hit then return nil, nil end
    
    -- Try to get material from entity first (models)
    if IsValid(tr.Entity) and tr.Entity:GetClass() ~= "worldspawn" then
        local ent = tr.Entity
        local materials = ent:GetMaterials()
        if materials and #materials > 0 then
            -- Return first material and entity info
            return materials[1], {
                type = "entity",
                entity = ent,
                class = ent:GetClass(),
                model = ent:GetModel(),
                allMaterials = materials
            }
        end
    end
    
    -- Fall back to brush/world material
    if tr.HitTexture and tr.HitTexture ~= "" and tr.HitTexture ~= "**empty**" then
        return tr.HitTexture, {
            type = "brush",
            hitPos = tr.HitPos,
            hitNormal = tr.HitNormal
        }
    end
    
    return nil, nil
end

--[[
    Inspect a specific material's PBR properties
]]--
function RTXToPBR.InspectMaterial(materialName)
    if not materialName or materialName == "" then
        MsgC(Color(255, 200, 100), "Usage: RTXToPBR.InspectMaterial(materialName)\n")
        return nil
    end
    
    if not RTXToPBR.Initialize() then
        return nil
    end
    
    local processor = GetProcessor()
    local props = processor.InspectMaterial(materialName)
    
    MsgC(Color(100, 200, 255), string.format("\n[RTX ToPBR] Material: %s\n", materialName))
    MsgC(Color(100, 200, 255), string.rep("=", 70) .. "\n")
    
    if not props then
        MsgC(Color(255, 100, 100), "  Failed to load material\n")
        return nil
    end
    
    -- =========================================================================
    -- Detected Format (most important info first!)
    -- =========================================================================
    local formatColor = Color(200, 200, 200)
    local formatStr = props.detectedFormat or "Source Engine (Standard)"
    
    if props.isExoPBR then
        formatColor = Color(100, 255, 200)
    elseif props.isGPBR then
        formatColor = Color(200, 100, 255)
    elseif props.isMWBPBR then
        formatColor = Color(150, 255, 150)
        formatStr = "MWB PBR Gen (Modern Warfare Base)"
    elseif props.isBFTPseudoPBR then
        formatColor = Color(255, 200, 100)
    end
    
    MsgC(formatColor, string.format("  ★ Detected Format: %s\n", formatStr))
    MsgC(Color(150, 150, 150), string.format("  Shader: %s\n", props.shaderName or "(unknown)"))
    
    -- =========================================================================
    -- Base Textures
    -- =========================================================================
    MsgC(Color(100, 200, 255), "\n  --- Textures ---\n")
    MsgC(Color(200, 200, 200), string.format("  Base Texture: %s\n", props.baseTexture or "(none)"))
    
    -- Bumpmap/Normal
    if props.hasBumpMap then
        local ssbumpStr = ""
        if props.isSSBump then
            ssbumpStr = " [SSBump→Normal]"
        end
        MsgC(Color(100, 255, 100), string.format("  ✓ Bumpmap: %s%s\n", props.bumpMap, ssbumpStr))
    else
        MsgC(Color(255, 200, 100), "  ✗ Bumpmap: (none)\n")
    end
    
    -- Phong exponent texture
    if props.hasPhongExponentTexture then
        MsgC(Color(100, 255, 100), string.format("  ✓ Phong Exponent Texture: %s\n", props.phongExponentTexture))
    end
    
    -- Envmap mask
    if props.hasEnvMapMask then
        MsgC(Color(100, 255, 100), string.format("  ✓ Envmap Mask: %s\n", props.envMapMask))
    end
    
    -- =========================================================================
    -- Format-specific info
    -- =========================================================================
    if props.isExoPBR then
        MsgC(Color(100, 255, 200), "\n  --- ExoPBR Format ---\n")
        if props.hasARMTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ ARM Texture: %s\n", props.armTexture))
        end
        if props.hasExoNormal then
            MsgC(Color(100, 255, 100), string.format("  ✓ ExoPBR Normal: %s\n", props.exoNormal))
        end
        if props.hasEmissionTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ Emission: %s\n", props.emissionTexture))
        end
    end
    
    if props.isGPBR then
        MsgC(Color(200, 100, 255), "\n  --- GPBR (Strata) Format ---\n")
        if props.hasMRAOTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ MRAO Texture: %s\n", props.mraoTexture))
        end
        if props.hasGPBREmission then
            MsgC(Color(100, 255, 100), string.format("  ✓ Emission: %s\n", props.gpbrEmission))
        end
    end
    
    if props.isMWBPBR then
        MsgC(Color(150, 255, 150), "\n  --- MWB PBR Gen Format ---\n")
        MsgC(Color(200, 200, 200), "  MWB encoding uses $phongexponenttexture for PBR data:\n")
        if props.hasBFTExponentTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ Exponent Texture: %s\n", props.bftExponentTexture))
            MsgC(Color(150, 150, 150), "    Red channel: pow(gloss, 4.0) → roughness via pow^0.25\n")
            MsgC(Color(150, 150, 150), "    Green channel: metallic value (direct)\n")
            MsgC(Color(150, 150, 150), "    Alpha channel: roughness for rimlight\n")
        end
        if props.hasBaseTexture then
            MsgC(Color(150, 150, 150), "  Base texture alpha may contain metallic mask\n")
        end
        MsgC(Color(200, 200, 200), "  Note: MWB converts PBR textures to Source Engine phong workflow\n")
    end
    
    if props.isBFTPseudoPBR then
        MsgC(Color(255, 200, 100), "\n  --- PseudoPBR (BlueFlyTrap/MWB) ---\n")
        if props.hasBFTExponentTexture then
            MsgC(Color(100, 255, 100), string.format("  ✓ Exponent Texture (roughness): %s\n", props.bftExponentTexture))
        end
        if props.isBFTMetallicLayer then
            MsgC(Color(255, 200, 100), "  ! Metallic Layer ($translucent + $phongalbedotint)\n")
        end
        if props.isBFTDiffuseLayer then
            MsgC(Color(255, 200, 100), "  ! Diffuse Layer (uses $blendTintByBaseAlpha)\n")
        end
        if props.hasBFTBlendTintByBaseAlpha then
            MsgC(Color(255, 150, 100), "  ! $blendTintByBaseAlpha detected (alpha = metallic mask)\n")
        end
        if props.hasBFTColor2 and props.bftColor2 then
            MsgC(Color(200, 200, 200), string.format("  $color2: [%.2f %.2f %.2f]\n", 
                props.bftColor2.r or 0, props.bftColor2.g or 0, props.bftColor2.b or 0))
        end
    end
    
    -- =========================================================================
    -- Auto-discovered textures
    -- =========================================================================
    local hasDiscovered = props.hasDiscoveredNormal or props.hasDiscoveredHeight or 
                          props.hasDiscoveredMask or props.hasDiscoveredAO
    if hasDiscovered then
        MsgC(Color(100, 200, 255), "\n  --- Auto-Discovered Textures ---\n")
        if props.hasDiscoveredNormal then
            MsgC(Color(100, 255, 100), string.format("  ✓ Normal: %s\n", props.discoveredNormal))
        end
        if props.hasDiscoveredHeight then
            MsgC(Color(100, 255, 100), string.format("  ✓ Height: %s\n", props.discoveredHeight))
        end
        if props.hasDiscoveredMask then
            MsgC(Color(100, 255, 100), string.format("  ✓ Mask/Spec: %s\n", props.discoveredMask))
        end
        if props.hasDiscoveredAO then
            MsgC(Color(100, 255, 100), string.format("  ✓ AO: %s\n", props.discoveredAO))
        end
    end
    
    -- =========================================================================
    -- Roughness Sources
    -- =========================================================================
    MsgC(Color(100, 200, 255), "\n  --- Roughness Sources ---\n")
    local roughnessSource = "Default (0.5)"
    
    if props.hasPhongExponentTexture then
        roughnessSource = "Phong Exponent Texture (best)"
    elseif props.normalMapAlphaEnvMapMask and props.hasBumpMap then
        roughnessSource = "Normal Map Alpha ($normalmapalphaenvmapmask)"
    elseif props.hasBaseAlphaEnvMapMask then
        roughnessSource = "Base Texture Alpha ($basealphaenvmapmask)"
    elseif props.hasBaseMapAlphaPhongMask then
        roughnessSource = "Base Texture Alpha ($basemapalphaphongmask)"
    elseif props.hasEnvMapMask then
        roughnessSource = "Envmap Mask Texture"
    elseif props.hasDiscoveredMask then
        roughnessSource = "Auto-discovered Mask/Spec"
    elseif props.hasPhong then
        roughnessSource = string.format("Phong Exponent (%.1f)", props.phongExponent or 0)
    end
    
    MsgC(Color(200, 200, 200), string.format("  Source: %s\n", roughnessSource))
    
    -- =========================================================================
    -- Calculated PBR Values
    -- =========================================================================
    MsgC(Color(100, 200, 255), "\n  --- Calculated PBR Values ---\n")
    MsgC(Color(200, 200, 200), string.format("  Roughness: %.2f\n", props.roughness or 0.5))
    MsgC(Color(200, 200, 200), string.format("  Metallic: %.2f\n", props.metallic or 0))
    
    if props.hasBaseTextureBrightness then
        MsgC(Color(150, 150, 150), string.format("  Base Texture Brightness: %.2f\n", props.baseTextureBrightness or 0))
    end
    
    -- =========================================================================
    -- Envmap Properties
    -- =========================================================================
    if props.hasEnvMap or props.hasEnvMapTint then
        MsgC(Color(100, 200, 255), "\n  --- Environment Map ---\n")
        if props.hasEnvMap then
            MsgC(Color(100, 255, 100), "  ✓ Has Envmap\n")
        end
        if props.hasEnvMapTint and props.envMapTint then
            MsgC(Color(200, 200, 200), string.format("  $envmaptint: [%.2f %.2f %.2f]\n", 
                props.envMapTint.r or 0, props.envMapTint.g or 0, props.envMapTint.b or 0))
        end
        if props.hasEnvMapContrast then
            MsgC(Color(200, 200, 200), string.format("  $envmapcontrast: %.2f\n", props.envMapContrast or 1))
        end
        if props.hasEnvMapSaturation then
            MsgC(Color(200, 200, 200), string.format("  $envmapsaturation: %.2f\n", props.envMapSaturation or 1))
        end
    end
    
    -- =========================================================================
    -- Phong Properties
    -- =========================================================================
    if props.hasPhong or props.hasPhongFresnelRanges or props.hasRimLight then
        MsgC(Color(100, 200, 255), "\n  --- Phong/Specular ---\n")
        if props.hasPhong then
            MsgC(Color(200, 200, 200), string.format("  Exponent: %.1f\n", props.phongExponent or 0))
        end
        if props.phongBoost and props.phongBoost > 0 then
            MsgC(Color(200, 200, 200), string.format("  Boost: %.2f\n", props.phongBoost))
        end
        if props.hasPhongFresnelRanges and props.phongFresnelRanges then
            MsgC(Color(200, 200, 200), string.format("  Fresnel: [%.2f %.2f %.2f]\n", 
                props.phongFresnelRanges[1] or 0, props.phongFresnelRanges[2] or 0, props.phongFresnelRanges[3] or 0))
        end
        if props.hasRimLight then
            MsgC(Color(200, 200, 200), string.format("  Rim Light: exp=%.1f boost=%.2f\n", 
                props.rimLightExponent or 0, props.rimLightBoost or 0))
        end
    end
    
    -- =========================================================================
    -- Material Flags
    -- =========================================================================
    local hasFlags = props.isSelfIllum or props.isTranslucent or props.isGlass
    if hasFlags then
        MsgC(Color(100, 200, 255), "\n  --- Flags ---\n")
        if props.isSelfIllum then
            MsgC(Color(255, 200, 100), "  ! Self-illuminated (emissive)\n")
            if props.hasSelfIllumMask then
                MsgC(Color(150, 150, 150), string.format("    Mask: %s\n", props.selfIllumMask))
            end
        end
        if props.isTranslucent then
            MsgC(Color(255, 200, 100), "  ! Translucent material\n")
        end
        if props.isGlass then
            MsgC(Color(100, 200, 255), "  ✓ GLASS MATERIAL (RTX Translucent shader, IOR 1.5)\n")
        end
    end
    
    -- =========================================================================
    -- Surface Properties
    -- =========================================================================
    if props.surfaceProp and props.surfaceProp ~= "" then
        MsgC(Color(100, 200, 255), "\n  --- Surface ---\n")
        MsgC(Color(150, 150, 150), string.format("  Surface Prop: %s\n", props.surfaceProp))
    end
    
    -- Parallax
    if props.hasParallaxMap then
        MsgC(Color(100, 200, 255), "\n  --- Parallax ---\n")
        MsgC(Color(100, 255, 100), string.format("  ✓ Parallax Map: %s\n", props.parallaxMap))
    end
    
    MsgC(Color(100, 200, 255), string.rep("=", 70) .. "\n\n")
    
    return props
end

--[[
    Get conversion statistics
]]--
function RTXToPBR.GetStats()
    local processor = GetProcessor()
    if not processor then
        return {
            materialsProcessed = 0,
            texturesUploaded = 0,
            materialsWithNormals = 0,
            materialsWithRoughness = 0,
            failedConversions = 0
        }
    end
    
    return processor.GetStats()
end

--[[
    Clear conversion cache
]]--
local gameAssets, gameKey, gameParts, gameSlot, gameSubmitted, gameNext = nil, nil, nil, 1, {}, 0
function RTXToPBR.ClearCache()
    local processor = GetProcessor()
    if processor then
        processor.ClearCache()
    end
    gameAssets, gameKey, gameParts, gameSlot, gameSubmitted, gameNext = nil, nil, nil, 1, {}, 0
    MsgC(Color(100, 255, 100), "[RTX ToPBR] Cache cleared\n")
end

--[[
    Set debug output
]]--
function RTXToPBR.SetDebugOutput(enabled)
    local processor = GetProcessor()
    if processor then
        processor.SetDebugOutput(enabled)
    end
end

-- NOTE: Continuous processing (StartContinuousProcessing, StopContinuousProcessing, IsContinuousProcessing)
-- has been REMOVED. All material discovery and continuous processing is now handled by RTXMaterialPipeline.
-- Use rtx_mat_continuous and rtx_mat_continuous_interval convars to control pipeline processing.

-- Console Commands
concommand.Add("rtx_topbr_inspect", function(ply, cmd, args)
    if not args[1] or args[1] == "" then
        -- No material specified - try to get from what player is looking at
        local matName, traceInfo = RTXToPBR.GetMaterialFromTrace()
        
        if not matName then
            MsgC(Color(255, 200, 100), "Usage: rtx_topbr_inspect [material_name]\n")
            MsgC(Color(255, 200, 100), "  If no material specified, looks at what you're aiming at.\n")
            MsgC(Color(255, 200, 100), "Example: rtx_topbr_inspect concrete/concretefloor001a\n")
            return
        end
        
        -- Show trace info
        if traceInfo then
            if traceInfo.type == "entity" then
                MsgC(Color(100, 200, 255), string.format("[RTX ToPBR] Looking at entity: %s\n", traceInfo.class or "unknown"))
                if traceInfo.model then
                    MsgC(Color(150, 150, 150), string.format("  Model: %s\n", traceInfo.model))
                end
                if traceInfo.allMaterials and #traceInfo.allMaterials > 1 then
                    MsgC(Color(150, 150, 150), string.format("  Entity has %d materials. Showing first one.\n", #traceInfo.allMaterials))
                    MsgC(Color(150, 150, 150), "  All materials:\n")
                    for i, mat in ipairs(traceInfo.allMaterials) do
                        MsgC(Color(120, 120, 120), string.format("    [%d] %s\n", i, mat))
                    end
                end
            elseif traceInfo.type == "brush" then
                MsgC(Color(100, 200, 255), "[RTX ToPBR] Looking at brush/world surface\n")
            end
        end
        
        RTXToPBR.InspectMaterial(matName)
    else
        RTXToPBR.InspectMaterial(args[1])
    end
end, nil, "Inspect a material's PBR properties. If no material specified, inspects what you're looking at.")

concommand.Add("rtx_topbr_stats", function()
    local stats = RTXToPBR.GetStats()
    MsgC(Color(100, 200, 255), "[RTX ToPBR] Conversion Statistics:\n")
    MsgC(Color(200, 200, 200), string.format("  Materials processed: %d\n", stats.materialsProcessed or 0))
    MsgC(Color(200, 200, 200), string.format("  Textures uploaded: %d\n", stats.texturesUploaded or 0))
    MsgC(Color(200, 200, 200), string.format("  Materials with normals: %d\n", stats.materialsWithNormals or 0))
    MsgC(Color(200, 200, 200), string.format("  Materials with roughness: %d\n", stats.materialsWithRoughness or 0))
    MsgC(Color(200, 200, 200), string.format("  Failed conversions: %d\n", stats.failedConversions or 0))
    
    print(string.format("[RTX ToPBR] max client snapshot %.3f ms, max worker job %.3f ms", stats.snapshotMaxMs or 0, stats.decodeMaxMs or 0))

    -- Background processing status
    local p = GetProcessor()
    local isProcessing = p and p.IsProcessingInBackground and p.IsProcessingInBackground() or false
    local queuedCount = p and p.GetQueuedMaterialCount and p.GetQueuedMaterialCount() or 0
    local lastProcessed = p and p.GetLastProcessedCount and p.GetLastProcessedCount() or 0
    
    MsgC(Color(100, 200, 255), "\n  Background Processing:\n")
    if isProcessing then
        MsgC(Color(100, 255, 100), string.format("  ✓ ACTIVE - %d materials in queue, %d processed this run\n", queuedCount, lastProcessed))
    else
        MsgC(Color(200, 200, 200), string.format("  Idle - %d processed in last run\n", lastProcessed))
    end
    

end, nil, "Show PBR conversion statistics")

concommand.Add("rtx_topbr_clear", function()
    RTXToPBR.ClearCache()
end, nil, "Clear PBR conversion cache")

-- These are convars, not commands with the same name (Source refuses duplicates).
for _, pair in ipairs({{"rtx_topbr_debug", "SetDebugOutput"},
    {"rtx_topbr_metallic", "SetMetallicGeneration"},
    {"rtx_topbr_autodiscover", "SetAutoDiscover"},
    {"rtx_topbr_parse_commented_properties", "SetParseCommentedProperties"}}) do
    cvars.AddChangeCallback(pair[1], function(_, _, value)
        local p = GetProcessor()
        if p and p[pair[2]] then p[pair[2]](tobool(value)) end
    end, "RTXToPBR_" .. pair[1])
end

hook.Add("Think", "RTXToPBR_Snapshots", function()
    local p = GetProcessor()
    if p and p.PumpSnapshots then p.PumpSnapshots() end
end)

concommand.Add("rtx_topbr_process", function()
    local p = GetProcessor()
    if p and p.QueueMaterialsForProcessing then p.QueueMaterialsForProcessing() end
end)

concommand.Add("rtx_topbr_help", function()
    MsgC(Color(100, 200, 255), "\n[RTX ToPBR] Runtime PBR Material Converter\n")
    MsgC(Color(100, 200, 255), string.rep("=", 70) .. "\n")
    MsgC(Color(255, 255, 255), [[
This module converts Source Engine materials to PBR materials in RTX Remix.

NOTE: Material discovery and continuous processing is now handled by
RTXMaterialPipeline (cl_material_pipeline.lua). ToPBR only processes
individual materials when called by the pipeline.

Use these pipeline convars for continuous processing:
  rtx_mat_continuous          - Enable continuous discovery (default: 1)
  rtx_mat_continuous_interval - Discovery interval in seconds (default: 5)

ToPBR Configuration Commands:
  rtx_topbr_inspect [material] - Inspect material's PBR properties
                                 (no argument = look at what you're aiming at)
  rtx_topbr_stats             - Show conversion statistics
  rtx_topbr_clear             - Clear conversion cache
  rtx_topbr_debug 1/0         - Enable/disable debug output
  rtx_topbr_metallic 1/0      - Compatibility flag (darkness inference removed)
  rtx_topbr_autodiscover 1/0  - Enable/disable auto-discovery of 
                                companion textures (_normal, _mask, _spec)
  rtx_topbr_parse_commented_properties 1/0
                              - Enable/disable parsing of commented-out
                                VMT properties (e.g., //"$envmap")
  rtx_topbr_help              - Show this help

SUPPORTED PBR FORMATS:
- ExoPBR (screenspace_general_8tex shader with ARM textures)
- GPBR/Strata ("PBR" shader with MRAO textures)
- PseudoPBR (BlueFlyTrap/MWB phong-based PBR encoding)
- Standard Source Engine materials (phong, envmap, etc.)

Roughness Priority (phong materials are handled first):
1. $phongexponenttexture (best quality)
2. $basemapalphaphongmask / $normalmapalphaenvmapmask
3. $envmapmask texture
4. Auto-discovered _mask/_spec textures
5. Base texture alpha with envmap

Note: Dark envmap materials (chrome balls, etc.) use low roughness
for reflections by default. Darkness alone no longer makes a material metallic. Explicit community
PBR channels and unmasked chrome remain supported.

]])
    MsgC(Color(100, 200, 255), string.rep("=", 60) .. "\n\n")
end, nil, "Show ToPBR help information")

-- Sync rtx_topbr_enabled ConVar to C++ when changed at runtime
cvars.AddChangeCallback("rtx_topbr_enabled", function(_, _, new)
    local processor = GetProcessor()
    if processor and processor.SetEnabled then
        processor.SetEnabled(tobool(new))
    end
end, "RTXToPBREnabled")

-- NOTE: Auto-processing and continuous processing hooks have been REMOVED.
-- All material discovery and processing timing is now handled by RTXMaterialPipeline.
-- ToPBR is called as Stage 3 of the unified pipeline.

-- Startup message
MsgC(Color(100, 255, 100), "[RTX ToPBR] Runtime PBR Converter loaded.\n")
MsgC(Color(200, 200, 200), "  Processing controlled by RTXMaterialPipeline.\n")
if MaterialPipeline and MaterialPipeline.ToPBR then
    MsgC(Color(200, 200, 200), "  C++ MaterialPipeline.ToPBR module available.\n")
    -- Sync enabled state immediately at load time so a saved rtx_topbr_enabled=0
    -- takes effect before the C++ worker thread processes any queued materials
    if MaterialPipeline.ToPBR.SetEnabled then
        MaterialPipeline.ToPBR.SetEnabled(GetConVarBoolSafe("rtx_topbr_enabled", false))
    end
else
    MsgC(Color(255, 200, 100), "  C++ MaterialPipeline.ToPBR module not loaded - waiting for binary module.\n")
end
MsgC(Color(200, 200, 200), "  Use 'rtx_topbr_help' for usage information.\n")


-- The source path is local-only hotloader data; no network or importer hook is needed.
CreateClientConVar("rtx_topbr_game_maps", "1", true, false, "Use shipped packed game PBR maps on imported characters")
local function syncGameMaps()
    local p = GetProcessor()
    if p and p.SetGameEnabled then p.SetGameEnabled(GetConVarBoolSafe("rtx_topbr_game_maps", true)) end
end
cvars.AddChangeCallback("rtx_topbr_game_maps", syncGameMaps, "RTXToPBRGameMaps")
hook.Add("Think", "RTXToPBR_GameMaps", function()
    local p = GetProcessor()
    if not p or not p.QueueGameMaterial then return end
    syncGameMaps()
    if not GetConVarBoolSafe("rtx_topbr_game_maps", true) then return end
    if not gameAssets then
        if RealTime() < gameNext then return end
        gameAssets = mmdhl and mmdhl.assets or {}
        gameKey, gameParts, gameSlot = nil, nil, 1
    end
    for _ = 1, 8 do
        if gameParts and gameParts[gameSlot] then
            local slot = gameSlot
            local part = gameParts[slot]
            gameSlot = slot + 1
            local entry = mmdhl and mmdhl.library and mmdhl.library.entries[gameKey]
            local original = entry and entry.info and entry.info.materials and entry.info.materials[slot]
            local name = istable(part) and part.path
            local source = entry and entry.source
            local base = original and original.base
            if isstring(name) and not gameSubmitted[name] then
                -- Native restores only recorded, validated maps for the live texture identity.
                if p.QueueGameMaterial(name, isstring(source) and source or "", isstring(base) and base or "") then
                    gameSubmitted[name] = true
                end
            end
        else
            if gameKey and gameAssets[gameKey] == nil then gameKey = nil end
            local info
            gameKey, info = next(gameAssets, gameKey)
            if not gameKey then
                gameAssets, gameParts, gameNext = nil, nil, RealTime() + 5
                break
            end
            gameParts, gameSlot = istable(info) and info.materials or {}, 1
        end
    end
end)

-- BEGIN R12 IMPORTED GAME PBR PANEL
do
-- GPL-2.0. Imported-game PBR choices, shared by the actual base texture.
if SERVER or not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
RTXGamePBRPanel = RTXGamePBRPanel or {}
local P = RTXGamePBRPanel
local i18n = file.Exists("nativeloader/i18n.lua", "LUA") and include("nativeloader/i18n.lua") or nil
-- New panel phrases live in the GPL part; use the bundle catalog first.
local panelPhrases = {
    ["zh-CN"] = {
        ["Character"] = "角色",
        ["Selected maps use another game layout."] = "所选贴图使用另一种游戏格式。",
        ["Imported game PBR"] = "导入的游戏 PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "看向角色后列出材质。选择适用于所有共用此纹理的角色。",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "手工制作的 Remix 替换优先。脸和眼睛保护仍然有效。",
        ["Select a material"] = "选择材质",
        ["Map family"] = "贴图组",
        ["Normal map"] = "法线贴图",
        ["Packed map"] = "打包贴图",
        ["Emission map"] = "自发光贴图",
        ["Game layout"] = "游戏格式",
        ["List looked-at character"] = "列出所看角色",
        ["Use selected family"] = "使用所选贴图组",
        ["Use individual maps"] = "使用单独贴图",
        ["No game maps for this texture"] = "此纹理不使用游戏贴图",
        ["Return to automatic"] = "恢复自动",
        ["None"] = "无",
        ["waiting"] = "等待中",
        ["automatic"] = "自动",
        ["cached"] = "已缓存",
        ["override"] = "手动覆盖",
        ["none"] = "无",
        ["error"] = "错误",
    },
    ["zh-TW"] = {
        ["Character"] = "角色",
        ["Selected maps use another game layout."] = "所選貼圖使用另一種遊戲格式。",
        ["Imported game PBR"] = "匯入的遊戲 PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "看向角色後列出材質。選擇適用於所有共用此紋理的角色。",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "手工製作的 Remix 替換優先。臉和眼睛保護仍然有效。",
        ["Select a material"] = "選擇材質",
        ["Map family"] = "貼圖組",
        ["Normal map"] = "法線貼圖",
        ["Packed map"] = "打包貼圖",
        ["Emission map"] = "自發光貼圖",
        ["Game layout"] = "遊戲格式",
        ["List looked-at character"] = "列出所看角色",
        ["Use selected family"] = "使用所選貼圖組",
        ["Use individual maps"] = "使用個別貼圖",
        ["No game maps for this texture"] = "此紋理不使用遊戲貼圖",
        ["Return to automatic"] = "恢復自動",
        ["None"] = "無",
        ["waiting"] = "等待中",
        ["automatic"] = "自動",
        ["cached"] = "已快取",
        ["override"] = "手動覆寫",
        ["none"] = "無",
        ["error"] = "錯誤",
    },
    ["ja"] = {
        ["Character"] = "キャラクター",
        ["Selected maps use another game layout."] = "選択したマップは別のゲーム形式です。",
        ["Imported game PBR"] = "インポートしたゲームの PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "キャラクターを見て材質を一覧表示します。同じテクスチャを使う全キャラクターに適用されます。",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "作成済みの Remix 置換が優先されます。顔と目の保護は有効です。",
        ["Select a material"] = "材質を選択",
        ["Map family"] = "マップの組",
        ["Normal map"] = "法線マップ",
        ["Packed map"] = "パックマップ",
        ["Emission map"] = "発光マップ",
        ["Game layout"] = "ゲーム形式",
        ["List looked-at character"] = "見ているキャラを一覧表示",
        ["Use selected family"] = "選択した組を使用",
        ["Use individual maps"] = "個別のマップを使用",
        ["No game maps for this texture"] = "このテクスチャのゲームマップを無効化",
        ["Return to automatic"] = "自動に戻す",
        ["None"] = "なし",
        ["waiting"] = "待機中",
        ["automatic"] = "自動",
        ["cached"] = "キャッシュ済み",
        ["override"] = "手動設定",
        ["none"] = "なし",
        ["error"] = "エラー",
    },
    ["ko"] = {
        ["Character"] = "캐릭터",
        ["Selected maps use another game layout."] = "선택한 맵은 다른 게임 형식입니다.",
        ["Imported game PBR"] = "가져온 게임 PBR",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "캐릭터를 바라본 뒤 재질을 나열하세요. 같은 텍스처를 쓰는 모든 캐릭터에 적용됩니다.",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "제작된 Remix 교체가 우선합니다. 얼굴과 눈 보호는 유지됩니다.",
        ["Select a material"] = "재질 선택",
        ["Map family"] = "맵 그룹",
        ["Normal map"] = "노멀 맵",
        ["Packed map"] = "패킹 맵",
        ["Emission map"] = "발광 맵",
        ["Game layout"] = "게임 형식",
        ["List looked-at character"] = "바라보는 캐릭터 나열",
        ["Use selected family"] = "선택한 그룹 사용",
        ["Use individual maps"] = "개별 맵 사용",
        ["No game maps for this texture"] = "이 텍스처의 게임 맵 끄기",
        ["Return to automatic"] = "자동으로 복귀",
        ["None"] = "없음",
        ["waiting"] = "대기 중",
        ["automatic"] = "자동",
        ["cached"] = "캐시됨",
        ["override"] = "수동 설정",
        ["none"] = "없음",
        ["error"] = "오류",
    },
    ["fr"] = {
        ["Character"] = "Personnage",
        ["Selected maps use another game layout."] = "Ces cartes utilisent un autre format de jeu.",
        ["Imported game PBR"] = "PBR des jeux importés",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "Visez un personnage, puis listez ses matériaux. Les choix concernent tous les personnages partageant cette texture.",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "Les remplacements Remix créés ont priorité. La protection du visage et des yeux reste active.",
        ["Select a material"] = "Choisir un matériau",
        ["Map family"] = "Famille de cartes",
        ["Normal map"] = "Carte normale",
        ["Packed map"] = "Carte groupée",
        ["Emission map"] = "Carte émissive",
        ["Game layout"] = "Format du jeu",
        ["List looked-at character"] = "Lister le personnage visé",
        ["Use selected family"] = "Utiliser cette famille",
        ["Use individual maps"] = "Utiliser des cartes séparées",
        ["No game maps for this texture"] = "Aucune carte de jeu pour cette texture",
        ["Return to automatic"] = "Revenir au mode automatique",
        ["None"] = "Aucune",
        ["waiting"] = "en attente",
        ["automatic"] = "automatique",
        ["cached"] = "en cache",
        ["override"] = "personnalisé",
        ["none"] = "aucune",
        ["error"] = "erreur",
    },
    ["ru"] = {
        ["Character"] = "Персонаж",
        ["Selected maps use another game layout."] = "Выбранные карты используют другой формат игры.",
        ["Imported game PBR"] = "PBR импортированных игр",
        ["Look at a character, then list its materials. Choices apply to every character sharing the same texture."] = "Посмотрите на персонажа и откройте список материалов. Выбор применяется ко всем персонажам с этой текстурой.",
        ["Authored Remix replacements take priority. Face and eye protection stays active."] = "Авторские замены Remix имеют приоритет. Защита лица и глаз сохраняется.",
        ["Select a material"] = "Выберите материал",
        ["Map family"] = "Набор карт",
        ["Normal map"] = "Карта нормалей",
        ["Packed map"] = "Упакованная карта",
        ["Emission map"] = "Карта свечения",
        ["Game layout"] = "Формат игры",
        ["List looked-at character"] = "Материалы выбранного персонажа",
        ["Use selected family"] = "Применить набор",
        ["Use individual maps"] = "Применить отдельные карты",
        ["No game maps for this texture"] = "Без игровых карт для этой текстуры",
        ["Return to automatic"] = "Вернуть автоматический выбор",
        ["None"] = "Нет",
        ["waiting"] = "ожидание",
        ["automatic"] = "автоматически",
        ["cached"] = "из кеша",
        ["override"] = "переопределение",
        ["none"] = "нет",
        ["error"] = "ошибка",
    },
}
local function L(text)
    local translated = i18n and i18n.A(text) or text
    if translated ~= text then return translated end
    local cv = GetConVar("nativeloader_language")
    local code = cv and cv:GetString() or ""
    if code == "" then local game = GetConVar("gmod_language") code = game and game:GetString() or "en" end
    code = ({zh="zh-CN", ["zh-cn"]="zh-CN", ["zh-tw"]="zh-TW"})[code] or code
    local phrases = panelPhrases[code]
    return phrases and phrases[text] or text
end
local function processor() return MaterialPipeline and MaterialPipeline.ToPBR end
local actionErrors = {}

function P.Materials(ent)
    local id = IsValid(ent) and mmdhl and mmdhl.GetAsset and mmdhl.GetAsset(ent)
    local asset = id and mmdhl.assets and mmdhl.assets[id]
    local entry = id and mmdhl.library and mmdhl.library.entries and mmdhl.library.entries[id]
    local rows = {}
    for slot, part in ipairs(asset and asset.materials or {}) do
        local original = entry and entry.info and entry.info.materials and entry.info.materials[slot] or {}
        if isstring(part.path) then rows[#rows + 1] = {name=part.path, source=entry and entry.source or "",
            base=original.base or "", label=original.name or part.name or original.base or part.path} end
    end
    return rows
end
function P.Targets()
    local targets = {}
    for _, ent in ipairs(mmdhl and mmdhl.Entities and mmdhl.Entities() or {}) do
        if #targets >= 128 then break end
        if IsValid(ent) and not (mmdhl.PresentationSuppressed and mmdhl.PresentationSuppressed(ent)) and #P.Materials(ent) > 0 then
            local id = mmdhl.GetAsset(ent)
            local entry = mmdhl.library and mmdhl.library.entries and mmdhl.library.entries[id]
            local asset = mmdhl.assets[id]
            local label = entry and (entry.name or entry.info and entry.info.name) or asset and asset.name
            if not isstring(label) or label == "" then label = L("Character") end
            if mmdhl.names and mmdhl.names.Display then label = mmdhl.names.Display(label, id) end
            targets[#targets + 1] = {entity=ent, label=label}
        end
    end
    return targets
end
function P.Action(row, action, maps)
    local p = processor()
    if not p or not p.GameMaterialAction or not row then return false end
    maps = maps or {}
    if action == "maps" and p.GetGameMaterial then
        local function path(value) return (value or ""):gsub("\\", "/"):lower() end
        for _, choice in ipairs(p.GetGameMaterial(row.name).choices or {}) do
            if choice.layout ~= (maps.layout or 0) then
                for _, selected in ipairs({maps.normal or "", maps.packed or "", maps.emission or ""}) do
                    if selected ~= "" then
                        for _, known in ipairs({choice.normal or "", choice.packed or "", choice.emission or ""}) do
                            if path(selected) == path(known) then
                                actionErrors[row.name] = L("Selected maps use another game layout.")
                                return false
                            end
                        end
                    end
                end
            end
        end
    end
    actionErrors[row.name] = nil
    return p.GameMaterialAction(row.name, row.source, row.base, action,
        maps.normal or "", maps.packed or "", maps.emission or "", maps.layout or 0)
end
function P.State(row)
    local p = processor()
    local view = p and p.GetGameMaterial and p.GetGameMaterial(row.name) or {state="waiting", identity=""}
    if actionErrors[row.name] then view.error = actionErrors[row.name] end
    return view
end

function P.Build(panel)
    panel:Clear()
    panel:CheckBox(L("Imported game PBR"), "rtx_topbr_game_maps")
    panel:Help(L("Look at a character, then list its materials. Choices apply to every character sharing the same texture."))
    panel:Help(L("Authored Remix replacements take priority. Face and eye protection stays active."))
    local characters = panel:ComboBox(L("Character"))
    local list = vgui.Create("DScrollPanel", panel)
    list:SetTall(240) panel:AddItem(list)
    local selected, signature, family, files = nil, nil, nil, nil
    local rowUpdates = {}
    local status = panel:Help(L("Select a material"))
    local families = panel:ComboBox(L("Map family"))
    local normal = panel:ComboBox(L("Normal map"))
    local packed = panel:ComboBox(L("Packed map"))
    local emission = panel:ComboBox(L("Emission map"))
    local layout = panel:ComboBox(L("Game layout"))
    for i, name in ipairs({"Wuthering Waves", "Endfield", "Silver Palace"}) do layout:AddChoice(name, i-1) end
    layout:ChooseOptionID(1)
    local function rebuild(target)
        list:Clear() rowUpdates = {}
        local default, defaultRank = nil, -1
        local ply = LocalPlayer()
        local trace = IsValid(ply) and (ply.GetEyeTraceNoCursor and ply:GetEyeTraceNoCursor() or ply:GetEyeTrace())
        local ent = target or trace and trace.Entity
        for _, row in ipairs(P.Materials(ent)) do
            local button = list:Add("DButton")
            button:Dock(TOP) button:SetTall(64) button:DockMargin(0, 0, 0, 4)
            button:SetText("")
            local image = vgui.Create("DImage", button) image:Dock(LEFT) image:SetWide(60)
            local label = vgui.Create("DLabel", button) label:Dock(FILL) label:SetWrap(true) label:SetDark(true)
            local thumbnail = ""
            local function update()
                local state = P.State(row)
                -- Never load an unseen material just to show a thumbnail.
                if state.identity ~= "" and thumbnail ~= state.identity then
                    image:SetMaterial(Material(row.name)) thumbnail = state.identity
                end
                label:SetText(tostring(row.label) .. "\n" .. L(state.state or "waiting"))
                return state
            end
            rowUpdates[#rowUpdates + 1] = update
            local state = update()
            local rank = state.state == "override" and 3 or (state.state == "automatic" or state.state == "cached") and 2 or 0
            if state.identity ~= "" and rank > defaultRank then default, defaultRank = button, rank end
            button.DoClick = function()
                selected, signature, family, files = row, nil, nil, nil
                P.Action(row, "options")
            end
        end
        if default then default.DoClick() list:ScrollToChild(default) end
    end
    local refresh = panel:Button(L("List looked-at character")) refresh.DoClick = function() rebuild() end
    families.OnSelect = function(_, _, _, data) family = data if data then layout:ChooseOptionID(data.layout + 1) end end
    local function chosen(combo) local _, data = combo:GetSelected() return data or "" end
    local useFamily = panel:Button(L("Use selected family"))
    useFamily.DoClick = function() if family then P.Action(selected, "maps", family) end end
    local useFiles = panel:Button(L("Use individual maps"))
    useFiles.DoClick = function()
        local _, gameLayout = layout:GetSelected()
        P.Action(selected, "maps", {normal=chosen(normal), packed=chosen(packed), emission=chosen(emission), layout=gameLayout or 0})
    end
    local none = panel:Button(L("No game maps for this texture")) none.DoClick = function() P.Action(selected, "none") end
    local automatic = panel:Button(L("Return to automatic")) automatic.DoClick = function() P.Action(selected, "automatic") end
    local nextPoll = 0
    if not panel.RTXGamePBRThinkInstalled then
        panel.RTXGamePBRThinkInstalled = true
        panel.RTXGamePBRBaseThink = panel.Think
    end
    panel.Think = function(self)
        if self.RTXGamePBRBaseThink then self:RTXGamePBRBaseThink() end
        if RealTime() < nextPoll then return end
        nextPoll = RealTime() + .5
        for _, update in ipairs(rowUpdates) do update() end
        if not selected then return end
        local view = P.State(selected)
        status:SetText(tostring(selected.label) .. "\n" .. (view.identity or "") .. "\n" .. L(view.state or "waiting") ..
            " " .. (view.family or "") .. "\n" .. (view.error or ""))
        local key = tostring(selected.name) .. ":" .. #(view.choices or {}) .. ":" .. #(view.files or {})
        if signature == key then return end
        signature = key families:Clear() normal:Clear() packed:Clear() emission:Clear()
        for index, choice in ipairs(view.choices or {}) do
            families:AddChoice(choice.name, choice)
            if choice.name == view.family then families:ChooseOptionID(index) end
        end
        for _, combo in ipairs({normal, packed, emission}) do
            combo:AddChoice(L("None"), "")
            for _, path in ipairs(view.files or {}) do combo:AddChoice(path, path) end
            combo:ChooseOptionID(1)
        end
    end
    characters.OnSelect = function(_, _, _, target) rebuild(target) end
    local ply = LocalPlayer()
    local trace = IsValid(ply) and (ply.GetEyeTraceNoCursor and ply:GetEyeTraceNoCursor() or ply:GetEyeTrace())
    local wanted = trace and trace.Entity
    local targets, index = P.Targets(), 1
    for number, target in ipairs(targets) do
        characters:AddChoice(target.label, target.entity)
        if target.entity == wanted then index = number end
    end
    if #targets > 0 then characters:ChooseOptionID(index) rebuild(targets[index].entity) else rebuild() end
end
hook.Add("PopulateToolMenu", "RTXImportedGamePBR", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix", "RTX_ImportedGamePBR", L("Imported game PBR"), "", "", P.Build)
end)
concommand.Add("rtx_topbr_game_editor", function()
    local frame = vgui.Create("DFrame") frame:SetSize(math.min(620, ScrW()-40), math.min(820, ScrH()-40)) frame:Center()
    P.Frame = frame
    frame:SetTitle(L("Imported game PBR")) frame:MakePopup()
    local scroll = vgui.Create("DScrollPanel", frame) scroll:Dock(FILL)
    local panel = vgui.Create("DForm", scroll) panel:SetName(L("Imported game PBR")) panel:Dock(TOP) P.Build(panel)
end)

end
-- END R12 IMPORTED GAME PBR PANEL

return RTXToPBR
