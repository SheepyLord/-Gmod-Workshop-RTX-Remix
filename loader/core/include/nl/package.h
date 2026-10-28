#pragma once
// A package's files, from a .gma archive (plain or LZMA-wrapped) or an unpacked development folder
// with the same layout, and load(), which reads native/manifest.json and checks it against them.

#include "nl/manifest.h"

#include <cstddef>
#include <filesystem>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace nl::package {

// The package cannot be used: no manifest, unreadable folder, a file too large to read.
class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

using Entry = manifest::ContentEntry;

inline constexpr std::size_t kMaxManifestBytes = std::size_t{1} << 20;
inline constexpr std::size_t kMaxFolderEntries = 100000;

// Receives the files Contents::extract delivers.
class Sink {
 public:
  virtual ~Sink() = default;
  virtual void begin(const Entry& entry) = 0;  // the path as the package stores it, and its size
  virtual void data(const unsigned char* bytes, std::size_t size) = 0;
  virtual void end() = 0;  // every byte delivered; the archive's CRC for it (if any) matched
};

class Contents {
 public:
  virtual ~Contents() = default;
  virtual const std::vector<Entry>& entries() const = 0;
  // Bytes of one file (paths compare without case); throws Error if missing or over `max_bytes`.
  virtual std::string read(std::string_view path, std::size_t max_bytes) const = 0;
  // Streams the files whose folded path (paths::fold) is in `wanted` to `sink` in one pass, in the
  // order cheapest for the container (archive order), with bounded memory however large they are.
  // Throws Error if one is missing; gma::FormatError for a damaged archive or a CRC mismatch.
  virtual void extract(const std::set<std::string>& wanted, Sink& sink) const = 0;
  virtual std::filesystem::path location() const = 0;
  const Entry* find(std::string_view path) const;
};

// Index of a .gma; throws gma::FormatError for a malformed archive.
std::unique_ptr<Contents> open_archive(const std::filesystem::path& gma);

// Files below a folder, '/'-separated relative paths. Refuses symbolic links and other reparse
// points anywhere below it, and folders with more than kMaxFolderEntries files.
std::unique_ptr<Contents> open_folder(const std::filesystem::path& folder);

struct Package {
  std::unique_ptr<Contents> contents;
  manifest::Manifest manifest;
  std::string manifest_sha256;  // of the manifest bytes that were parsed: the package version's identity
};

// Reads native/manifest.json, parses it and checks it against the contents. Throws Error (not a
// native package), manifest::Error (invalid manifest) or gma::FormatError (damaged archive).
Package load(std::unique_ptr<Contents> contents);

}  // namespace nl::package
