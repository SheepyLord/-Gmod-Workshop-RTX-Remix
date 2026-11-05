#include "gma_fixture.h"
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
  CHECK(candidates[11].problem.find("not subscribed") != std::string::npos);  // 999: Steam lists it nowhere
  CHECK(candidates[11].unsubscribed);
  CHECK(!candidates[11].disabled_by_user);
  for (std::size_t i = 6; i < 11; ++i) CHECK(!candidates[i].unsubscribed);
  fs::remove_all(dir);
}

TEST_CASE("discovery: only an item Steam lists nowhere, with its folder gone, counts as unsubscribed (ADR 0025)") {
  const auto dir = nl::test::scratch_dir("discovery_unsubscribed");
  const FakeLibrary lib(dir);
  const auto acf = lib.steamapps / "workshop" / "appworkshop_4000.acf";
  // 777: subscribed, first download running (details only, no folder). 888: updating (installed, folder
  // being replaced). 666: Steam dropped the subscription record but not yet the files. 999: gone.
  touch(acf, R"("AppWorkshop" { "appid" "4000"
      "WorkshopItemsInstalled" { "111" { "size" "1" } "888" { "size" "1" } "666" { "size" "1" } }
      "WorkshopItemDetails" { "111" { "subscribedby" "1" } "777" { "subscribedby" "1" } "888" { "subscribedby" "1" } } })");
  touch(lib.content / "666" / "still.gma");
  nl::config::Config config;
  config.workshop = {"777", "888", "666", "999"};
  const auto env = nl::discovery::environment_for(lib.game, dir / "no-steam");
  auto c = nl::discovery::discover(config, env);
  REQUIRE(c.size() == 4);
  CHECK(!c[0].unsubscribed && c[0].problem.find("not installed") != std::string::npos);  // downloading: kept
  CHECK(!c[1].unsubscribed && c[1].problem.find("not installed") != std::string::npos);  // updating: kept
  CHECK(!c[2].unsubscribed && c[2].problem.empty());                                     // its files still work
  CHECK(c[3].unsubscribed);
  // Without a readable record nothing can be told apart: never unsubscribed.
  touch(acf, "\"AppWorkshop\" { broken");
  c = nl::discovery::discover(config, env);
  CHECK(!c[3].unsubscribed && c[3].problem.find("not installed") != std::string::npos);
  fs::remove(acf);
  c = nl::discovery::discover(config, env);
  CHECK(!c[3].unsubscribed);
  touch(acf, R"("SomethingElse" { })");  // no AppWorkshop section: not Steam's Workshop record
  c = nl::discovery::discover(config, env);
  CHECK(!c[3].unsubscribed);
  fs::remove_all(dir);
}

TEST_CASE("discovery: subscribedby names an account only with a non-zero account id (ADR 0111)") {
  using nl::discovery::subscribed_by_an_account;
  CHECK(subscribed_by_an_account("1") == true);
  CHECK(subscribed_by_an_account("123456789,234567890,3456789012") == true);  // the shape Steam writes
  CHECK(subscribed_by_an_account("0,345678901") == true);
  CHECK(subscribed_by_an_account(" 42 ") == true);
  CHECK(subscribed_by_an_account("42,") == true);
  CHECK(subscribed_by_an_account("76561198000000000") == true);     // a 64-bit id would do too
  CHECK(subscribed_by_an_account("18446744073709551615") == true);  // 20 digits
  CHECK(subscribed_by_an_account("") == false);
  CHECK(subscribed_by_an_account("0") == false);
  CHECK(subscribed_by_an_account("000") == false);
  CHECK(subscribed_by_an_account("0,0") == false);
  CHECK(subscribed_by_an_account(" , ") == false);
  // Not what Steam writes: neither added nor removed on its strength.
  CHECK(!subscribed_by_an_account("abc").has_value());
  CHECK(!subscribed_by_an_account("12a").has_value());
  CHECK(!subscribed_by_an_account("-1").has_value());
  CHECK(!subscribed_by_an_account("123456789012345678901").has_value());  // 21 digits
  CHECK(!subscribed_by_an_account("1;2").has_value());
}

