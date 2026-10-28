#include "gma_fixture.h"
#include "nl/config.h"
#include "nl/core.h"
#include "nl/deploy.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/manifest.h"
#include "nl/planner.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <string>
#include <system_error>
#include <vector>

namespace sfs = std::filesystem;

namespace {

using Files = std::map<std::string, std::string>;  // package path -> bytes

struct Pkg {
  std::string id;
  std::string version;
  std::string kinds;  // JSON array
  std::string extra;  // further manifest members, each starting with ", "
  Files files;        // native/... -> bytes
};

std::string manifest_of(const Pkg& p) {
  std::string listed;
  for (const auto& file : p.files) {
    listed += (listed.empty() ? "" : ", ") + std::string("\"") + file.first + "\": {\"size\": " +
              std::to_string(file.second.size()) + ", \"sha256\": \"" + nl::sha256::of(file.second) + "\"}";
  }
  return "{\"schema\": 1, \"id\": \"" + p.id + "\", \"version\": \"" + p.version + "\", \"kinds\": " + p.kinds +
         ", \"files\": {" + listed + "}" + p.extra + "}";
}

void write_file(const sfs::path& file, const std::string& bytes) {
  sfs::create_directories(file.parent_path());
  std::ofstream(file, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

void write_gma(const sfs::path& file, const Pkg& p) {
  nl::test::FixtureArchive archive;
  archive.files.push_back({"native/manifest.json", manifest_of(p)});
  for (const auto& entry : p.files) archive.files.push_back({entry.first, entry.second});
  write_file(file, nl::test::build_gma(archive));
}

const std::string kMod = "native/root/rtx-remix/mods/test_mod/";

Pkg runtime(const std::string& version, const std::string& dll) {
  return {"test-runtime", version, "[\"remix-runtime\"]",
          ", \"remix\": {\"entry\": \"runtime/d3d9.dll\", \"rtx_conf_layers\": [\"config/rtx.conf\"]}",
          {{"native/payload/runtime/d3d9.dll", dll}, {"native/payload/config/rtx.conf", "rtx.version = " + version + "\n"}}};
}

Pkg mods(const std::string& version, const Files& files) {
  return {"test-mods", version, "[\"root-files\"]", ", \"root_files\": [{\"path\": \"rtx-remix/mods/test_mod\"}]", files};
}

std::string json_list(const std::vector<std::string>& items) {
  std::string out;
  for (const auto& item : items) out += (out.empty() ? "\"" : ", \"") + item + "\"";
  return "[" + out + "]";
}

// A fake game folder in the test's scratch folder.
struct Game {
  explicit Game(const char* name) : dir(nl::test::scratch_dir(name)), root(dir / "game") {
    write_file(root / "bin" / "win64" / "gmod.exe", "");
    sfs::create_directories(root / "garrysmod" / "cfg");
    sfs::create_directories(root / "native-loader");
  }
  ~Game() {
    std::error_code ec;
    sfs::remove_all(dir, ec);
  }
  Game(const Game&) = delete;
  Game& operator=(const Game&) = delete;

  void allow(const std::vector<std::string>& local, const std::vector<std::string>& dev = {}) const {
    write_file(root / "native-loader" / "config.json",
               "{\"schema\": 1, \"allow\": {\"local\": " + json_list(local) + ", \"dev_folders\": " + json_list(dev) + "}}");
  }
  void add(const std::string& archive, const Pkg& p) const { write_gma(root / "garrysmod" / "addons" / archive, p); }
  std::string read(const std::string& relative) const { return nl::fs::read_file(nl::fs::join(root, relative), 1 << 20); }
  bool has(const std::string& relative) const { return nl::fs::stat(nl::fs::join(root, relative)).exists; }
  nl::journal::Journal journal() const {
    const auto j = nl::journal::load(root);
    REQUIRE(j.has_value());
    return *j;
  }

  sfs::path dir;
  sfs::path root;
};

nl::deploy::Options with(nl::fs::FileSystem* disk, bool dry_run = false) {
  nl::deploy::Options options;
  options.filesystem = disk;
  options.dry_run = dry_run;
  // No game runs from a scratch folder; skipping the process scan keeps the loops below fast. The
  // refusal itself is tested end to end (loader/cli/tests/e2e_deploy.py).
  options.allow_running_game = true;
  return options;
}

nl::deploy::Report apply_at(const sfs::path& root, nl::fs::FileSystem* disk = nullptr, bool dry_run = false) {
  const nl::config::Config config = nl::config::load(root);
  const auto env = nl::discovery::environment_for(root, root / "no-steam");
  return nl::deploy::apply(root, nl::planner::consider(nl::discovery::discover(config, env)), config,
                           *nl::manifest::parse_version(nl::version()), with(disk, dry_run));
}

bool has_change(const nl::deploy::Report& r, const std::string& action, const std::string& path) {
  return std::any_of(r.changes.begin(), r.changes.end(),
                     [&](const nl::deploy::Change& c) { return c.action == action && c.path == path; });
}

bool mentions(const std::vector<std::string>& texts, const std::string& part) {
  return std::any_of(texts.begin(), texts.end(), [&](const std::string& t) { return t.find(part) != std::string::npos; });
}

bool skipped_because(const nl::deploy::Report& r, const std::string& part) {
  return std::any_of(r.skipped.begin(), r.skipped.end(),
                     [&](const nl::deploy::Skipped& s) { return s.reason.find(part) != std::string::npos; });
}

using State = std::map<std::string, std::string>;

// Every file (path -> SHA-256) and folder below a game folder, except the journal and the lock.
State snapshot(const sfs::path& root) {
  State out;
  for (const auto& entry : sfs::recursive_directory_iterator(root)) {
    const std::string relative = sfs::relative(entry.path(), root).generic_string();
    if (relative == "native-loader/state.json" || relative == "native-loader/lock") continue;
    out[relative] = entry.is_directory() ? std::string("<folder>") : nl::fs::hash_file(entry.path()).sha256;
  }
  return out;
}

void copy_tree(const sfs::path& from, const sfs::path& to) {
  sfs::remove_all(to);
  sfs::copy(from, to, sfs::copy_options::recursive);
}

// The real file-system calls without the flushes and write-through renames that make fs::win32()
// durable against power loss: these loops test the deployer's logic, run thousands of deployments,
// and would otherwise spend most of their time waiting for the disk. test_fs.cpp covers fs::win32(),
// and the kill CTest (deploy_faults.py) deploys through it.
class FastDisk final : public nl::fs::FileSystem {
 public:
  void create_directory(const nl::fs::Path& dir) override { check(CreateDirectoryW(nl::fs::long_path(dir).c_str(), nullptr), dir); }
  void remove_directory(const nl::fs::Path& dir) override { check(RemoveDirectoryW(nl::fs::long_path(dir).c_str()), dir); }
  void remove_file(const nl::fs::Path& file) override { check(DeleteFileW(nl::fs::long_path(file).c_str()), file); }
  void move(const nl::fs::Path& from, const nl::fs::Path& to, bool replace) override {
    check(MoveFileExW(nl::fs::long_path(from).c_str(), nl::fs::long_path(to).c_str(), replace ? MOVEFILE_REPLACE_EXISTING : 0), from);
  }
  std::unique_ptr<nl::fs::Writer> create_file(const nl::fs::Path& file) override {
    const HANDLE handle =
        CreateFileW(nl::fs::long_path(file).c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    check(handle != INVALID_HANDLE_VALUE, file);
    return std::make_unique<Writer>(handle);
  }

 private:
  class Writer final : public nl::fs::Writer {
   public:
    explicit Writer(HANDLE handle) : handle_(handle) {}
    ~Writer() override { close(); }
    Writer(const Writer&) = delete;
    Writer& operator=(const Writer&) = delete;
    void write(const void* data, std::size_t size) override {
      DWORD written = 0;
      if (!WriteFile(handle_, data, static_cast<DWORD>(size), &written, nullptr) || written != size) {
        throw nl::fs::Error("write failed", GetLastError());
      }
    }
    void close() override {
      if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
      handle_ = INVALID_HANDLE_VALUE;
    }

   private:
    HANDLE handle_;
  };

  static void check(BOOL ok, const nl::fs::Path& path) {
    if (!ok) throw nl::fs::Error("file-system call failed for " + nl::fs::utf8(path), GetLastError());
  }
};

FastDisk g_fast;

using Command = std::function<nl::deploy::Report(const sfs::path& root, nl::fs::FileSystem* disk)>;

const Command kApply = [](const sfs::path& root, nl::fs::FileSystem* disk) { return apply_at(root, disk); };
const Command kRollback = [](const sfs::path& root, nl::fs::FileSystem* disk) { return nl::deploy::rollback(root, with(disk)); };
const Command kUninstall = [](const sfs::path& root, nl::fs::FileSystem* disk) { return nl::deploy::uninstall(root, with(disk)); };
const Command kRecover = [](const sfs::path& root, nl::fs::FileSystem* disk) { return nl::deploy::recover(root, with(disk)); };

// Thrown by the fault hook. Not a std::exception, so nothing in the deployer catches it: it unwinds
// the way a crash ends the process (handles close, nothing else of the deployer runs).
struct Killed {};

// Runs `command`, stopping it just before change `n`. False if it finished before change n.
bool interrupted(const sfs::path& root, const Command& command, std::uint64_t n) {
  nl::fs::Counting disk(g_fast, [n](std::uint64_t change, std::string_view) {
    if (change == n) throw Killed{};
  });
  try {
    command(root, &disk);
  } catch (const Killed&) {
    return true;
  }
  return false;
}

// Interrupts `command` before each of its changes in turn, every time on a fresh copy of `before`,
// runs recovery, and checks that the folder is then exactly as before the command or exactly as
// after it, with nothing pending. Up to `nested` of those recoveries, taken where a transaction is
// pending, are themselves interrupted before each of their changes. Returns how many changes the
// command makes.
std::uint64_t interrupt_everywhere(const sfs::path& scratch, const sfs::path& before, const Command& command, int nested) {
  sfs::create_directories(scratch);
  const sfs::path done = scratch / "after";
  copy_tree(before, done);
  REQUIRE(command(done, nullptr).ok());
  const State old_state = snapshot(before);
  const State new_state = snapshot(done);
  CHECK(old_state != new_state);
  const auto settled = [&](const sfs::path& work, std::uint64_t n, std::uint64_t m) {
    const auto report = kRecover(work, &g_fast);
    const State state = snapshot(work);
    const auto j = nl::journal::load(work);
    const bool ok = report.ok() && (state == old_state || state == new_state) && (!j || (!j->pending && j->retired.empty())) &&
                    !nl::fs::stat(work / "native-loader" / "staging").exists;
    if (!ok) std::printf("  interrupted before change %llu (recovery before its change %llu): %s\n", n, m, report.error.c_str());
    CHECK(ok);
  };
  std::uint64_t n = 1;
  for (;; ++n) {
    const sfs::path work = scratch / "work";
    copy_tree(before, work);
    if (!interrupted(work, command, n)) break;
    const auto j = nl::journal::load(work);
    if (nested > 0 && j && j->pending && n % 4 == 0) {
      --nested;
      for (std::uint64_t m = 1;; ++m) {
        const sfs::path again = scratch / "again";
        copy_tree(work, again);
        if (!interrupted(again, kRecover, m)) break;
        settled(again, n, m);
      }
    }
    settled(work, n, 0);
  }
  return n - 1;
}

// Makes each change fail in turn (on a fresh copy of `before`). After recovery the folder must be as
// before (the failed deployment was undone) or, when the failure hit the clean-up after the commit,
// as after.
std::uint64_t fail_everywhere(const sfs::path& scratch, const sfs::path& before, const Command& command) {
  sfs::create_directories(scratch);
  const sfs::path done = scratch / "after";
  copy_tree(before, done);
  REQUIRE(command(done, nullptr).ok());
  const State old_state = snapshot(before);
  const State new_state = snapshot(done);
  std::uint64_t n = 1;
  for (;; ++n) {
    const sfs::path work = scratch / "work";
    copy_tree(before, work);
    nl::fs::Counting disk(g_fast, [n](std::uint64_t change, std::string_view) {
      if (change == n) throw nl::fs::Error("injected failure", 0);
    });
    const auto report = command(work, &disk);
    if (disk.operations() < n) break;  // finished before change n
    CHECK(kRecover(work, &g_fast).ok());
    const State state = snapshot(work);
    const bool ok = report.ok() ? state == new_state : state == old_state;
    if (!ok) std::printf("  failure at change %llu: %s %s\n", n, report.outcome.c_str(), report.error.c_str());
    CHECK(ok);
  }
  return n - 1;
}

// Two versions of a runtime and a root-files package; v2 replaces, adds and removes root files.
void version_1(const Game& g) {
  g.add("runtime.gma", runtime("1.0.0", "MZ-one"));
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}, {kMod + "a.dds", "A"}}));
  g.allow({"garrysmod/addons/runtime.gma", "garrysmod/addons/mods.gma"});
}

