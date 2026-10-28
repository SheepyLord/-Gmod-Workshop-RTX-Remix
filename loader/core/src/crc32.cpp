#include "nl/crc32.h"

#include <array>

namespace nl {

namespace {

constexpr std::array<std::uint32_t, 256> make_table() {
  std::array<std::uint32_t, 256> table{};
  for (std::uint32_t i = 0; i < 256; ++i) {
    std::uint32_t c = i;
    for (int bit = 0; bit < 8; ++bit) {
      c = (c & 1u) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

constexpr auto kTable = make_table();

}  // namespace

std::uint32_t crc32_update(std::uint32_t crc, const void* data, std::size_t size) noexcept {
  const auto* bytes = static_cast<const unsigned char*>(data);
  crc = ~crc;
  for (std::size_t i = 0; i < size; ++i) {
    crc = kTable[(crc ^ bytes[i]) & 0xFFu] ^ (crc >> 8);
  }
  return ~crc;
}

}  // namespace nl
