#pragma once
// Reading Garry's Mod .gma archives (GMAD format v1-v3), as documented in
// tools/gmapack/GMA_FORMAT.md. Archive bytes are untrusted input: string lengths, entry counts and
// size sums are bounded, and every failure is a FormatError rather than undefined behaviour.

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace nl::gma {

// Malformed, truncated or unsupported archive data.
class FormatError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

// A forward-only byte stream.
class Source {
 public:
  virtual ~Source() = default;
  // Reads up to `size` bytes into `buffer`; returns how many were read, 0 only at the end.
  virtual std::size_t read(void* buffer, std::size_t size) = 0;
  // Skips `count` bytes; false if the stream ends first. The default reads and discards them.
  virtual bool skip(std::uint64_t count);
};

// Reads bytes the caller keeps alive (tests, small in-memory archives).
class MemorySource final : public Source {
 public:
  explicit MemorySource(std::string_view bytes) noexcept : bytes_(bytes) {}
  std::size_t read(void* buffer, std::size_t size) override;

 private:
  std::string_view bytes_;
  std::size_t position_ = 0;
};

// Reads a file from its start. Opened with full sharing, so Steam can still update it meanwhile.
class FileSource final : public Source {
 public:
  explicit FileSource(const std::filesystem::path& path);  // throws std::filesystem::filesystem_error
  ~FileSource() override;
  FileSource(const FileSource&) = delete;
  FileSource& operator=(const FileSource&) = delete;
  std::size_t read(void* buffer, std::size_t size) override;
  bool skip(std::uint64_t count) override;  // seeks
  std::uint64_t size() const noexcept { return size_; }

 private:
  std::FILE* file_ = nullptr;
  std::uint64_t size_ = 0;
};

// What a file starts with: a GMAD stream, an LZMA-alone wrapper (gmpublish uploads), or neither.
enum class Container { gmad, lzma, unknown };
Container detect_container(std::string_view prefix) noexcept;  // pass at least the first 13 bytes

struct Limits {
  std::size_t max_string_bytes = std::size_t{16} << 20;  // same as gmapack.py MAX_STRING_SIZE
  std::size_t max_entries = std::size_t{1} << 20;
};

struct Entry {
  std::uint32_t number{};  // as stored (gmad writes 1, 2, 3, ...)
  std::string path;        // raw bytes as stored; gmad writes lowercase UTF-8 with '/'
  std::uint64_t size{};
  std::uint32_t crc32{};   // 0 = written without a CRC
  std::uint64_t offset{};  // from the start of the GMAD stream
};

struct Index {
  std::uint8_t version{};
  std::uint64_t steamid{};
  std::uint64_t timestamp{};
  std::vector<std::string> required_content;
  std::string title;
  std::string description;  // gmad stores a JSON object here (description, type, tags)
  std::string author;
  std::int32_t addon_version{};
  std::vector<Entry> entries;
  std::uint64_t data_offset{};  // first content byte
  std::uint64_t data_end{};     // one past the last content byte; a 4-byte addon CRC may follow
};

// The 4-byte addon CRC trailer is optional: 19 of the 81 legacy Workshop items (GMAD v3, uploaded
// 2012-2019) end right after their last file, and GMod mounts them. A stream that ends inside the
// contents, or 1-3 bytes into a trailer, is truncated.

// Parses the header and file index at the start of a GMAD stream.
Index read_index(Source& source, const Limits& limits = {});

struct VerifyReport {
  Index index;
  std::vector<std::size_t> bad_entries;  // positions in index.entries whose nonzero CRC mismatches
  bool crc_trailer = false;              // false: the stream ends right after the contents
  std::uint32_t addon_crc_stored = 0;    // 0 = written without a CRC (or no trailer at all)
  std::uint32_t addon_crc_actual = 0;
  std::uint64_t trailing_bytes = 0;      // bytes after the CRC trailer
  bool ok() const noexcept {
    return bad_entries.empty() && (addon_crc_stored == 0 || addon_crc_stored == addon_crc_actual) &&
           trailing_bytes == 0;
  }
};

// Reads a whole GMAD stream once: index, every file (checking nonzero CRCs), the optional addon CRC
// and any trailing data. Throws FormatError when the stream ends inside the contents or the trailer.
VerifyReport verify(Source& source, const Limits& limits = {});

// Opens an archive file positioned at the start of its GMAD stream. LZMA-wrapped files (Workshop
// *_legacy.bin) are decoded on the fly with bounded memory (see nl/lzma.h).
std::unique_ptr<Source> open_archive(const std::filesystem::path& path, Container* container = nullptr);

// Reads one file of an archive (at most `max_bytes`; otherwise FormatError), checking its CRC when
// it has one. `entry` must come from this archive's index. Plain archives seek; LZMA ones decode up
// to the entry.
std::string read_entry(const std::filesystem::path& archive, const Entry& entry, std::size_t max_bytes);

// Key for duplicate-path detection: ASCII-lowercased with '\\' turned into '/'. Matches gmapack.py
// for ASCII names (gmapack casefolds full Unicode).
std::string path_key(std::string_view path);

}  // namespace nl::gma