void version_2(const Game& g) {
  g.add("runtime.gma", runtime("1.1.0", "MZ-two"));
  g.add("mods.gma", mods("1.1.0", {{kMod + "mod.usda", "#usda v2\n"}, {kMod + "textures/b.dds", "B"}}));
}

const std::string kModDir = "rtx-remix/mods/test_mod/";

}  // namespace

TEST_CASE("deploy: the first apply places payload and root files; the next one writes nothing") {
  Game g("deploy_first");
  version_1(g);
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(r.generation == 1);
  CHECK(r.packages.size() == 2);
  CHECK(has_change(r, "add", kModDir + "mod.usda"));
  CHECK(has_change(r, "payload", "native-loader/packages/test-runtime/1.0.0_1"));
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");
  CHECK(g.read("native-loader/packages/test-runtime/1.0.0_1/runtime/d3d9.dll") == "MZ-one");
  CHECK(!g.has("native-loader/staging"));
  const auto j = g.journal();
  REQUIRE(j.current.has_value());
  CHECK(j.current->files.size() == 4);
  CHECK(j.current->packages[0].remix.has_value());
  CHECK(!j.previous && !j.pending && j.retired.empty());
  CHECK(j.next == 2);

  nl::fs::Counting counting(nl::fs::win32());
  const auto again = apply_at(g.root, &counting);
  CHECK(again.outcome == "unchanged");
  CHECK(again.operations == 0);
  CHECK(counting.operations() == 0);
  const auto status = nl::deploy::status(g.root, true);
  CHECK(status.drift.empty());
}

