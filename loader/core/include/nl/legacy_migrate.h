#pragma once
// Read-only planning of the pre-loader RTXLauncher layout (ADR 0042). Execution belongs to
// deploy.cpp's normal durable transaction; a backup never becomes an uninstall original.

#include "nl/fs.h"

#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace nl::legacy {

inline constexpr std::string_view kBackups = "native-loader/backup/legacy";

struct SavedFile {
  std::string path;
  fs::Hash before;
  std::filesystem::path stock_source;  // empty for a file that should only be archived
  fs::Hash stock;
  std::string restore_target;  // old uninstall original already kept inside native-loader/backup
};

struct Migration {
  std::string archive;  // empty if no independently installed Remix runtime was found
  std::vector<SavedFile> files;
  std::vector<std::string> notes;
};

// `owned` is every current loader-owned path, folded. None is treated as a legacy installation.
// A source override is for offline nlctl recovery; otherwise discover Steam's registered install
// and the launcher's backup_patches folders. An explicit root replaces automatic Steam discovery;
// local launcher backups remain candidates. Every recovery file needs a known stock SHA-256.
Migration plan(const std::filesystem::path& root, const std::set<std::string>& owned,
               std::uint64_t transaction, const std::optional<std::filesystem::path>& stock_source = std::nullopt);

// Narrow journal exception for migration transaction steps. This does not allow a package to
// declare Steam/bin files as payload targets, or let generations own them.
bool step_path(std::string_view path);
bool installed_path(std::string_view path);  // recognized legacy roots/files, for kept originals
std::string backup_manifest(const Migration& migration);

}  // namespace nl::legacy
