#include "runtime.h"
#include "nl/activate.h"
#include "nl/fs.h"
#include "nl_test.h"
#include <algorithm>
#include <filesystem>
#include <fstream>

namespace {
namespace fs = std::filesystem;

struct Fixture {
  fs::path root = nl::test::scratch_dir("rt_fallback");
  fs::path previous = fs::current_path();
  nl::journal::Generation generation;
  Fixture() {
    nl::journal::Package package;
    package.id = "runtime";
    package.version = "1.0.0";
    package.payload = "payload";
    package.remix = nl::manifest::Remix{};
    package.remix->entry = "d3d9.dll";
    package.remix->prefer_system_vulkan_loader = false;
    generation.packages.push_back(package);
    fs::create_directories(root / "payload");
    for (const char* name : {"d3d9.dll", "nl_m4_static.dll", "nl_m4_delay.dll"}) {
      const std::string relative = std::string("payload/") + name;
      const auto path = nl::fs::join(root, relative);
      fs::copy_file(fs::path(NL_RUNTIME_FIXTURE_DIR) / name, path);
      const auto info = nl::fs::stat(path);
      nl::journal::File record;
      record.package = package.id;
      record.path = relative;
      record.size = info.size;
      record.mtime = info.mtime;
      generation.files.push_back(record);
    }
    fs::create_directories(root / "native-loader/remix");
    const auto menu = root / "garrysmod/html/js/menu/control.Menu.js";
    fs::create_directories(menu.parent_path());
    std::ofstream(menu) << "function MenuController( $scope, $rootScope ) {}\n";
    fs::current_path(root);
  }
  ~Fixture() {
    fs::current_path(previous);
    SetFileAttributesW((root / nl::activate::kTierLayer).c_str(), FILE_ATTRIBUTE_NORMAL);
    std::error_code ignored;
    fs::remove_all(root, ignored);
  }
  nl::activate::Plan plan(nl::config::GpuCrashDumps mode = nl::config::GpuCrashDumps::off) const {
    nl::config::Config config;
    config.performance_tier = nl::config::PerformanceTier::low;
    config.gpu_crash_dumps = mode;
    // No GPU reader deliberately: exercises the unknown-GPU override on every test machine.
    return nl::activate::plan(generation, config, [](const auto&) { return std::optional<std::string>{}; },
                              L"gmod.exe -windowed", [] { return nl::activate::Display{}; });
  }
};
}  // namespace

TEST_CASE("runtime: failed low fallback writes preserve RTX and never list a stale tier") {
  for (bool read_only : {false, true}) {
    Fixture fixture;
    const auto tier = fixture.root / nl::activate::kTierLayer;
    if (read_only) {
      std::ofstream(tier, std::ios::binary) << "rtx.skyProbeSide = 999\n";
      REQUIRE(SetFileAttributesW(tier.c_str(), FILE_ATTRIBUTE_READONLY));
    } else fs::create_directory(tier);  // a directory blocks the generated file
    nl::status::Activation report;
    report.plan = fixture.plan();
    REQUIRE(report.plan.low_tier_fallback);
    nl::status::Session session;
    nl::proxy::RuntimeActivation activation;
    CHECK(activation.apply(fixture.root, fixture.generation, report, session));
    CHECK(report.outcome == "active");
    CHECK(report.plan.performance_tier.layer.empty());
    CHECK(std::find(report.plan.dxvk_layers.begin(), report.plan.dxvk_layers.end(), nl::activate::kTierLayer) == report.plan.dxvk_layers.end());
    const auto value = nl::activate::environment_value("DXVK_CONFIG_FILE");
    REQUIRE(value);
    CHECK(value->find("tier.conf") == std::string::npos);
    CHECK(std::any_of(report.plan.notes.begin(), report.plan.notes.end(), [](const auto& note) {
      return note.find("built-in low-tier Remix layer was not written") != std::string::npos;
    }));
    if (read_only) CHECK(nl::fs::read_file(tier, 4096) == "rtx.skyProbeSide = 999\n");
    else CHECK(fs::is_directory(tier));
    // The generated view must use the effective plan after the failed write, not the preview.
    const auto cache = nl::fs::list(fixture.root / "native-loader/presentation");
    REQUIRE(cache.size() == 1);
    CHECK(nl::fs::read_file(fixture.root / "native-loader/presentation" / cache.front().name, 1 << 20)
            .find("\"performance_tier\":null") != std::string::npos);
  }
}

TEST_CASE("runtime: a failed off-mode rearm leaves RTX active and reports the marker") {
  Fixture fixture;
  const auto marker = fixture.root / nl::gpu_diagnostics::kUsed;
  fs::create_directory(marker);
  std::ofstream(marker / "keep.txt") << "keep";
  nl::status::Activation report;
  report.plan = fixture.plan();
  nl::status::Session session;
  nl::proxy::RuntimeActivation activation;
  CHECK(activation.apply(fixture.root, fixture.generation, report, session));
  CHECK(report.outcome == "active");
  CHECK(nl::fs::read_file(marker / "keep.txt", 4096) == "keep");
  CHECK(std::any_of(session.notes.begin(), session.notes.end(), [](const auto& note) {
    return note.find("next_start was not rearmed") != std::string::npos;
  }));
}