TEST_CASE("discovery: subscribed items holding a package are content-only candidates after the allowlist (ADR 0027)") {
  const auto dir = nl::test::scratch_dir("discovery_subscribed");
  const FakeLibrary lib(dir);
  const auto gma = [&](const std::string& item, const std::string& name, bool package) {
    nl::test::FixtureArchive archive;
    if (package) archive.files.push_back({"native/manifest.json", "{}"});
    archive.files.push_back({"lua/autorun/x.lua", "-- x"});
    touch(lib.content / item / name, nl::test::build_gma(archive));
  };
  gma("1000", "pbr.gma", true);
  gma("999", "another.gma", true);
  gma("900", "plain.gma", false);  // an ordinary add-on
  gma("1100", "a.gma", true);      // two archives: not taken
  gma("1100", "b.gma", true);
  gma("1200", "off.gma", true);    // disabled in GMod's addon list
  touch(lib.content / "1300" / "387671470694828055_legacy.bin", "LZMA");  // never scanned
  touch(lib.game / "garrysmod" / "cfg" / "addonnomount.txt",
        "\"addonnomount\"\n{\n\t\"1\"\t\t\"222\"\n\t\"2\"\t\t\"1200\"\n}\n");
  // Steam's record: each of these is subscribed (ADR 0111).
  touch(lib.steamapps / "workshop" / "appworkshop_4000.acf", R"("AppWorkshop" { "appid" "4000"
      "WorkshopItemsInstalled" { "111" { "size" "1" "timeupdated" "1793000000" "manifest" "987" } "999" { "size" "1" }
        "1000" { "size" "1" } "1100" { "size" "1" } "1200" { "size" "1" } }
      "WorkshopItemDetails" { "999" { "subscribedby" "12345678" } "1000" { "subscribedby" "12345678,23456789" }
        "1100" { "subscribedby" "12345678" } "1200" { "subscribedby" "12345678" } } })");
  CHECK(nl::discovery::lists_native_manifest(lib.content / "1000" / "pbr.gma"));
  CHECK(!nl::discovery::lists_native_manifest(lib.content / "900" / "plain.gma"));
  CHECK(!nl::discovery::lists_native_manifest(lib.content / "111" / "runtime.gma"));  // not a GMAD archive
  CHECK(!nl::discovery::lists_native_manifest(lib.content / "nowhere.gma"));

  nl::config::Config config;
  config.workshop = {"111", "1000"};  // an allowlisted item is not listed again as content
  auto env = nl::discovery::environment_for(lib.game, dir / "no-steam");
  auto c = nl::discovery::discover(config, env);
  REQUIRE(c.size() == 3);
  CHECK(c[0].label == "111" && !c[0].content_only);
  CHECK(c[1].label == "1000" && !c[1].content_only);
  CHECK(c[2].label == "999" && c[2].content_only && c[2].problem.empty() && c[2].location.filename() == "another.gma");

  // Deployed content keeps a candidate: disabled (removed), gone from Steam (unsubscribed), installed.
  config.workshop = {"111"};
  env.deployed_workshop = {"111", "1200", "1400", "1000"};
  c = nl::discovery::discover(config, env);
  REQUIRE(c.size() == 5);
  CHECK(c[1].label == "999" && c[2].label == "1000" && c[3].label == "1200" && c[4].label == "1400");  // item order
  for (std::size_t i = 1; i < c.size(); ++i) CHECK(c[i].content_only);
  CHECK(c[2].problem.empty());
  CHECK(c[3].disabled_by_user);
  CHECK(c[4].unsubscribed);  // no folder, and Steam's record does not list it
  CHECK(c[4].problem.find("Steam no longer has the item") != std::string::npos);

  config.subscribed_content = false;
  c = nl::discovery::discover(config, env);
  REQUIRE(c.size() == 1);
  CHECK(c[0].label == "111");
  fs::remove_all(dir);
}

