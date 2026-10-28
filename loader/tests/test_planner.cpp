#include "nl/manifest.h"
#include "nl/planner.h"
#include "nl_test.h"

#include <memory>
#include <string>
#include <vector>

using nl::discovery::Source;
using nl::planner::Considered;

namespace {

const std::string kSha(64, 'a');

// A package with the given id and kinds; runtimes get a remix section, root files one mod folder.
std::shared_ptr<const nl::package::Package> package(const std::string& id, bool runtime, const std::string& mod = "",
                                                    const std::string& requires_loader = "") {
  std::string kinds, files, extra;
  if (runtime) {
    kinds = "\"remix-runtime\"";
    files = "\"native/payload/d3d9.dll\": {\"size\": 1, \"sha256\": \"" + kSha + "\"}";
    extra = ", \"remix\": {\"entry\": \"d3d9.dll\"}";
  }
  if (!mod.empty()) {
    kinds += std::string(kinds.empty() ? "" : ", ") + "\"root-files\"";
    files += std::string(files.empty() ? "" : ", ") + "\"native/root/rtx-remix/mods/" + mod + "/mod.usda\": {\"size\": 1, \"sha256\": \"" + kSha + "\"}";
    extra += ", \"root_files\": [{\"path\": \"rtx-remix/mods/" + mod + "\"}]";
  }
  if (!requires_loader.empty()) extra += ", \"requires_loader\": \">=" + requires_loader + "\"";
  const std::string text = "{\"schema\": 1, \"id\": \"" + id + "\", \"version\": \"1.0.0\", \"kinds\": [" + kinds +
                           "], \"files\": {" + files + "}" + extra + "}";
  auto p = std::make_shared<nl::package::Package>();
  p->manifest = nl::manifest::parse(text);
  return p;
}

Considered item(Source source, const std::string& label, std::shared_ptr<const nl::package::Package> pkg,
                const std::string& problem = "") {
  Considered c;
  c.candidate.source = source;
  c.candidate.label = label;
  c.package = std::move(pkg);
  c.problem = problem;
  return c;
}

const nl::manifest::Version kLoader = *nl::manifest::parse_version("0.2.0");

}  // namespace

TEST_CASE("planner: problems, versions and the disabled switch skip candidates") {
  nl::config::Config config;
  const std::vector<Considered> items = {
      item(Source::local, "broken.gma", nullptr, "not a native package: no native/manifest.json"),
      item(Source::local, "future.gma", package("future", false, "future_mod", "9.0.0")),
      item(Source::local, "ok.gma", package("ok", false, "ok_mod", "0.1.0")),
  };
  const auto plan = nl::planner::make_plan(items, config, kLoader);
  REQUIRE(plan.decisions.size() == 3);
  CHECK(!plan.decisions[0].active);
  CHECK(plan.decisions[0].reason.find("no native/manifest.json") != std::string::npos);
  CHECK(!plan.decisions[1].active);
  CHECK(plan.decisions[1].reason.find("needs loader >=9.0.0") != std::string::npos);
  CHECK(plan.decisions[2].active);

  config.enabled = false;
  const auto off = nl::planner::make_plan(items, config, kLoader);
  for (const auto& d : off.decisions) CHECK(!d.active && d.reason.find("disabled") != std::string::npos);
}

TEST_CASE("planner: a higher-precedence source shadows the same id") {
  const std::vector<Considered> items = {
      item(Source::dev_folder, "D:/dev/rt", package("rtx-remix-runtime", true)),
      item(Source::workshop, "3600000000", package("rtx-remix-runtime", true)),
  };
  const auto plan = nl::planner::make_plan(items, nl::config::Config{}, kLoader);
  CHECK(plan.decisions[0].active);
  CHECK(plan.decisions[0].activate_runtime);
  CHECK(!plan.decisions[1].active);
  CHECK(plan.decisions[1].reason.find("shadowed by dev_folder") != std::string::npos);
  REQUIRE(plan.runtime() != nullptr);
  CHECK(plan.runtime()->item.candidate.label == "D:/dev/rt");
}

TEST_CASE("planner: a broken higher-precedence copy does not block a working one") {
  const std::vector<Considered> items = {
      item(Source::dev_folder, "D:/dev/rt", nullptr, "manifest: missing \"version\""),
      item(Source::workshop, "3600000000", package("rtx-remix-runtime", true)),
  };
  const auto plan = nl::planner::make_plan(items, nl::config::Config{}, kLoader);
  CHECK(!plan.decisions[0].active);
  CHECK(plan.decisions[1].active);
}

TEST_CASE("planner: only one remix-runtime package is active") {
  const std::vector<Considered> items = {
      item(Source::local, "a.gma", package("runtime-a", true)),
      item(Source::workshop, "1", package("runtime-b", true)),
  };
  const auto plan = nl::planner::make_plan(items, nl::config::Config{}, kLoader);
  CHECK(plan.decisions[0].active);
  CHECK(!plan.decisions[1].active);
  CHECK(plan.decisions[1].reason.find("only one remix-runtime") != std::string::npos);
}

TEST_CASE("planner: overlapping root files are refused") {
  const std::vector<Considered> items = {
      item(Source::local, "a.gma", package("mods-a", false, "base_mod")),
      item(Source::local, "b.gma", package("mods-b", false, "base_mod")),
      item(Source::local, "c.gma", package("mods-c", false, "other_mod")),
  };
  const auto plan = nl::planner::make_plan(items, nl::config::Config{}, kLoader);
  CHECK(plan.decisions[0].active);
  CHECK(!plan.decisions[1].active);
  CHECK(plan.decisions[1].reason.find("overlaps") != std::string::npos);
  CHECK(plan.decisions[2].active);
}

TEST_CASE("planner: remix.enabled false keeps the package but does not load the runtime") {
  nl::config::Config config;
  config.remix_enabled = false;
  const auto plan = nl::planner::make_plan({item(Source::local, "a.gma", package("runtime", true))}, config, kLoader);
  CHECK(plan.decisions[0].active);
  CHECK(!plan.decisions[0].activate_runtime);
  CHECK(plan.decisions[0].reason.find("remix.enabled") != std::string::npos);
}