TEST_CASE("deploy: an upgrade replaces, adds and removes; rollback restores it exactly and holds it") {
  Game g("deploy_upgrade");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  const auto up = apply_at(g.root);
  CHECK(up.outcome == "deployed");
  CHECK(up.generation == 2);
  CHECK(has_change(up, "replace", kModDir + "mod.usda"));
  CHECK(has_change(up, "add", kModDir + "textures/b.dds"));
  CHECK(has_change(up, "remove", kModDir + "a.dds"));
  CHECK(g.read(kModDir + "mod.usda") == "#usda v2\n");
  CHECK(!g.has(kModDir + "a.dds"));
  const auto j2 = g.journal();
  REQUIRE(j2.previous.has_value());
  CHECK(j2.previous->number == 1);
  CHECK(j2.previous_backup == "native-loader/backup/2");
  CHECK(g.read("native-loader/backup/2/" + kModDir + "mod.usda") == "#usda v1\n");
  CHECK(g.has("native-loader/packages/test-runtime/1.0.0_1/runtime/d3d9.dll"));  // kept for rollback
  CHECK(g.read("native-loader/packages/test-runtime/1.1.0_2/runtime/d3d9.dll") == "MZ-two");

  const auto back = nl::deploy::rollback(g.root);
  CHECK(back.outcome == "rolled-back");
  CHECK(back.generation == 3);
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");
  CHECK(g.read(kModDir + "a.dds") == "A");
  CHECK(!g.has(kModDir + "textures/b.dds"));
  const auto j3 = g.journal();
  CHECK(j3.current->packages[0].payload == "native-loader/packages/test-runtime/1.0.0_1");
  CHECK(j3.hold && j3.hold->size() == 2);

  nl::fs::Counting counting(nl::fs::win32());
  const auto held = apply_at(g.root, &counting);  // the archives are still version 2
  CHECK(held.outcome == "held");
  CHECK(counting.operations() == 0);
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");

  const auto forth = nl::deploy::rollback(g.root);  // rolling back twice returns
  CHECK(forth.outcome == "rolled-back");
  CHECK(g.read(kModDir + "mod.usda") == "#usda v2\n");
  CHECK(g.read(kModDir + "textures/b.dds") == "B");
  CHECK(apply_at(g.root).outcome == "unchanged");

  // A third version retires the oldest generation: its payload folder and backups are deleted.
  g.add("mods.gma", mods("1.2.0", {{kMod + "mod.usda", "#usda v3\n"}}));
  const auto v3 = apply_at(g.root);
  CHECK(v3.outcome == "deployed");
  CHECK(!g.has("native-loader/packages/test-runtime/1.0.0_1"));
  CHECK(g.has("native-loader/packages/test-runtime/1.1.0_2/runtime/d3d9.dll"));
  CHECK(!g.has("native-loader/backup/2"));
  CHECK(!g.has("native-loader/backup/3"));
  CHECK(!g.has("native-loader/backup/4"));
  CHECK(g.read("native-loader/backup/5/" + kModDir + "mod.usda") == "#usda v2\n");
  CHECK(!g.has(kModDir + "textures"));
  const auto j5 = g.journal();
  CHECK(j5.retired.empty());
  CHECK(nl::deploy::status(g.root, true).drift.empty());
}

