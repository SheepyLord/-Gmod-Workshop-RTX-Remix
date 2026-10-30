#include "legacy_fixture.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/legacy_migrate.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <set>

namespace {
struct Fixture {
  std::filesystem::path root = nl::test::scratch_dir("legacy-migrate");
  ~Fixture() { std::error_code ec; std::filesystem::remove_all(root, ec); }
  void put(std::string_view path, const std::string& bytes) {
    const auto at = nl::fs::join(root, path);
    std::filesystem::create_directories(at.parent_path());
    std::ofstream(at, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  }
  void remix() { put("bin/win64/d3d9.dll", nl::test::legacy_fixture::fixture()); }
};
std::set<std::string> saved(const nl::legacy::Migration& plan) {
  std::set<std::string> out;
  for (const auto& file : plan.files) out.insert(file.path);
  return out;
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

TEST_CASE("legacy migrate: unknown depot edits fail closed and recovery sources reject parent traversal") {
  Fixture f; f.remix(); f.put("bin/win64/engine.dll", "unknown edited native module");
  CHECK_THROWS_AS(nl::legacy::plan(f.root, {}, 1), std::runtime_error);
  CHECK(nl::fs::read_file(f.root / "bin/win64/engine.dll", 128) == "unknown edited native module");
  std::filesystem::remove(f.root / "bin/win64/engine.dll");
  CHECK_THROWS_AS(nl::legacy::plan(f.root, {}, 1, f.root / ".." / "elsewhere"), std::runtime_error);
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
