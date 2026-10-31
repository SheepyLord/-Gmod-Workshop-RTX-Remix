#include "nl/legacy_detect.h"

#include "nl/fs.h"
#include "nl/paths.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace nl::legacy {
namespace {

constexpr std::size_t kMaxImageBytes = std::size_t{512} << 20;
constexpr std::uint32_t kMaxExports = 65536;
constexpr std::size_t kMaxExportString = 4096;
struct Invalid {};

class Source {
 public:
  explicit Source(std::size_t size) : size_(size) {}
  virtual ~Source() = default;
  std::size_t size() const noexcept { return size_; }
  bool inside(std::size_t offset, std::size_t count) const noexcept {
    return offset <= size_ && count <= size_ - offset;
  }
  virtual void read(std::size_t offset, char* destination, std::size_t count) = 0;
 private:
  std::size_t size_;
};

class Bytes final : public Source {
 public:
  explicit Bytes(std::string_view bytes) : Source(bytes.size()), bytes_(bytes) {}
  void read(std::size_t offset, char* destination, std::size_t count) override {
    if (!inside(offset, count)) throw Invalid{};
    if (count) std::memcpy(destination, bytes_.data() + offset, count);
  }
 private:
  std::string_view bytes_;
};

// Retain only 128 KiB of file pages. Export names are usually adjacent; the cache also avoids
// seeking back and forth for the name, ordinal and function tables. A read budget bounds work on
// a hostile export table with thousands of scattered names. No image is mapped or executed.
class File final : public Source {
 public:
  File(const std::filesystem::path& path, std::size_t size)
      : Source(size), stream_(path, std::ios::binary), pages_(32) {
    if (!stream_) throw Invalid{};
  }
  void read(std::size_t offset, char* destination, std::size_t count) override {
    if (!inside(offset, count)) throw Invalid{};
    while (count) {
      const auto page_offset = offset - offset % kPageSize;
      auto page = std::find_if(pages_.begin(), pages_.end(), [page_offset](const Page& candidate) {
        return candidate.length && candidate.offset == page_offset;
      });
      if (page == pages_.end()) {
        page = pages_.begin() + next_;
        next_ = (next_ + 1) % pages_.size();
        const auto length = std::min(kPageSize, size() - page_offset);
        if (length > kReadBudget - read_) throw Invalid{};
        stream_.seekg(static_cast<std::streamoff>(page_offset));
        if (!stream_) throw Invalid{};
        stream_.read(page->bytes.data(), static_cast<std::streamsize>(length));
        if (stream_.gcount() != static_cast<std::streamsize>(length)) throw Invalid{};
        page->offset = page_offset; page->length = length; read_ += length;
      }
      const auto in_page = offset - page_offset;
      const auto length = std::min(count, page->length - in_page);
      std::memcpy(destination, page->bytes.data() + in_page, length);
      offset += length; destination += length; count -= length;
    }
  }
 private:
  static constexpr std::size_t kPageSize = 4096;
  static constexpr std::size_t kReadBudget = std::size_t{32} << 20;
  struct Page {
    std::size_t offset = 0, length = 0;
    std::array<char, kPageSize> bytes{};
  };
  std::ifstream stream_;
  std::vector<Page> pages_;
  std::size_t next_ = 0, read_ = 0;
};

struct Range {
  std::size_t offset;
  std::size_t available;
};
struct Section {
  std::uint32_t address;
  std::uint32_t span;
  std::uint32_t raw;
  std::uint32_t raw_size;
};

class Image {
 public:
  explicit Image(Source& source) : source_(source) {
    if (source_.size() > kMaxImageBytes || u16(0) != 0x5a4d) throw Invalid{};
    const std::uint32_t pe = u32(0x3c);
    if (pe < 0x40 || u32(pe) != 0x00004550) throw Invalid{};
    const std::size_t coff = static_cast<std::size_t>(pe) + 4;
    const auto machine = u16(coff);
    const auto count = u16(coff + 2);
    const auto optional_size = u16(coff + 16);
    const auto flags = u16(coff + 18);
    if (!count || count > 96 || (flags & 0x2002) != 0x2002) throw Invalid{}; // executable DLL
    const auto optional = coff + 20;
    const auto magic = u16(optional);
    std::size_t directory_offset;
    if (machine == 0x8664 && magic == 0x20b) directory_offset = 112;
    else if (machine == 0x014c && magic == 0x10b) directory_offset = 96;
    else throw Invalid{};
    if (optional_size < directory_offset + 8 || !inside(optional, optional_size)) throw Invalid{};
    image_size_ = u32(optional + 56);
    header_size_ = u32(optional + 60);
    if (!header_size_ || header_size_ > image_size_ || header_size_ > source_.size()) throw Invalid{};
    if (u32(optional + directory_offset - 4) < 1) throw Invalid{};
    export_rva_ = u32(optional + directory_offset);
    export_size_ = u32(optional + directory_offset + 4);
    if (!export_rva_ || export_size_ < 40 || !image_range(export_rva_, export_size_)) throw Invalid{};
    const auto table = optional + optional_size;
    if (!inside(table, static_cast<std::size_t>(count) * 40) ||
        table > header_size_ || static_cast<std::size_t>(count) * 40 > header_size_ - table) throw Invalid{};
    for (std::size_t i = 0; i < count; ++i) {
      const auto at = table + i * 40;
      Section section{u32(at + 12), std::max(u32(at + 8), u32(at + 16)), u32(at + 20), u32(at + 16)};
      if (!section.span) continue;
      if (section.address < header_size_ || !image_range(section.address, section.span)) throw Invalid{};
      if (section.raw_size && (section.raw < header_size_ || !inside(section.raw, section.raw_size))) throw Invalid{};
      for (const auto& prior : sections_) {
        if (overlap(section.address, section.span, prior.address, prior.span) ||
            (section.raw_size && prior.raw_size && overlap(section.raw, section.raw_size, prior.raw, prior.raw_size)))
          throw Invalid{};
      }
      sections_.push_back(section);
    }
  }

