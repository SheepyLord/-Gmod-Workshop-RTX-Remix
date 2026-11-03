#pragma once
// R13 memory profiles (ADR 0101). A computer's VRAM and RAM choose how much the game keeps in memory:
// the minimum (8 GB VRAM, 16 GB RAM) loads characters on first use and keeps one copy of a game
// texture; larger computers keep more. Pure: the bootstrap reads the sizes and writes the layer.
#include "nl/config.h"
#include <cstdint>
#include <string>

namespace nl::memory_profile {

enum class Profile { below_minimum, minimum, recommended, high };  // increasing means more kept in memory
const char* name(Profile profile);

// The smallest size of each profile, in MiB. Windows reports a little less than the installed
// memory, so 8/16/24 GB cards and 16/32/64 GB computers land in their profile with room to spare.
inline constexpr std::uint64_t kMinimumVramMib = 7680, kRecommendedVramMib = 15360, kHighVramMib = 23552;
inline constexpr std::uint64_t kMinimumRamMib = 14336, kRecommendedRamMib = 28672, kHighRamMib = 57344;

struct Budget {
  Profile profile = Profile::minimum;
  std::string source = "auto";  // auto, or config: remix.memory_profile chose it
  std::string reason;
  std::uint64_t vram_mib = 0;  // the largest hardware adapter's dedicated VRAM; 0 when not read
  std::uint64_t ram_mib = 0;   // total physical memory; 0 when not read
  // Saved characters the hotloader keeps ready at map start (the most recently used), and at most
  // this many MiB of their material archives. The rest load when first used.
  unsigned warm_characters = 0;
  std::uint64_t warm_mib = 0;
  // The runtime releases the GPU images of idle game textures while they hold more than this
  // (d3d9.managedTextureBudgetMiB), and frees a game texture's CPU copy once it is on the GPU
  // (d3d9.releaseManagedHostCopies).
  std::uint64_t managed_texture_budget_mib = 0;
  bool release_host_copies = false;
  std::string layer;  // the DXVK layer that carries the runtime's two settings, when listed
};

// vram_bytes: the largest hardware adapter's dedicated memory, any vendor; ram_bytes: the total
// physical memory. 0 means not read, which counts as the minimum. Auto sizes the budgets from the
// measured memory. An explicit profile sizes them as that profile's computer (at most the measured
// memory), so remix.memory_profile=minimum on a large computer runs the minimum's budgets.
Budget plan(std::uint64_t vram_bytes, std::uint64_t ram_bytes, config::MemoryProfile requested);

std::string serialize(const Budget& budget);   // status.json activation.memory
std::string layer_text(const Budget& budget);  // the DXVK layer (d3d9 options only, ADR 0062)

}  // namespace nl::memory_profile
