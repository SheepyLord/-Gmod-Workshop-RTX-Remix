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
  CHECK(c.subscribed_content);  // content-only packages from subscriptions, without listing them (ADR 0027)
  const nl::config::Config defaults;
  CHECK(!defaults.from_file);
  CHECK(defaults.workshop.empty());
}

TEST_CASE("config: allow.subscribed_content switches content packages from subscriptions off") {
  CHECK(!nl::config::parse(R"({"schema": 1, "allow": {"subscribed_content": false}})").subscribed_content);
  CHECK(nl::config::parse(R"({"schema": 1, "allow": {"subscribed_content": true, "workshop": ["1"]}})").subscribed_content);
  bool rejected = false;
  try {
    nl::config::parse(R"({"schema": 1, "allow": {"subscribed_content": "no"}})");
  } catch (const Error&) {
    rejected = true;
  }
  CHECK(rejected);
}

TEST_CASE("config: secure RTX renderer opt-out preserves the general insecure gate and allowlist") {
  const auto defaults = nl::config::parse(R"({"schema":1})");
  CHECK(defaults.allow_secure_rtx_render_patches);
  CHECK(defaults.patch_sets_require_insecure);
  const auto disabled = nl::config::parse(R"({"schema":1,"patch_sets":{"allow_rtx_render_patches":false}})");
  CHECK(!disabled.allow_secure_rtx_render_patches);
  CHECK(disabled.patch_sets_require_insecure);
  CHECK(disabled.workshop.empty() && disabled.local.empty() && disabled.dev_folders.empty());
  const auto enabled = nl::config::parse(R"({"schema":1,"patch_sets":{"require_insecure":true,"allow_rtx_render_patches":true}})");
  CHECK(enabled.allow_secure_rtx_render_patches);
  CHECK(enabled.patch_sets_require_insecure);
  const auto explicitPolicy = nl::config::parse(R"({"schema":1,"patch_sets":{"require_insecure":false,"allow_rtx_render_patches":false}})");
  CHECK(!explicitPolicy.allow_secure_rtx_render_patches);
  CHECK(!explicitPolicy.patch_sets_require_insecure);
}

TEST_CASE("config: secure RTX renderer permission must be a boolean with the exact key") {
  for (const char* text : {
    R"({"schema":1,"patch_sets":{"allow_rtx_render_patches":"false"}})",
    R"({"schema":1,"patch_sets":{"allow_rtx_render_patches":0}})",
    R"({"schema":1,"patch_sets":{"allow_rtx_render_patches":null}})",
    R"({"schema":1,"patch_sets":{"allow_render_patches":true}})"
  }) {
    CHECK_THROWS_AS(nl::config::parse(text), Error);
  }
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

TEST_CASE("config: performance tier defaults and overrides, invalid values recover with a note") {
  using nl::config::PerformanceTier;
  CHECK(nl::config::parse(R"({"schema":1})").performance_tier == PerformanceTier::automatic);
  for (const auto& [name, tier] : std::vector<std::pair<std::string, PerformanceTier>>{
         {"auto", PerformanceTier::automatic}, {"high", PerformanceTier::high},
         {"medium", PerformanceTier::medium}, {"low", PerformanceTier::low}}) {
    const auto config = nl::config::parse("{\"schema\":1,\"remix\":{\"performance_tier\":\"" + name + "\"}}");
    CHECK(config.performance_tier == tier);
    CHECK(config.notes.empty());
  }
  for (const char* invalid : {"\"LOW\"", "\"fast\"", "\"\"", "true", "null", "8", "[]", "{}"}) {
    const auto config = nl::config::parse(std::string("{\"schema\":1,\"remix\":{\"performance_tier\":") + invalid + "}}");
    CHECK(config.performance_tier == PerformanceTier::automatic);
    REQUIRE(config.notes.size() == 1);
    CHECK(config.notes.front().find("using auto") != std::string::npos);
  }
}

TEST_CASE("config: GPU crash dumps are opt-in with strict off next_start always modes") {
  using nl::config::GpuCrashDumps;
  CHECK(nl::config::parse(R"({"schema":1})").gpu_crash_dumps == GpuCrashDumps::off);
  for (const auto& [name, mode] : std::vector<std::pair<std::string, GpuCrashDumps>>{
         {"off", GpuCrashDumps::off}, {"next_start", GpuCrashDumps::next_start}, {"always", GpuCrashDumps::always}}) {
    CHECK(nl::config::parse("{\"schema\":1,\"diagnostics\":{\"gpu_crash_dumps\":\"" + name + "\"}}").gpu_crash_dumps == mode);
  }
  for (const char* invalid : {"\"on\"", "\"NEXT_START\"", "true", "null", "1"})
    CHECK_THROWS_AS(nl::config::parse(std::string("{\"schema\":1,\"diagnostics\":{\"gpu_crash_dumps\":") + invalid + "}}"), Error);
  CHECK_THROWS_AS(nl::config::parse(R"({"schema":1,"diagnostics":{"gpu_dump":"always"}})"), Error);
}
