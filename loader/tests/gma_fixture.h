#pragma once
// Builds synthetic GMAD archives for tests, written independently of the reader under test.

#include "nl/crc32.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace nl::test {

struct FixtureFile {
  std::string path;
  std::string data;
  std::optional<std::uint32_t> crc;  // default: the real CRC-32 of data
  std::optional<std::int64_t> size;  // default: data.size()
};

struct FixtureArchive {
  std::uint8_t version = 3;
  std::uint64_t steamid = 0;
  std::uint64_t timestamp = 1700000000;
  std::vector<std::string> required_content;
  std::string title = "Test addon";
  std::string description = "{\n\t\"description\": \"Description\",\n\t\"type\": \"model\",\n\t\"tags\": []\n}";
  std::string author = "Author Name";
  std::int32_t addon_version = 1;
  std::vector<FixtureFile> files;
  bool addon_crc = true;    // false writes 0, like gmad -nocrc
  bool crc_trailer = true;  // false omits the 4-byte trailer (seen in legacy Workshop items)
  std::string trailing;     // bytes appended after the CRC trailer
};

inline void put_u32(std::string& out, std::uint32_t value) {
  for (int i = 0; i < 4; ++i) out.push_back(static_cast<char>((value >> (8 * i)) & 0xFFu));
}

inline void put_u64(std::string& out, std::uint64_t value) {
  for (int i = 0; i < 8; ++i) out.push_back(static_cast<char>((value >> (8 * i)) & 0xFFu));
}

inline void put_cstring(std::string& out, const std::string& text) {
  out += text;
  out.push_back('\0');
}

// Returns the archive bytes; `data_offset` receives the offset of the first content byte.
inline std::string build_gma(const FixtureArchive& archive, std::uint64_t* data_offset = nullptr) {
  std::string out = "GMAD";
  out.push_back(static_cast<char>(archive.version));
  put_u64(out, archive.steamid);
  put_u64(out, archive.timestamp);
  if (archive.version > 1) {
    for (const std::string& item : archive.required_content) put_cstring(out, item);
    out.push_back('\0');
  }
  put_cstring(out, archive.title);
  put_cstring(out, archive.description);
  put_cstring(out, archive.author);
  put_u32(out, static_cast<std::uint32_t>(archive.addon_version));
  std::uint32_t number = 1;
  for (const FixtureFile& file : archive.files) {
    put_u32(out, number++);
    put_cstring(out, file.path);
    put_u64(out, static_cast<std::uint64_t>(file.size.value_or(static_cast<std::int64_t>(file.data.size()))));
    put_u32(out, file.crc.value_or(nl::crc32(file.data.data(), file.data.size())));
  }
  put_u32(out, 0);
  if (data_offset) *data_offset = out.size();
  for (const FixtureFile& file : archive.files) out += file.data;
  if (archive.crc_trailer) put_u32(out, archive.addon_crc ? nl::crc32(out.data(), out.size()) : 0);
  out += archive.trailing;
  return out;
}

}  // namespace nl::test