  bool exports(std::string_view name) const {
    if (name.empty() || name.size() >= kMaxExportString || name.find('\0') != std::string_view::npos) return false;
    const auto directory = mapped(export_rva_, 40).offset;
    const auto functions = u32(directory + 20), names = u32(directory + 24);
    if (!functions || functions > kMaxExports || !names || names > kMaxExports) throw Invalid{};
    const auto eat_rva = u32(directory + 28), names_rva = u32(directory + 32), ordinals_rva = u32(directory + 36);
    if (!eat_rva || !names_rva || !ordinals_rva) throw Invalid{};
    const auto eat = mapped(eat_rva, static_cast<std::size_t>(functions) * 4).offset;
    const auto name_table = mapped(names_rva, static_cast<std::size_t>(names) * 4).offset;
    const auto ordinal_table = mapped(ordinals_rva, static_cast<std::size_t>(names) * 2).offset;
    bool found = false;
    for (std::size_t i = 0; i < names; ++i) {
      const auto ordinal = u16(ordinal_table + i * 2);
      if (ordinal >= functions) throw Invalid{};
      const auto exported_name = text(u32(name_table + i * 4));
      if (exported_name.empty()) throw Invalid{};
      const auto function = u32(eat + static_cast<std::size_t>(ordinal) * 4);
      if (!function) throw Invalid{};
      if (function >= export_rva_ && function - export_rva_ < export_size_) {
        const auto forwarder = text(function, export_size_ - (function - export_rva_));
        const auto dot = forwarder.rfind('.');
        if (dot == std::string_view::npos || dot == 0 || dot + 1 == forwarder.size()) throw Invalid{};
        if (forwarder[dot + 1] == '#') {
          std::uint32_t forwarded_ordinal = 0;
          if (dot + 2 == forwarder.size()) throw Invalid{};
          for (std::size_t at = dot + 2; at < forwarder.size(); ++at) {
            const auto digit = forwarder[at];
            if (digit < '0' || digit > '9') throw Invalid{};
            forwarded_ordinal = forwarded_ordinal * 10 + static_cast<unsigned>(digit - '0');
            if (forwarded_ordinal > 65535) throw Invalid{};
          }
          if (!forwarded_ordinal) throw Invalid{};
        }
      } else {
        static_cast<void>(mapped(function, 1));
      }
      found = found || exported_name == name;
    }
    return found;
  }

