#include "nl/gma.h"

#include "nl/crc32.h"
#include "nl/lzma.h"

#include <share.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <limits>
#include <system_error>
#include <unordered_set>
#include <utility>

namespace nl::gma {

namespace {

constexpr char kIdent[4] = {'G', 'M', 'A', 'D'};
constexpr unsigned kMaxLzmaProperties = 9 * 5 * 5;  // lc < 9, lp < 5, pb < 5

// Path text safe to put in an error message: control bytes become '?', long names are cut.
std::string printable(std::string_view path) {
  std::string out;
  for (const unsigned char c : path.substr(0, 200)) {
    out.push_back(c < 0x20 || c == 0x7F ? '?' : static_cast<char>(c));
  }
  if (path.size() > 200) out += "...";
  return out;
}

// Buffered reader that tracks the stream position and a CRC-32 of every byte consumed.
class Reader {
 public:
  explicit Reader(Source& source) : source_(source), buffer_(64 * 1024) {}

  std::uint64_t position() const noexcept { return position_; }
  std::uint32_t crc() const noexcept { return crc_; }

  void read_exact(void* out, std::size_t size, std::string_view field) {
    auto* dest = static_cast<unsigned char*>(out);
    while (size) {
      if (begin_ == end_ && !fill()) truncated(field);
      const std::size_t n = std::min(size, end_ - begin_);
      std::memcpy(dest, buffer_.data() + begin_, n);
      consume(n);
      dest += n;
      size -= n;
    }
  }

  // Reads up to `size` bytes; fewer only at the end of the stream.
  std::size_t read_some(void* out, std::size_t size) {
    auto* dest = static_cast<unsigned char*>(out);
    std::size_t done = 0;
    while (done < size) {
      if (begin_ == end_ && !fill()) break;
      const std::size_t n = std::min(size - done, end_ - begin_);
      std::memcpy(dest + done, buffer_.data() + begin_, n);
      consume(n);
      done += n;
    }
    return done;
  }

  std::uint8_t u8(std::string_view field) {
    unsigned char b{};
    read_exact(&b, 1, field);
    return b;
  }

  std::uint32_t u32(std::string_view field) {
    unsigned char b[4];
    read_exact(b, 4, field);
    return static_cast<std::uint32_t>(b[0]) | static_cast<std::uint32_t>(b[1]) << 8 |
           static_cast<std::uint32_t>(b[2]) << 16 | static_cast<std::uint32_t>(b[3]) << 24;
  }

  std::uint64_t u64(std::string_view field) {
    const std::uint64_t low = u32(field);
    const std::uint64_t high = u32(field);
    return low | high << 32;
  }

  // NUL-terminated string of at most `limit` bytes (terminator excluded).
  std::string cstring(std::string_view field, std::size_t limit) {
    std::string out;
    for (;;) {
      if (begin_ == end_ && !fill()) truncated(field);
      const auto* start = buffer_.data() + begin_;
      const auto* nul = static_cast<const unsigned char*>(std::memchr(start, 0, end_ - begin_));
      const std::size_t n = nul ? static_cast<std::size_t>(nul - start) : end_ - begin_;
      if (out.size() + n > limit) {
        throw FormatError(std::string(field) + " exceeds the " + std::to_string(limit) + "-byte safety limit");
      }
      out.append(reinterpret_cast<const char*>(start), n);
      consume(n + (nul ? 1 : 0));
      if (nul) return out;
    }
  }

  // Passes `size` bytes to sink(data, count) without keeping them.
  template <class Sink>
  void stream(std::uint64_t size, std::string_view field, Sink&& sink) {
    while (size) {
      if (begin_ == end_ && !fill()) truncated(field);
      const std::size_t n = static_cast<std::size_t>(std::min<std::uint64_t>(size, end_ - begin_));
      sink(buffer_.data() + begin_, n);
      consume(n);
      size -= n;
    }
  }

  // Consumes everything that is left; returns the byte count.
  std::uint64_t drain() {
    std::uint64_t total = 0;
    while (begin_ != end_ || fill()) {
      total += end_ - begin_;
      consume(end_ - begin_);
    }
    return total;
  }

 private:
  bool fill() {
    begin_ = 0;
    end_ = source_.read(buffer_.data(), buffer_.size());
    return end_ != 0;
  }

