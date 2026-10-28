#include "nl/package.h"

#include "nl/gma.h"
#include "nl/paths.h"

#include <windows.h>

#include <fstream>
#include <system_error>

namespace nl::package {

namespace {

namespace fs = std::filesystem;

std::string utf8_path(const fs::path& path) {
  const std::u8string text = path.u8string();
  return std::string(text.begin(), text.end());
}

fs::path from_utf8(const std::string& text) {
  return fs::path(std::u8string(reinterpret_cast<const char8_t*>(text.data()), text.size()));
}

class ArchiveContents final : public Contents {
 public:
  explicit ArchiveContents(fs::path file) : file_(std::move(file)) {
    const auto source = gma::open_archive(file_);
    index_ = gma::read_index(*source);
    for (const gma::Entry& e : index_.entries) entries_.push_back({e.path, e.size});
  }

  const std::vector<Entry>& entries() const override { return entries_; }

  std::string read(std::string_view path, std::size_t max_bytes) const override {
    const std::string key = paths::fold(path);
    for (const gma::Entry& e : index_.entries) {
      if (paths::fold(e.path) == key) return gma::read_entry(file_, e, max_bytes);
    }
    throw Error(utf8_path(file_) + " has no " + std::string(path));
  }

  fs::path location() const override { return file_; }

 private:
  fs::path file_;
  gma::Index index_;
  std::vector<Entry> entries_;
};

class FolderContents final : public Contents {
 public:
  explicit FolderContents(fs::path folder) : folder_(std::move(folder)) {
    std::error_code ec;
    if (!fs::is_directory(folder_, ec)) throw Error(utf8_path(folder_) + " is not a folder");
    if (fs::is_symlink(folder_, ec)) throw Error(utf8_path(folder_) + " is a link; use the real folder");
    for (fs::recursive_directory_iterator it(folder_, ec), end; !ec && it != end; it.increment(ec)) {
      const fs::directory_entry& item = *it;
      if (item.is_symlink(ec) || (GetFileAttributesW(item.path().c_str()) & FILE_ATTRIBUTE_REPARSE_POINT)) {
        throw Error(utf8_path(item.path()) + " is a link or reparse point; packages may not contain them");
      }
      if (!item.is_regular_file(ec)) continue;
      if (entries_.size() >= kMaxFolderEntries) throw Error(utf8_path(folder_) + " has too many files");
      const std::u8string relative = fs::relative(item.path(), folder_).generic_u8string();
      entries_.push_back({std::string(relative.begin(), relative.end()), item.file_size(ec)});
    }
    if (ec) throw Error("cannot list " + utf8_path(folder_) + ": " + ec.message());
  }

  const std::vector<Entry>& entries() const override { return entries_; }

  std::string read(std::string_view path, std::size_t max_bytes) const override {
    const Entry* entry = find(path);
    if (!entry) throw Error(utf8_path(folder_) + " has no " + std::string(path));
    if (entry->size > max_bytes) throw Error(std::string(path) + " is larger than " + std::to_string(max_bytes) + " bytes");
    std::ifstream in(folder_ / from_utf8(entry->path), std::ios::binary);
    std::string bytes(static_cast<std::size_t>(entry->size), '\0');
    if (!in.read(bytes.data(), static_cast<std::streamsize>(bytes.size()))) throw Error("cannot read " + entry->path);
    return bytes;
  }

  fs::path location() const override { return folder_; }

 private:
  fs::path folder_;
  std::vector<Entry> entries_;
};

}  // namespace

const Entry* Contents::find(std::string_view path) const {
  const std::string key = paths::fold(path);
  for (const Entry& e : entries()) {
    if (paths::fold(e.path) == key) return &e;
  }
  return nullptr;
}

std::unique_ptr<Contents> open_archive(const std::filesystem::path& gma) {
  return std::make_unique<ArchiveContents>(gma);
}

std::unique_ptr<Contents> open_folder(const std::filesystem::path& folder) {
  return std::make_unique<FolderContents>(folder);
}

Package load(std::unique_ptr<Contents> contents) {
  if (!contents->find(manifest::kManifestPath)) {
    throw Error("not a native package: no " + std::string(manifest::kManifestPath));
  }
  Package package;
  package.manifest = manifest::parse(contents->read(manifest::kManifestPath, kMaxManifestBytes));
  manifest::check_contents(package.manifest, contents->entries());
  package.contents = std::move(contents);
  return package;
}

}  // namespace nl::package
