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
  std::uint64_t data_end{};     // one past the last content byte; the 4-byte addon CRC follows
};

// Parses the header and file index at the start of a GMAD stream.
Index read_index(Source& source, const Limits& limits = {});

struct VerifyReport {
  Index index;
  std::vector<std::size_t> bad_entries;  // positions in index.entries whose nonzero CRC mismatches
  std::uint32_t addon_crc_stored = 0;    // 0 = archive written without a CRC
  std::uint32_t addon_crc_actual = 0;
  std::uint64_t trailing_bytes = 0;      // bytes after the CRC trailer
  bool ok() const noexcept {
    return bad_entries.empty() && (addon_crc_stored == 0 || addon_crc_stored == addon_crc_actual) &&
           trailing_bytes == 0;
  }
};

// Reads a whole GMAD stream once: index, every file (checking nonzero CRCs), the addon CRC and any
// trailing data. Throws FormatError when the stream ends before the CRC trailer.
VerifyReport verify(Source& source, const Limits& limits = {});

// Opens an archive file positioned at the start of its GMAD stream. LZMA-wrapped files are
// recognised but not decoded yet (M2 part 2) and raise FormatError.
std::unique_ptr<Source> open_archive(const std::filesystem::path& path, Container* container = nullptr);

// Key for duplicate-path detection: ASCII-lowercased with '\\' turned into '/'. Matches gmapack.py
// for ASCII names (gmapack casefolds full Unicode).
std::string path_key(std::string_view path);

}  // namespace nl::gma
