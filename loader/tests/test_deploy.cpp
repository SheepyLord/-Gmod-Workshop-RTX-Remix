#include "gma_fixture.h"
#include "legacy_fixture.h"
#include "nl/config.h"
#include "nl/core.h"
#include "nl/deploy.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/json.h"
#include "nl/legacy_migrate.h"
#include "nl/manifest.h"
#include "nl/planner.h"
#include "nl/sha256.h"
#include "nl/startup.h"
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

// Workshop items of a fake game: their folders, and Steam's record of them (appworkshop_4000.acf).
struct Workshop {
  explicit Workshop(const Game& g) : content(g.dir / "content"), acf(g.dir / "appworkshop_4000.acf") {}

  // Steam lists these items as subscribed and installed, and has forgotten every other one.
  void record(const std::vector<std::string>& ids) const {
    std::string items;
    for (const std::string& id : ids) items += "\"" + id + "\" { \"size\" \"1\" } ";
    write_file(acf, "\"AppWorkshop\" { \"WorkshopItemsInstalled\" { " + items + "} \"WorkshopItemDetails\" { " + items + "} }");
  }
  nl::deploy::Report apply(const sfs::path& root, nl::fs::FileSystem* disk = nullptr) const {
    const nl::config::Config config = nl::config::load(root);
    nl::discovery::Environment env;
    env.game_root = root;
    env.workshop_content = content;
    env.appworkshop_acf = acf;
    return nl::deploy::apply(root, nl::planner::consider(nl::discovery::discover(config, env)), config,
                             *nl::manifest::parse_version(nl::version()), with(disk));
  }

  sfs::path content;
  sfs::path acf;
};

