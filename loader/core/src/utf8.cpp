#include "nl/utf8.h"

#include <cstdint>

namespace nl::utf8 {

std::size_t sequence_length(std::string_view text, std::size_t i) noexcept {
  if (i >= text.size()) return 0;
  const auto lead = static_cast<unsigned char>(text[i]);
  if (lead < 0x80) return 1;
  std::size_t length = 0;
  std::uint32_t code = 0;
  if (lead >= 0xC2 && lead <= 0xDF) {
    length = 2;
    code = lead & 0x1Fu;
  } else if (lead >= 0xE0 && lead <= 0xEF) {
    length = 3;
    code = lead & 0x0Fu;
  } else if (lead >= 0xF0 && lead <= 0xF4) {
    length = 4;
    code = lead & 0x07u;
  } else {
    return 0;
  }
  if (i + length > text.size()) return 0;
  for (std::size_t k = 1; k < length; ++k) {
    const auto next = static_cast<unsigned char>(text[i + k]);
    if ((next & 0xC0u) != 0x80u) return 0;
    code = code << 6 | (next & 0x3Fu);
  }
  if (length == 3 && (code < 0x800 || (code >= 0xD800 && code <= 0xDFFF))) return 0;
  if (length == 4 && (code < 0x10000 || code > 0x10FFFF)) return 0;
  return length;
}

bool valid(std::string_view text) noexcept {
  for (std::size_t i = 0; i < text.size();) {
    const std::size_t length = sequence_length(text, i);
    if (!length) return false;
    i += length;
  }
  return true;
}

}  // namespace nl::utf8
