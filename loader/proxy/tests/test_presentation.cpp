#include "presentation.h"
#include "diagnostics.h"
#include "catalog.h"

#include "gma_fixture.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/package.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <string>

namespace {
namespace p = nl::proxy::presentation;
namespace fs = std::filesystem;

constexpr std::string_view kMenu = "garrysmod/html/js/menu/control.Addons.js";

std::string menu_source() {
  return R"(function ControllerAddons( $scope ) {
  $scope.GetAddonClasses = function( file ) {
    var classes = [];
    if ( $scope.IsSubscribed( file ) ) {
      classes.push( $scope.IsEnabled( file ) ? "installed" : "disabled" );
      if ( subscriptions.GetInvalidReason( file.id ) ) classes.push( "invalid" );
    }
    if ( file.info && file.info.floating ) classes.push( "floating" );
    return classes.join( " " );
  }
  $scope.GetAddonDescription = function( file ) {
    var invalid = subscriptions.GetInvalidReason( file.id )
    if ( invalid ) return invalid;
    if ( !file.info ) return "ERROR?";
    return file.info.description
  }
})";
}

void write(const fs::path& path, const std::string& bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream(path, std::ios::binary) << bytes;
}

struct Setup {
  fs::path folder;
  fs::path root;
  fs::path archive;
  nl::journal::Generation generation;
};

Setup fixture(std::string_view name) {
  Setup result;
  result.folder = nl::test::scratch_dir(name);
  result.root = result.folder / "game";
  result.archive = result.folder / "workshop" / "content" / "4000" / "3829070317" / "native.gma";
  const std::string payload = "#usda 1.0\n";
  const std::string manifest = R"({"schema":1,"id":"native-display-test","version":"1.2.3","kinds":["root-files"],"files":{"native/root/rtx-remix/mods/display/mod.usda":{"size":)" +
      std::to_string(payload.size()) + R"(,"sha256":")" + nl::sha256::of(payload) +
      R"("}},"root_files":[{"path":"rtx-remix/mods/display"}]})";
  nl::test::FixtureArchive original;
  original.title = "Native test title";
  original.description = R"({"description":"Actual native description","type":"effects","tags":[]})";
  original.author = "Synthetic Author";
  original.files = {{"native/manifest.json", manifest}, {"native/root/rtx-remix/mods/display/mod.usda", payload}};
  write(result.archive, nl::test::build_gma(original));
  write(nl::fs::join(result.root, kMenu), menu_source());
  nl::journal::Package package;
  package.id = "native-display-test";
  package.version = "1.2.3";
  package.manifest_sha256 = nl::sha256::of(manifest);
  package.source = "workshop";
  package.location = nl::fs::utf8(result.archive);
  result.generation.packages.push_back(package);
  return result;
}

}  // namespace

TEST_CASE("main menu diagnostics contain hardware and package identity without private source paths") {
  nl::proxy::diagnostics::System system;
  system.os = "Windows x64";
  system.cpu = "CPU \"quoted\" <script>literal</script>\n";
  system.threads = 12;
  system.memory = 32ull << 30;
  system.graphics.push_back({"GPU", 8ull << 30});
  nl::journal::Generation generation;
  nl::journal::Package package;
  package.id = "example";
  package.version = "1.2.3+test";
  package.manifest_sha256 = std::string(64, 'a');
  package.location = "C:/private/location/not-for-display";
  generation.packages.push_back(package);
  const auto data = nl::proxy::diagnostics::serialize(system, "0.8.1", std::string(64, 'b'), generation);
  const auto parsed = nl::json::parse(data);
  CHECK(parsed.find("cpu")->as_string() == system.cpu);
  CHECK(parsed.find("threads")->as_int() == 12);
  CHECK(parsed.find("loader")->find("sha256")->as_string() == std::string(64, 'b'));
  CHECK(data.find("private/location") == std::string::npos);
  const std::string original = "function MenuController( $scope, $rootScope ) {}\n";
  const auto decorated = p::decorate_main_menu(original, data);
  CHECK(decorated.starts_with(original));
  CHECK(decorated.find("native-loader-diagnostics") != std::string::npos);
  CHECK_THROWS_AS(p::decorate_main_menu("changed menu", data), std::runtime_error);
  CHECK_THROWS_AS(p::decorate_main_menu(original, "{};unexpected()"), std::runtime_error);
  CHECK_THROWS_AS(p::decorate_main_menu(original, "[]"), std::runtime_error);
}

