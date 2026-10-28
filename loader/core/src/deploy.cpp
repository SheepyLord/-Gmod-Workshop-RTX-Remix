#include "nl/deploy.h"

#include "nl/core.h"
#include "nl/discovery.h"
#include "nl/gma.h"
#include "nl/package.h"
#include "nl/paths.h"
#include "nl/sha256.h"
#include "nl/startup.h"
#include "nl/status.h"

#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <utility>

namespace nl::deploy {

namespace {

using Path = std::filesystem::path;
using journal::File;
using journal::Generation;
using journal::Journal;
using journal::Step;

constexpr std::string_view kLoaderDir = "native-loader";
constexpr std::string_view kStaging = "native-loader/staging";
constexpr std::string_view kBackup = "native-loader/backup";
constexpr std::string_view kPackages = "native-loader/packages";
constexpr std::string_view kLock = "native-loader/lock";
constexpr std::string_view kPayloadPrefix = "native/payload/";
constexpr std::string_view kRootPrefix = "native/root/";
constexpr std::uint64_t kSpareBytes = std::uint64_t{64} << 20;  // left free after staging
constexpr std::size_t kMaxVersionInFolderName = 64;
constexpr std::size_t kNoPackage = static_cast<std::size_t>(-1);

// A package that cannot be deployed: its files fail their checks, or a target is taken. The run
// goes on without it.
class PackageProblem : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

// Ends a planning pass: the package of decision `index` is re-planned as broken.
struct Broken {
  std::size_t index;
  std::string reason;
};

std::string fold(std::string_view path) {
  return paths::fold(path);
}

// Every folder above a relative path: "a/b/c" gives "a" and "a/b".
std::vector<std::string> ancestors(std::string_view path) {
  std::vector<std::string> out;
  for (std::size_t at = path.find('/'); at != std::string_view::npos; at = path.find('/', at + 1)) {
    out.emplace_back(path.substr(0, at));
  }
  return out;
}

bool is_payload(std::string_view path) {
  return paths::within(path, kPackages);
}

// A generation's packages as a comparable set.
std::vector<std::string> package_set(const std::vector<journal::Package>& packages) {
  std::vector<std::string> out;
  for (const journal::Package& p : packages) out.push_back(p.id + "@" + p.manifest_sha256);
  std::sort(out.begin(), out.end());
  return out;
}

template <class T>
void append(std::vector<T>& to, const std::vector<T>& from) {
  to.insert(to.end(), from.begin(), from.end());
}

void add_dir(std::vector<std::string>& dirs, const std::string& dir) {
  const std::string key = fold(dir);
  if (std::none_of(dirs.begin(), dirs.end(), [&](const std::string& d) { return fold(d) == key; })) dirs.push_back(dir);
}

void sort_dirs(std::vector<std::string>& dirs) {
  std::sort(dirs.begin(), dirs.end(), [](const std::string& a, const std::string& b) { return fold(a) < fold(b); });
}

// An exclusive handle on native-loader\lock: one deployer per game folder at a time. Windows closes
// the handle when the process ends, however it ends.
class Lock {
 public:
  Lock() = default;
  ~Lock() { release(); }
  Lock(const Lock&) = delete;
  Lock& operator=(const Lock&) = delete;

  bool acquire(const Path& file) {
    handle_ = CreateFileW(fs::long_path(file).c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS,
                          FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle_ != INVALID_HANDLE_VALUE) return true;
    error_ = GetLastError();
    return false;
  }

  void release() {
    if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
    handle_ = INVALID_HANDLE_VALUE;
  }

  unsigned long error() const { return error_; }

 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  unsigned long error_ = 0;
};

// True if this folder's gmod.exe is running, or a gmod.exe whose folder cannot be read is.
bool game_running(const Path& root, std::uint32_t excluded_process) {
  const std::wstring targets[] = {std::filesystem::absolute(root / L"bin" / L"win64" / L"gmod.exe").lexically_normal().native(),
                                  std::filesystem::absolute(root / L"gmod.exe").lexically_normal().native()};
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return false;
  std::vector<PROCESSENTRY32W> entries;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) entries.push_back(entry);
  CloseHandle(snapshot);
  // The game started through the root gmod.exe (the 32-bit launcher) may find its parent still
  // alive for a moment; that launcher is part of this start, not another game.
  std::uint32_t launcher = 0;
  if (excluded_process) {
    for (const auto& item : entries) {
      if (item.th32ProcessID == excluded_process) launcher = item.th32ParentProcessID;
    }
  }
  bool running = false;
  for (const auto& item : entries) {
    if (running) break;
    if (item.th32ProcessID == excluded_process) continue;
    if (CompareStringOrdinal(item.szExeFile, -1, L"gmod.exe", -1, TRUE) != CSTR_EQUAL) continue;
    const bool parent = launcher && item.th32ProcessID == launcher;
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, item.th32ProcessID);
    if (!process) {
      // Access denied: it cannot be told where it runs from, so assume here. Anything else: it has
      // exited since the snapshot.
      if (GetLastError() == ERROR_ACCESS_DENIED) running = true;
      continue;
    }
    std::wstring image(32768, L'\0');
    DWORD size = static_cast<DWORD>(image.size());
    if (QueryFullProcessImageNameW(process, 0, image.data(), &size)) {
      image.resize(size);
      for (std::size_t i = 0; i < std::size(targets); ++i) {
        if (parent && i == 1) continue;  // our own launcher, root\gmod.exe
        if (CompareStringOrdinal(image.c_str(), -1, targets[i].c_str(), -1, TRUE) == CSTR_EQUAL) running = true;
      }
    } else {
      DWORD code = 0;
      if (!parent && GetExitCodeProcess(process, &code) && code == STILL_ACTIVE) running = true;  // alive, place unknown
    }
    CloseHandle(process);
  }
  return running;
}

// Everything one command works with.
struct Run {
  Run(Path game_root, const Options& options, const char* action)
      : root(std::move(game_root)),
        disk(options.filesystem ? *options.filesystem : fs::win32()),
        dry_run(options.dry_run),
        allow_running_game(options.allow_running_game),
        exclude_process_id(options.exclude_process_id) {
    report.action = action;
  }

  Path at(std::string_view relative) const { return fs::join(root, relative); }
  void note(std::string text) { report.notes.push_back(std::move(text)); }

  Path root;
  fs::Counting disk;  // every change goes through it, so the report can count them
  bool dry_run;
  bool allow_running_game;
  std::uint32_t exclude_process_id;
  Report report;
  Journal journal;
};