TEST_CASE("deploy: removing every package keeps a rollback target, and that rollback is held too") {
  Game g("deploy_empty");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  g.allow({});  // nothing allowlisted any more
  const auto emptied = apply_at(g.root);
  CHECK(emptied.outcome == "deployed");
  CHECK(emptied.packages.empty());
  CHECK(!g.has(kModDir + "mod.usda"));
  const auto back = nl::deploy::rollback(g.root);
  CHECK(back.outcome == "rolled-back");
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");
  const auto j = g.journal();
  CHECK(j.hold && j.hold->empty());  // held: the empty set it rolled back from
  CHECK(apply_at(g.root).outcome == "held");
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");
}

TEST_CASE("deploy: a foreign file at a target blocks its package; an identical one is adopted and kept") {
  Game g("deploy_foreign");
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "someone else's");
  write_file(g.root / "garrysmod" / "lua" / "bin" / "gmcl_test_win64.dll", "MZ-module");
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}}));
  g.add("lua.gma", {"test-lua", "1.0.0", "[\"lua-binary-module\"]",
                    ", \"root_files\": [{\"path\": \"garrysmod/lua/bin/gmcl_test_win64.dll\"}]",
                    {{"native/root/garrysmod/lua/bin/gmcl_test_win64.dll", "MZ-module"}}});
  g.allow({"garrysmod/addons/mods.gma", "garrysmod/addons/lua.gma"});
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(r.packages.size() == 1);
  CHECK(skipped_because(r, "not placed by the loader"));
  CHECK(has_change(r, "adopt", "garrysmod/lua/bin/gmcl_test_win64.dll"));
  CHECK(g.read(kModDir + "mod.usda") == "someone else's");
  const auto j = g.journal();
  REQUIRE(j.current.has_value() && j.current->files.size() == 1);
  CHECK(j.current->files[0].adopted);

  const auto removed = nl::deploy::uninstall(g.root);
  CHECK(removed.outcome == "removed");
  CHECK(g.read("garrysmod/lua/bin/gmcl_test_win64.dll") == "MZ-module");  // was there before: stays
  CHECK(g.read(kModDir + "mod.usda") == "someone else's");
  CHECK(!g.has("native-loader/state.json"));
  CHECK(!g.has("native-loader/lock"));
}

