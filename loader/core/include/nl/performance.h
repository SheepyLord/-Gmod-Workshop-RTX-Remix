#pragma once
// R6 GPU policy (ADR 0062). Classification and I2 serialization are pure; no DXGI or file access.
#include "nl/config.h"
#include <cstdint>
#include <string>
#include <vector>

namespace nl::performance {
inline constexpr unsigned kNvidia = 0x10DE;
struct Adapter {
  unsigned vendor = 0;
  std::string description;
  std::uint64_t dedicated_video_memory = 0;  // bytes, DXGI DedicatedVideoMemory
};
enum class Tier { high, medium, low };  // increasing means lighter defaults
const char* name(Tier tier);
struct Selection {
  Tier tier = Tier::high;
  std::string source = "auto";
  std::string reason = "performance tier not selected (RTX inactive)";
  std::string adapter;
  std::uint64_t dedicated_vram_mib = 0;
  std::string layer;  // the listed short copy, or empty
  bool nvidia = false;  // internal: not part of interface I2
};
// Largest NVIDIA adapter; lower of the VRAM tier and recognized consumer RTX class, with laptops
// one class step down. Known non-NVIDIA adapters get no tier layer. An empty query honors an
// explicit override; its reason reports that the GPU was not read. Overrides report source config.
Selection classify(const std::vector<Adapter>& adapters, config::PerformanceTier requested);
std::string serialize(const Selection& selection);  // R6 interface I2
}  // namespace nl::performance