// The file is as the loader recorded it: the same size and either the same time or, failing that
// (or always, with `hash`), the same SHA-256.
bool unchanged(const Path& file, const File& record, bool hash) {
  const fs::Stat s = fs::stat(file);
  if (!s.exists || s.directory || s.link || s.size != record.size) return false;
  if (!hash && s.mtime == record.mtime) return true;
  return fs::hash_file(file).sha256 == record.sha256;
}

bool refuse(Run& run, std::string why) {
  run.report.outcome = "refused";
  run.report.error = std::move(why);
  return false;
}

void list_packages(Report& report, const std::vector<journal::Package>& packages) {
  report.packages.clear();
  for (const journal::Package& p : packages) report.packages.push_back(p.id + " " + p.version + (p.remix ? " (runtime)" : ""));
}

// Undoes one step if it happened. Idempotent, so recovery can itself be interrupted and run again.
// It never follows a link and never moves a file other than the one the step moved (its hash).
// What it cannot put back stays known to the journal, so clean-up removes it later.
void undo(Run& run, const Step& step) {
  if (step.op == Step::Op::make_dir) {
    const Path dir = run.at(step.to);
    const fs::Stat s = fs::stat(dir);
    if (!s.exists || !s.directory || s.link) return;
    if (fs::list(dir).empty()) {
      run.disk.remove_directory(dir);
    } else {
      add_dir(run.journal.dirs, step.to);  // something else is in it now: removed once empty
      sort_dirs(run.journal.dirs);
    }
    return;
  }
  for (const std::string* path : {&step.from, &step.to}) {
    try {
      fs::refuse_links(run.root, *path);
    } catch (const fs::Error& e) {
      run.note(std::string("an interrupted change was not undone: ") + e.what());
      return;
    }
  }
  const Path from = run.at(step.from);
  const Path to = run.at(step.to);
  const fs::Stat at_to = fs::stat(to);
  if (!at_to.exists) return;  // never moved
  if (fs::stat(from).exists) {
    // Moved, and something else has taken its old place since. A copy the step put into the
    // loader's own folders (a file moved aside) is retired: deleted once clean-up finds it unchanged.
    if (!step.sha256.empty() && !at_to.directory && paths::within(step.to, kLoaderDir) &&
        fs::hash_file(to).sha256 == step.sha256) {
      run.journal.retired.push_back({step.to, "", step.sha256, at_to.size, at_to.mtime, false});
      run.note(step.from + " changed while a deployment was interrupted; the loader's earlier copy of it is deleted");
    }
    return;
  }
  if (!step.sha256.empty() && (at_to.directory || fs::hash_file(to).sha256 != step.sha256)) {
    run.note(step.to + ": left in place while undoing an interrupted change; it is not the file the loader moved there");
    return;
  }
  run.disk.move(to, from, false);
}

// Undoes the transaction an earlier run did not commit.
void recover_pending(Run& run) {
  if (!run.journal.pending) return;
  const std::vector<Step> steps = run.journal.pending->steps;
  for (auto it = steps.rbegin(); it != steps.rend(); ++it) undo(run, *it);
  run.journal.pending.reset();
  journal::save(run.disk, run.root, run.journal);
  run.report.recovered = true;
}

bool through_link(const Run& run, std::string_view relative) {
  try {
    fs::refuse_links(run.root, relative);
    return false;
  } catch (const fs::Error&) {
    return true;
  }
}

// Clean-up: the staging folder, retired files that are still unchanged, and the empty folders the
// loader made. Each part can be interrupted and redone. Something that cannot be removed now (open
// in another program, read-only) stays listed and is tried again by the next run, so clean-up never
// stops a command; only a journal that cannot be written does. Returns false if something stayed.
bool collect(Run& run) {
  bool complete = true;
  if (fs::stat(run.at(kStaging)).exists) {
    try {
      fs::remove_tree(run.disk, run.at(kStaging));
    } catch (const fs::Error& e) {
      run.note(std::string("the staging folder could not be removed yet (") + e.what() + "); the next run tries again");
      complete = false;
    }
  }
  std::vector<File> retired;  // what stays to be deleted
  for (const File& f : run.journal.retired) {
    const Path file = run.at(f.path);
    if (through_link(run, f.path)) {
      run.note(f.path + ": not deleted, because its path now passes through a link");
      continue;
    }
    try {
      const fs::Stat s = fs::stat(file);
      if (!s.exists) continue;
      if (!unchanged(file, f, true)) {
        run.note(f.path + ": not deleted, because it changed after the loader placed it");
      } else if (s.readonly) {
        run.note(f.path + ": not deleted, because it is read-only; clear the flag and the next run deletes it");
        retired.push_back(f);
        complete = false;
      } else {
        run.disk.remove_file(file);
        run.report.changes.push_back({"delete", f.path});
      }
    } catch (const fs::Error& e) {
      run.note(f.path + ": could not be deleted yet (" + e.what() + "); the next run tries again");
      retired.push_back(f);
      complete = false;
    }
  }
  bool changed = retired.size() != run.journal.retired.size();
  run.journal.retired = std::move(retired);
  std::vector<std::string> dirs = run.journal.dirs;
  std::sort(dirs.begin(), dirs.end(), [](const std::string& a, const std::string& b) { return fold(a) > fold(b); });  // children first
  std::vector<std::string> kept;
  for (const std::string& dir : dirs) {
    const Path path = run.at(dir);
    if (through_link(run, dir)) {
      changed = true;  // a link now: no longer the loader's folder
      continue;
    }
    try {
      const fs::Stat s = fs::stat(path);
      if (!s.exists || !s.directory) {
        changed = true;  // gone, or replaced by a file
      } else if (fs::list(path).empty()) {
        run.disk.remove_directory(path);
        changed = true;
      } else {
        kept.push_back(dir);
      }
    } catch (const fs::Error& e) {
      run.note(dir + ": folder could not be removed yet (" + e.what() + "); the next run tries again");
      kept.push_back(dir);
      complete = false;
    }
  }
  if (changed) {
    sort_dirs(kept);
    run.journal.dirs = std::move(kept);
    journal::save(run.disk, run.root, run.journal);
  }
  return complete;
}

// Clean-up after a commit: a failure there does not undo the deployment, the next run finishes it.
void finish(Run& run) {
  try {
    collect(run);
  } catch (const std::exception& e) {
    run.note(std::string("clean-up stopped (") + e.what() + "); the next run finishes it");
  }
}