// Two versions deployed from two Workshop items: a runtime (123, payload files) and a root-files
// package (124), so the journal keeps a rollback target with backups and an older payload folder.
void workshop_versions(const Game& g, const Workshop& w) {
  write_file(g.root / "native-loader" / "config.json", R"({"schema": 1, "allow": {"workshop": ["123", "124"]}})");
  w.record({"123", "124"});
  write_gma(w.content / "123" / "runtime.gma", runtime("1.0.0", "MZ-one"));
  write_gma(w.content / "124" / "mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}, {kMod + "a.dds", "A"}}));
  REQUIRE(w.apply(g.root).outcome == "deployed");
  write_gma(w.content / "123" / "runtime.gma", runtime("1.1.0", "MZ-two"));
  write_gma(w.content / "124" / "mods.gma", mods("1.1.0", {{kMod + "mod.usda", "#usda v2\n"}, {kMod + "textures/b.dds", "B"}}));
  REQUIRE(w.apply(g.root).outcome == "deployed");
  REQUIRE(nl::fs::stat(nl::fs::join(g.root, "native-loader/packages/test-runtime/1.0.0_1/runtime/d3d9.dll")).exists);
  REQUIRE(nl::fs::stat(nl::fs::join(g.root, "native-loader/backup/2/" + kModDir + "mod.usda")).exists);
}

// Steam's state after the user unsubscribed: the item's folder deleted, the item gone from its record.
void unsubscribe(const Workshop& w, const std::string& id, const std::vector<std::string>& still) {
  sfs::remove_all(w.content / id);
  w.record(still);
}

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

TEST_CASE("deploy legacy: migration archives obsolete addon files and uninstall never reactivates old RTX") {
  Game g("deploy_legacy");
  const auto old_runtime = nl::test::legacy_fixture::fixture();
  write_file(g.root / "bin/win64/d3d9.dll", old_runtime);
  write_file(g.root / "rtx.conf", "old RTX config");
  write_file(g.root / "user.conf", "keep user settings");
  const std::string addon = "garrysmod/addons/remixbinary/lua/";
  write_file(nl::fs::join(g.root, addon + "old.lua"), "obsolete Lua");
  write_file(nl::fs::join(g.root, addon + "new.lua"), "old implementation");
  auto p = runtime("1.0.0", "new runtime");
  p.kinds = "[\"remix-runtime\", \"lua-addon\"]";
  p.extra += ", \"root_files\": [{\"path\": \"garrysmod/addons/remixbinary\"}]";
  p.files["native/root/" + addon + "new.lua"] = "new implementation";
  g.add("runtime.gma", p);
  g.allow({"garrysmod/addons/runtime.gma"});
  const State before = snapshot(g.root);
  const auto dry = apply_at(g.root, nullptr, true);
  if (dry.outcome != "planned") {
    std::printf("legacy dry run: %s %s\n", dry.outcome.c_str(), dry.error.c_str());
    for (const auto& s : dry.skipped) std::printf("skipped: %s\n", s.reason.c_str());
  }
  REQUIRE(dry.outcome == "planned");
  CHECK(dry.operations == 0);
  CHECK(snapshot(g.root) == before);
  CHECK(has_change(dry, "archive-legacy", "bin/win64/d3d9.dll"));
  const auto deployed = apply_at(g.root);
  REQUIRE(deployed.outcome == "deployed");
  CHECK(!g.has("bin/win64/d3d9.dll"));
  CHECK(!g.has(addon + "old.lua"));
  CHECK(g.read(addon + "new.lua") == "new implementation");
  const std::string backup = "native-loader/backup/legacy/1/";
  CHECK(g.read(backup + "bin/win64/d3d9.dll") == old_runtime);
  CHECK(g.read(backup + addon + "old.lua") == "obsolete Lua");
  CHECK(g.journal().originals.empty());
  CHECK(apply_at(g.root).operations == 0);
  REQUIRE(nl::deploy::uninstall(g.root, with(nullptr)).ok());
  CHECK(!g.has("bin/win64/d3d9.dll"));
  CHECK(!g.has(addon + "new.lua"));
  CHECK(g.read(backup + "bin/win64/d3d9.dll") == old_runtime);
  CHECK(g.read("user.conf") == "keep user settings");
}

TEST_CASE("deploy legacy: failed shipment integrity and disabled RTX never archive the old installation") {
  Game g("deploy_legacy_invalid");
  const auto old_runtime = nl::test::legacy_fixture::fixture();
  write_file(g.root / "bin/win64/d3d9.dll", old_runtime);
  version_1(g);
  write_file(g.root / "native-loader/config.json",
             R"({"schema":1,"allow":{"local":["garrysmod/addons/runtime.gma"]},"remix":{"enabled":false}})");
  CHECK(apply_at(g.root).ok());
  CHECK(g.read("bin/win64/d3d9.dll") == old_runtime);
  REQUIRE(nl::deploy::uninstall(g.root, with(nullptr)).ok());
  g.allow({"garrysmod/addons/runtime.gma"});
  auto bytes = g.read("garrysmod/addons/runtime.gma");
  const auto offset = bytes.find("MZ-one");
  REQUIRE(offset != std::string::npos);
  bytes.at(offset) = 'X';
  write_file(g.root / "garrysmod/addons/runtime.gma", bytes);
  CHECK(apply_at(g.root).ok());  // package is skipped; the legacy installation stays untouched
  CHECK(g.read("bin/win64/d3d9.dll") == old_runtime);
  CHECK(!g.has("native-loader/backup/legacy"));
}

TEST_CASE("deploy legacy: enabling RTX after an off deployment archives old uninstall originals") {
  Game g("deploy_legacy_off_first");
  write_file(g.root / "bin/win64/d3d9.dll", nl::test::legacy_fixture::fixture());
  const std::string file = "garrysmod/addons/remixbinary/lua/old.lua";
  write_file(nl::fs::join(g.root, file), "old legacy implementation");
  auto p = runtime("1.0.0", "new runtime");
  p.kinds = "[\"remix-runtime\", \"lua-addon\"]";
  p.extra += ", \"root_files\": [{\"path\": \"garrysmod/addons/remixbinary\"}]";
  p.files["native/root/" + file] = "new implementation";
  g.add("runtime.gma", p);
  write_file(g.root / "native-loader/config.json",
             R"({"schema":1,"allow":{"local":["garrysmod/addons/runtime.gma"]},"remix":{"enabled":false}})");
  REQUIRE(apply_at(g.root).ok());
  REQUIRE(g.journal().originals.size() == 1);
  g.allow({"garrysmod/addons/runtime.gma"});
  REQUIRE(apply_at(g.root).outcome == "deployed");
  CHECK(g.journal().originals.empty());
  CHECK(g.read("native-loader/backup/legacy/2/native-loader/backup/originals/" + file) == "old legacy implementation");
  REQUIRE(nl::deploy::uninstall(g.root, with(nullptr)).ok());
  CHECK(!g.has(file));
  CHECK(!g.has("bin/win64/d3d9.dll"));
}

TEST_CASE("deploy faults: legacy migration recovers from interruption and failure before every filesystem operation") {
  Game g("deploy_legacy_faults");
  version_1(g);
  write_file(g.root / "bin/win64/d3d9.dll", nl::test::legacy_fixture::fixture());
  write_file(g.root / "rtx.conf", "old RTX config");
  write_file(g.root / "garrysmod/addons/remixbinary/lua/obsolete.lua", "obsolete");
  const Command command = [](const sfs::path& root, nl::fs::FileSystem* disk) { return apply_at(root, disk); };
  CHECK(interrupt_everywhere(g.dir / "interruptions", g.root, command, 1) > 25);
  CHECK(fail_everywhere(g.dir / "failures", g.root, command) > 25);
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

TEST_CASE("deploy: a package whose Workshop item was unsubscribed is deleted, with no rollback copy (ADR 0025)") {
  Game g("deploy_unsubscribed");
  const Workshop w(g);
  workshop_versions(g, w);

  // The runtime's item is unsubscribed: Steam deleted its folder and forgot it.
  unsubscribe(w, "123", {"124"});
  const auto partial = w.apply(g.root);
  CHECK(partial.outcome == "deployed");
  CHECK(mentions(partial.notes, "test-runtime 1.1.0: its Workshop item was unsubscribed"));
  CHECK(skipped_because(partial, "not subscribed"));
  CHECK(!g.has("native-loader/packages/test-runtime"));  // both versions
  CHECK(!g.has("native-loader/backup/2"));               // the older generation's copies went too
  CHECK(g.read(kModDir + "mod.usda") == "#usda v2\n");   // the other item's package is untouched
  auto j = g.journal();
  REQUIRE(j.previous.has_value());
  REQUIRE(j.previous->packages.size() == 1);
  CHECK(j.previous->packages[0].id == "test-mods");
  CHECK(std::none_of(j.previous->files.begin(), j.previous->files.end(),
                     [](const nl::journal::File& f) { return f.package == "test-runtime"; }));
  CHECK(j.retired.empty());

  // Then the other one: nothing is left, not even for a rollback.
  unsubscribe(w, "124", {});
  const auto all = w.apply(g.root);
  CHECK(all.outcome == "deployed");
  CHECK(all.packages.empty());
  CHECK(has_change(all, "remove", kModDir + "mod.usda"));
  CHECK(!g.has("rtx-remix"));
  CHECK(!g.has("native-loader/packages"));
  CHECK(!g.has("native-loader/backup"));
  j = g.journal();
  CHECK(!j.previous);
  CHECK(j.previous_backup.empty());
  CHECK(j.retired.empty());
  CHECK(j.dirs.empty());
  CHECK(nl::deploy::rollback(g.root, with(nullptr)).outcome == "refused");

  // Subscribed again: deployed afresh.
  w.record({"123"});
  write_gma(w.content / "123" / "runtime.gma", runtime("1.1.0", "MZ-two"));
  const auto again = w.apply(g.root);
  CHECK(again.outcome == "deployed");
  CHECK(g.read("native-loader/packages/test-runtime/1.1.0_5/runtime/d3d9.dll") == "MZ-two");
}

TEST_CASE("deploy: unsubscribing puts back at once what the package had taken over (ADR 0025, ADR 0035)") {
  Game g("deploy_unsubscribed_original");
  const Workshop w(g);
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "someone else's");
  write_file(g.root / "native-loader" / "config.json", R"({"schema": 1, "allow": {"workshop": ["124"]}})");
  w.record({"124"});
  write_gma(w.content / "124" / "mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}}));
  const auto first = w.apply(g.root);
  REQUIRE(first.outcome == "deployed");
  REQUIRE(has_change(first, "take-over", kModDir + "mod.usda"));

  unsubscribe(w, "124", {});  // no rollback copy is kept (ADR 0025), so no generation names the path
  const auto gone = w.apply(g.root);
  CHECK(gone.outcome == "deployed");
  CHECK(has_change(gone, "restore-original", kModDir + "mod.usda"));
  CHECK(g.read(kModDir + "mod.usda") == "someone else's");
  CHECK(g.journal().originals.empty());
  CHECK(!g.has("native-loader/backup"));
}

TEST_CASE("deploy: a foreign file at a target is kept and put back at uninstall; an identical one is adopted (ADR 0035)") {
  Game g("deploy_foreign");
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "someone else's");
  write_file(g.root / "garrysmod" / "lua" / "bin" / "gmcl_test_win64.dll", "MZ-module");
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}}));
  g.add("lua.gma", {"test-lua", "1.0.0", "[\"lua-binary-module\"]",
                    ", \"root_files\": [{\"path\": \"garrysmod/lua/bin/gmcl_test_win64.dll\"}]",
                    {{"native/root/garrysmod/lua/bin/gmcl_test_win64.dll", "MZ-module"}}});
  g.allow({"garrysmod/addons/mods.gma", "garrysmod/addons/lua.gma"});
  const State with_files = snapshot(g.root);
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(r.packages.size() == 2);
  CHECK(has_change(r, "take-over", kModDir + "mod.usda"));
  CHECK(has_change(r, "adopt", "garrysmod/lua/bin/gmcl_test_win64.dll"));
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");  // the package's copy is in place
  CHECK(g.read("native-loader/backup/originals/" + kModDir + "mod.usda") == "someone else's");
  CHECK(mentions(r.notes, "was there before the loader"));
  const auto j = g.journal();
  REQUIRE(j.originals.size() == 1);
  CHECK(j.originals[0].path == kModDir + "mod.usda");
  CHECK(j.originals[0].sha256 == nl::sha256::of("someone else's"));
  CHECK(apply_at(g.root).outcome == "unchanged");  // kept while the loader manages the path
  CHECK(g.journal().originals.size() == 1);

  const auto removed = nl::deploy::uninstall(g.root);
  CHECK(removed.outcome == "removed");
  CHECK(has_change(removed, "restore-original", kModDir + "mod.usda"));
  CHECK(g.read("garrysmod/lua/bin/gmcl_test_win64.dll") == "MZ-module");  // was there before: stays
  CHECK(g.read(kModDir + "mod.usda") == "someone else's");                // put back
  CHECK(!g.has("native-loader/state.json"));
  CHECK(!g.has("native-loader/lock"));
  CHECK(!g.has("native-loader/backup"));
  CHECK(snapshot(g.root) == with_files);  // as it was before the first deployment
}