TEST_CASE("deploy: files the user changed are never replaced or removed") {
  Game g("deploy_edited");
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}, {kMod + "a.dds", "A"}}));
  g.allow({"garrysmod/addons/mods.gma"});
  REQUIRE(apply_at(g.root).ok());
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "#usda mine\n");
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "a.dds", "mine too");
  const auto drift = nl::deploy::status(g.root, false);
  CHECK(drift.drift.size() == 2);

  g.add("mods.gma", mods("1.1.0", {{kMod + "mod.usda", "#usda v2\n"}}));
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(g.read(kModDir + "mod.usda") == "#usda mine\n");
  CHECK(g.read(kModDir + "a.dds") == "mine too");
  CHECK(mentions(r.notes, "not updated to the package's new version"));
  CHECK(mentions(r.notes, "left in place"));

  const auto removed = nl::deploy::uninstall(g.root);
  CHECK(removed.outcome == "removed");
  CHECK(g.read(kModDir + "mod.usda") == "#usda mine\n");
  CHECK(g.read(kModDir + "a.dds") == "mine too");
  CHECK(mentions(removed.notes, "not deleted"));
}

TEST_CASE("deploy: create-only files are created once and never replaced") {
  Game g("deploy_create_only");
  write_file(g.root / "garrysmod" / "cfg" / "user.cfg", "mine");
  const auto cfg = [](const std::string& version, const std::string& text) {
    return Pkg{"test-cfg", version, "[\"root-files\"]",
               ", \"root_files\": [{\"path\": \"garrysmod/cfg/test.cfg\", \"policy\": \"create-only\"}, "
               "{\"path\": \"garrysmod/cfg/user.cfg\", \"policy\": \"create-only\"}]",
               {{"native/root/garrysmod/cfg/test.cfg", text}, {"native/root/garrysmod/cfg/user.cfg", "default"}}};
  };
  g.add("cfg.gma", cfg("1.0.0", "v1"));
  g.allow({"garrysmod/addons/cfg.gma"});
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(g.read("garrysmod/cfg/test.cfg") == "v1");
  CHECK(g.read("garrysmod/cfg/user.cfg") == "mine");
  CHECK(mentions(r.notes, "create-only"));

  g.add("cfg.gma", cfg("1.1.0", "v2"));
  CHECK(apply_at(g.root).outcome == "deployed");
  CHECK(g.read("garrysmod/cfg/test.cfg") == "v1");  // never replaced, not even by a new version
  sfs::remove(g.root / "garrysmod" / "cfg" / "test.cfg");
  CHECK(apply_at(g.root).outcome == "deployed");
  CHECK(g.read("garrysmod/cfg/test.cfg") == "v2");  // created again once it is gone
}