// The start of every command: game check, lock, journal, recovery, clean-up. False when there is
// nothing to work on (outcome "unchanged") or the command is refused.
bool begin(Run& run, Lock& lock) {
  const fs::Stat dir = fs::stat(run.at(kLoaderDir));
  if (!dir.exists) {
    run.report.outcome = "unchanged";  // no native-loader folder: no config.json, nothing deployed
    return false;
  }
  if (!dir.directory || dir.link) {
    return refuse(run, "native-loader is not an ordinary folder (a file, junction or link); the loader only works in a real folder");
  }
  // Its own folders must not lead elsewhere either: moves between them must stay on this volume.
  for (const std::string_view own : {kStaging, kPackages, kBackup}) {
    try {
      fs::refuse_links(run.root, own);
    } catch (const fs::Error& e) {
      return refuse(run, e.what());
    }
  }
  if (!run.dry_run) {
    if (!run.allow_running_game && game_running(run.root, run.exclude_process_id)) {
      run.report.blocked_by = Report::BlockedBy::running_game;
      return refuse(run, "Garry's Mod is running from this folder; close it first");
    }
    if (!lock.acquire(run.at(kLock))) {
      if (lock.error() == ERROR_SHARING_VIOLATION) run.report.blocked_by = Report::BlockedBy::deployer_lock;
      return refuse(run, lock.error() == ERROR_SHARING_VIOLATION
                             ? std::string("another deployment is running in this folder")
                             : "cannot open native-loader/lock (Windows error " + std::to_string(lock.error()) + ")");
    }
  }
  if (auto loaded = journal::load(run.root)) run.journal = std::move(*loaded);
  if (run.dry_run) {
    if (run.journal.pending) run.note("an interrupted deployment will be undone first when this runs for real");
    return true;
  }
  // A journal write that was cut off before its rename leaves only this temporary file.
  const Path stale = run.at(std::string(journal::kPath) + ".tmp");
  if (fs::stat(stale).exists) run.disk.remove_file(stale);
  recover_pending(run);
  collect(run);
  return true;
}

// Makes the steps, then commits `next`. Any failure before the commit undoes them, so the install
// is as it was; a crash instead leaves `pending` in the journal for the next run to undo.
bool transact(Run& run, Journal next, const std::vector<Step>& steps, std::uint64_t tx, const char* action) {
  Journal& j = run.journal;
  j.pending = journal::Pending{tx, action, steps};
  j.next = tx + 1;  // a number is never reused, even if this transaction is undone
  journal::save(run.disk, run.root, j);
  try {
    for (const Step& step : steps) {
      if (step.op == Step::Op::make_dir) {
        run.disk.create_directory(run.at(step.to));
      } else {
        run.disk.move(run.at(step.from), run.at(step.to), false);
      }
    }
    journal::save(run.disk, run.root, next);
  } catch (const std::exception& e) {
    run.report.outcome = "failed";
    run.report.error = e.what();
    try {
      for (auto it = steps.rbegin(); it != steps.rend(); ++it) undo(run, *it);
      j.pending.reset();
      journal::save(run.disk, run.root, j);
      run.report.error += "; the change was undone";
    } catch (const std::exception& again) {
      run.report.error += std::string("; undoing it failed too (") + again.what() + "), so the next run finishes undoing it";
    }
    return false;
  }
  run.journal = std::move(next);
  return true;
}

// Every physical file a journal refers to (adopted ones excepted), by folded path. A previous-
// generation file is in place unless the current generation replaced or removed it, which moved it
// into previous_backup.
std::map<std::string, File> locations(const Journal& j) {
  std::map<std::string, File> out;
  std::set<std::string> in_place;
  if (j.current) {
    for (const File& f : j.current->files) {
      in_place.insert(fold(f.path) + "@" + f.sha256);
      if (!f.adopted) out.emplace(fold(f.path), f);
    }
  }
  if (j.previous) {
    for (const File& f : j.previous->files) {
      if (f.adopted) continue;
      File at = f;
      if (!is_payload(f.path) && !j.previous_backup.empty() && !in_place.count(fold(f.path) + "@" + f.sha256)) {
        at.path = j.previous_backup + "/" + f.path;
      }
      std::string key = fold(at.path);
      out.emplace(std::move(key), std::move(at));
    }
  }
  return out;
}

// Moves the entries the way `steps` move files and folders.
void follow_moves(std::map<std::string, File>& entries, const std::vector<Step>& steps) {
  for (const Step& step : steps) {
    if (step.op != Step::Op::move) continue;
    std::vector<File> moved;
    for (auto it = entries.begin(); it != entries.end();) {
      if (paths::within(it->first, step.from)) {
        File f = it->second;
        f.path = step.to + f.path.substr(step.from.size());
        moved.push_back(std::move(f));
        it = entries.erase(it);
      } else {
        ++it;
      }
    }
    for (File& f : moved) {
      std::string key = fold(f.path);
      entries.emplace(std::move(key), std::move(f));
    }
  }
}

// Files `before` refers to that `after` no longer does once `steps` moved them: they are retired.
// `left` are current files the loader stops tracking and leaves in place.
std::vector<File> retired_after(const Journal& before, const std::vector<Step>& steps, const Journal& after,
                                const std::set<std::string>& left) {
  std::map<std::string, File> old = locations(before);
  for (const std::string& key : left) old.erase(key);
  follow_moves(old, steps);
  const std::map<std::string, File> now = locations(after);
  std::vector<File> out;
  for (const auto& entry : old) {
    if (!now.count(entry.first)) out.push_back(entry.second);
  }
  return out;
}

// --- apply ---------------------------------------------------------------------------------------

struct Staged {
  std::string from;  // where it is in the staging folder, relative to the root
  std::string sha256;
  std::uint64_t size = 0;
  std::uint64_t mtime = 0;
};
using StagedFiles = std::map<std::string, Staged>;          // by folded package path
using StagedByPackage = std::map<std::size_t, StagedFiles>;  // by decision index

std::string staging_base(std::uint64_t tx, std::size_t index) {
  return std::string(kStaging) + "/" + std::to_string(tx) + "/" + std::to_string(index);
}

// Creates the missing folders above `file` (relative). Staging only, so no journal entry is needed.
void make_parents(Run& run, std::string_view file) {
  for (const std::string& dir : ancestors(file)) {
    const fs::Stat s = fs::stat(run.at(dir));
    if (!s.exists) {
      run.disk.create_directory(run.at(dir));
    } else if (!s.directory || s.link) {
      throw fs::Error(dir + " is not an ordinary folder", 0);
    }
  }
}

// Writes the files a package delivers into staging, checking each against its manifest entry.
class StagingSink final : public package::Sink {
 public:
  StagingSink(Run& run, const manifest::Manifest& manifest, const std::map<std::string, std::string>& targets, StagedFiles& out)
      : run_(&run), targets_(&targets), out_(&out) {
    for (const auto& file : manifest.files) infos_.emplace(fold(file.first), &file);
  }

