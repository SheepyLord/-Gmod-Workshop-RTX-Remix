#include "nl/discovery.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;
using nl::discovery::Source;

namespace {

void touch(const fs::path& file, const std::string& text = "x") {
  fs::create_directories(file.parent_path());
  std::ofstream(file, std::ios::binary) << text;
}

// A fake Steam library: <lib>\steamapps\common\GarrysMod plus Workshop items 111..555.
struct FakeLibrary {
  fs::path base;
  fs::path steamapps;
  fs::path game;
  fs::path content;

  explicit FakeLibrary(const fs::path& dir) : base(dir), steamapps(dir / "lib" / "steamapps") {
    game = steamapps / "common" / "GarrysMod";
    content = steamapps / "workshop" / "content" / "4000";
    touch(game / "bin" / "win64" / "gmod.exe");
    touch(game / "garrysmod" / "cfg" / "addonnomount.txt", "\"addonnomount\"\n{\n\t\"1\"\t\t\"222\"\n}\n");
    touch(content / "111" / "runtime.gma");
    touch(content / "222" / "disabled.gma");
    fs::create_directories(content / "333");  // installed folder without an archive
    touch(content / "444" / "a.gma");
    touch(content / "444" / "b.gma");
    touch(content / "555" / "387671470694828055_legacy.bin");
    touch(steamapps / "workshop" / "appworkshop_4000.acf",
          R"("AppWorkshop" { "appid" "4000" "WorkshopItemsInstalled" { "111" { "size" "1" "timeupdated" "1793000000" "manifest" "987" } } })");
    touch(game / "garrysmod" / "addons" / "local.gma");
    touch(game / "garrysmod" / "addons" / "notes.txt");
    touch(base / "dev" / "pkg" / "native" / "manifest.json", "{}");
    fs::create_directories(base / "dev" / "empty");
  }
};

}  // namespace

TEST_CASE("discovery: the Workshop folder comes from the game's own library") {
  const auto dir = nl::test::scratch_dir("discovery_env");
  const FakeLibrary lib(dir);
  const auto env = nl::discovery::environment_for(lib.game, dir / "no-steam");
  REQUIRE(env.workshop_content.has_value());
  CHECK(fs::equivalent(*env.workshop_content, lib.content));
  CHECK(env.disabled_workshop.count("222") == 1);
  fs::remove_all(dir);
}

TEST_CASE("discovery: outside steamapps, Steam's libraryfolders.vdf finds the library") {
  const auto dir = nl::test::scratch_dir("discovery_steam");
  const FakeLibrary lib(dir);
  const fs::path steam = dir / "steam";
  std::string escaped = (dir / "lib").string();
  for (std::size_t at = 0; (at = escaped.find('\\', at)) != std::string::npos; at += 2) escaped.replace(at, 1, "\\\\");
  touch(steam / "steamapps" / "libraryfolders.vdf",
        "\"libraryfolders\" { \"0\" { \"path\" \"C:\\\\nowhere\" \"apps\" { \"220\" \"1\" } } \"1\" { \"path\" \"" + escaped +
            "\" \"apps\" { \"4000\" \"7279850621\" } } }");
  const fs::path elsewhere = dir / "GMod_dev";
  fs::create_directories(elsewhere);
  const auto env = nl::discovery::environment_for(elsewhere, steam);
  REQUIRE(env.workshop_content.has_value());
  CHECK(fs::equivalent(*env.workshop_content, lib.content));
  CHECK(!nl::discovery::environment_for(elsewhere, dir / "no-steam").workshop_content.has_value());
  fs::remove_all(dir);
}

TEST_CASE("discovery: one candidate per allowlisted entry, in precedence order") {
  const auto dir = nl::test::scratch_dir("discovery_candidates");
  const FakeLibrary lib(dir);
  nl::config::Config config;
  config.workshop = {"111", "222", "333", "444", "555", "999"};
  config.local = {"garrysmod/addons/local.gma", "garrysmod/addons/missing.gma", "garrysmod/addons/notes.txt"};
  config.dev_folders = {(dir / "dev" / "pkg").string(), (dir / "dev" / "empty").string(), "no/such/folder"};
  const auto candidates = nl::discovery::discover(config, nl::discovery::environment_for(lib.game, dir / "no-steam"));
  REQUIRE(candidates.size() == 12);

  CHECK(candidates[0].source == Source::dev_folder);
  CHECK(candidates[0].problem.empty());
  CHECK(!candidates[1].problem.empty());  // no manifest
  CHECK(!candidates[2].problem.empty());  // missing folder

  CHECK(candidates[3].source == Source::local);
  CHECK(candidates[3].problem.empty());
  CHECK(fs::equivalent(candidates[3].location, lib.game / "garrysmod" / "addons" / "local.gma"));
  CHECK(!candidates[4].problem.empty());  // missing file
  CHECK(!candidates[5].problem.empty());  // not an archive

  CHECK(candidates[6].source == Source::workshop);
  CHECK(candidates[6].label == "111");
  CHECK(candidates[6].problem.empty());
  CHECK(candidates[6].location.filename() == "runtime.gma");
  CHECK(candidates[6].time_updated.value_or(0) == 1793000000u);
  CHECK(candidates[6].workshop_manifest == "987");
  CHECK(candidates[7].problem.find("disabled") != std::string::npos);   // 222 in addonnomount
  CHECK(candidates[7].disabled_by_user);
  CHECK(candidates[8].problem.find("no .gma") != std::string::npos);    // 333 empty
  CHECK(candidates[9].problem.find("archives") != std::string::npos);   // 444 ambiguous
  CHECK(candidates[10].problem.empty());                                // 555 legacy .bin
  CHECK(candidates[10].location.filename() == "387671470694828055_legacy.bin");
  CHECK(candidates[11].problem.find("not installed") != std::string::npos);  // 999
  CHECK(!candidates[11].disabled_by_user);
  fs::remove_all(dir);
}

TEST_CASE("discovery: local and dev locations are absolute even for a relative game root") {
  // The journal records these locations and start-up compares them with what it finds; a root
  // given relative to nlctl's working directory must not give another spelling of the same file.
  const auto dir = nl::test::scratch_dir("discovery_relative_root");
  const FakeLibrary lib(dir);
  nl::config::Config config;
  config.local = {"garrysmod/addons/local.gma"};
  config.dev_folders = {"dev/../dev/pkg"};
  const auto relative = fs::relative(lib.game, fs::current_path());
  REQUIRE(!relative.empty());
  nl::discovery::Environment environment;
  environment.game_root = relative;
  const auto candidates = nl::discovery::discover(config, environment);
  REQUIRE(candidates.size() == 2);
  for (const auto& candidate : candidates) {
    CHECK(candidate.location.is_absolute());
    CHECK(candidate.location == candidate.location.lexically_normal());
  }
  CHECK(fs::equivalent(candidates[1].location, lib.game / "garrysmod" / "addons" / "local.gma"));
  fs::remove_all(dir);
}

TEST_CASE("discovery: nothing allowlisted means nothing discovered") {
  const auto dir = nl::test::scratch_dir("discovery_empty");
  const FakeLibrary lib(dir);
  CHECK(nl::discovery::discover(nl::config::Config{}, nl::discovery::environment_for(lib.game, dir / "no-steam")).empty());
  fs::remove_all(dir);
}
