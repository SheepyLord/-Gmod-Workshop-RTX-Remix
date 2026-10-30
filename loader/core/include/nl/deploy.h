#pragma once
// The deployer (M3, docs/decisions/0007-transactional-deployment.md): turns a plan into files on disk
// as one transaction, with a journal that lets it verify, roll back and remove exactly what it placed.
// nlctl runs it outside the game; from M4 the bootstrap runs it in its start-up step.
//
// Every command locks native-loader\lock, refuses while this folder's Garry's Mod is running, undoes
// a transaction an earlier run left unfinished, and finishes pending clean-up before its own work.

#include "nl/config.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/manifest.h"
#include "nl/planner.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace nl::deploy {

struct Options {
  fs::FileSystem* filesystem = nullptr;  // where changes go; default fs::win32()
  bool dry_run = false;                  // work out and report the changes, make none
  bool allow_running_game = false;       // test/explicit caller override; skips every process check
  std::uint32_t exclude_process_id = 0;  // M4 ignores only itself, preserving the second-instance check
  bool keep_last_good = false;           // M4 only: an unusable still-allowlisted source cannot remove/replace current
};

struct Change {
  std::string action;  // add, replace, remove, adopt, restore, payload, delete
  std::string path;    // relative to the game root
};

struct Skipped {
  std::string package;  // source and label, as nlctl plan shows them
  std::string reason;
};

struct Report {
  enum class BlockedBy { none, running_game, deployer_lock };
  std::string action;   // apply, rollback, uninstall or recover
  // deployed, unchanged, held, planned (dry run), rolled-back, removed, recovered; failed or refused
  // when nothing was changed (a failed transaction is undone before the report is returned).
  std::string outcome;
  std::uint64_t generation = 0;       // the current generation afterwards; 0 if none
  bool recovered = false;             // an interrupted transaction was undone first
  std::vector<std::string> packages;  // deployed afterwards (dry run: would be), "id version"
  std::vector<Skipped> skipped;       // allowlisted packages that are not deployed, and why
  std::vector<Change> changes;        // what was done (dry run: would be done)
  std::vector<std::string> notes;     // files left alone, and why
  std::string error;                  // why it failed or was refused
  std::uint64_t operations = 0;       // file-system changes made; 0 means nothing was written
  BlockedBy blocked_by = BlockedBy::none;
  bool ok() const { return outcome != "failed" && outcome != "refused"; }
};

// Deploys the active packages of the plan made from `considered`. A package whose files fail their
// checks, or whose target is a folder or a link, is re-planned as broken, so a lower-precedence copy
// can take over (ADR 0006). A file in a package's way is kept aside and put back later (ADR 0035).
// Throws journal::Error if state.json is invalid.
Report apply(const std::filesystem::path& root, std::vector<planner::Considered> considered, const config::Config& config,
             const manifest::Version& loader, const Options& options = {});

// Returns to the previous generation, then holds it: apply leaves it in place until the set of
// packages changes again. Rolling back twice returns to where it started.
Report rollback(const std::filesystem::path& root, const Options& options = {});

// Removes every file and folder the loader placed and its journal, and puts back the originals it
// kept (ADR 0035). Files changed since they were placed stay and are reported. config.json, the
// bootstrap and its logs are not touched.
Report uninstall(const std::filesystem::path& root, const Options& options = {});

// Only undoes an interrupted transaction and finishes pending clean-up.
Report recover(const std::filesystem::path& root, const Options& options = {});

struct Drift {
  std::string path;
  std::string problem;  // missing, changed
};

struct Status {
  std::optional<journal::Journal> journal;  // nullopt: nothing deployed
  std::vector<Drift> drift;                 // current generation's files that are not as placed
};

// Read-only: compares every file of the current generation with the disk (size and time, and the
// SHA-256 where those differ; with `hashes`, always the SHA-256). Throws journal::Error.
Status status(const std::filesystem::path& root, bool hashes);

}  // namespace nl::deploy
