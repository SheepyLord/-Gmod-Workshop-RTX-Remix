#pragma once
// CRC-32 as used by zlib, PKZIP and the GMA format (reflected polynomial 0xEDB88320).

#include <cstddef>
#include <cstdint>

namespace nl {

// Continues a CRC-32 over `size` bytes. Start a new checksum with crc = 0.
std::uint32_t crc32_update(std::uint32_t crc, const void* data, std::size_t size) noexcept;

inline std::uint32_t crc32(const void* data, std::size_t size) noexcept {
  return crc32_update(0, data, size);
}

}  // namespace nl