  void consume(std::size_t n) {
    crc_ = crc32_update(crc_, buffer_.data() + begin_, n);
    begin_ += n;
    position_ += n;
  }

  [[noreturn]] static void truncated(std::string_view field) {
    throw FormatError("truncated archive while reading " + std::string(field));
  }

  Source& source_;
  std::vector<unsigned char> buffer_;
  std::size_t begin_ = 0;
  std::size_t end_ = 0;
  std::uint64_t position_ = 0;
  std::uint32_t crc_ = 0;
};

Index parse(Reader& r, const Limits& limits) {
  Index index;
  char ident[4];
  r.read_exact(ident, sizeof(ident), "archive identifier");
  if (std::memcmp(ident, kIdent, sizeof(kIdent)) != 0) throw FormatError("not a GMAD archive (bad identifier)");
  index.version = r.u8("format version");
  if (index.version < 1 || index.version > 3) {
    throw FormatError("unsupported GMAD version " + std::to_string(index.version));
  }
  index.steamid = r.u64("SteamID64 field");
  index.timestamp = r.u64("timestamp");
  if (index.version > 1) {
    for (;;) {
      std::string item = r.cstring("required-content entry", limits.max_string_bytes);
      if (item.empty()) break;
      if (index.required_content.size() >= limits.max_entries) throw FormatError("too many required-content entries");
      index.required_content.push_back(std::move(item));
    }
  }
  index.title = r.cstring("title", limits.max_string_bytes);
  index.description = r.cstring("description", limits.max_string_bytes);
  index.author = r.cstring("author", limits.max_string_bytes);
  index.addon_version = static_cast<std::int32_t>(r.u32("addon version"));

  std::unordered_set<std::string> seen;
  for (;;) {
    const std::uint32_t number = r.u32("file number");
    if (number == 0) break;
    if (index.entries.size() >= limits.max_entries) {
      throw FormatError("archive lists more than " + std::to_string(limits.max_entries) + " files");
    }
    Entry entry;
    entry.number = number;
    entry.path = r.cstring("file name", limits.max_string_bytes);
    if (entry.path.empty()) throw FormatError("archive contains an empty file name");
    if (!seen.insert(path_key(entry.path)).second) {
      throw FormatError("archive contains a duplicate path: " + printable(entry.path));
    }
    const auto size = static_cast<std::int64_t>(r.u64("file size"));
    if (size < 0) throw FormatError("archive contains a negative file size: " + printable(entry.path));
    entry.size = static_cast<std::uint64_t>(size);
    entry.crc32 = r.u32("file CRC");
    index.entries.push_back(std::move(entry));
  }

  index.data_offset = r.position();
  std::uint64_t offset = index.data_offset;
  for (Entry& entry : index.entries) {
    entry.offset = offset;
    if (entry.size > std::numeric_limits<std::uint64_t>::max() - offset) {
      throw FormatError("file sizes overflow the archive size");
    }
    offset += entry.size;
  }
  index.data_end = offset;
  return index;
}

}  // namespace

bool Source::skip(std::uint64_t count) {
  char scratch[64 * 1024];
  while (count) {
    const std::size_t n = read(scratch, static_cast<std::size_t>(std::min<std::uint64_t>(count, sizeof(scratch))));
    if (!n) return false;
    count -= n;
  }
  return true;
}

std::size_t MemorySource::read(void* buffer, std::size_t size) {
  const std::size_t n = std::min(size, bytes_.size() - position_);
  std::memcpy(buffer, bytes_.data() + position_, n);
  position_ += n;
  return n;
}

FileSource::FileSource(const std::filesystem::path& path) {
  file_ = _wfsopen(path.c_str(), L"rb", _SH_DENYNO);
  if (!file_) {
    throw std::filesystem::filesystem_error("cannot open archive", path, std::error_code(errno, std::generic_category()));
  }
  std::error_code ec;
  size_ = std::filesystem::file_size(path, ec);
  if (ec) {
    std::fclose(file_);
    file_ = nullptr;
    throw std::filesystem::filesystem_error("cannot read archive size", path, ec);
  }
}

FileSource::~FileSource() {
  if (file_) std::fclose(file_);
}

std::size_t FileSource::read(void* buffer, std::size_t size) {
  const std::size_t n = std::fread(buffer, 1, size, file_);
  if (n == 0 && std::ferror(file_)) throw std::system_error(errno, std::generic_category(), "reading archive");
  return n;
}

bool FileSource::skip(std::uint64_t count) {
  const auto position = _ftelli64(file_);
  if (position < 0) throw std::system_error(errno, std::generic_category(), "reading archive position");
  const auto here = static_cast<std::uint64_t>(position);
  if (count > size_ - std::min(here, size_)) {
    _fseeki64(file_, 0, SEEK_END);
    return false;
  }
  if (_fseeki64(file_, static_cast<long long>(count), SEEK_CUR) != 0) {
    throw std::system_error(errno, std::generic_category(), "seeking in archive");
  }
  return true;
}

Container detect_container(std::string_view prefix) noexcept {
  if (prefix.size() >= 4 && std::memcmp(prefix.data(), kIdent, 4) == 0) return Container::gmad;
  // LZMA-alone header: properties byte, 32-bit dictionary size, 64-bit uncompressed size.
  if (prefix.size() >= 13 && static_cast<unsigned char>(prefix[0]) < kMaxLzmaProperties) return Container::lzma;
  return Container::unknown;
}

Index read_index(Source& source, const Limits& limits) {
  Reader reader(source);
  return parse(reader, limits);
}

VerifyReport verify(Source& source, const Limits& limits) {
  Reader reader(source);
  VerifyReport report;
  report.index = parse(reader, limits);
  for (std::size_t i = 0; i < report.index.entries.size(); ++i) {
    const Entry& entry = report.index.entries[i];
    std::uint32_t crc = 0;
    reader.stream(entry.size, "contents of " + printable(entry.path),
                  [&crc](const unsigned char* data, std::size_t n) { crc = crc32_update(crc, data, n); });
    if (entry.crc32 != 0 && crc != entry.crc32) report.bad_entries.push_back(i);
  }
  report.addon_crc_actual = reader.crc();
  unsigned char trailer[4];
  const std::size_t have = reader.read_some(trailer, sizeof(trailer));
  if (have == 0) return report;  // no trailer: allowed, nothing to check
  if (have < sizeof(trailer)) throw FormatError("truncated archive while reading addon CRC");
  report.crc_trailer = true;
  report.addon_crc_stored = static_cast<std::uint32_t>(trailer[0]) | static_cast<std::uint32_t>(trailer[1]) << 8 |
                            static_cast<std::uint32_t>(trailer[2]) << 16 | static_cast<std::uint32_t>(trailer[3]) << 24;
  report.trailing_bytes = reader.drain();
  return report;
}

std::unique_ptr<Source> open_archive(const std::filesystem::path& path, Container* container) {
  char prefix[13]{};
  std::size_t have = 0;
  {
    FileSource peek(path);
    while (have < sizeof(prefix)) {
      const std::size_t n = peek.read(prefix + have, sizeof(prefix) - have);
      if (!n) break;
      have += n;
    }
  }
  const Container kind = detect_container({prefix, have});
  if (container) *container = kind;
  switch (kind) {
    case Container::gmad:
      return std::make_unique<FileSource>(path);
    case Container::lzma:
      return std::make_unique<lzma::Source>(std::make_unique<FileSource>(path));
    case Container::unknown:
      break;
  }
  throw FormatError("not a GMAD archive and not LZMA-wrapped");
}

std::string read_entry(const std::filesystem::path& archive, const Entry& entry, std::size_t max_bytes) {
  if (entry.size > max_bytes) {
    throw FormatError(printable(entry.path) + " is " + std::to_string(entry.size) + " bytes; the limit is " +
                      std::to_string(max_bytes));
  }
  const auto source = open_archive(archive);
  if (!source->skip(entry.offset)) throw FormatError("truncated archive before " + printable(entry.path));
  std::string bytes(static_cast<std::size_t>(entry.size), '\0');
  std::size_t have = 0;
  while (have < bytes.size()) {
    const std::size_t n = source->read(bytes.data() + have, bytes.size() - have);
    if (!n) throw FormatError("truncated archive while reading " + printable(entry.path));
    have += n;
  }
  if (entry.crc32 != 0 && crc32(bytes.data(), bytes.size()) != entry.crc32) {
    throw FormatError("CRC mismatch in " + printable(entry.path));
  }
  return bytes;
}

std::string path_key(std::string_view path) {
  std::string key(path);
  for (char& c : key) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    if (c == '\\') c = '/';
  }
  return key;
}

}  // namespace nl::gma
