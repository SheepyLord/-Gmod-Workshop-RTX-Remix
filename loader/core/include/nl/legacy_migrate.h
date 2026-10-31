#pragma once
// Read-only planning of the pre-loader RTXLauncher layout (ADR 0042). Execution belongs to
// deploy.cpp's normal durable transaction; a backup never becomes an uninstall original.

#include "nl/fs.h"

#include <cstdint>
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
  // stock_source as the archive's manifest records it: relative to the game root for a copy inside
  // the game folder (the launcher's backup_patches, a .bak), absolute for an external root.
  std::string source;
};

struct Migration {
  std::string archive;  // empty if no independently installed Remix runtime was found
  std::vector<SavedFile> files;
  std::vector<std::string> notes;
};

// A Steam depot file by hash only: its size and SHA-256 in one GMod build and, for a file the
// launcher replaces, the exact SHA-256 its replacement has. A build anchor has no legacy hash.
struct DepotFile {
  std::string path;
  std::uint64_t size = 0;
  std::string sha256;
  std::string legacy_sha256;
};

// What stock restoration trusts: one build's replaced depot files, and unmodified files that confirm
// that build. builtin_catalog() is GMod x86-64 build 26229091 (legacy_stock_data.h).
struct Catalog {
  std::string build;
  std::vector<DepotFile> files;
  std::vector<DepotFile> anchors;
};
const Catalog& builtin_catalog();

// `owned` is every path the current generation placed, folded. None is treated as a legacy file.
// A source override is for offline nlctl recovery; otherwise discover Steam's registered install
// and the launcher's backup_patches folders. An explicit root replaces automatic Steam discovery;
// local launcher backups remain candidates. Every recovery file needs a known stock SHA-256.
// Links are never followed: one inside the former installation stays in place, with a note. Steam's
// files are restored as a complete, recognized set of the catalogued build or left as they are, with
// a note. Throws when the plan cannot be made (a recovery file with no verified stock copy, a linked
// archive folder, a file that cannot be read); deploy.cpp then deploys without a migration.
Migration plan(const std::filesystem::path& root, const std::set<std::string>& owned,
               std::uint64_t transaction, const std::optional<std::filesystem::path>& stock_source = std::nullopt);
// The same with another catalog, for tests: synthetic identities for the built-in catalog's paths.
// A catalog naming any other depot path is refused (std::invalid_argument), so step_path stays exact.
Migration plan(const std::filesystem::path& root, const std::set<std::string>& owned, std::uint64_t transaction,
               const std::optional<std::filesystem::path>& stock_source, const Catalog& catalog);

// Narrow journal exception for migration transaction steps. This does not allow a package to
// declare Steam/bin files as payload targets, or let generations own them.
bool step_path(std::string_view path);
bool installed_path(std::string_view path);  // recognized legacy roots/files, for kept originals
std::string backup_manifest(const Migration& migration);

}  // namespace nl::legacy
