#pragma once
// The deployer's journal, <game root>\native-loader\state.json (schema 1, docs/ON_DISK_LAYOUT.md):
// every file the loader placed, the generation kept for rollback, files waiting to be deleted, and
// a transaction that has not committed. It is parsed as strictly as a manifest: a journal that does
// not parse stops the deployer, which then changes nothing.

#include "nl/fs.h"
#include "nl/manifest.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace nl::journal {

class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

inline constexpr int kSchema = 1;
inline constexpr std::string_view kPath = "native-loader/state.json";

// A file the loader placed, or found already there with the right content (adopted). Paths are
// relative to the game root and '/'-separated.
struct File {
  std::string path;
  std::string package;      // id of the package it belongs to
  std::string sha256;
  std::uint64_t size = 0;
  std::uint64_t mtime = 0;  // last write time when placed (FILETIME units)
  bool adopted = false;     // was there before the loader: never moved or deleted by it
};

struct Package {
  std::string id;
  std::string version;
  std::string manifest_sha256;
  std::string source;    // dev_folder, local or workshop
  std::string location;  // the archive or folder it came from
  std::string payload;   // its payload folder, relative to the root; empty if it has no payload
  std::optional<manifest::Remix> remix;  // remix-runtime packages: what M4 activates
  manifest::Session session;             // RTX-session extras (M5): patch sets, overrides, cvars
  bool requires_remix = false;           // add-on folders hidden from sessions without a runtime (ADR 0013)
  std::vector<manifest::ModuleDependency> module_dependencies;  // every session (ADR 0024)
  std::optional<manifest::Reshade> reshade;                     // RTX sessions (ADR 0028)
};

// One deployed state of the install.
struct Generation {
  std::uint64_t number = 0;
  std::vector<Package> packages;
  std::vector<File> files;  // root files and payload files
};

// One change of a transaction. Recovery undoes them in reverse order, each only if it happened.
struct Step {
  enum class Op { make_dir, move };
  Op op = Op::move;
  std::string from;    // move only
  std::string to;      // the folder made, or where the move goes
  std::string sha256;  // a file move: the file's hash; empty for a folder
};

struct Pending {
  std::uint64_t transaction = 0;
  std::string action;  // apply or rollback
  std::vector<Step> steps;
};

struct Journal {
  std::string loader;                  // version that wrote it
  std::uint64_t next = 1;              // number of the next transaction (and generation)
  std::optional<Generation> current;
  std::optional<Generation> previous;  // what rollback returns to
  std::string previous_backup;         // folder holding the previous generation's files that current replaced or removed
  std::vector<File> retired;           // waiting to be deleted (only while still unchanged)
  std::vector<std::string> dirs;       // folders the loader created; removed once empty
  // After a rollback: the packages ("id@manifest_sha256") it rolled back from, which apply does not
  // deploy again until the planned set differs. The set may be empty; nullopt means no hold.
  std::optional<std::vector<std::string>> hold;
  std::optional<Pending> pending;      // a transaction that did not commit
};

Journal parse(std::string_view text);  // throws Error
std::string serialize(const Journal& journal);

// <root>\native-loader\state.json: nullopt if there is none; throws Error if it cannot be read or is invalid.
std::optional<Journal> load(const std::filesystem::path& root);

// Writes the journal atomically through `disk`.
void save(fs::FileSystem& disk, const std::filesystem::path& root, const Journal& journal);

}  // namespace nl::journal