TEST_CASE("deploy: a changed file of the loader's is put back at the next start; the change is kept (ADR 0035)") {
  Game g("deploy_edited");
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}, {kMod + "a.dds", "A"}}));
  g.allow({"garrysmod/addons/mods.gma"});
  REQUIRE(apply_at(g.root).ok());
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "#usda mine\n");
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "a.dds", "mine too");
  CHECK(nl::deploy::status(g.root, false).drift.size() == 2);

  // The same version: both are put back, the changed copies kept where the note says.
  const auto same = apply_at(g.root);
  CHECK(same.outcome == "deployed");
  CHECK(has_change(same, "put-back", kModDir + "mod.usda"));
  CHECK(has_change(same, "put-back", kModDir + "a.dds"));
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");
  CHECK(g.read(kModDir + "a.dds") == "A");
  const std::string edits = "native-loader/backup/edits/" + std::to_string(same.generation) + "/";
  CHECK(g.read(edits + kModDir + "mod.usda") == "#usda mine\n");
  CHECK(g.read(edits + kModDir + "a.dds") == "mine too");
  CHECK(mentions(same.notes, "the package's copy is back"));
  CHECK(nl::deploy::status(g.root, true).drift.empty());
  CHECK(g.journal().originals.empty());  // a changed copy is no original: it is not put back later

  // A new version over a changed file: the new version goes in, the change is kept too.
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "#usda mine again\n");
  g.add("mods.gma", mods("1.1.0", {{kMod + "mod.usda", "#usda v2\n"}}));
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(has_change(r, "put-back", kModDir + "mod.usda"));
  CHECK(has_change(r, "remove", kModDir + "a.dds"));
  CHECK(g.read(kModDir + "mod.usda") == "#usda v2\n");
  CHECK(g.read("native-loader/backup/edits/" + std::to_string(r.generation) + "/" + kModDir + "mod.usda") ==
        "#usda mine again\n");
  REQUIRE(nl::deploy::rollback(g.root).ok());  // the rollback target never claims the changed copy
  CHECK(g.read(kModDir + "a.dds") == "A");

  // Uninstall deletes the loader's files; the kept copies stay, they are the user's.
  const auto removed = nl::deploy::uninstall(g.root);
  CHECK(removed.outcome == "removed");
  CHECK(!g.has(kModDir + "mod.usda"));
  CHECK(g.read(edits + kModDir + "mod.usda") == "#usda mine\n");
  CHECK(mentions(removed.notes, "folder kept"));
}

TEST_CASE("deploy: create-only files are created once and never replaced") {
  Game g("deploy_create_only");
  write_file(g.root / "garrysmod" / "data" / "nl_seed" / "user.txt", "mine");
  const auto seed = [](const std::string& version, const std::string& text) {
    return Pkg{"test-seed", version, "[\"root-files\"]",
               ", \"root_files\": [{\"path\": \"garrysmod/data/nl_seed/test.txt\", \"policy\": \"create-only\"}, "
               "{\"path\": \"garrysmod/data/nl_seed/user.txt\", \"policy\": \"create-only\"}]",
               {{"native/root/garrysmod/data/nl_seed/test.txt", text}, {"native/root/garrysmod/data/nl_seed/user.txt", "default"}}};
  };
  g.add("seed.gma", seed("1.0.0", "v1"));
  g.allow({"garrysmod/addons/seed.gma"});
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(g.read("garrysmod/data/nl_seed/test.txt") == "v1");
  CHECK(g.read("garrysmod/data/nl_seed/user.txt") == "mine");
  CHECK(mentions(r.notes, "create-only"));

  g.add("seed.gma", seed("1.1.0", "v2"));
  CHECK(apply_at(g.root).outcome == "deployed");
  CHECK(g.read("garrysmod/data/nl_seed/test.txt") == "v1");  // never replaced, not even by a new version
  sfs::remove(g.root / "garrysmod" / "data" / "nl_seed" / "test.txt");
  CHECK(apply_at(g.root).outcome == "deployed");
  CHECK(g.read("garrysmod/data/nl_seed/test.txt") == "v2");  // created again once it is gone
}

