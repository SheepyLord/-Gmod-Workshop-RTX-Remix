#include "nl/config.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <string>

using nl::config::Error;

TEST_CASE("config: a full config.json parses") {
  const auto c = nl::config::parse(R"({
    "schema": 1,
    "enabled": true,
    "allow": {"workshop": ["3600000000", "104486597"], "local": ["garrysmod/addons/runtime.gma"], "dev_folders": ["D:/dev/pkg"]},
    "remix": {"enabled": false},
    "patch_sets": {"require_insecure": true}
  })");
  CHECK(c.from_file);
  CHECK(c.enabled);
  REQUIRE(c.workshop.size() == 2);
  CHECK(c.workshop[0] == "3600000000");
  CHECK(c.local.size() == 1);
  CHECK(c.dev_folders.size() == 1);
  CHECK(!c.remix_enabled);
  CHECK(c.patch_sets_require_insecure);
}

TEST_CASE("config: only the schema is required; defaults allow nothing") {
  const auto c = nl::config::parse(R"({"schema": 1})");
  CHECK(c.enabled);
  CHECK(c.workshop.empty() && c.local.empty() && c.dev_folders.empty());
  CHECK(c.remix_enabled);
  const nl::config::Config defaults;
  CHECK(!defaults.from_file);
  CHECK(defaults.workshop.empty());
}

TEST_CASE("config: typos and unsafe values are errors") {
  const char* bad[] = {
      "",                                                         // not JSON
      "[]",                                                       // not an object
      R"({})",                                                    // no schema
      R"({"schema": 2})",
      R"({"schema": 1, "alow": {}})",                             // typo at the top
      R"({"schema": 1, "allow": {"workshops": []}})",             // typo in allow
      R"({"schema": 1, "allow": {"workshop": [3600000000]}})",   // number, not string
      R"({"schema": 1, "allow": {"workshop": ["12ab"]}})",
      R"({"schema": 1, "allow": {"workshop": ["0123"]}})",
      R"({"schema": 1, "allow": {"workshop": ["1", "1"]}})",
      R"({"schema": 1, "allow": {"local": [""]}})",
      R"({"schema": 1, "enabled": "yes"})",
      R"({"schema": 1, "remix": {"enable": true}})",
  };
  for (const char* text : bad) {
    bool rejected = false;
    try {
      nl::config::parse(text);
    } catch (const Error&) {
      rejected = true;
    }
    if (!rejected) nl::test::fail(text, __FILE__, __LINE__);
  }
}

TEST_CASE("config: load reads native-loader/config.json or falls back to defaults") {
  const auto root = nl::test::scratch_dir("config_load");
  CHECK(!nl::config::load(root).from_file);
  std::filesystem::create_directories(root / "native-loader");
  std::ofstream(root / "native-loader" / "config.json") << R"({"schema": 1, "allow": {"workshop": ["42"]}})";
  const auto c = nl::config::load(root);
  CHECK(c.from_file);
  REQUIRE(c.workshop.size() == 1);
  CHECK(c.workshop[0] == "42");
  std::ofstream(root / "native-loader" / "config.json") << "{broken";
  CHECK_THROWS_AS(nl::config::load(root), Error);
  std::filesystem::remove_all(root);
}
