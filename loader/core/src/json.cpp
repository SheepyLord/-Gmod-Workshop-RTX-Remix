#include "nl/json.h"

#include <cstdint>
#include <cstdio>

namespace nl::json {

namespace {

// Length of the well-formed UTF-8 sequence at text[i], or 0 if it is not one (overlong forms,
// surrogates and code points above U+10FFFF are rejected).
std::size_t utf8_sequence(std::string_view text, std::size_t i) {
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

}  // namespace

std::string quote(std::string_view text) {
  std::string out;
  out.reserve(text.size() + 2);
  out.push_back('"');
  for (std::size_t i = 0; i < text.size();) {
    const auto c = static_cast<unsigned char>(text[i]);
    if (c == '"' || c == '\\') {
      out.push_back('\\');
      out.push_back(static_cast<char>(c));
      ++i;
    } else if (c < 0x20) {
      switch (c) {
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        default: {
          char escaped[8];
          std::snprintf(escaped, sizeof(escaped), "\\u%04x", static_cast<unsigned>(c));
          out += escaped;
        }
      }
      ++i;
    } else if (const std::size_t length = utf8_sequence(text, i)) {
      out.append(text.substr(i, length));
      i += length;
    } else {
      out += "\\ufffd";
      ++i;
    }
  }
  out.push_back('"');
  return out;
}

}  // namespace nl::json