TEST_CASE("deploy: a package cannot create a missing Steam file in garrysmod/cfg (R1-007)") {
  Game g("deploy_no_cfg_area");
  // config_default.cfg is a depot file; here it is missing, as after an interrupted Steam update.
  g.add("cfg.gma", Pkg{"test-cfg", "1.0.0", "[\"root-files\"]",
                       ", \"root_files\": [{\"path\": \"garrysmod/cfg/config_default.cfg\", \"policy\": \"create-only\"}]",
                       {{"native/root/garrysmod/cfg/config_default.cfg", "package bytes"}}});
  g.allow({"garrysmod/addons/cfg.gma"});
  const auto r = apply_at(g.root);
  CHECK(!sfs::exists(g.root / "garrysmod" / "cfg" / "config_default.cfg"));
  CHECK(r.changes.empty());
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

namespace {

const nl::journal::File* record_of(const nl::journal::Generation& g, const std::string& path) {
  for (const nl::journal::File& f : g.files) {
    if (f.path == path) return &f;
  }
  return nullptr;
}

const Pkg kLua = {"test-lua", "1.0.0", "[\"lua-binary-module\"]",
                  ", \"root_files\": [{\"path\": \"garrysmod/lua/bin/gmcl_test_win64.dll\"}]",
                  {{"native/root/garrysmod/lua/bin/gmcl_test_win64.dll", "MZ-module"}}};

// A runtime that also ships files into one of RTXLauncher's add-on folders, as the RTX package does.
Pkg rtx_package(const std::string& version, const Files& addon_files) {
  Pkg p = runtime(version, "new runtime " + version);
  p.kinds = "[\"remix-runtime\", \"lua-addon\"]";
  p.extra += ", \"root_files\": [{\"path\": \"garrysmod/addons/remixbinary\"}]";
  for (const auto& [path, bytes] : addon_files) p.files["native/root/" + path] = bytes;
  return p;
}

const char* const kRtxOff = R"({"schema":1,"allow":{"local":["garrysmod/addons/runtime.gma"]},"remix":{"enabled":false}})";

// Directory junctions need no special rights; mklink is the simplest way to make one.
bool junction(const sfs::path& link, const sfs::path& target) {
  const std::string command = "cmd /c mklink /J \"" + link.string() + "\" \"" + target.string() + "\" >nul";
  return std::system(command.c_str()) == 0;
}

// apply_at with a synthetic stock catalog and an explicit vanilla root (no Steam discovery).
nl::deploy::Report apply_legacy(const sfs::path& root, const nl::legacy::Catalog& catalog, const sfs::path& vanilla,
                                nl::fs::FileSystem* disk = nullptr, bool dry_run = false) {
  const nl::config::Config config = nl::config::load(root);
  const auto env = nl::discovery::environment_for(root, root / "no-steam");
  nl::deploy::Options options = with(disk, dry_run);
  options.legacy_catalog = &catalog;
  options.legacy_source = vanilla;
  return nl::deploy::apply(root, nl::planner::consider(nl::discovery::discover(config, env)), config,
                           *nl::manifest::parse_version(nl::version()), options);
}

const std::string kBackupPatches = "backup_patches_20261030_120000/";

// A former installation whose three replaced Steam files can be restored: the launcher's bytes in
// place, stock copies in its backup_patches folder, beside the file (.bak) and in `vanilla`.
void legacy_depot(const Game& g, const nl::test::legacy_fixture::Depot& depot, const sfs::path& vanilla) {
  write_file(g.root / "bin" / "win64" / "d3d9.dll", nl::test::legacy_fixture::fixture());
  write_file(g.root / "rtx.conf", "old RTX config");
  for (const auto& [path, bytes] : depot.anchors) write_file(nl::fs::join(g.root, path), bytes);
  for (const auto& [path, bytes] : depot.legacy) write_file(nl::fs::join(g.root, path), bytes);
  write_file(nl::fs::join(g.root, kBackupPatches + "bin/win64/engine.dll"), depot.stock.at("bin/win64/engine.dll"));
  write_file(nl::fs::join(g.root, "garrysmod/gamemodes/sandbox/logo.png.bak"), depot.stock.at("garrysmod/gamemodes/sandbox/logo.png"));
  write_file(nl::fs::join(vanilla, "garrysmod/html/loading.png"), depot.stock.at("garrysmod/html/loading.png"));
}

}  // namespace

TEST_CASE("deploy legacy: Steam's replaced files go back to verified stock bytes in the transaction") {
  Game g("deploy_legacy_stock");
  const auto depot = nl::test::legacy_fixture::depot();
  const sfs::path vanilla = g.dir / "vanilla";
  legacy_depot(g, depot, vanilla);
  version_1(g);
  const State before = snapshot(g.root);
  const auto dry = apply_legacy(g.root, depot.catalog, vanilla, nullptr, true);
  REQUIRE(dry.outcome == "planned");
  CHECK(snapshot(g.root) == before);
  for (const auto& [path, bytes] : depot.stock) CHECK(has_change(dry, "restore-stock", path));
  const auto r = apply_legacy(g.root, depot.catalog, vanilla);
  if (r.outcome != "deployed") std::printf("  stock: %s %s\n", r.outcome.c_str(), r.error.c_str());
  REQUIRE(r.outcome == "deployed");
  const std::string archive = "native-loader/backup/legacy/" + std::to_string(r.generation) + "/";
  for (const auto& [path, bytes] : depot.stock) {
    CHECK(has_change(r, "archive-legacy", path));
    CHECK(has_change(r, "restore-stock", path));
    CHECK(g.read(path) == bytes);
    CHECK(g.read(archive + path) == depot.legacy.at(path));
  }
  CHECK(!g.has("bin/win64/d3d9.dll"));
  CHECK(g.read(archive + "rtx.conf") == "old RTX config");
  CHECK(g.read(kBackupPatches + "bin/win64/engine.dll") == depot.stock.at("bin/win64/engine.dll"));  // recovery material stays
  const auto manifest = nl::json::parse(g.read(archive + "manifest.json"));
  std::size_t restored = 0;
  for (const auto& file : manifest.find("files")->as_array()) {
    if (const auto* sha = file.find("restored_stock_sha256")) {
      ++restored;
      CHECK(sha->as_string("sha") == nl::sha256::of(depot.stock.at(file.find("path")->as_string("path"))));
    }
  }
  CHECK(restored == depot.stock.size());
  for (const auto& [path, bytes] : depot.anchors) CHECK(g.read(path) == bytes);  // never written
  CHECK(apply_legacy(g.root, depot.catalog, vanilla).operations == 0);  // migrated once, and only once
  REQUIRE(nl::deploy::uninstall(g.root, with(nullptr)).ok());
  for (const auto& [path, bytes] : depot.stock) CHECK(g.read(path) == bytes);  // uninstall restores no legacy file
  CHECK(!g.has("bin/win64/d3d9.dll"));
}

TEST_CASE("deploy legacy: without a verified stock copy the package deploys and the old installation waits for one") {
  // RTXLauncher overwrote five Lua and image files without a backup: an in-place install has no
  // vanilla copy of them until Steam verifies the game (or nlctl gets --legacy-source).
  Game g("deploy_legacy_no_stock");
  const auto depot = nl::test::legacy_fixture::depot();
  const sfs::path vanilla = g.dir / "vanilla";
  legacy_depot(g, depot, vanilla);
  const std::string logo = "garrysmod/gamemodes/sandbox/logo.png";
  sfs::remove(nl::fs::join(g.root, logo + ".bak"));
  version_1(g);
  const auto r = apply_legacy(g.root, depot.catalog, vanilla);
  CHECK(r.outcome == "deployed");
  CHECK(mentions(r.notes, "verified vanilla copy of " + logo));
  CHECK(mentions(r.notes, "the next start tries again"));
  CHECK(r.changes.end() == std::find_if(r.changes.begin(), r.changes.end(),
                                        [](const nl::deploy::Change& c) { return c.action == "archive-legacy"; }));
  CHECK(g.read("bin/win64/d3d9.dll") == nl::test::legacy_fixture::fixture());
  for (const auto& [path, bytes] : depot.legacy) CHECK(g.read(path) == bytes);
  CHECK(g.read("native-loader/packages/test-runtime/1.0.0_1/runtime/d3d9.dll") == "MZ-one");
  write_file(nl::fs::join(g.root, logo + ".bak"), depot.stock.at(logo));  // a copy is available now
  const auto next = apply_legacy(g.root, depot.catalog, vanilla);
  CHECK(next.outcome == "deployed");
  CHECK(has_change(next, "restore-stock", logo));
  CHECK(g.read(logo) == depot.stock.at(logo));
  CHECK(!g.has("bin/win64/d3d9.dll"));
}

TEST_CASE("deploy legacy: a legacy file or stock copy changed just before its move stops the transaction") {
  // These moves keep their SHA-256 check right before the move. The hook changes a file just before
  // the second move of the run: the first is the journal's commit of the pending transaction.
  Game g("deploy_legacy_changed");
  const auto depot = nl::test::legacy_fixture::depot();
  const sfs::path vanilla = g.dir / "vanilla";
  legacy_depot(g, depot, vanilla);
  version_1(g);
  const auto changed_before_steps = [&](const sfs::path& file) {
    int moves = 0;
    nl::fs::Counting disk(g_fast, [&](std::uint64_t, std::string_view what) {
      if (what == "move" && ++moves == 2) write_file(file, "changed at the last moment");
    });
    return apply_legacy(g.root, depot.catalog, vanilla, &disk);
  };
  const auto runtime_changed = changed_before_steps(g.root / "rtx.conf");
  CHECK(runtime_changed.outcome == "failed");
  CHECK(runtime_changed.error.find("changed before its move") != std::string::npos);
  CHECK(g.read("rtx.conf") == "changed at the last moment");  // undone, and the changed file never archived
  CHECK(g.has("bin/win64/d3d9.dll"));
  CHECK(!g.has("native-loader/backup/legacy"));
  CHECK(!g.journal().pending.has_value());
  write_file(g.root / "rtx.conf", "old RTX config");
  // The staged stock copy: transaction 2 now, since the failed one used up its number.
  const auto stock_changed = changed_before_steps(nl::fs::join(g.root, "native-loader/staging/2/legacy/stock/bin/win64/engine.dll"));
  CHECK(stock_changed.outcome == "failed");
  CHECK(stock_changed.error.find("changed before its move") != std::string::npos);
  CHECK(g.read("bin/win64/engine.dll") == depot.legacy.at("bin/win64/engine.dll"));
  CHECK(!g.has("native-loader/backup/legacy"));
  // Undisturbed, the next run migrates.
  const auto r = apply_legacy(g.root, depot.catalog, vanilla);
  CHECK(r.outcome == "deployed");
  CHECK(g.read("bin/win64/engine.dll") == depot.stock.at("bin/win64/engine.dll"));
}

TEST_CASE("deploy legacy: links in the former installation stay in place and never stop the package") {
  Game g("deploy_legacy_links");
  write_file(g.root / "bin/win64/d3d9.dll", nl::test::legacy_fixture::fixture());
  const std::string addon = "garrysmod/addons/mount-hl2rtx/";
  write_file(nl::fs::join(g.root, addon + "addon.json"), "{}");
  write_file(g.dir / "hl2rtx" / "models" / "headcrab.mdl", "another game's model");
  // RTXLauncher's Mount HL2 RTX links mount-hl2rtx/models (and materials, maps) to Half-Life 2 RTX.
  if (!junction(nl::fs::join(g.root, addon + "models"), g.dir / "hl2rtx" / "models")) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  g.add("runtime.gma", rtx_package("1.0.0", {{"garrysmod/addons/remixbinary/lua/new.lua", "new"}}));
  g.allow({"garrysmod/addons/runtime.gma"});
  const auto r = apply_at(g.root);
  if (r.outcome != "deployed") std::printf("  links: %s %s\n", r.outcome.c_str(), r.error.c_str());
  CHECK(r.outcome == "deployed");
  CHECK(has_change(r, "archive-legacy", "bin/win64/d3d9.dll"));
  CHECK(has_change(r, "archive-legacy", addon + "addon.json"));
  CHECK(mentions(r.notes, addon + "models"));
  CHECK(g.read("garrysmod/addons/remixbinary/lua/new.lua") == "new");
  CHECK(nl::fs::stat(nl::fs::join(g.root, addon + "models")).link);
  CHECK(nl::fs::read_file(g.dir / "hl2rtx" / "models" / "headcrab.mdl", 64) == "another game's model");
  CHECK(apply_at(g.root).operations == 0);
  sfs::remove(nl::fs::join(g.root, addon + "models"));  // the junction, not its target
}

TEST_CASE("deploy legacy: a migration that cannot be planned leaves the old installation and deploys the package") {
  Game g("deploy_legacy_unplanned");
  const auto old_runtime = nl::test::legacy_fixture::fixture();
  write_file(g.root / "bin/win64/d3d9.dll", old_runtime);
  sfs::create_directories(g.dir / "elsewhere");
  sfs::create_directories(g.root / "native-loader" / "backup");
  // The archive's folder leads elsewhere, so no archive can be planned.
  if (!junction(g.root / "native-loader" / "backup" / "legacy", g.dir / "elsewhere")) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  version_1(g);
  const auto r = apply_at(g.root);
  if (r.outcome != "deployed") std::printf("  unplanned: %s %s\n", r.outcome.c_str(), r.error.c_str());
  CHECK(r.outcome == "deployed");
  CHECK(mentions(r.notes, "left as it is"));
  CHECK(g.read("bin/win64/d3d9.dll") == old_runtime);
  CHECK(g.read("native-loader/packages/test-runtime/1.0.0_1/runtime/d3d9.dll") == "MZ-one");
  CHECK(sfs::is_empty(g.dir / "elsewhere"));
  sfs::remove(g.root / "native-loader" / "backup" / "legacy");  // the junction, not its target
  const auto next = apply_at(g.root);  // the next start migrates it
  CHECK(next.outcome == "deployed");
  CHECK(has_change(next, "archive-legacy", "bin/win64/d3d9.dll"));
  CHECK(!g.has("bin/win64/d3d9.dll"));
}

TEST_CASE("deploy legacy: a junctioned game root and a linked d3d9.dll deploy, and the root still migrates") {
  Game g("deploy_legacy_linked_root");
  version_1(g);
  const sfs::path linked = g.dir / "GarrysMod";
  if (!junction(linked, g.root)) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  const auto first = apply_at(linked);
  if (first.outcome != "deployed") std::printf("  linked root: %s %s\n", first.outcome.c_str(), first.error.c_str());
  CHECK(first.outcome == "deployed");
  // A d3d9.dll that is a link: never followed, not Remix, left alone.
  sfs::create_directories(g.dir / "dxvk");
  REQUIRE(junction(g.root / "bin" / "win64" / "d3d9.dll", g.dir / "dxvk"));
  version_2(g);
  const auto second = apply_at(linked);
  if (second.outcome != "deployed") std::printf("  linked d3d9: %s %s\n", second.outcome.c_str(), second.error.c_str());
  CHECK(second.outcome == "deployed");
  CHECK(nl::fs::stat(g.root / "bin" / "win64" / "d3d9.dll").link);
  sfs::remove(g.root / "bin" / "win64" / "d3d9.dll");  // the junction, not its target
  // A symbolic link where Windows allows one without elevation (Developer Mode) or the test is elevated.
  write_file(g.dir / "dxvk" / "d3d9.dll", nl::test::legacy_fixture::fixture());
  if (CreateSymbolicLinkW((g.root / "bin" / "win64" / "d3d9.dll").c_str(), (g.dir / "dxvk" / "d3d9.dll").c_str(),
                          SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)) {
    version_1(g);
    const auto third = apply_at(linked);
    CHECK(third.outcome == "deployed");
    CHECK(!has_change(third, "archive-legacy", "bin/win64/d3d9.dll"));
    CHECK(nl::fs::stat(g.root / "bin" / "win64" / "d3d9.dll").link);
    sfs::remove(g.root / "bin" / "win64" / "d3d9.dll");
  } else {
    std::printf("  (symbolic link part skipped: Windows error %lu)\n", GetLastError());
  }
  // A real legacy runtime below the junctioned root is found and archived through it.
  write_file(g.root / "bin" / "win64" / "d3d9.dll", nl::test::legacy_fixture::fixture());
  version_2(g);
  const auto migrated = apply_at(linked);
  CHECK(migrated.outcome == "deployed");
  CHECK(has_change(migrated, "archive-legacy", "bin/win64/d3d9.dll"));
  CHECK(!g.has("bin/win64/d3d9.dll"));
  sfs::remove(linked);
}

TEST_CASE("deploy legacy: files adopted before RTX was on are archived and become the loader's") {
  // RTX off (or loader 0.7.0) adopts a legacy file that matches the package byte for byte. The
  // migration must archive it all the same: left adopted, uninstall would leave it active, and a
  // later version would take it over as an original that uninstall puts back.
  Game g("deploy_legacy_adopted");
  write_file(g.root / "bin/win64/d3d9.dll", nl::test::legacy_fixture::fixture());
  const std::string same = "garrysmod/addons/remixbinary/lua/same.lua";
  const std::string gone = "garrysmod/addons/remixbinary/lua/gone.lua";
  write_file(nl::fs::join(g.root, same), "shared implementation");
  write_file(nl::fs::join(g.root, gone), "dropped later");
  g.add("runtime.gma", rtx_package("1.0.0", {{same, "shared implementation"}, {gone, "dropped later"}}));
  write_file(g.root / "native-loader" / "config.json", kRtxOff);
  REQUIRE(apply_at(g.root).ok());
  REQUIRE(record_of(*g.journal().current, same) != nullptr);
  REQUIRE(record_of(*g.journal().current, same)->adopted);
  REQUIRE(record_of(*g.journal().current, gone)->adopted);
  // RTX on with a version that no longer has gone.lua (so it is dropped, not placed).
  g.add("runtime.gma", rtx_package("1.1.0", {{same, "shared implementation"}}));
  g.allow({"garrysmod/addons/runtime.gma"});
  const auto on = apply_at(g.root);
  if (on.outcome != "deployed") std::printf("  adopted: %s %s\n", on.outcome.c_str(), on.error.c_str());
  REQUIRE(on.outcome == "deployed");
  const std::string archive = "native-loader/backup/legacy/" + std::to_string(on.generation) + "/";
  CHECK(g.read(archive + same) == "shared implementation");
  CHECK(g.read(archive + gone) == "dropped later");
  CHECK(g.read(same) == "shared implementation");
  CHECK(!g.has(gone));
  REQUIRE(record_of(*g.journal().current, same) != nullptr);
  CHECK(!record_of(*g.journal().current, same)->adopted);
  CHECK(record_of(*g.journal().current, gone) == nullptr);
  // A later version replaces the loader's copy; nothing of the former installation is an original.
  g.add("runtime.gma", rtx_package("1.2.0", {{same, "newer implementation"}}));
  const auto newer = apply_at(g.root);
  CHECK(newer.outcome == "deployed");
  CHECK(has_change(newer, "replace", same));
  CHECK(g.journal().originals.empty());
  REQUIRE(nl::deploy::uninstall(g.root, with(nullptr)).ok());
  CHECK(!g.has(same));
  CHECK(!g.has(gone));
  CHECK(!g.has("bin/win64/d3d9.dll"));
  CHECK(g.read(archive + same) == "shared implementation");
}

TEST_CASE("deploy: a file the loader adopted and later put back itself is the loader's after a rollback") {
  Game g("deploy_adopt_rollback");
  const std::string module = "garrysmod/lua/bin/gmcl_test_win64.dll";
  write_file(g.root / "garrysmod" / "lua" / "bin" / "gmcl_test_win64.dll", "MZ-module");  // the user's own copy
  g.add("lua.gma", kLua);
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}}));
  g.allow({"garrysmod/addons/lua.gma"});
  REQUIRE(apply_at(g.root).ok());  // adopts the module
  REQUIRE(record_of(*g.journal().current, module)->adopted);
  sfs::remove(g.root / "garrysmod" / "lua" / "bin" / "gmcl_test_win64.dll");  // the user deletes it
  g.allow({"garrysmod/addons/lua.gma", "garrysmod/addons/mods.gma"});
  REQUIRE(apply_at(g.root).ok());  // the loader places the module itself
  REQUIRE(nl::deploy::rollback(g.root).ok());
  const auto rolled_back = g.journal();
  const nl::journal::File* back = record_of(*rolled_back.current, module);
  REQUIRE(back != nullptr);
  CHECK(!back->adopted);  // the file in place is the one the loader put there
  // A later deployment drops the generation that placed it; the file must stay, as listed.
  g.add("mods.gma", mods("1.1.0", {{kMod + "mod.usda", "#usda v2\n"}}));
  REQUIRE(apply_at(g.root).outcome == "deployed");
  CHECK(g.read(module) == "MZ-module");
  CHECK(nl::deploy::status(g.root, true).drift.empty());
}

