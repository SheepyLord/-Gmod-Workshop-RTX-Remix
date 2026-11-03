#include "nl/memory_profile.h"
#include "nl/json.h"
#include <algorithm>

namespace nl::memory_profile {
namespace {
constexpr std::uint64_t kMib = std::uint64_t{1} << 20;

Profile by_vram(std::uint64_t mib) {
  return mib >= kHighVramMib ? Profile::high : mib >= kRecommendedVramMib ? Profile::recommended
       : mib >= kMinimumVramMib ? Profile::minimum : Profile::below_minimum;
}
Profile by_ram(std::uint64_t mib) {
  return mib >= kHighRamMib ? Profile::high : mib >= kRecommendedRamMib ? Profile::recommended
       : mib >= kMinimumRamMib ? Profile::minimum : Profile::below_minimum;
}
// The computer an explicit minimum or recommended profile stands for. High keeps the measured memory.
std::uint64_t nominal_vram(Profile profile) { return profile == Profile::recommended ? 16384 : 8192; }
std::uint64_t nominal_ram(Profile profile) { return profile == Profile::recommended ? 32768 : 16384; }
std::string size_text(std::uint64_t mib, const char* what) {
  return mib ? std::to_string(mib) + " MiB " + what : std::string(what) + " not read";
}
}  // namespace

const char* name(Profile profile) {
  switch (profile) {
    case Profile::below_minimum: return "below_minimum";
    case Profile::minimum: return "minimum";
    case Profile::recommended: return "recommended";
    case Profile::high: return "high";
  }
  return "minimum";
}

Budget plan(std::uint64_t vram_bytes, std::uint64_t ram_bytes, config::MemoryProfile requested) {
  Budget b;
  b.vram_mib = vram_bytes / kMib;
  b.ram_mib = ram_bytes / kMib;
  // A size that was not read counts as the minimum's: never assume more than the computer may have.
  const Profile vram = b.vram_mib ? by_vram(b.vram_mib) : Profile::minimum;
  const Profile ram = b.ram_mib ? by_ram(b.ram_mib) : Profile::minimum;
  b.profile = std::min(vram, ram);
  b.reason = size_text(b.vram_mib, "VRAM") + " -> " + name(vram) + "; " + size_text(b.ram_mib, "RAM") + " -> " + name(ram);
  if (b.profile == Profile::below_minimum) b.reason += "; below the supported minimum of 8 GB VRAM and 16 GB RAM, using the minimum's budgets";
  std::uint64_t vram_mib = b.vram_mib ? b.vram_mib : nominal_vram(Profile::minimum);
  std::uint64_t ram_mib = b.ram_mib ? b.ram_mib : nominal_ram(Profile::minimum);
  if (requested != config::MemoryProfile::automatic) {
    b.profile = requested == config::MemoryProfile::high ? Profile::high
              : requested == config::MemoryProfile::recommended ? Profile::recommended : Profile::minimum;
    b.source = "config";
    if (b.profile != Profile::high) {
      vram_mib = std::min(vram_mib, nominal_vram(b.profile));
      ram_mib = std::min(ram_mib, nominal_ram(b.profile));
    }
    b.reason = "remix.memory_profile=" + std::string(name(b.profile)) + "; " + b.reason + "; budgets for " +
               std::to_string(vram_mib) + " MiB VRAM and " + std::to_string(ram_mib) + " MiB RAM";
  }
  // The user (2026-11-03): a short first-spawn delay on the minimum; the five most recently used
  // characters ready when memory is plentiful; more kept on larger computers.
  const bool roomy = b.profile >= Profile::recommended;
  b.warm_characters = b.profile == Profile::high ? 10 : roomy ? 5 : 0;
  b.warm_mib = roomy ? ram_mib / 10 : 0;
  b.managed_texture_budget_mib = std::max<std::uint64_t>(vram_mib / 4, 512);
  b.release_host_copies = !roomy;
  return b;
}

std::string serialize(const Budget& b) {
  return "{\"profile\":" + json::quote(name(b.profile)) + ",\"source\":" + json::quote(b.source) +
         ",\"reason\":" + json::quote(b.reason) + ",\"vram_mib\":" + std::to_string(b.vram_mib) +
         ",\"ram_mib\":" + std::to_string(b.ram_mib) + ",\"warm_characters\":" + std::to_string(b.warm_characters) +
         ",\"warm_mib\":" + std::to_string(b.warm_mib) +
         ",\"managed_texture_budget_mib\":" + std::to_string(b.managed_texture_budget_mib) +
         ",\"release_host_copies\":" + (b.release_host_copies ? "true" : "false") + ",\"layer\":" + json::quote(b.layer) + '}';
}

std::string layer_text(const Budget& b) {
  return "# Written by the GMod native loader at each RTX start (R13, ADR 0101): the runtime's budgets for\r\n"
         "# the " + std::string(name(b.profile)) + " memory profile (" + b.reason + ").\r\n"
         "# Set remix.memory_profile in native-loader\\config.json to choose another; your own dxvk.conf wins.\r\n"
         "d3d9.managedTextureBudgetMiB = " + std::to_string(b.managed_texture_budget_mib) + "\r\n"
         "d3d9.releaseManagedHostCopies = " + (b.release_host_copies ? "True" : "False") + "\r\n";
}

}  // namespace nl::memory_profile