TEST_CASE("deploy: a package that fails its checks is not deployed; a lower-precedence copy takes over") {
  Game g("deploy_fallback");
  const Pkg good = runtime("1.0.0", "MZ-one");
  g.add("runtime.gma", good);
  // A development copy whose d3d9.dll has the listed size but not the listed SHA-256.
  const sfs::path dev = g.dir / "dev" / "runtime";
  write_file(dev / "native" / "manifest.json", manifest_of(good));
  write_file(dev / "native" / "payload" / "runtime" / "d3d9.dll", "MZ-bad");
  write_file(dev / "native" / "payload" / "config" / "rtx.conf", good.files.at("native/payload/config/rtx.conf"));
  g.allow({"garrysmod/addons/runtime.gma"}, {dev.generic_string()});
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(skipped_because(r, "does not match its SHA-256"));
  const auto j = g.journal();
  REQUIRE(j.current.has_value() && j.current->packages.size() == 1);
  CHECK(j.current->packages[0].source == "local");
  CHECK(g.read(j.current->packages[0].payload + "/runtime/d3d9.dll") == "MZ-one");
  CHECK(!g.has("native-loader/staging"));
}

TEST_CASE("deploy: junctions under the game folder are never written through") {
  Game g("deploy_junction");
  sfs::create_directories(g.dir / "elsewhere");
  sfs::create_directories(g.root / "rtx-remix");
  const std::string command = "cmd /c mklink /J \"" + (g.root / "rtx-remix" / "mods").string() + "\" \"" +
                              (g.dir / "elsewhere").string() + "\" >nul";
  if (std::system(command.c_str()) != 0) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}}));
  g.allow({"garrysmod/addons/mods.gma"});
  const auto r = apply_at(g.root);
  CHECK(skipped_because(r, "link or junction"));
  CHECK(sfs::is_empty(g.dir / "elsewhere"));
  sfs::remove(g.root / "rtx-remix" / "mods");  // the junction, not its target
}