 private:
  bool inside(std::size_t offset, std::size_t count) const noexcept {
    return source_.inside(offset, count);
  }
  bool image_range(std::uint32_t rva, std::uint32_t count) const noexcept {
    return rva < image_size_ && count <= image_size_ - rva;
  }
  static bool overlap(std::uint32_t first, std::uint32_t size, std::uint32_t second, std::uint32_t second_size) noexcept {
    return static_cast<std::uint64_t>(first) < static_cast<std::uint64_t>(second) + second_size &&
           static_cast<std::uint64_t>(second) < static_cast<std::uint64_t>(first) + size;
  }
  std::uint16_t u16(std::size_t offset) const {
    std::array<unsigned char, 2> p{};
    source_.read(offset, reinterpret_cast<char*>(p.data()), p.size());
    return static_cast<std::uint16_t>(p[0] | (static_cast<std::uint16_t>(p[1]) << 8));
  }
  std::uint32_t u32(std::size_t offset) const {
    std::array<unsigned char, 4> p{};
    source_.read(offset, reinterpret_cast<char*>(p.data()), p.size());
    return static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
           (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
  }
  Range mapped(std::uint32_t rva, std::size_t count) const {
    if (count > image_size_ || rva >= image_size_ || count > image_size_ - rva) throw Invalid{};
    if (rva < header_size_) {
      if (count > header_size_ - rva || !inside(rva, count)) throw Invalid{};
      return {rva, header_size_ - rva};
    }
    for (const auto& section : sections_) {
      if (rva < section.address || rva - section.address >= section.span) continue;
      const auto delta = rva - section.address;
      if (delta >= section.raw_size || count > section.raw_size - delta) throw Invalid{};
      const std::size_t offset = static_cast<std::size_t>(section.raw) + delta;
      if (!inside(offset, count)) throw Invalid{};
      return {offset, section.raw_size - delta};
    }
    throw Invalid{};
  }
  std::string text(std::uint32_t rva, std::size_t limit = kMaxExportString) const {
    if (!rva) throw Invalid{};
    const auto range = mapped(rva, 1);
    std::string value(std::min({range.available, limit, kMaxExportString}), '\0');
    source_.read(range.offset, value.data(), value.size());
    const auto end = value.find('\0');
    if (end == std::string::npos) throw Invalid{};
    value.resize(end);
    return value;
  }

  Source& source_;
  std::uint32_t image_size_ = 0, header_size_ = 0, export_rva_ = 0, export_size_ = 0;
  std::vector<Section> sections_;
};

// The export check of a file whose path the caller has checked for links. A file that changes while
// it is read gives false.
bool remix_file(const std::filesystem::path& file) {
  const auto before = fs::stat(file);
  if (!before.exists || before.directory || before.link || before.size > kMaxImageBytes) return false;
  File source(file, static_cast<std::size_t>(before.size));
  const auto result = Image(source).exports(kRemixExport);
  const auto after = fs::stat(file);
  if (!after.exists || after.directory || after.link || before.size != after.size || before.mtime != after.mtime) return false;
  return result;
}

}  // namespace

bool exports_function(std::string_view bytes, std::string_view name) noexcept {
  try { Bytes source(bytes); return Image(source).exports(name); } catch (...) { return false; }
}

bool is_remix_runtime(const std::filesystem::path& file) noexcept {
  try {
    for (const auto& part : file) if (part == L"." || part == L"..") return false;
    const auto absolute = std::filesystem::absolute(file);
    for (const auto& part : absolute) if (part == L"." || part == L"..") return false;
    const auto utf8 = absolute.relative_path().generic_u8string();
    fs::refuse_links(absolute.root_path(), std::string(utf8.begin(), utf8.end()));
    return remix_file(absolute);
  } catch (...) {
    return false;
  }
}

bool is_remix_runtime(const std::filesystem::path& root, std::string_view relative) noexcept {
  try {
    if (!paths::is_safe(relative)) return false;
    fs::refuse_links(root, relative);
    return remix_file(fs::join(root, relative));
  } catch (...) {
    return false;
  }
}

}  // namespace nl::legacy