  void begin(const package::Entry& entry) override {
    key_ = fold(entry.path);
    const auto info = infos_.find(key_);
    const auto target = targets_->find(key_);
    if (info == infos_.end() || target == targets_->end()) throw PackageProblem("it delivered an unexpected file " + entry.path);
    file_ = info->second;
    to_ = target->second;
    make_parents(*run_, to_);
    writer_ = run_->disk.create_file(run_->at(to_));
    hasher_ = std::make_unique<sha256::Hasher>();
    written_ = 0;
  }

  void data(const unsigned char* bytes, std::size_t size) override {
    written_ += size;
    if (written_ > file_->second.size) throw PackageProblem(file_->first + " is larger than its manifest says");
    hasher_->update(bytes, size);
    writer_->write(bytes, size);
  }

  void end() override {
    if (written_ != file_->second.size) throw PackageProblem(file_->first + " is smaller than its manifest says");
    const std::string sha = hasher_->finish_hex();
    if (sha != file_->second.sha256) throw PackageProblem(file_->first + " does not match its SHA-256 in the manifest");
    writer_->close();
    writer_.reset();
    (*out_)[key_] = {to_, sha, written_, fs::stat(run_->at(to_)).mtime};
  }

 private:
  using ManifestFile = std::pair<std::string, manifest::FileInfo>;
  Run* run_;
  const std::map<std::string, std::string>* targets_;
  StagedFiles* out_;
  std::map<std::string, const ManifestFile*> infos_;
  const ManifestFile* file_ = nullptr;
  std::string key_;
  std::string to_;
  std::unique_ptr<fs::Writer> writer_;
  std::unique_ptr<sha256::Hasher> hasher_;
  std::uint64_t written_ = 0;
};

// An active package of the plan, worked out against the journal and the disk.
struct Planned {
  struct Root {
    std::string path;          // target relative to the root, as the manifest spells it
    std::string package_path;  // native/root/<path>
    manifest::FileInfo info;
    manifest::Policy policy = manifest::Policy::replace_owned;
  };
  std::size_t index = 0;  // decision (and candidate) index in the plan
  const package::Package* package = nullptr;
  journal::Package record;
  bool stage_payload = false;  // the payload goes into a new folder
  std::vector<File> payload;   // records of a reused payload folder
  std::vector<Root> roots;
};

const Generation* generation(const std::optional<Generation>& g) {
  return g ? &*g : nullptr;
}

// Reuses an intact payload folder of this package version from the current or previous generation.
bool reuse_payload(const Run& run, Planned& p) {
  for (const Generation* gen : {generation(run.journal.current), generation(run.journal.previous)}) {
    if (!gen) continue;
    for (const journal::Package& kept : gen->packages) {
      if (kept.id != p.record.id || kept.manifest_sha256 != p.record.manifest_sha256 || kept.payload.empty()) continue;
      std::vector<File> files;
      bool intact = true;
      for (const File& f : gen->files) {
        if (!paths::within(f.path, kept.payload)) continue;
        if (!unchanged(run.at(f.path), f, false)) {
          intact = false;
          break;
        }
        files.push_back(f);
      }
      if (intact && !files.empty()) {
        p.record.payload = kept.payload;
        p.payload = std::move(files);
        return true;
      }
    }
  }
  return false;
}

Planned work_out(const Run& run, const planner::Decision& decision, std::size_t index, std::uint64_t tx) {
  const package::Package& pkg = *decision.item.package;
  const manifest::Manifest& m = pkg.manifest;
  Planned p;
  p.index = index;
  p.package = &pkg;
  p.record.id = m.id;
  p.record.version = m.version.text;
  p.record.manifest_sha256 = pkg.manifest_sha256;
  p.record.source = discovery::source_name(decision.item.candidate.source);
  p.record.location = fs::utf8(decision.item.candidate.location);
  p.record.remix = m.remix;
  p.record.session = m.session;
  p.record.requires_remix = m.requires_remix;
  bool has_payload = false;
  for (const auto& file : m.files) {
    if (paths::within(file.first, "native/payload")) {
      has_payload = true;
      continue;
    }
    Planned::Root target;
    target.path = file.first.substr(kRootPrefix.size());
    target.package_path = file.first;
    target.info = file.second;
    for (const manifest::RootFile& rf : m.root_files) {
      if (paths::within(target.path, rf.path)) target.policy = rf.policy;
    }
    p.roots.push_back(std::move(target));
  }
  if (has_payload && !reuse_payload(run, p)) {
    p.record.payload = std::string(kPackages) + "/" + m.id + "/" + m.version.text.substr(0, kMaxVersionInFolderName) + "_" +
                       std::to_string(tx);
    if (const std::string why = paths::problem(p.record.payload); !why.empty()) {
      throw PackageProblem("its payload cannot go to " + p.record.payload + ": " + why);
    }
    p.stage_payload = true;
  }
  return p;
}

enum class Act {
  keep,         // in place as recorded
  keep_edited,  // in place, but the user changed it: left alone
  adopt,        // already there with the right content, not placed by the loader
  install,      // new (or the loader's copy is gone): extract and place
  replace,      // the loader's copy, unchanged, and the package has a new version
  skip,         // create-only and someone else's file is there: kept
  remove,       // the plan no longer has it and it is unchanged: moved aside
  drop,         // the plan no longer has it, but it changed or is gone: no longer tracked
};

struct RootPlan {
  std::size_t planned = kNoPackage;  // position in the planned packages (not for remove and drop)
  std::string path;
  std::string package_path;
  manifest::FileInfo info;        // the version wanted
  const File* current = nullptr;  // the current generation's record
  Act act = Act::install;
  std::uint64_t mtime = 0;  // adopt: the file's time
  bool missing = false;     // drop: the file is gone
  bool linked = false;      // drop: its path passes through a link now
};

