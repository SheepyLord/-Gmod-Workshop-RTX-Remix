#pragma once
// In-memory byte patches for engine DLLs (M5, ADR 0010). A patch names a byte pattern (with
// wildcards) that must occur exactly once in the module's mapped image, and the bytes to write at an
// offset inside that match. The bootstrap applies them when a DLL is mapped, before its code runs,
// in place of the on-disk patches the classic RTX install writes into its copy of the game.

#include "nl/manifest.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace nl::patch {

// Offsets of the first `limit` matches of `pattern` (-1 = any byte) in [data, data + size).
std::vector<std::size_t> find(const std::uint8_t* data, std::size_t size, const std::vector<int>& pattern,
                              std::size_t limit = 2);

// A readable range of a mapped module: one section.
struct Section {
  std::uint8_t* data = nullptr;
  std::size_t size = 0;
};

// The sections of a module mapped at `base` (a PE32+ image). Empty if the headers are not valid.
std::vector<Section> sections(void* base);

struct Result {
  std::string module;
  std::string name;
  std::string result;  // applied, skipped
  std::string reason;  // why skipped
  std::uintptr_t address = 0;
};

// Applies `patch` to the module mapped at `base` if its pattern occurs exactly once across the
// module's sections; otherwise changes nothing and says why. The write makes the page writable for
// the moment it takes and flushes the instruction cache.
Result apply(void* base, std::string_view module, const manifest::Patch& patch);

}  // namespace nl::patch