TEST_CASE("deploy: a new version takes over a file the loader adopted, which goes back at uninstall (ADR 0035)") {
  Game g("deploy_adopted_upgrade");
  const std::string module = "garrysmod/lua/bin/gmcl_test_win64.dll";
  write_file(g.root / "garrysmod" / "lua" / "bin" / "gmcl_test_win64.dll", "MZ-module");  // the user's own copy
  g.add("lua.gma", kLua);
  g.allow({"garrysmod/addons/lua.gma"});
  REQUIRE(apply_at(g.root).ok());
  REQUIRE(record_of(*g.journal().current, module)->adopted);
  Pkg newer = kLua;
  newer.version = "1.1.0";
  newer.files = {{"native/root/" + module, "MZ-module two"}};
  g.add("lua.gma", newer);
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(has_change(r, "take-over", module));
  CHECK(g.read(module) == "MZ-module two");
  CHECK(g.read("native-loader/backup/originals/" + module) == "MZ-module");
  CHECK(!record_of(*g.journal().current, module)->adopted);  // the loader's own copy now

  // The user changes it: the next start puts the package's copy back, and the original stays the one put back later.
  write_file(g.root / "garrysmod" / "lua" / "bin" / "gmcl_test_win64.dll", "MZ-changed");
  const auto back = apply_at(g.root);
  CHECK(has_change(back, "put-back", module));
  CHECK(g.read(module) == "MZ-module two");
  CHECK(g.journal().originals.size() == 1);

  REQUIRE(nl::deploy::uninstall(g.root).outcome == "removed");
  CHECK(g.read(module) == "MZ-module");
}