// What happens to one root file of the plan. Throws PackageProblem if its package cannot place it.
RootPlan decide(const Run& run, const Planned::Root& r, const File* current) {
  RootPlan rp;
  rp.path = r.path;
  rp.package_path = r.package_path;
  rp.info = r.info;
  rp.current = current;
  fs::refuse_links(run.root, r.path);
  for (const std::string& dir : ancestors(r.path)) {
    const fs::Stat above = fs::stat(run.at(dir));
    if (!above.exists) break;
    if (!above.directory) throw PackageProblem(dir + " is a file, so " + r.path + " cannot be placed");
  }
  const Path target = run.at(r.path);
  const fs::Stat s = fs::stat(target);
  if (s.exists && (s.directory || s.link)) throw PackageProblem(r.path + " exists as a folder or a link");
  if (!s.exists) {
    rp.act = Act::install;
  } else if (current) {
    if (current->sha256 == r.info.sha256) {
      rp.act = unchanged(target, *current, false) ? Act::keep : Act::keep_edited;
    } else if (r.policy == manifest::Policy::create_only) {
      rp.act = Act::keep;  // never replaced, not even by a new version
    } else if (current->adopted) {
      throw PackageProblem(r.path +
                           " was there before the loader, which does not replace it with another version; delete it to let the "
                           "loader manage it");
    } else {
      rp.act = unchanged(target, *current, true) ? Act::replace : Act::keep_edited;
    }
  } else if (fs::hash_file(target).sha256 == r.info.sha256) {
    rp.act = Act::adopt;
    rp.mtime = s.mtime;
  } else if (r.policy == manifest::Policy::create_only) {
    rp.act = Act::skip;
  } else {
    throw PackageProblem(r.path + " already exists and was not placed by the loader, which does not replace such files");
  }
  return rp;
}

// Decides every root file: the plan's, and the current generation's that the plan no longer has.
std::vector<RootPlan> check_roots(const Run& run, const std::vector<Planned>& planned) {
  std::map<std::string, const File*> current;
  if (run.journal.current) {
    for (const File& f : run.journal.current->files) {
      if (!is_payload(f.path)) current.emplace(fold(f.path), &f);
    }
  }
  std::vector<RootPlan> out;
  std::set<std::string> wanted;
  for (std::size_t i = 0; i < planned.size(); ++i) {
    for (const Planned::Root& r : planned[i].roots) {
      const std::string key = fold(r.path);
      wanted.insert(key);
      const auto found = current.find(key);
      try {
        RootPlan rp = decide(run, r, found == current.end() ? nullptr : found->second);
        rp.planned = i;
        out.push_back(std::move(rp));
      } catch (const PackageProblem& e) {
        throw Broken{planned[i].index, e.what()};
      } catch (const fs::Error& e) {
        throw Broken{planned[i].index, e.what()};
      }
    }
  }
  if (run.journal.current) {
    for (const File& f : run.journal.current->files) {
      if (is_payload(f.path) || wanted.count(fold(f.path))) continue;
      RootPlan rp;
      rp.path = f.path;
      rp.current = &f;
      rp.info = {f.size, f.sha256};
      rp.linked = through_link(run, f.path);
      rp.missing = !rp.linked && !fs::stat(run.at(f.path)).exists;
      rp.act = !rp.linked && !f.adopted && unchanged(run.at(f.path), f, true) ? Act::remove : Act::drop;
      out.push_back(std::move(rp));
    }
  }
  return out;
}

std::vector<std::string> notes_for(const std::vector<RootPlan>& roots) {
  std::vector<std::string> notes;
  for (const RootPlan& r : roots) {
    if (r.act == Act::keep_edited) {
      notes.push_back(r.path + (r.current->sha256 != r.info.sha256
                                    ? ": not updated to the package's new version, because it changed after the loader placed it"
                                    : ": changed after the loader placed it; left as it is"));
    } else if (r.act == Act::skip) {
      notes.push_back(r.path + ": already there; the existing file is kept (create-only)");
    } else if (r.act == Act::drop && r.linked) {
      notes.push_back(r.path + ": not removed, because its path now passes through a link; the loader no longer tracks it");
    } else if (r.act == Act::drop && !r.current->adopted) {
      notes.push_back(r.path + (r.missing ? ": already gone" : ": left in place; it changed after the loader placed it"));
    }
  }
  return notes;
}

// The files of a package that must be extracted (a new payload folder, new and replaced root
// files): folded package path -> staging path.
std::map<std::string, std::string> staging_targets(const Planned& p, std::size_t position, const std::vector<RootPlan>& roots,
                                                   std::uint64_t tx) {
  const std::string base = staging_base(tx, p.index);
  std::map<std::string, std::string> targets;
  if (p.stage_payload) {
    for (const auto& file : p.package->manifest.files) {
      if (paths::within(file.first, "native/payload")) {
        targets.emplace(fold(file.first), base + "/payload/" + file.first.substr(kPayloadPrefix.size()));
      }
    }
  }
  for (const RootPlan& r : roots) {
    if (r.planned == position && (r.act == Act::install || r.act == Act::replace)) {
      targets.emplace(fold(r.package_path), base + "/root/" + r.path);
    }
  }
  return targets;
}

void ensure_space(const Run& run, std::uint64_t needed) {
  if (!needed) return;
  std::wstring dir = std::filesystem::absolute(run.root).native();
  if (dir.back() != L'\\') dir += L'\\';
  ULARGE_INTEGER available{};
  if (!GetDiskFreeSpaceExW(dir.c_str(), &available, nullptr, nullptr)) return;  // cannot tell: go ahead
  if (available.QuadPart < needed + kSpareBytes) {
    throw std::runtime_error("not enough free disk space: the new files need " + std::to_string(needed >> 20) + " MiB and " +
                             std::to_string(kSpareBytes >> 20) + " MiB should stay free, but only " +
                             std::to_string(available.QuadPart >> 20) + " MiB are free");
  }
}

// The active packages of a plan as a comparable set, like package_set() for a generation.
std::vector<std::string> plan_set(const planner::Plan& plan) {
  std::vector<std::string> out;
  for (const planner::Decision& d : plan.decisions) {
    if (d.active && d.item.package) out.push_back(d.item.package->manifest.id + "@" + d.item.package->manifest_sha256);
  }
  std::sort(out.begin(), out.end());
  return out;
}

void report_skipped(Report& report, const planner::Plan& plan) {
  for (const planner::Decision& d : plan.decisions) {
    if (d.active) continue;
    report.skipped.push_back({std::string(discovery::source_name(d.item.candidate.source)) + " \"" + d.item.candidate.label + "\"",
                              d.reason});
  }
}