TEST_CASE("main menu diagnostics expose the same localized performance tier data as activation") {
  nl::proxy::diagnostics::System system;
  system.performance_tier = nl::performance::classify({{nl::performance::kNvidia, "RTX 4060 Ti", 16ull << 30}},
                                                     nl::config::PerformanceTier::automatic);
  system.performance_tier->source = "fallback";
  const auto data = nl::proxy::diagnostics::serialize(system, "0.10.1", "", {});
  const auto json = nl::json::parse(data);
  CHECK(json.find("performance_tier")->find("tier")->as_string() == "low");
  CHECK(json.find("performance_tier")->find("source")->as_string() == "fallback");
  const auto script = p::decorate_main_menu("function MenuController( $scope, $rootScope ) {}\n", data);
  CHECK(script.find("labels.performance_tier") != std::string::npos);
  CHECK(script.find("labels['tier_' + tier.source]") != std::string::npos);
}

TEST_CASE("main menu: the generated script is ASCII, non-ASCII text written as \\u escapes") {
  // R4: GMod's menu decoded the script as Windows-1252, so the panel's separator showed as "Â·" and the
  // translated labels as mojibake.
  nl::proxy::diagnostics::System system;
  system.os = "Windows x64";
  system.cpu = "CPU caf\xC3\xA9 \xE6\xB8\xB8 \xF0\x9F\x8E\xAE";  // é, 游, U+1F3AE
  system.threads = 8;
  system.graphics.push_back({"GPU", 8ull << 30});
  nl::journal::Generation generation;
  const auto data = nl::proxy::diagnostics::serialize(system, "0.10.1", std::string(64, 'b'), generation);
  const std::string original = "function MenuController( $scope, $rootScope ) {}\n";
  for (const auto& script : {p::decorate_main_menu(original, data, true), p::add_client_bootstrap(original)}) {
    CHECK(std::all_of(script.begin(), script.end(), [](char c) { return static_cast<unsigned char>(c) < 0x80; }));
  }
  const auto decorated = p::decorate_main_menu(original, data, true);
  CHECK(decorated.find("\\u00b7") != std::string::npos);  // the script's own separator
  CHECK(decorated.find("caf\\u00e9 \\u6e38 \\ud83c\\udfae") != std::string::npos);
  CHECK(decorated.starts_with(original));
}

TEST_CASE("main menu: the multiplayer bootstrap trigger does not depend on the overlay anchor") {
  nl::proxy::diagnostics::System system;
  const auto data = nl::proxy::diagnostics::serialize(system, "0.10.1", std::string(64, 'b'), {});
  const std::string original = "function MenuController( $scope, $rootScope ) {}\n";
  const auto overlay = p::decorate_main_menu(original, data, true);
  CHECK(overlay.find("window.NativeLoaderClientBootstrap = true;") != std::string::npos);
  CHECK(overlay.find("window.NativeLoaderDiagnostics = ") != std::string::npos);
  CHECK(p::decorate_main_menu(original, data).find("window.NativeLoaderClientBootstrap = false;") != std::string::npos);
  // A GMod update that moves the controller costs the overlay, never the trigger.
  const std::string changed = "function NewMenuController( $scope ) {}\n";
  CHECK_THROWS_AS(p::decorate_main_menu(changed, data, true), std::runtime_error);
  const auto trigger = p::add_client_bootstrap(changed);
  CHECK(trigger.starts_with(changed));
  CHECK(trigger.find("window.NativeLoaderClientBootstrap = true;") != std::string::npos);
  CHECK(trigger.find("require( \"nlrtxclient\" )") != std::string::npos);
  CHECK(trigger.find("window.NativeLoaderDiagnostics = ") == std::string::npos);
}

