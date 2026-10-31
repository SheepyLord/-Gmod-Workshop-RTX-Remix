#include "legacy_fixture.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/legacy_migrate.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>

namespace {
void write(const std::filesystem::path& at, const std::string& bytes) {
  std::filesystem::create_directories(at.parent_path());
  std::ofstream(at, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}
struct Fixture {
  std::filesystem::path root = nl::test::scratch_dir("legacy-migrate");
  ~Fixture() { std::error_code ec; std::filesystem::remove_all(root, ec); }
  void put(std::string_view path, const std::string& bytes) { write(nl::fs::join(root, path), bytes); }
  void remix() { put("bin/win64/d3d9.dll", nl::test::legacy_fixture::fixture()); }
};
std::set<std::string> saved(const nl::legacy::Migration& plan) {
  std::set<std::string> out;
  for (const auto& file : plan.files) out.insert(file.path);
  return out;
}
bool mentions(const std::vector<std::string>& notes, const std::string& part) {
  return std::any_of(notes.begin(), notes.end(), [&](const std::string& note) { return note.find(part) != std::string::npos; });
}
// Directory junctions need no special rights; mklink is the simplest way to make one.
bool make_junction(const std::filesystem::path& link, const std::filesystem::path& target) {
  const std::string command = "cmd /c mklink /J \"" + link.string() + "\" \"" + target.string() + "\" >nul";
  return std::system(command.c_str()) == 0;
}
}

TEST_CASE("legacy migrate: plain DXVK and arbitrary strings never trigger migration") {
  Fixture f;
  f.put("bin/win64/d3d9.dll", "Direct3DCreate9 remixapi_InitializeLibrary");
  f.put("rtx.conf", "keep");
  CHECK(nl::legacy::plan(f.root, {}, 1).files.empty());
  CHECK(nl::legacy::plan(f.root, {}, 1).archive.empty());
}

TEST_CASE("legacy migrate: archive known leftovers and preserve unrelated and protected user files") {
  Fixture f; f.remix();
  f.put("rtx.conf", "old config");
  f.put("user.conf", "never modify");
  f.put("garrysmod/addons/remixbinary/lua/old.lua", "obsolete");
  f.put("garrysmod/addons/remixbinary/user.conf", "also protected");
  f.put("garrysmod/addons/personal/lua/my.lua", "personal");
  f.put("rtx-remix/mods/base_mod/old.usda", "old authored mod");
  f.put("rtx-remix/mods/my-mod/mod.usda", "personal");
  f.put("rtx-remix/mods/~gmod_topbr/mod.usda", "generated user data");
  f.put("garrysmod/data/remix_map_configs/default.txt", "personal");
  f.put("garrysmod/cfg/autoexec.cfg", "bind f flashlight\n");
  const auto plan = nl::legacy::plan(f.root, {}, 7);
  CHECK(plan.archive == "native-loader/backup/legacy/7");
  CHECK(saved(plan) == std::set<std::string>({"bin/win64/d3d9.dll", "rtx.conf",
        "garrysmod/addons/remixbinary/lua/old.lua", "rtx-remix/mods/base_mod/old.usda"}));
  const auto manifest = nl::json::parse(nl::legacy::backup_manifest(plan));
  CHECK(manifest.find("files")->as_array().size() == plan.files.size());
  for (const auto& file : plan.files) CHECK(file.before.sha256 == nl::fs::hash_file(nl::fs::join(f.root, file.path)).sha256);
  CHECK(plan.notes.size() == 2);
}

TEST_CASE("legacy migrate: loader ownership is excluded and prior permanent archives are never reused") {
  Fixture f; f.remix(); f.put("rtx.conf", "current");
  CHECK(nl::legacy::plan(f.root, {"bin/win64/d3d9.dll"}, 1).files.empty());
  CHECK(saved(nl::legacy::plan(f.root, {"rtx.conf"}, 1)) == std::set<std::string>({"bin/win64/d3d9.dll"}));
  f.put("native-loader/backup/legacy/1/manifest.json", "valuable backup");
  CHECK(nl::legacy::plan(f.root, {}, 1).archive == "native-loader/backup/legacy/1-2");
  CHECK(nl::fs::read_file(f.root / "native-loader/backup/legacy/1/manifest.json", 128) == "valuable backup");
  CHECK(nl::fs::read_file(f.root / "rtx.conf", 128) == "current");
}

TEST_CASE("legacy migrate: another build or an unknown depot edit leaves every Steam file and still archives the rest") {
  // A GMod update leaves new stock bytes the catalog does not know; Steam's verification, not the
  // loader, repairs Steam's files then. The runtime and the add-ons still go to the archive.
  Fixture f; f.remix(); f.put("bin/win64/engine.dll", "unknown edited native module");
  f.put("garrysmod/addons/remixbinary/lua/old.lua", "obsolete");
  const auto plan = nl::legacy::plan(f.root, {}, 1);
  CHECK(saved(plan) == std::set<std::string>({"bin/win64/d3d9.dll", "garrysmod/addons/remixbinary/lua/old.lua"}));
  CHECK(mentions(plan.notes, "verify this install in Steam"));
  CHECK(mentions(plan.notes, "build 26229091"));
  CHECK(nl::fs::read_file(f.root / "bin/win64/engine.dll", 128) == "unknown edited native module");
}

TEST_CASE("legacy migrate: Steam's files are restored as one recognized set of the catalogued build, from verified copies") {
  Fixture f; f.remix();
  const auto depot = nl::test::legacy_fixture::depot();
  for (const auto& [path, bytes] : depot.anchors) f.put(path, bytes);
  for (const auto& [path, bytes] : depot.legacy) f.put(path, bytes);
  // Stock copies in the launcher's backup_patches folder, beside the file (.bak), and in an explicit
  // vanilla root, which replaces Steam discovery.
  const std::string engine = "bin/win64/engine.dll", logo = "garrysmod/gamemodes/sandbox/logo.png",
                    loading = "garrysmod/html/loading.png";
  f.put("backup_patches_20261030_120000/" + engine, depot.stock.at(engine));
  f.put(logo + ".bak", depot.stock.at(logo));
  const auto vanilla = nl::test::scratch_dir("legacy-migrate-vanilla");
  write(nl::fs::join(vanilla, loading), depot.stock.at(loading));
  const auto plan = nl::legacy::plan(f.root, {}, 3, vanilla, depot.catalog);
  CHECK(saved(plan) == std::set<std::string>({"bin/win64/d3d9.dll", engine, logo, loading}));
  const auto source_of = [&](const std::string& path) {
    for (const auto& file : plan.files) if (file.path == path) return file.stock_source.lexically_normal();
    return std::filesystem::path();
  };
  CHECK(source_of(engine) == nl::fs::join(f.root / "backup_patches_20261030_120000", engine).lexically_normal());
  CHECK(source_of(logo) == nl::fs::join(f.root, logo + ".bak").lexically_normal());
  CHECK(source_of(loading) == nl::fs::join(vanilla, loading).lexically_normal());
  CHECK(source_of("bin/win64/d3d9.dll").empty());  // archived only
  for (const auto& file : plan.files) {
    if (file.stock_source.empty()) continue;
    CHECK(file.before.sha256 == nl::sha256::of(depot.legacy.at(file.path)));
    CHECK(file.stock.sha256 == nl::sha256::of(depot.stock.at(file.path)));
  }
  // The archive's manifest names copies inside the game folder relative to it, so it stays valid
  // wherever the folder goes; an external root by its full path.
  std::map<std::string, std::string> named;
  const auto manifest = nl::json::parse(nl::legacy::backup_manifest(plan));
  for (const auto& file : manifest.find("files")->as_array()) {
    if (const auto* source = file.find("source")) named[file.find("path")->as_string()] = source->as_string();
  }
  CHECK(named.size() == 3);
  CHECK(named[engine] == "backup_patches_20261030_120000/" + engine);
  CHECK(named[logo] == logo + ".bak");
  CHECK(named[loading] == nl::fs::utf8(nl::fs::join(vanilla, loading)));

  // A stock copy that does not verify is no source; without another one nothing is planned at all.
  f.put(logo + ".bak", "not the stock bytes");
  CHECK_THROWS_AS(nl::legacy::plan(f.root, {}, 3, vanilla, depot.catalog), std::runtime_error);
  f.put(logo + ".bak", depot.stock.at(logo));
  // Another build (an anchor differs) or a change the catalog does not know: every Steam file stays as
  // it is, with a note, and the rest is archived all the same.
  f.put("bin/win64/client.dll", "a newer build");
  auto kept = nl::legacy::plan(f.root, {}, 3, vanilla, depot.catalog);
  CHECK(saved(kept) == std::set<std::string>({"bin/win64/d3d9.dll"}));
  CHECK(mentions(kept.notes, "not GMod build test-build"));
  f.put("bin/win64/client.dll", depot.anchors.at("bin/win64/client.dll"));
  f.put(loading, "someone else's edit");
  kept = nl::legacy::plan(f.root, {}, 3, vanilla, depot.catalog);
  CHECK(saved(kept) == std::set<std::string>({"bin/win64/d3d9.dll"}));
  CHECK(mentions(kept.notes, loading + " holds changes the loader does not recognize"));
  // Stock files need nothing; the anchors are only consulted when something differs.
  for (const auto& [path, bytes] : depot.stock) f.put(path, bytes);
  f.put("bin/win64/client.dll", "a newer build");
  kept = nl::legacy::plan(f.root, {}, 3, vanilla, depot.catalog);
  CHECK(saved(kept) == std::set<std::string>({"bin/win64/d3d9.dll"}));
  CHECK(!mentions(kept.notes, "Steam's files"));
  // A catalog cannot widen the journal's exception for migration steps.
  auto wider = depot.catalog;
  wider.files.push_back({"bin/win64/server.dll", 1, nl::sha256::of("a"), nl::sha256::of("b")});
  CHECK_THROWS_AS(nl::legacy::plan(f.root, {}, 3, vanilla, wider), std::invalid_argument);
  std::filesystem::remove_all(vanilla);
}

TEST_CASE("legacy migrate: recovery sources reject '.' and '..' components even where they resolve") {
  // absolute() resolves them before any check could see them, so the path is checked as given.
  Fixture f; f.remix();
  std::filesystem::create_directories(f.root / "elsewhere");
  std::filesystem::create_directories(f.root / "inner");
  CHECK_THROWS_AS(nl::legacy::plan(f.root, {}, 1, f.root / "inner" / ".." / "elsewhere"), std::runtime_error);
  CHECK_THROWS_AS(nl::legacy::plan(f.root, {}, 1, f.root / "." / "elsewhere"), std::runtime_error);
  CHECK(nl::legacy::plan(f.root, {}, 1, f.root / "elsewhere").archive == "native-loader/backup/legacy/1");
}

TEST_CASE("legacy migrate: links inside the former installation stay in place and are never followed") {
  // RTXLauncher's Mount HL2 RTX fills mount-hl2rtx/{models,materials,maps} with links to another game.
  Fixture f; f.remix();
  const auto other = nl::test::scratch_dir("legacy-migrate-other-game");
  write(other / "models" / "headcrab.mdl", "another game's model");
  write(other / "addon" / "lua" / "autorun" / "x.lua", "a developer's checkout");
  f.put("garrysmod/addons/mount-hl2rtx/addon.json", "{}");
  const auto models = f.root / "garrysmod/addons/mount-hl2rtx/models";
  const auto niknaks = f.root / "garrysmod/addons/niknaks";
  if (!make_junction(models, other / "models") || !make_junction(niknaks, other / "addon")) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  const auto plan = nl::legacy::plan(f.root, {}, 1);
  CHECK(saved(plan) == std::set<std::string>({"bin/win64/d3d9.dll", "garrysmod/addons/mount-hl2rtx/addon.json"}));
  CHECK(mentions(plan.notes, "garrysmod/addons/mount-hl2rtx/models"));
  CHECK(mentions(plan.notes, "garrysmod/addons/niknaks"));
  std::filesystem::remove(models); std::filesystem::remove(niknaks);  // the junctions, not their targets
  CHECK(nl::fs::read_file(other / "models" / "headcrab.mdl", 128) == "another game's model");
  std::filesystem::remove_all(other);
}

TEST_CASE("legacy migrate: a linked runtime entry is not Remix, and a junctioned game root migrates") {
  const auto dir = nl::test::scratch_dir("legacy-migrate-junction");
  const auto real = dir / "real";
  write(dir / "dxvk" / "d3d9.dll", nl::test::legacy_fixture::fixture());
  write(real / "rtx.conf", "old config");
  std::filesystem::create_directories(real / "bin" / "win64");
  // A link where an entry is expected (here a junction), or a linked .trex folder: never followed,
  // so not Remix. Nothing is planned and nothing fails.
  if (!make_junction(real / "bin" / "win64" / "d3d9.dll", dir / "dxvk") ||
      !make_junction(real / "bin" / "win64" / ".trex", dir / "dxvk")) {
    std::printf("  (skipped: could not create a junction)\n");
    return;
  }
  const auto none = nl::legacy::plan(real, {}, 1);
  CHECK(none.archive.empty());
  CHECK(none.files.empty());
  std::filesystem::remove(real / "bin" / "win64" / "d3d9.dll");  // the junctions, not their targets
  std::filesystem::remove(real / "bin" / "win64" / ".trex");
  // Steam libraries on another drive are often reached through a junction at steamapps\common\GarrysMod.
  write(real / "bin" / "win64" / "d3d9.dll", nl::test::legacy_fixture::fixture());
  REQUIRE(make_junction(dir / "GarrysMod", real));
  CHECK(saved(nl::legacy::plan(dir / "GarrysMod", {}, 1)) == std::set<std::string>({"bin/win64/d3d9.dll", "rtx.conf"}));
  std::filesystem::remove(dir / "GarrysMod");
  CHECK(nl::fs::read_file(dir / "dxvk" / "d3d9.dll", 1 << 20) == nl::test::legacy_fixture::fixture());
  std::filesystem::remove_all(dir);
}

TEST_CASE("legacy migrate: journal exceptions are exact and exclude arbitrary engine and user paths") {
  CHECK(nl::legacy::step_path("bin/win64/engine.dll"));
  CHECK(nl::legacy::step_path("BIN/WIN64/D3D9.DLL.DISABLED"));
  CHECK(nl::legacy::step_path("bin/win64/.trex/usd/plugInfo.json"));
  CHECK(!nl::legacy::step_path("bin/win64/server.dll"));
  CHECK(!nl::legacy::step_path("bin/win64/user.conf"));
  CHECK(!nl::legacy::step_path("user.conf"));
  CHECK(!nl::legacy::step_path("../bin/win64/engine.dll"));
}