// One planning pass of apply. Throws Broken to have a package re-planned as broken. `release_hold`:
// a rollback's hold is in place and the plan no longer names the packages it came from, so the hold
// ends with this run, which therefore writes the journal even when it changes nothing else.
void deploy_plan(Run& run, const planner::Plan& plan, std::uint64_t tx, StagedByPackage& staged, bool release_hold) {
  std::vector<Planned> planned;
  for (std::size_t i = 0; i < plan.decisions.size(); ++i) {
    if (!plan.decisions[i].active) continue;
    try {
      planned.push_back(work_out(run, plan.decisions[i], i, tx));
    } catch (const PackageProblem& e) {
      throw Broken{i, e.what()};
    }
  }
  const std::vector<RootPlan> roots = check_roots(run, planned);
  std::vector<journal::Package> records;
  for (const Planned& p : planned) records.push_back(p.record);
  const Generation none;
  const Generation& cur = run.journal.current ? *run.journal.current : none;
  std::vector<std::string> notes = notes_for(roots);

  const std::vector<std::string> wanted = package_set(records);
  bool work = std::any_of(roots.begin(), roots.end(), [](const RootPlan& r) {
    return r.act == Act::install || r.act == Act::replace || r.act == Act::remove || r.act == Act::adopt || r.act == Act::drop;
  });
  for (const Planned& p : planned) {
    const auto same = std::find_if(cur.packages.begin(), cur.packages.end(), [&](const journal::Package& c) { return c.id == p.record.id; });
    if (p.stage_payload || same == cur.packages.end() || same->payload != p.record.payload) work = true;
  }
  if (!work && wanted == package_set(cur.packages)) {
    run.report.outcome = "unchanged";
    run.report.generation = cur.number;
    list_packages(run.report, cur.packages);
    append(run.report.notes, notes);
    if (release_hold && !run.dry_run) {
      run.journal.hold.reset();
      journal::save(run.disk, run.root, run.journal);
      run.note("the hold after the rollback has ended: the planned packages are no longer the ones it rolled back from");
    }
    return;
  }

  std::vector<Change> changes;
  for (const Planned& p : planned) {
    if (p.stage_payload) changes.push_back({"payload", p.record.payload});
  }
  for (const RootPlan& r : roots) {
    if (r.act == Act::install) changes.push_back({"add", r.path});
    if (r.act == Act::replace) changes.push_back({"replace", r.path});
    if (r.act == Act::remove) changes.push_back({"remove", r.path});
    if (r.act == Act::adopt) changes.push_back({"adopt", r.path});
  }
  if (run.dry_run) {
    run.report.outcome = "planned";
    run.report.generation = cur.number;
    list_packages(run.report, records);
    append(run.report.changes, changes);
    append(run.report.notes, notes);
    return;
  }

  // Extract everything new. Every check happens here, before anything in place changes.
  std::vector<std::map<std::string, std::string>> targets;
  std::uint64_t needed = 0;
  for (std::size_t i = 0; i < planned.size(); ++i) {
    targets.push_back(staging_targets(planned[i], i, roots, tx));
    const StagedFiles& done = staged[planned[i].index];
    for (const auto& file : planned[i].package->manifest.files) {
      const std::string key = fold(file.first);
      if (targets.back().count(key) && !done.count(key)) needed += file.second.size;
    }
  }
  ensure_space(run, needed);
  for (std::size_t i = 0; i < planned.size(); ++i) {
    StagedFiles& done = staged[planned[i].index];
    std::set<std::string> missing;
    for (const auto& target : targets[i]) {
      if (!done.count(target.first)) missing.insert(target.first);
    }
    if (missing.empty()) continue;
    StagingSink sink(run, planned[i].package->manifest, targets[i], done);
    try {
      planned[i].package->contents->extract(missing, sink);
    } catch (const PackageProblem& e) {
      throw Broken{planned[i].index, e.what()};
    } catch (const gma::FormatError& e) {
      throw Broken{planned[i].index, e.what()};
    } catch (const package::Error& e) {
      throw Broken{planned[i].index, e.what()};
    }
  }

  // The steps: folders, files moved aside (kept for rollback), then the new files, payload files
  // included, each moved on its own with its hash so that undoing never moves anything else.
  const std::string backup = std::string(kBackup) + "/" + std::to_string(tx);
  std::map<std::string, std::string> make;  // folded -> path; parents sort before their children
  const auto parents_of = [&](std::string_view file) {
    for (const std::string& dir : ancestors(file)) {
      if (!make.count(fold(dir)) && !fs::stat(run.at(dir)).exists) make.emplace(fold(dir), dir);
    }
  };
  std::vector<Step> aside;
  std::vector<Step> payload_moves;
  std::vector<Step> installs;
  for (const RootPlan& r : roots) {
    if (r.act == Act::replace || r.act == Act::remove) {
      const std::string to = backup + "/" + r.path;
      parents_of(to);
      aside.push_back({Step::Op::move, r.path, to, r.current->sha256});
    }
    if (r.act == Act::install || r.act == Act::replace) {
      const Staged& s = staged.at(planned[r.planned].index).at(fold(r.package_path));
      parents_of(r.path);
      installs.push_back({Step::Op::move, s.from, r.path, s.sha256});
    }
  }
  for (const Planned& p : planned) {
    if (!p.stage_payload) continue;
    const StagedFiles& done = staged.at(p.index);
    for (const auto& file : p.package->manifest.files) {
      if (!paths::within(file.first, "native/payload")) continue;
      const Staged& s = done.at(fold(file.first));
      const std::string to = p.record.payload + "/" + file.first.substr(kPayloadPrefix.size());
      parents_of(to);  // the payload folder and its subfolders, which the journal then owns
      payload_moves.push_back({Step::Op::move, s.from, to, s.sha256});
    }
  }
  std::vector<Step> steps;
  for (const auto& dir : make) steps.push_back({Step::Op::make_dir, "", dir.second, ""});
  append(steps, aside);
  append(steps, payload_moves);
  append(steps, installs);

  // The generation they produce.
  Generation next_gen;
  next_gen.number = tx;
  next_gen.packages = records;
  for (const Planned& p : planned) {
    if (p.stage_payload) {
      const StagedFiles& done = staged.at(p.index);
      for (const auto& file : p.package->manifest.files) {
        if (!paths::within(file.first, "native/payload")) continue;
        const Staged& s = done.at(fold(file.first));
        next_gen.files.push_back(
            {p.record.payload + "/" + file.first.substr(kPayloadPrefix.size()), p.record.id, s.sha256, s.size, s.mtime, false});
      }
    } else {
      for (File f : p.payload) {
        f.package = p.record.id;
        next_gen.files.push_back(std::move(f));
      }
    }
  }
  std::set<std::string> left;  // current files the loader stops tracking because they changed or are gone
  for (const RootPlan& r : roots) {
    switch (r.act) {
      case Act::keep:
      case Act::keep_edited: {
        File f = *r.current;
        f.package = planned[r.planned].record.id;
        next_gen.files.push_back(std::move(f));
        break;
      }
      case Act::adopt:
        next_gen.files.push_back({r.path, planned[r.planned].record.id, r.info.sha256, r.info.size, r.mtime, true});
        break;
      case Act::install:
      case Act::replace: {
        const Staged& s = staged.at(planned[r.planned].index).at(fold(r.package_path));
        next_gen.files.push_back({r.path, planned[r.planned].record.id, s.sha256, s.size, s.mtime, false});
        // The loader's earlier copy was gone, so nothing was kept: the previous generation must not
        // claim it, or a rollback could never be done.
        if (r.act == Act::install && r.current && !r.current->adopted) left.insert(fold(r.path));
        break;
      }
      case Act::drop:
        if (!r.current->adopted) left.insert(fold(r.path));
        break;
      case Act::skip:
      case Act::remove:
        break;
    }
  }

  Journal next = run.journal;
  next.loader = std::string(nl::version());
  next.next = tx + 1;
  next.current = std::move(next_gen);
  // The same packages again (files put back): a repair, which keeps the rollback target.
  const bool repair = wanted == package_set(cur.packages) && aside.empty();
  if (!repair) {
    if (run.journal.current) {
      Generation prev = *run.journal.current;
      std::erase_if(prev.files, [&](const File& f) { return left.count(fold(f.path)) > 0; });
      next.previous = std::move(prev);
    } else {
      next.previous.reset();
    }
    next.previous_backup = aside.empty() ? std::string() : backup;
  }
  next.hold.reset();
  next.pending.reset();
  for (const auto& dir : make) add_dir(next.dirs, dir.second);
  sort_dirs(next.dirs);
  append(next.retired, retired_after(run.journal, steps, next, left));

  if (!transact(run, std::move(next), steps, tx, "apply")) return;
  run.report.outcome = "deployed";
  run.report.generation = tx;
  list_packages(run.report, records);
  append(run.report.changes, changes);
  append(run.report.notes, notes);
  finish(run);
}