TEST_CASE("deploy: a dry run reports the changes and makes none") {
  Game g("deploy_dry_run");
  version_1(g);
  const State before = snapshot(g.root);
  const auto r = apply_at(g.root, nullptr, true);
  CHECK(r.outcome == "planned");
  CHECK(r.operations == 0);
  CHECK(has_change(r, "add", kModDir + "mod.usda"));
  CHECK(snapshot(g.root) == before);
  CHECK(!g.has("native-loader/state.json"));
  CHECK(!g.has("native-loader/lock"));
}

TEST_CASE("deploy: refused while another deployment holds the lock, and with an invalid journal") {
  Game g("deploy_refused");
  version_1(g);
  {
    const HANDLE lock = CreateFileW((g.root / "native-loader" / "lock").c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                                    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    REQUIRE(lock != INVALID_HANDLE_VALUE);
    const auto r = apply_at(g.root);
    CloseHandle(lock);
    CHECK(r.outcome == "refused");
    CHECK(r.error.find("another deployment") != std::string::npos);
  }
  write_file(g.root / "native-loader" / "state.json", "{\"schema\": 1}");
  CHECK_THROWS_AS(apply_at(g.root), nl::journal::Error);
  CHECK(!g.has(kModDir + "mod.usda"));
  CHECK(nl::deploy::rollback(sfs::path(g.dir / "nowhere")).outcome == "refused");
}

TEST_CASE("deploy: uninstall returns the folder to how it was before the first deployment") {
  Game g("deploy_uninstall");
  version_1(g);
  const State before = snapshot(g.root);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  REQUIRE(apply_at(g.root).ok());
  version_1(g);  // put the archives back as they were
  const auto r = nl::deploy::uninstall(g.root);
  CHECK(r.outcome == "removed");
  CHECK(snapshot(g.root) == before);
  CHECK(!g.has("native-loader/state.json"));
  CHECK(!g.has("native-loader/lock"));
  CHECK(nl::deploy::uninstall(g.root).outcome == "unchanged");
}

TEST_CASE("deploy faults: an upgrade interrupted before any change ends in exactly the old or the new state") {
  Game g("deploy_kill_upgrade");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  const sfs::path before = g.dir / "before";
  copy_tree(g.root, before);
  CHECK(interrupt_everywhere(g.dir / "kill", before, kApply, 2) > 20);
}

TEST_CASE("deploy faults: first deployments, rollbacks and uninstalls interrupted anywhere end in the old or the new state") {
  Game g("deploy_kill_other");
  version_1(g);
  const sfs::path fresh = g.dir / "fresh";
  copy_tree(g.root, fresh);
  CHECK(interrupt_everywhere(g.dir / "first", fresh, kApply, 0) > 10);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  REQUIRE(apply_at(g.root).ok());
  const sfs::path upgraded = g.dir / "upgraded";
  copy_tree(g.root, upgraded);
  CHECK(interrupt_everywhere(g.dir / "rollback", upgraded, kRollback, 1) > 5);
  CHECK(interrupt_everywhere(g.dir / "uninstall", upgraded, kUninstall, 0) > 5);
}

TEST_CASE("deploy faults: a failure at any change leaves the old state (or, after the commit, the new one)") {
  Game g("deploy_fail");
  version_1(g);
  const sfs::path fresh = g.dir / "fresh";
  copy_tree(g.root, fresh);
  CHECK(fail_everywhere(g.dir / "first", fresh, kApply) > 10);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  const sfs::path before = g.dir / "before";
  copy_tree(g.root, before);
  CHECK(fail_everywhere(g.dir / "upgrade", before, kApply) > 20);
  REQUIRE(apply_at(g.root).ok());
  const sfs::path upgraded = g.dir / "upgraded";
  copy_tree(g.root, upgraded);
  CHECK(fail_everywhere(g.dir / "rollback", upgraded, kRollback) > 5);
  CHECK(fail_everywhere(g.dir / "uninstall", upgraded, kUninstall) > 5);
}