TEST_CASE("deploy: an original goes back once no generation refers to its path (ADR 0035)") {
  Game g("deploy_original_dropped");
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "someone else's");
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}, {kMod + "a.dds", "A"}}));
  g.allow({"garrysmod/addons/mods.gma"});
  REQUIRE(apply_at(g.root).outcome == "deployed");  // takes mod.usda over
  REQUIRE(g.journal().originals.size() == 1);

  // A version without the file: its copy is kept for a rollback, so the original waits.
  g.add("mods.gma", mods("1.1.0", {{kMod + "a.dds", "A2"}}));
  REQUIRE(apply_at(g.root).outcome == "deployed");
  CHECK(!g.has(kModDir + "mod.usda"));
  CHECK(g.journal().originals.size() == 1);

  // The next one leaves no generation naming it: the original goes back.
  g.add("mods.gma", mods("1.2.0", {{kMod + "a.dds", "A3"}}));
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(has_change(r, "restore-original", kModDir + "mod.usda"));
  CHECK(g.read(kModDir + "mod.usda") == "someone else's");
  CHECK(g.journal().originals.empty());
  CHECK(!g.has("native-loader/backup/originals"));
}

TEST_CASE("deploy: an original stays kept while another file is at its path (ADR 0035)") {
  Game g("deploy_original_blocked");
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "someone else's");
  g.add("mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}}));
  g.allow({"garrysmod/addons/mods.gma"});
  REQUIRE(apply_at(g.root).outcome == "deployed");  // takes it over
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda", "#usda mine\n");  // then the loader's copy changes
  const auto removed = nl::deploy::uninstall(g.root);
  CHECK(removed.outcome == "removed");
  CHECK(g.read(kModDir + "mod.usda") == "#usda mine\n");  // a changed file is not the loader's to delete
  CHECK(mentions(removed.notes, "put it back by hand"));
  CHECK(g.read("native-loader/backup/originals/" + kModDir + "mod.usda") == "someone else's");
}

