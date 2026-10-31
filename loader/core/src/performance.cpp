#include "nl/performance.h"
#include "nl/json.h"
#include <algorithm>
#include <optional>
#include <string_view>

namespace nl::performance {
namespace {
bool word(char c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; }
std::optional<Tier> class_tier(std::string description) {
  for (char& c : description) if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
  // Restrict the class rule to a whole consumer model number: RTX A4000, RTX 6000 Ada,
  // Quadro and future naming schemes keep the VRAM rule instead of guessing a class.
  for (std::size_t at = 0; (at = description.find("RTX ", at)) != std::string::npos; ++at) {
    if (at && word(description[at - 1])) continue;
    auto model = at + 4;
    while (model < description.size() && description[model] == ' ') ++model;
    if (model + 4 > description.size()) continue;
    const std::string_view digits(description.data() + model, 4);
    if (!std::all_of(digits.begin(), digits.end(), [](char c) { return c >= '0' && c <= '9'; }) ||
        digits[0] == '0' || digits[3] != '0' || (model + 4 < description.size() && word(description[model + 4]))) continue;
    Tier tier;
    switch (digits[2]) {
      case '9': case '8': tier = Tier::high; break;
      case '7': tier = Tier::medium; break;
      case '6': case '5': tier = Tier::low; break;
      default: continue;
    }
    if (description.find("LAPTOP") != std::string::npos && tier != Tier::low)
      tier = tier == Tier::high ? Tier::medium : Tier::low;
    return tier;
  }
  return std::nullopt;
}
}  // namespace

const char* name(Tier tier) {
  switch (tier) {
    case Tier::high: return "high";
    case Tier::medium: return "medium";
    case Tier::low: return "low";
  }
  return "high";
}

Selection classify(const std::vector<Adapter>& adapters, config::PerformanceTier requested) {
  Selection result;
  const Adapter* largest = nullptr;
  for (const auto& adapter : adapters)
    if (adapter.vendor == kNvidia && (!largest || adapter.dedicated_video_memory > largest->dedicated_video_memory)) largest = &adapter;
  if (!largest) {
    result.reason = "no NVIDIA adapter detected; no performance tier layer";
    return result;
  }
  result.nvidia = true;
  result.adapter = largest->description;
  result.dedicated_vram_mib = largest->dedicated_video_memory / (std::uint64_t{1} << 20);
  // Compare bytes so boundary adapters are classified before any MiB rounding.
  const auto memory = largest->dedicated_video_memory;
  const Tier vram = memory <= (std::uint64_t{8704} << 20) ? Tier::low
                  : memory <= (std::uint64_t{12800} << 20) ? Tier::medium : Tier::high;
  const auto model = class_tier(largest->description);
  result.tier = model ? std::max(vram, *model) : vram;
  result.reason = std::to_string(result.dedicated_vram_mib) + " MiB dedicated VRAM -> " + name(vram) +
                  (model ? "; RTX class (including laptop adjustment) -> " + std::string(name(*model))
                         : "; unrecognized RTX class, using VRAM alone");
  if (requested != config::PerformanceTier::automatic) {
    result.tier = requested == config::PerformanceTier::high ? Tier::high
                : requested == config::PerformanceTier::medium ? Tier::medium : Tier::low;
    result.source = "config";
    result.reason = "remix.performance_tier=" + std::string(name(result.tier)) + "; " + result.reason;
  }
  return result;
}

std::string serialize(const Selection& s) {
  return "{\"tier\":" + json::quote(name(s.tier)) + ",\"source\":" + json::quote(s.source) +
         ",\"reason\":" + json::quote(s.reason) + ",\"adapter\":" + json::quote(s.adapter) +
         ",\"dedicated_vram_mib\":" + std::to_string(s.dedicated_vram_mib) + ",\"layer\":" + json::quote(s.layer) + '}';
}
}  // namespace nl::performance