// --- rollback, uninstall, recover -----------------------------------------------------------------

void roll_back(Run& run) {
  Lock lock;
  if (!begin(run, lock)) {
    if (run.report.outcome == "unchanged") refuse(run, "nothing has been deployed here, so there is nothing to roll back to");
    return;
  }
  const Journal& j = run.journal;
  if (!j.previous) {
    refuse(run, "there is no previous generation to roll back to");
    return;
  }
  const Generation none;
  const Generation& prev = *j.previous;
  const Generation& cur = j.current ? *j.current : none;
  const std::uint64_t tx = j.next;
  const std::string backup = std::string(kBackup) + "/" + std::to_string(tx);

  for (const File& f : prev.files) {
    if (is_payload(f.path) && !unchanged(run.at(f.path), f, false)) {
      refuse(run, f.path + " is missing or changed, so the previous generation cannot be restored");
      return;
    }
  }
  std::map<std::string, const File*> prev_roots;
  std::map<std::string, const File*> cur_roots;
  for (const File& f : prev.files) {
    if (!is_payload(f.path)) prev_roots.emplace(fold(f.path), &f);
  }
  for (const File& f : cur.files) {
    if (!is_payload(f.path)) cur_roots.emplace(fold(f.path), &f);
  }

  std::map<std::string, std::string> make;
  const auto parents_of = [&](std::string_view file) {
    for (const std::string& dir : ancestors(file)) {
      if (!make.count(fold(dir)) && !fs::stat(run.at(dir)).exists) make.emplace(fold(dir), dir);
    }
  };
  std::vector<Step> aside;
  std::vector<Step> restore;
  std::vector<Change> changes;
  std::set<std::string> left;
  std::set<std::string> freed;
  // Current root files the previous generation does not have in the same version: moved aside.
  for (const auto& [key, mine] : cur_roots) {
    const auto theirs = prev_roots.find(key);
    if (theirs != prev_roots.end() && theirs->second->sha256 == mine->sha256) continue;  // the same in both
    if (mine->adopted) continue;  // not the loader's: stays where it is
    if (through_link(run, mine->path)) {
      refuse(run, mine->path + ": its path now passes through a link, so the rollback does not move it");
      return;
    }
    if (!unchanged(run.at(mine->path), *mine, true)) {
      if (fs::stat(run.at(mine->path)).exists) run.note(mine->path + ": left in place; it changed after the loader placed it");
      left.insert(key);
      continue;
    }
    const std::string to = backup + "/" + mine->path;
    parents_of(to);
    aside.push_back({Step::Op::move, mine->path, to, mine->sha256});
    freed.insert(key);
    if (theirs == prev_roots.end()) changes.push_back({"remove", mine->path});
  }
  // Previous root files that are not in place: brought back from where the current generation put them.
  for (const auto& [key, theirs] : prev_roots) {
    const auto mine = cur_roots.find(key);
    if (mine != cur_roots.end() && mine->second->sha256 == theirs->sha256) continue;  // in place
    if (theirs->adopted) continue;  // not the loader's; checked below
    const std::string from = j.previous_backup.empty() ? std::string() : j.previous_backup + "/" + theirs->path;
    if (!from.empty() && (through_link(run, from) || through_link(run, theirs->path))) {
      refuse(run, theirs->path + ": its path, or its kept copy's, now passes through a link, so the rollback does not restore it");
      return;
    }
    if (from.empty() || !unchanged(run.at(from), *theirs, true)) {
      refuse(run, "the kept copy of " + theirs->path + " is missing or changed, so the previous generation cannot be restored");
      return;
    }
    if (fs::stat(run.at(theirs->path)).exists && !freed.count(key)) {
      refuse(run, theirs->path + " is in the way: it changed, or the loader did not place it");
      return;
    }
    parents_of(theirs->path);
    restore.push_back({Step::Op::move, from, theirs->path, theirs->sha256});
    changes.push_back({mine != cur_roots.end() ? "replace" : "restore", theirs->path});
  }

  Generation target = prev;
  target.number = tx;
  // A file the previous generation adopted that the current one placed itself (it had gone, and
  // the loader put it back) belongs to the loader now: restored as the loader's, not as adopted.
  for (File& f : target.files) {
    if (!f.adopted) continue;
    const auto placed = cur_roots.find(fold(f.path));
    if (placed != cur_roots.end() && !placed->second->adopted && placed->second->sha256 == f.sha256) {
      const std::string package = f.package;
      f = *placed->second;
      f.package = package;
    }
  }
  std::erase_if(target.files, [&](const File& f) {
    if (!f.adopted || unchanged(run.at(f.path), f, false)) return false;
    run.note(f.path + ": no longer there as it was; the restored generation does without it");
    return true;
  });
  std::vector<Step> steps;
  for (const auto& dir : make) steps.push_back({Step::Op::make_dir, "", dir.second, ""});
  append(steps, aside);
  append(steps, restore);
  const std::vector<journal::Package> packages = target.packages;
  if (run.dry_run) {
    run.report.outcome = "planned";
    run.report.generation = cur.number;
    list_packages(run.report, packages);
    append(run.report.changes, changes);
    return;
  }

  Journal next = j;
  next.loader = std::string(nl::version());
  next.next = tx + 1;
  next.current = std::move(target);
  if (j.current) {
    Generation kept = cur;
    std::erase_if(kept.files, [&](const File& f) { return left.count(fold(f.path)) > 0; });
    next.previous = std::move(kept);
  } else {
    next.previous.reset();
  }
  next.previous_backup = aside.empty() ? std::string() : backup;
  next.hold = package_set(cur.packages);
  next.pending.reset();
  for (const auto& dir : make) add_dir(next.dirs, dir.second);
  sort_dirs(next.dirs);
  append(next.retired, retired_after(j, steps, next, left));

  if (!transact(run, std::move(next), steps, tx, "rollback")) return;
  run.report.outcome = "rolled-back";
  run.report.generation = tx;
  list_packages(run.report, packages);
  append(run.report.changes, changes);
  finish(run);
}