TEST_CASE("deploy: a retired file that cannot be deleted does not stop later commands") {
  Game g("deploy_readonly");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  REQUIRE(apply_at(g.root).ok());
  // A third version retires the first one; one of its files is read-only.
  const std::string locked = "native-loader/packages/test-runtime/1.0.0_1/runtime/d3d9.dll";
  REQUIRE(SetFileAttributesW(nl::fs::join(g.root, locked).c_str(), FILE_ATTRIBUTE_READONLY));
  g.add("mods.gma", mods("1.2.0", {{kMod + "mod.usda", "#usda v3\n"}}));
  const auto r = apply_at(g.root);
  CHECK(r.outcome == "deployed");
  CHECK(mentions(r.notes, "read-only"));
  CHECK(g.has(locked));
  CHECK(!g.has("native-loader/packages/test-runtime/1.0.0_1/config"));
  CHECK(g.journal().retired.size() == 1);
  nl::fs::Counting counting(nl::fs::win32());
  const auto again = apply_at(g.root, &counting);
  CHECK(again.outcome == "unchanged");
  CHECK(counting.operations() == 0);
  CHECK(mentions(again.notes, "read-only"));
  REQUIRE(SetFileAttributesW(nl::fs::join(g.root, locked).c_str(), FILE_ATTRIBUTE_NORMAL));
  CHECK(apply_at(g.root).outcome == "unchanged");
  CHECK(!g.has("native-loader/packages/test-runtime/1.0.0_1"));
  CHECK(g.journal().retired.empty());
}

TEST_CASE("deploy: a rollback's hold ends when the plan moves on, and a broken package does not lift it") {
  Game g("deploy_hold");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  version_2(g);
  REQUIRE(apply_at(g.root).ok());
  REQUIRE(nl::deploy::rollback(g.root).ok());
  // Version 2's mods package cannot be deployed now (someone else's file is at one of its targets);
  // the plan still names version 2, so the rollback stays held instead of deploying the rest of it.
  write_file(g.root / "rtx-remix" / "mods" / "test_mod" / "textures" / "b.dds", "someone else's");
  CHECK(apply_at(g.root).outcome == "held");
  CHECK(g.read(kModDir + "mod.usda") == "#usda v1\n");
  sfs::remove_all(g.root / "rtx-remix" / "mods" / "test_mod" / "textures");
  // The plan names what is deployed: nothing to do, but the hold ends.
  version_1(g);
  const auto same = apply_at(g.root);
  CHECK(same.outcome == "unchanged");
  CHECK(mentions(same.notes, "hold"));
  CHECK(!g.journal().hold.has_value());
  // So version 2 is deployed when the plan names it again.
  version_2(g);
  CHECK(apply_at(g.root).outcome == "deployed");
  CHECK(g.read(kModDir + "mod.usda") == "#usda v2\n");
}

TEST_CASE("deploy: an upgrade that puts back a deleted file still leaves a rollback that works") {
  Game g("deploy_missing_upgrade");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  sfs::remove(g.root / "rtx-remix" / "mods" / "test_mod" / "mod.usda");
  version_2(g);
  REQUIRE(apply_at(g.root).outcome == "deployed");
  CHECK(g.read(kModDir + "mod.usda") == "#usda v2\n");
  const auto back = nl::deploy::rollback(g.root);
  CHECK(back.outcome == "rolled-back");
  CHECK(g.read(kModDir + "a.dds") == "A");
  CHECK(!g.has(kModDir + "mod.usda"));  // it was gone before the upgrade, so the rollback does without it
}

TEST_CASE("deploy: recovery retires what it cannot put back and never takes someone else's file") {
  Game g("deploy_recovery_leftovers");
  using nl::journal::Step;
  const std::string sha_old = nl::sha256::of("old");
  const std::string sha_new = nl::sha256::of("MZ-new");
  const std::string sha_mod = nl::sha256::of("new mod");
  // An interrupted transaction 7: x.usda was moved aside and the new one placed, a payload file was
  // placed; then, before the next run, the user edited x.usda and put a note into the new folder.
  write_file(g.root / "rtx-remix" / "mods" / "m" / "x.usda", "edited by the user");
  write_file(g.root / "native-loader" / "backup" / "7" / "rtx-remix" / "mods" / "m" / "x.usda", "old");
  write_file(g.root / "native-loader" / "packages" / "p" / "1.0.0_7" / "runtime" / "d3d9.dll", "MZ-new");
  write_file(g.root / "native-loader" / "packages" / "p" / "1.0.0_7" / "notes.txt", "mine");
  sfs::create_directories(g.root / "native-loader" / "staging" / "7" / "0" / "payload" / "runtime");
  sfs::create_directories(g.root / "native-loader" / "staging" / "7" / "0" / "root" / "rtx-remix" / "mods" / "m");
  nl::journal::Journal j;
  j.loader = "0.1.0";
  j.next = 8;
  nl::journal::Generation cur;
  cur.number = 6;
  cur.packages.push_back({"m", "1.0.0", std::string(64, 'a'), "local", "m.gma", "", std::nullopt});
  cur.files.push_back({"rtx-remix/mods/m/x.usda", "m", sha_old, 3, 1, false});
  j.current = cur;
  j.dirs = {"rtx-remix", "rtx-remix/mods", "rtx-remix/mods/m"};
  nl::journal::Pending pending{7, "apply", {}};
  for (const char* dir : {"native-loader/backup", "native-loader/backup/7", "native-loader/backup/7/rtx-remix",
                          "native-loader/backup/7/rtx-remix/mods", "native-loader/backup/7/rtx-remix/mods/m",
                          "native-loader/packages", "native-loader/packages/p", "native-loader/packages/p/1.0.0_7",
                          "native-loader/packages/p/1.0.0_7/runtime"}) {
    pending.steps.push_back({Step::Op::make_dir, "", dir, ""});
  }
  pending.steps.push_back({Step::Op::move, "rtx-remix/mods/m/x.usda", "native-loader/backup/7/rtx-remix/mods/m/x.usda", sha_old});
  pending.steps.push_back({Step::Op::move, "native-loader/staging/7/0/payload/runtime/d3d9.dll",
                           "native-loader/packages/p/1.0.0_7/runtime/d3d9.dll", sha_new});
  pending.steps.push_back({Step::Op::move, "native-loader/staging/7/0/root/rtx-remix/mods/m/x.usda", "rtx-remix/mods/m/x.usda", sha_mod});
  j.pending = pending;
  nl::journal::save(nl::fs::win32(), g.root, j);

  const auto r = nl::deploy::recover(g.root);
  CHECK(r.outcome == "recovered");
  CHECK(g.read("rtx-remix/mods/m/x.usda") == "edited by the user");             // the user's edit stays
  CHECK(!g.has("native-loader/backup"));                                       // the stranded copy is gone
  CHECK(g.read("native-loader/packages/p/1.0.0_7/notes.txt") == "mine");       // the stranger's file stays
  CHECK(!g.has("native-loader/packages/p/1.0.0_7/runtime"));                   // the loader's file and folder do not
  CHECK(!g.has("native-loader/staging"));
  const auto after = g.journal();
  CHECK(!after.pending && after.retired.empty());
  CHECK(std::find(after.dirs.begin(), after.dirs.end(), "native-loader/packages/p/1.0.0_7") != after.dirs.end());
  CHECK(mentions(r.notes, "changed while a deployment was interrupted"));
  sfs::remove(g.root / "native-loader" / "packages" / "p" / "1.0.0_7" / "notes.txt");
  CHECK(nl::deploy::recover(g.root).ok());  // once empty, the folders it made go too
  CHECK(!g.has("native-loader/packages/p"));
}

