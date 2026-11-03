// GPL-2.0. SDK-free test/probe transport types; algorithms come from production headers.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>
#define GAME_PBR_TYPES_PROVIDED
constexpr int REMIXAPI_FORMAT_R8G8B8A8_UNORM=0;
namespace MaterialPipeline {namespace ToPBR {
struct ConvertedTexture {uint32_t width=0,height=0,mipLevels=0;int format=0;bool isNormalMap=false;std::vector<uint8_t> pixelData;};
}}