void remove_all(Run& run) {
  Lock lock;
  if (!begin(run, lock)) return;
  const bool had_journal = fs::stat(run.at(journal::kPath)).exists;
  Journal next;
  next.loader = std::string(nl::version());
  next.next = run.journal.next;
  for (const auto& entry : locations(run.journal)) next.retired.push_back(entry.second);
  next.dirs = run.journal.dirs;
  if (run.journal.current) {
    for (const File& f : run.journal.current->files) {
      if (f.adopted) run.note(f.path + ": left in place; it was there before the loader");
    }
  }
  if (run.dry_run) {
    for (const File& f : next.retired) run.report.changes.push_back({"delete", f.path});
    run.report.outcome = "planned";
    return;
  }
  if (had_journal) {
    journal::save(run.disk, run.root, next);  // the commit: from here on, everything waits to be deleted
    run.journal = std::move(next);
  }
  try {
    // The journal goes last, and only once nothing it lists is left to delete: until then it is
    // what lets the next run finish the job.
    if (had_journal && !collect(run)) {
      run.note("not everything could be deleted yet; run uninstall again to finish");
    } else {
      if (had_journal) {
        for (const std::string& dir : run.journal.dirs) run.note(dir + ": folder kept; it holds files the loader did not place");
        run.disk.remove_file(run.at(journal::kPath));
      }
      lock.release();
      if (fs::stat(run.at(kLock)).exists) run.disk.remove_file(run.at(kLock));
    }
  } catch (const std::exception& e) {
    run.note(std::string("clean-up stopped (") + e.what() + "); run uninstall again to finish it");
  }
  run.report.outcome = had_journal ? "removed" : "unchanged";
}

void recover_only(Run& run) {
  Lock lock;
  if (!begin(run, lock)) return;
  run.report.outcome = run.report.recovered ? "recovered" : "unchanged";
  if (run.journal.current) {
    run.report.generation = run.journal.current->number;
    list_packages(run.report, run.journal.current->packages);
  }
}

// Runs a command; anything that goes wrong (other than an invalid journal) becomes a failed report.
template <class Body>
Report guarded(Run& run, Body&& body) {
  try {
    body();
  } catch (const journal::Error&) {
    throw;
  } catch (const std::exception& e) {
    run.report.outcome = "failed";
    run.report.error = e.what();
  }
  run.report.operations = run.disk.operations();
  return std::move(run.report);
}

}  // namespace

Report apply(const std::filesystem::path& root, std::vector<planner::Considered> considered, const config::Config& config,
             const manifest::Version& loader, const Options& options) {
  Run run(root, options, "apply");
  return guarded(run, [&] {
    Lock lock;
    if (!begin(run, lock)) return;
    // A rollback's hold is compared with the plan as it stands, before any package is re-planned as
    // broken: a package that cannot be deployed must not turn a held set into one that is deployed.
    const planner::Plan first = planner::make_plan(considered, config, loader);
    bool release_hold = false;
    if (run.journal.hold) {
      if (plan_set(first) == *run.journal.hold) {
        run.report.outcome = "held";
        if (run.journal.current) {
          run.report.generation = run.journal.current->number;
          list_packages(run.report, run.journal.current->packages);
        }
        run.note("held after a rollback: the packages it rolled back from are not deployed again while the plan names them");
        report_skipped(run.report, first);
        return;
      }
      release_hold = true;
    }
    const std::uint64_t tx = run.journal.next;
    StagedByPackage staged;  // kept across planning passes
    for (;;) {
      const planner::Plan plan = planner::make_plan(considered, config, loader);
      if (options.keep_last_good && run.journal.current) {
        if (const auto reason = startup::keep_last_good_reason(*run.journal.current, plan)) {
          run.report.outcome = "kept";
          run.report.generation = run.journal.current->number;
          list_packages(run.report, run.journal.current->packages);
          run.note(*reason);
          report_skipped(run.report, plan);
          if (!staged.empty()) finish(run);  // discard only this run's staged material; current stays intact
          return;
        }
      }
      try {
        deploy_plan(run, plan, tx, staged, release_hold);
        report_skipped(run.report, plan);
        return;
      } catch (const Broken& broken) {
        considered[broken.index].problem = "cannot be deployed: " + broken.reason;
      }
    }
  });
}

Report rollback(const std::filesystem::path& root, const Options& options) {
  Run run(root, options, "rollback");
  return guarded(run, [&] { roll_back(run); });
}

Report uninstall(const std::filesystem::path& root, const Options& options) {
  Run run(root, options, "uninstall");
  return guarded(run, [&] {
    remove_all(run);
    if (!run.dry_run && run.report.ok()) {
      try { nl::status::remove(run.disk, root); }
      catch (const fs::Error& error) { run.note(std::string("status cleanup: ") + error.what()); }
    }
  });
}

Report recover(const std::filesystem::path& root, const Options& options) {
  Run run(root, options, "recover");
  return guarded(run, [&] { recover_only(run); });
}

Status status(const std::filesystem::path& root, bool hashes) {
  Status s;
  s.journal = journal::load(root);
  if (!s.journal || !s.journal->current) return s;
  for (const File& f : s.journal->current->files) {
    const Path file = fs::join(root, f.path);
    if (!fs::stat(file).exists) {
      s.drift.push_back({f.path, "missing"});
    } else if (!unchanged(file, f, hashes)) {
      s.drift.push_back({f.path, "changed"});
    }
  }
  return s;
}

}  // namespace nl::deploy