TEST_CASE("deploy: nothing is deleted through a junction that replaced a loader folder") {
  Game g("deploy_junction_later");
  version_1(g);
  REQUIRE(apply_at(g.root).ok());
  const sfs::path elsewhere = g.dir / "elsewhere";
  sfs::create_directories(elsewhere);
  sfs::copy(g.root / "rtx-remix" / "mods" / "test_mod", elsewhere, sfs::copy_options::recursive);
  sfs::remove_all(g.root / "rtx-remix" / "mods" / "test_mod");
  const std::string command = "cmd /c mklink /J \"" + (g.root / "rtx-remix" / "mods" / "test_mod").string() + "\" \"" +
                              elsewhere.string() + "\" >nul";
  if (std::system(command.c_str()) != 0) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  const auto r = nl::deploy::uninstall(g.root);
  CHECK(r.outcome == "removed");
  CHECK(mentions(r.notes, "link"));
  CHECK(sfs::exists(elsewhere / "mod.usda"));
  CHECK(sfs::exists(elsewhere / "a.dds"));
  sfs::remove(g.root / "rtx-remix" / "mods" / "test_mod");  // the junction, not its target
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

TEST_CASE("deploy faults: an unsubscribe interrupted or failing at any change ends in the old or the new state") {
  Game g("deploy_faults_unsubscribe");
  const Workshop w(g);
  workshop_versions(g, w);
  unsubscribe(w, "123", {"124"});
  unsubscribe(w, "124", {});
  const sfs::path before = g.dir / "before";
  copy_tree(g.root, before);
  // Every copy of the game sees the same Workshop folder and record, with both items gone.
  const Command removal = [&w](const sfs::path& root, nl::fs::FileSystem* disk) { return w.apply(root, disk); };
  CHECK(interrupt_everywhere(g.dir / "kill", before, removal, 2) > 10);
  CHECK(fail_everywhere(g.dir / "fail", before, removal) > 10);
}

TEST_CASE("deploy faults: legacy stock restoration interrupted or failing at any change ends in the old or the new state") {
  // Staged stock copies, depot moves and their undo, over a synthetic build (no game bytes).
  Game g("deploy_faults_legacy_stock");
  const auto depot = nl::test::legacy_fixture::depot();
  const sfs::path vanilla = g.dir / "vanilla";
  legacy_depot(g, depot, vanilla);
  version_1(g);
  const sfs::path before = g.dir / "before";
  copy_tree(g.root, before);
  // Every copy of the game reads the same vanilla root; its backup_patches and .bak copies travel with it.
  const Command command = [&](const sfs::path& root, nl::fs::FileSystem* disk) {
    return apply_legacy(root, depot.catalog, vanilla, disk);
  };
  CHECK(interrupt_everywhere(g.dir / "kill", before, command, 2) > 40);
  CHECK(fail_everywhere(g.dir / "fail", before, command) > 40);
}

TEST_CASE("startup deployment: a late bad archive keeps all current packages without changing CLI behavior") {
  Game g("startup_bad_archive");
  g.add("runtime.gma", runtime("1.0.0", "one"));
  g.allow({"garrysmod/addons/runtime.gma"});
  const auto first = nl::startup::prepare(g.root, GetCurrentProcessId());
  REQUIRE(first.deployment.outcome == "deployed");
  REQUIRE(first.journal && first.journal->current);
  const auto generation = first.journal->current->number;
  const auto payload = first.journal->current->packages[0].payload;
  const auto journal_before = g.read("native-loader/state.json");

  const auto update = runtime("2.0.0", "two");
  nl::test::FixtureArchive archive;
  archive.files.push_back({"native/manifest.json", manifest_of(update)});
  for (const auto& [name, bytes] : update.files) {
    archive.files.push_back({name, name.ends_with("d3d9.dll") ? "BAD" : bytes});
  }
  write_file(g.root / "garrysmod/addons/runtime.gma", nl::test::build_gma(archive));
  g.add("mods.gma", mods("1.0.0", {{kMod + "new.txt", "new mod"}}));
  g.allow({"garrysmod/addons/runtime.gma", "garrysmod/addons/mods.gma"});
  const auto kept = nl::startup::prepare(g.root, GetCurrentProcessId());
  REQUIRE(kept.deployment.outcome == "kept");
  CHECK(kept.may_activate);
  CHECK(kept.deployment.generation == generation);
  CHECK(kept.deployment.changes.empty());
  CHECK(g.read(payload + "/runtime/d3d9.dll") == "one");
  CHECK(g.read("native-loader/state.json") == journal_before);
  CHECK(!g.has("rtx-remix/mods/test_mod/new.txt"));

  const auto cli_style = apply_at(g.root);
  REQUIRE(cli_style.outcome == "deployed");
  REQUIRE(g.journal().current && g.journal().current->packages.size() == 1);
  CHECK(g.journal().current->packages[0].id == "test-mods");
  CHECK(g.has("rtx-remix/mods/test_mod/new.txt"));
}

TEST_CASE("startup deployment: a subscription's content package needs no allowlist; native code does (ADR 0027)") {
  const auto dir = nl::test::scratch_dir("startup_subscribed");
  const sfs::path steamapps = dir / "lib" / "steamapps";
  const sfs::path root = steamapps / "common" / "game";  // where discovery finds the library's Workshop folder
  const sfs::path content = steamapps / "workshop" / "content" / "4000";
  const sfs::path config = root / "native-loader" / "config.json";
  write_file(root / "bin" / "win64" / "gmod.exe", "");
  sfs::create_directories(root / "garrysmod" / "cfg");
  write_file(config, R"({"schema": 1})");
  const std::string items = "\"700\" { \"size\" \"1\" } \"701\" { \"size\" \"1\" } ";
  write_file(steamapps / "workshop" / "appworkshop_4000.acf",
             "\"AppWorkshop\" { \"WorkshopItemsInstalled\" { " + items + "} \"WorkshopItemDetails\" { " + items + "} }");
  write_gma(content / "700" / "mods.gma", mods("1.0.0", {{kMod + "mod.usda", "#usda v1\n"}, {kMod + "a.dds", "A"}}));
  write_gma(content / "701" / "runtime.gma", runtime("1.0.0", "MZ-one"));
  const auto has = [&](const std::string& relative) { return nl::fs::stat(nl::fs::join(root, relative)).exists; };

  const auto first = nl::startup::prepare(root, GetCurrentProcessId());
  REQUIRE(first.deployment.outcome == "deployed");
  REQUIRE(first.deployment.packages.size() == 1);
  CHECK(first.deployment.packages[0].rfind("test-mods ", 0) == 0);
  CHECK(nl::fs::read_file(nl::fs::join(root, kModDir + "mod.usda"), 1 << 20) == "#usda v1\n");
  CHECK(skipped_because(first.deployment, "add Workshop item 701 to allow.workshop"));
  CHECK(!has("native-loader/packages/test-runtime"));

  // Allowlisted, the runtime deploys as well, and the content stays.
  write_file(config, R"({"schema": 1, "allow": {"workshop": ["701"]}})");
  const auto second = nl::startup::prepare(root, GetCurrentProcessId());
  REQUIRE(second.deployment.outcome == "deployed");
  CHECK(second.deployment.packages.size() == 2);
  CHECK(has("native-loader/packages/test-runtime/1.0.0_2/runtime/d3d9.dll"));
  CHECK(has(kModDir + "mod.usda"));

  // The off switch: packages from subscriptions are no longer planned, so the content goes.
  write_file(config, R"({"schema": 1, "allow": {"workshop": ["701"], "subscribed_content": false}})");
  const auto third = nl::startup::prepare(root, GetCurrentProcessId());
  REQUIRE(third.deployment.outcome == "deployed");
  CHECK(third.deployment.packages.size() == 1);
  CHECK(!has(kModDir + "mod.usda"));
  CHECK(has("native-loader/packages/test-runtime/1.0.0_2/runtime/d3d9.dll"));
  sfs::remove_all(dir);
}