TEST_CASE("main menu: a changed menu still receives the trigger when the helper is deployed") {
  auto f = fixture("main_menu_bootstrap_only");
  const auto main = nl::fs::join(f.root, "garrysmod/html/js/menu/control.Menu.js");
  const std::string original = "function MovedMenuController( $scope ) {}\n";
  write(main, original);
  nl::journal::File helper;
  helper.path = std::string(nl::client::kModule);
  helper.package = std::string(nl::client::kPackage);
  helper.sha256 = std::string(64, 'c');
  helper.size = 1;
  f.generation.files.push_back(helper);
  const auto prepared = p::prepare(f.root, f.generation, true);
  REQUIRE(prepared.redirects.size() == 3);
  CHECK(prepared.redirects[2].source == main);
  REQUIRE(prepared.notes.size() == 1);
  CHECK(prepared.notes[0].find("bootstrap trigger is installed without it") != std::string::npos);
  const auto decorated = nl::fs::read_file(prepared.redirects[2].replacement, 131072);
  CHECK(decorated == p::add_client_bootstrap(original));
  CHECK(nl::fs::read_file(main, 65536) == original);
  // Without the helper there is nothing to trigger: the changed menu is left alone, as before.
  f.generation.files.pop_back();
  const auto plain = p::prepare(f.root, f.generation, true);
  CHECK(plain.redirects.size() == 2);
  REQUIRE(plain.notes.size() == 1);
  CHECK(plain.notes[0].find("diagnostics overlay not installed") != std::string::npos);
}

TEST_CASE("main menu diagnostics redirect only a generated copy and preserve the stock source") {
  auto f = fixture("main_menu_diagnostics");
  const auto main = nl::fs::join(f.root, "garrysmod/html/js/menu/control.Menu.js");
  const std::string original = "function MenuController( $scope, $rootScope ) {}\n";
  write(main, original);
  write(nl::fs::join(f.root, "bin/win64/winmm.dll"), "synthetic bootstrap");
  const auto prepared = p::prepare(f.root, f.generation, true);
  REQUIRE(prepared.notes.empty());
  REQUIRE(prepared.redirects.size() == 3);
  CHECK(prepared.redirects[2].source == main);
  CHECK(nl::fs::read_file(main, 65536) == original);
  const auto decorated = nl::fs::read_file(prepared.redirects[2].replacement, 131072);
  CHECK(decorated.find(nl::sha256::of("synthetic bootstrap")) != std::string::npos);
}

TEST_CASE("presentation: archive preserves metadata and contains only one inert whitelisted JSON file") {
  nl::gma::Index original;
  original.steamid = 12345;
  original.timestamp = 1700000001;
  original.title = "RTX package";
  original.description = R"({"description":"Header description","type":"effects","tags":[]})";
  original.author = "Author";
  original.addon_version = 8;
  nl::journal::Package package;
  package.id = "test-package";
  package.version = "1.2.3";
  const std::string bytes = p::make_archive(original, package, "3829070317");
  nl::gma::MemorySource source(bytes);
  const auto verified = nl::gma::verify(source);
  CHECK(verified.ok());
  CHECK(verified.crc_trailer);
  CHECK(verified.addon_crc_stored != 0);
  CHECK(verified.index.version == 3);
  CHECK(verified.index.title == original.title);
  CHECK(verified.index.description == original.description);
  CHECK(verified.index.author == original.author);
  CHECK(verified.index.timestamp == original.timestamp);
  CHECK(verified.index.steamid == original.steamid);
  CHECK(verified.index.addon_version == original.addon_version);
  REQUIRE(verified.index.entries.size() == 1);
  const auto& entry = verified.index.entries[0];
  CHECK(entry.path == "data_static/native-loader/packages/3829070317.json");
  const auto metadata = nl::json::parse(bytes.substr(static_cast<std::size_t>(entry.offset), static_cast<std::size_t>(entry.size)));
  CHECK(metadata.find("package")->as_string() == package.id);
  CHECK(metadata.find("version")->as_string() == package.version);
  CHECK(metadata.find("workshop_item")->as_string() == "3829070317");
  CHECK(metadata.find("managed_by")->as_string() == "native-loader");
  CHECK(bytes.find("native/manifest.json") == std::string::npos);
  CHECK_THROWS_AS(p::make_archive(original, package, "3\";bad()"), std::runtime_error);
}

TEST_CASE("presentation: menu targets exact numeric IDs and preserves normal metadata and classes") {
  const std::string decorated = p::decorate_menu(menu_source(), {"3829070317", "3829275998", "3829070317"});
  CHECK(decorated.find("Object.freeze({\"3829070317\":true,\"3829275998\":true})") != std::string::npos);
  CHECK(decorated.find("classes.push( \"nl-native\" )") != std::string::npos);
  CHECK(decorated.find("!nativeLoaderPackage && subscriptions.GetInvalidReason( file.id )") != std::string::npos);
  CHECK(decorated.find("invalid && !NativeLoaderManagedAddon( file )") != std::string::npos);
  CHECK(decorated.find("return file.info.description") != std::string::npos);
  CHECK(decorated.find("? \"installed\" : \"disabled\"") != std::string::npos);
  CHECK(decorated.find("classes.push( \"floating\" )") != std::string::npos);
  CHECK(decorated.find("#2387ed") != std::string::npos);
  CHECK_THROWS_AS(p::decorate_menu(menu_source(), {"3829070317);alert(1)"}), std::runtime_error);
  CHECK_THROWS_AS(p::decorate_menu(menu_source(), {"0"}), std::runtime_error);
  CHECK_THROWS_AS(p::decorate_menu(menu_source(), {}), std::runtime_error);
}