TEST_CASE("discovery: installed is not subscribed; only a subscription brings content (ADR 0111)") {
  const auto dir = nl::test::scratch_dir("discovery_downloaded");
  const FakeLibrary lib(dir);
  const auto package = [&](const std::string& item) {
    nl::test::FixtureArchive archive;
    archive.files.push_back({"native/manifest.json", "{}"});
    archive.files.push_back({"lua/autorun/x.lua", "-- x"});
    touch(lib.content / item / (item + ".gma"), nl::test::build_gma(archive));
  };
  // 2001 subscribed. 2002: what steamworks.DownloadUGC leaves (a server's client Lua may call it):
  // installed, details without subscribedby. 2003 "0". 2004 installed with no details at all. 2005 a
  // value Steam does not write. 2006 subscribed, still downloading (details only, no folder yet).
  for (const char* item : {"2001", "2002", "2003", "2004", "2005"}) package(item);
  const auto acf = lib.steamapps / "workshop" / "appworkshop_4000.acf";
  const std::string record = R"("AppWorkshop" { "appid" "4000"
      "WorkshopItemsInstalled" { "2001" { "size" "1" } "2002" { "size" "1" } "2003" { "size" "1" } "2004" { "size" "1" }
        "2005" { "size" "1" } }
      "WorkshopItemDetails" { "2001" { "subscribedby" "12345678" "timetouched" "1" }
        "2002" { "manifest" "5" "ugchandle" "6" "timeupdated" "7" "timetouched" "8" }
        "2003" { "subscribedby" "0" } "2005" { "subscribedby" "everyone" } "2006" { "subscribedby" "12345678" } } })";
  touch(acf, record);
  nl::config::Config config;  // nothing allowlisted
  auto env = nl::discovery::environment_for(lib.game, dir / "no-steam");
  auto c = nl::discovery::discover(config, env);
  REQUIRE(c.size() == 1);
  CHECK(c[0].label == "2001" && c[0].content_only && c[0].problem.empty() && !c[0].unsubscribed);

  // Deployed from items that are not subscribed (an older loader took them, or the user unsubscribed
  // and Steam keeps the files for now): removed like an unsubscribe, the reason says why.
  env.deployed_workshop = {"2001", "2002", "2003", "2004", "2005", "2006"};
  c = nl::discovery::discover(config, env);
  REQUIRE(c.size() == 6);
  for (const auto& candidate : c) CHECK(candidate.content_only);
  CHECK(c[0].label == "2001" && c[0].problem.empty() && !c[0].unsubscribed);
  for (std::size_t i = 1; i <= 3; ++i) {  // 2002, 2003, 2004
    CHECK(c[i].unsubscribed);
    CHECK(!c[i].disabled_by_user);
    CHECK(c[i].problem.find("only because the game or a server downloaded it") != std::string::npos);
    CHECK(c[i].location.empty());
  }
  CHECK(c[4].label == "2005" && c[4].problem.empty() && !c[4].unsubscribed);  // not understood: kept as it is
  CHECK(c[5].label == "2006" && !c[5].unsubscribed && c[5].problem.find("not installed") != std::string::npos);

  // The allowlist is unaffected: an allowlisted item needs no subscription.
  config.workshop = {"2002"};
  c = nl::discovery::discover(config, env);
  REQUIRE(!c.empty());
  CHECK(c[0].label == "2002" && !c[0].content_only && c[0].problem.empty() && !c[0].unsubscribed);
  config.workshop.clear();

  // Without Steam's record (missing, unreadable, or no details section) nothing is new content, and
  // what is deployed stays as it is: one bad read must not remove and redeploy packages.
  for (const std::string broken : {std::string(), std::string("\"AppWorkshop\" { broken"),
                                   std::string(R"("AppWorkshop" { "WorkshopItemsInstalled" { "2001" { "size" "1" } } })")}) {
    if (broken.empty()) fs::remove(acf);
    else touch(acf, broken);
    env.deployed_workshop.clear();
    CHECK(nl::discovery::discover(config, env).empty());
    env.deployed_workshop = {"2001", "2002", "2006"};
    c = nl::discovery::discover(config, env);
    REQUIRE(c.size() == 3);
    CHECK(c[0].label == "2001" && c[0].problem.empty() && !c[0].unsubscribed);
    CHECK(c[1].label == "2002" && c[1].problem.empty() && !c[1].unsubscribed);
    // No folder: kept while it may be downloading. A readable record that lists it nowhere is
    // still ADR 0025's unsubscribe.
    const bool record_lists_nothing = broken.rfind("\"AppWorkshop\" { \"Workshop", 0) == 0;
    CHECK(c[2].label == "2006" && c[2].unsubscribed == record_lists_nothing);
    if (!record_lists_nothing) CHECK(c[2].problem.find("not installed") != std::string::npos);
  }
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
