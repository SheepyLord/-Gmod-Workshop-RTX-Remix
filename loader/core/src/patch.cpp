#include "nl/patch.h"

#include <windows.h>

#include <cstring>

namespace nl::patch {

std::vector<std::size_t> find(const std::uint8_t* data, std::size_t size, const std::vector<int>& pattern, std::size_t limit) {
  std::vector<std::size_t> found;
  if (pattern.empty() || size < pattern.size()) return found;
  // Anchor on the first concrete byte, then compare the rest.
  std::size_t anchor = 0;
  while (anchor < pattern.size() && pattern[anchor] < 0) ++anchor;
  if (anchor == pattern.size()) return found;
  const auto first = static_cast<std::uint8_t>(pattern[anchor]);
  for (std::size_t at = anchor; at + (pattern.size() - anchor) <= size;) {
    const void* hit = std::memchr(data + at, first, size - (pattern.size() - anchor) - at + 1);
    if (!hit) break;
    const std::size_t start = static_cast<std::size_t>(static_cast<const std::uint8_t*>(hit) - data) - anchor;
    bool match = true;
    for (std::size_t i = 0; i < pattern.size() && match; ++i) {
      if (pattern[i] >= 0 && data[start + i] != static_cast<std::uint8_t>(pattern[i])) match = false;
    }
    if (match) {
      found.push_back(start);
      if (found.size() >= limit) break;
    }
    at = start + anchor + 1;
  }
  return found;
}

std::vector<Section> sections(void* base) {
  std::vector<Section> out;
  auto* image = static_cast<std::uint8_t*>(base);
  if (!image) return out;
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return out;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return out;
  const auto* section = IMAGE_FIRST_SECTION(nt);
  const DWORD image_size = nt->OptionalHeader.SizeOfImage;
  for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
    const DWORD size = section->Misc.VirtualSize ? section->Misc.VirtualSize : section->SizeOfRawData;
    if (!size || section->VirtualAddress >= image_size || size > image_size - section->VirtualAddress) continue;
    out.push_back({image + section->VirtualAddress, size});
  }
  return out;
}

Result apply(void* base, std::string_view module, const manifest::Patch& patch) {
  Result result{std::string(module), patch.name, "skipped", {}, 0};
  const auto pattern = manifest::parse_pattern(patch.find);
  const auto bytes = manifest::parse_hex(patch.replace);
  if (pattern.empty() || bytes.empty() || patch.offset + bytes.size() > pattern.size()) {
    result.reason = "invalid patch";
    return result;
  }
  std::uint8_t* target = nullptr;
  std::size_t matches = 0;
  for (const Section& section : sections(base)) {
    for (const std::size_t at : find(section.data, section.size, pattern, 2)) {
      if (++matches == 1) target = section.data + at;
    }
    if (matches > 1) break;
  }
  if (matches != 1) {
    result.reason = matches ? "the pattern occurs more than once" : "the pattern does not occur (another build?)";
    return result;
  }
  std::uint8_t* where = target + patch.offset;
  DWORD previous = 0;
  if (!VirtualProtect(where, bytes.size(), PAGE_EXECUTE_READWRITE, &previous)) {
    result.reason = "VirtualProtect failed (" + std::to_string(GetLastError()) + ")";
    return result;
  }
  std::memcpy(where, bytes.data(), bytes.size());
  DWORD ignored = 0;
  VirtualProtect(where, bytes.size(), previous, &ignored);
  FlushInstructionCache(GetCurrentProcess(), where, bytes.size());
  result.result = "applied";
  result.address = reinterpret_cast<std::uintptr_t>(where);
  return result;
}

}  // namespace nl::patch