TEST_CASE("presentation: changed stock menu markers refuse a partial override") {
  CHECK_THROWS_AS(p::decorate_menu("different implementation", {"3829070317"}), std::runtime_error);
  CHECK_THROWS_AS(p::decorate_menu(menu_source() + "\nvar classes = [];", {"3829070317"}), std::runtime_error);
  std::string changed = menu_source();
  changed.replace(changed.find("if ( invalid ) return invalid;"), std::string("if ( invalid ) return invalid;").size(), "return 'new';");
  CHECK_THROWS_AS(p::decorate_menu(changed, {"3829070317"}), std::runtime_error);
}

TEST_CASE("presentation: prepare redirects only a matching deployed Workshop source and stock menu") {
  const auto f = fixture("presentation_prepare");
  const auto archive_before = nl::fs::hash_file(f.archive).sha256;
  const auto menu_before = nl::fs::read_file(nl::fs::join(f.root, kMenu), 65536);
  const auto prepared = p::prepare(f.root, f.generation);
  CHECK(prepared.notes.empty());
  REQUIRE(prepared.redirects.size() == 2);
  CHECK(prepared.redirects[0].source == f.archive);
  CHECK(prepared.redirects[0].workshop_item == "3829070317");
  CHECK(prepared.redirects[1].source == nl::fs::join(f.root, kMenu));
  CHECK(prepared.redirects[1].workshop_item.empty());
  CHECK(nl::fs::hash_file(f.archive).sha256 == archive_before);
  CHECK(nl::fs::read_file(nl::fs::join(f.root, kMenu), 65536) == menu_before);
  {
    nl::gma::FileSource display(prepared.redirects[0].replacement);
    CHECK(nl::gma::verify(display).ok());
  }
  CHECK(p::prepare(f.root, f.generation).notes.empty());
  fs::remove_all(f.folder);
}

TEST_CASE("presentation: unrecognized sources and mismatched deployed identities keep original behavior") {
  auto f = fixture("presentation_mismatch");
  f.generation.packages[0].source = "local";
  CHECK(p::prepare(f.root, f.generation).redirects.empty());
  f.generation.packages[0].source = "workshop";
  f.generation.packages[0].manifest_sha256 = std::string(64, '0');
  auto rejected = p::prepare(f.root, f.generation);
  CHECK(rejected.redirects.empty());
  CHECK(!rejected.notes.empty());
  f.generation.packages[0].location = nl::fs::utf8(f.folder / "outside.gma");
  CHECK(p::prepare(f.root, f.generation).redirects.empty());
  f.generation.packages[0].location = "workshop/content/4000/3829070317/native.gma";
  CHECK(p::prepare(f.root, f.generation).redirects.empty());
  fs::remove_all(f.folder);
}

TEST_CASE("presentation: changed menu source leaves the depot and archive behavior intact") {
  const auto f = fixture("presentation_new_menu");
  write(nl::fs::join(f.root, kMenu), "new menu implementation");
  const auto prepared = p::prepare(f.root, f.generation);
  REQUIRE(prepared.redirects.size() == 1);
  CHECK(!prepared.notes.empty());
  CHECK(nl::fs::read_file(nl::fs::join(f.root, kMenu), 65536) == "new menu implementation");
  fs::remove_all(f.folder);
}

TEST_CASE("presentation: modified content-addressed caches are preserved and refused") {
  const auto f = fixture("presentation_cache_edit");
  const auto first = p::prepare(f.root, f.generation);
  REQUIRE(first.redirects.size() == 2);
  write(first.redirects[0].replacement, "user edit");
  const auto next = p::prepare(f.root, f.generation);
  CHECK(next.redirects.empty());
  CHECK(!next.notes.empty());
  CHECK(nl::fs::read_file(first.redirects[0].replacement, 65536) == "user edit");
  fs::remove_all(f.folder);
}
