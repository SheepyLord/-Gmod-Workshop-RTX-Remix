// GPL-2.0. Production helper regression.
#include <cassert>
#include <cstring>
#include <sstream>
#include "../source/material_pipeline/to_pbr/formats.h"
#include "../source/material_pipeline/to_pbr/vtf.h"
#include "../source/material_pipeline/to_pbr/usda.h"
#include <limits>
#include "../source/material_pipeline/to_pbr/pbr_policy.h"
#include "../source/material_pipeline/to_pbr/fallback_guard.h"
using namespace MaterialPipeline::ToPBR;
int main(int argc, char** argv) {
    assert(argc == 2);
    assert(Policy::IsImportedMaterialName("mmd/0123456789abcdef/part"));
    assert(Policy::IsImportedMaterialName("!mmdhl_soft_v1_abcdef_2"));
    assert(!Policy::IsImportedMaterialName("models/props_c17/plastic"));
    assert(USDA::GetRelativeTexturePath("C:/textures/game/mod/textures/map.dds", "C:/textures/game/mod/textures") == "./textures/map.dds");
    assert(Policy::ValidImage(4096,4096));
    assert(!Policy::ValidImage(8192,8192));
    assert(!Policy::ValidImage(0,1));
    assert(Policy::PhongRoughness(10)>Policy::PhongRoughness(150));
    assert(std::isfinite(Policy::PhongRoughness(std::numeric_limits<float>::quiet_NaN())));
    assert(Policy::ReflectionRoughness(1)>=0.2f);
    assert(Policy::ReflectionRoughness(0)>0.85f);
    FallbackGuard::Result r;
    FallbackGuard::ExtractHashes("over \"mat_ABC\" def Material \"mat_0123456789abcdef\"",r);
    assert(r.complete && r.hashes.count(0xabc) && r.hashes.count(0x123456789abcdef));
    FallbackGuard::ExtractHashes("mat_0123456789abcdef0",r); assert(!r.complete);
    std::filesystem::path root=std::filesystem::u8path(argv[1]);
    std::filesystem::create_directories(root/L"~gmod_topbr");
    std::filesystem::create_directories(root/L"\uFFFFlater");
    { std::ofstream f(root/L"\uFFFFlater"/L"mod.usda"); f<<"#usda 1.0\nover \"mat_AABBCC\" {}"; }
    { std::ofstream f(root/L"~gmod_topbr"/L"mod.usda"); f<<"#usda 1.0\nover \"mat_112233\" {}"; }
    auto scan=FallbackGuard::Scan(root,root/L"~gmod_topbr");
    assert(scan.complete && scan.hashes.count(0xaabbcc) && !scan.hashes.count(0x112233));
    { std::ofstream f(root/L"\uFFFFlater"/L"new.usdc");f<<"PXR-USDC"; }
    assert(!FallbackGuard::Scan(root,root/L"~gmod_topbr").complete);
    std::filesystem::remove(root/L"\uFFFFlater"/L"new.usdc");
    { std::ofstream f(root/L"\uFFFFlater"/L"mod.usda"); f<<"#usda 1.0\nover \"mat_ABCDEF\" {}"; }
    scan=FallbackGuard::Scan(root,root/L"~gmod_topbr");
    assert(scan.complete && !scan.hashes.count(0xaabbcc) && scan.hashes.count(0xabcdef));
    assert(!Policy::ValidDDS(root/L"missing.dds"));
    // The production Source handler must not infer metal from a dark plastic diffuse.
    MaterialPBRProperties props{}; props.materialName="dark_plastic";
    props.hasEnvMap=true; props.hasBaseTextureBrightness=true; props.baseTextureBrightness=0.01f;
    props.baseTexturePath="plastic"; props.roughness=0.5f;
    ProcessingContext ctx;
    ctx.fileExists=[](const std::string&){return false;};
    ctx.readVTFFile=[](const std::string&,std::vector<uint8_t>&){return false;};
    ctx.metallicGenerationEnabled=true;
    auto output=SourceEngine::ProcessTextures(props,1,ctx);
    assert(output.success && output.metallicConstant==0 && output.albedoPath.empty());
    props.hasPhong=true;props.phongExponent=50;
    auto rough=SourceEngine::CalculateRoughness(props);
    props.phongBoost=100;props.hasPhongFresnelRanges=true; props.phongFresnelRanges[2]=100;
    assert(rough==SourceEngine::CalculateRoughness(props));
    // Exact VTF offsets, truncation, resources, unsupported formats and allocation bounds.
    VTFFileHeader header{}; std::memcpy(header.signature,"VTF\0",4);
    header.version[0]=7;header.version[1]=2;header.headerSize=80;
    header.width=header.height=2;header.frames=1;header.depth=1;header.mipmapCount=1;
    header.imageFormat=IMAGE_FORMAT_RGBA8888;
    std::vector<uint8_t> bytes(96,128); std::fill(bytes.begin(),bytes.begin()+80,0);
    ConvertedTexture image{};
    assert(VTF::ExtractVTFPixelData(bytes,header,image,false));
    bytes.resize(95);assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    bytes.resize(96);header.headerSize=4096;assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    header.headerSize=80; header.width=8192;assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    header.width=2;header.mipmapCount=255;assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    header.mipmapCount=1;header.frames=2;assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    header.frames=1;header.imageFormat=1000;assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    header.imageFormat=IMAGE_FORMAT_RGBA8888;header.version[1]=3;
    assert(!VTF::ExtractVTFPixelData(bytes,header,image,false));
    header.headerSize=88;bytes.resize(104);std::fill(bytes.begin()+80,bytes.begin()+88,0);bytes[68]=1;bytes[80]=0x30;bytes[84]=88;
    assert(VTF::ExtractVTFPixelData(bytes,header,image,false));
    // Publication replaces a complete snapshot, including deletion and changed existing hashes.
    std::unordered_map<uint64_t,TextureProcessor::ProcessedMaterialInfo> infos;
    TextureProcessor::ProcessedMaterialInfo info{};info.textureHash=0xabc;info.roughnessConstant=.5f;
    infos[0xabc]=info;
    const std::string dir=(root/"~gmod_topbr").u8string();
    assert(USDA::WriteMaterialsUSDAFile(dir,dir+"/textures",infos));
    infos.clear();assert(USDA::WriteMaterialsUSDAFile(dir,dir+"/textures",infos));
    std::ifstream empty(root/"~gmod_topbr"/"materials.usda");
    std::string text((std::istreambuf_iterator<char>(empty)),{});assert(text.find("mat_ABC")==std::string::npos);

    // A user-edited generated snapshot is retained byte-for-byte before replacement.
    const auto target=root/"~gmod_topbr"/"owned.usda", staging=root/"~gmod_topbr"/"owned.usda.tmp";
    {std::ofstream f(target);f<<"user original";}
    {std::ofstream f(staging);f<<"generated 1";}
    assert(USDA::PublishStagedFile(staging.u8string(),target.u8string()));
    {std::ofstream f(staging);f<<"generated 2";}
    assert(USDA::PublishStagedFile(staging.u8string(),target.u8string()));
    {std::ofstream f(target);f<<"user later edit";}
    {std::ofstream f(staging);f<<"generated 3";}
    assert(USDA::PublishStagedFile(staging.u8string(),target.u8string()));
    size_t originals=0,edits=0;
    for(const auto& entry:std::filesystem::directory_iterator(root/"~gmod_topbr")) {
        if(entry.path().extension()!=".bak")continue;
        std::ifstream f(entry.path());std::string text((std::istreambuf_iterator<char>(f)),{});
        originals+=text=="user original";edits+=text=="user later edit";
    }
    assert(originals==1 && edits==1);
    TextureProcessor::ProcessedMaterialInfo darkEmission{};darkEmission.emissivePath="C:/fixture/textures/glow.dds";darkEmission.emissionIntensity=0;
    std::ostringstream shaderText;USDA::WriteOpaqueMaterial(shaderText,1,darkEmission,"C:/fixture/textures");
    assert(shaderText.str().find("inputs:emissive_intensity = 0")!=std::string::npos);
    // Community channel unpackers stay independent of the vanilla heuristics.
    MaterialPBRProperties community{};community.materialName="fixture";
    std::unordered_map<std::string,ConvertedTexture> maps;
    ProcessingContext packedCtx;
    packedCtx.readVTFFile=[](const std::string&,std::vector<uint8_t>& data){data={16,64,192,255};return true;};
    packedCtx.parseVTFHeader=[](const std::vector<uint8_t>&,VTFFileHeader& h){h={};h.width=h.height=1;return true;};
    packedCtx.extractPixelData=[](const std::vector<uint8_t>& data,const VTFFileHeader&,ConvertedTexture& t,bool){t={};t.width=t.height=1;t.pixelData=data;return true;};
    packedCtx.generateOutputPath=[](const std::string& source,const std::string& suffix){return source+suffix;};
    packedCtx.fileExists=[](const std::string&){return false;};
    packedCtx.writeDDS=[&](const ConvertedTexture& t,const std::string& path){maps[path]=t;return true;};
    packedCtx.convertToOctahedral=[](ConvertedTexture&){};
    community.hasARMTexture=true;community.armTexturePath="arm";
    auto exo=ExoPBR::ProcessTextures(community,2,packedCtx);
    assert(exo.success && maps.at(exo.roughnessPath).pixelData[0]==64 && maps.at(exo.metallicPath).pixelData[0]==192);
    community={};community.hasMRAOTexture=true;community.mraoTexturePath="mrao";
    auto gpbr=GPBR::ProcessTextures(community,3,packedCtx);
    assert(gpbr.success && maps.at(gpbr.roughnessPath).pixelData[0]==64 && maps.at(gpbr.metallicPath).pixelData[0]==16);
    // All four format detectors handle unknown input without guessing an authored layout.
    VMTParseResult unknown;unknown.shaderName="unrecognized";
    assert(!ExoPBR::Detect(unknown) && !GPBR::Detect(unknown) && !MWBPBR::Detect(unknown) && !BFTPseudoPBR::Detect(unknown));

}

