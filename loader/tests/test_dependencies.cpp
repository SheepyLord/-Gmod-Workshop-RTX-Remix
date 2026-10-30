// Module dependencies (loader 0.3.0, ADR 0024): files a package's binary module needs loaded before
// it, kept in the journal and applied in every session. The manifest rules are in test_manifest.cpp.
#include "nl/activate.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/manifest.h"
#include "nl/session.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <optional>
#include <string>

namespace {

const std::string kSha(64, 'a');

void write_file(const std::filesystem::path& file, const std::string& bytes) {
  std::filesystem::create_directories(file.parent_path());
  std::ofstream(file, std::ios::binary | std::ios::trunc) << bytes;
}

nl::journal::Package package(const std::string& id, std::vector<nl::manifest::ModuleDependency> dependencies) {
  nl::journal::Package p;
  p.id = id;
  p.version = "1.0.0";
  p.manifest_sha256 = kSha;
  p.source = "local";
  p.location = "C:/" + id + ".gma";
  p.module_dependencies = std::move(dependencies);
  return p;
}

const std::string kClient = "garrysmod/lua/bin/gmcl_mmdhl_win64.dll";
const std::string kServer = "garrysmod/lua/bin/gmsv_mmdhl_win64.dll";
const std::string kRuntime = "garrysmod/lua/bin/mmdhl_runtime_win64.dll";

}  // namespace

TEST_CASE("dependencies: the journal keeps them, written only when there are some") {
  nl::journal::Journal journal;
  journal.loader = "0.3.0";
  journal.next = 2;
  journal.current = nl::journal::Generation{1, {package("hotloader", {{kClient, {kRuntime}}, {kServer, {kRuntime}}})}, {}};
  const auto text = nl::journal::serialize(journal);
  CHECK(text.find("\"module_dependencies\"") != std::string::npos);
  const auto back = nl::journal::parse(text);
  REQUIRE(back.current && back.current->packages[0].module_dependencies.size() == 2);
  CHECK(back.current->packages[0].module_dependencies[1].module == kServer);
  CHECK(back.current->packages[0].module_dependencies[1].load_first == std::vector<std::string>{kRuntime});
  CHECK(nl::journal::serialize(back) == text);

  journal.current->packages[0].module_dependencies.clear();
  const auto plain = nl::journal::serialize(journal);
  CHECK(plain.find("module_dependencies") == std::string::npos);  // journals of older loaders stay as they were
  CHECK(nl::journal::parse(plain).current->packages[0].module_dependencies.empty());

  // A journal that names files outside garrysmod/lua/bin, or none, is refused.
  for (const auto& [from, to] : {std::pair{kRuntime, std::string("garrysmod/addons/x/runtime.dll")},
                                 std::pair{kRuntime, std::string("../runtime.dll")},
                                 std::pair{"[\"" + kRuntime + "\"]", std::string("[]")}}) {
    std::string bad = text;
    bad.replace(bad.find(from), from.size(), to);
    CHECK_THROWS_AS(nl::journal::parse(bad), nl::journal::Error);
  }
}

TEST_CASE("dependencies: one entry per module across packages, lists joined without repeats") {
  nl::journal::Generation generation{1, {}, {}};
  generation.packages.push_back(package("hotloader", {{kClient, {kRuntime}}}));
  generation.packages.push_back(package("other", {{"garrysmod/lua/bin/GMCL_MMDHL_win64.dll", {"garrysmod/lua/bin/MMDHL_runtime_win64.dll",
                                                                                              "garrysmod/lua/bin/extra.dll"}},
                                                  {kServer, {kRuntime}}}));
  const auto merged = nl::session::module_dependencies(generation);
  REQUIRE(merged.size() == 2);
  CHECK(merged[0].module == kClient);  // the first package's spelling
  CHECK(merged[0].load_first == (std::vector<std::string>{kRuntime, "garrysmod/lua/bin/extra.dll"}));
  CHECK(merged[1].module == kServer);
  CHECK(nl::session::module_dependencies(nl::journal::Generation{1, {package("none", {})}, {}}).empty());
}

TEST_CASE("dependencies: an RTX session's plan carries them; a plan that does not activate does not") {
  nl::journal::Package runtime = package("runtime", {{kClient, {kRuntime}}});
  runtime.payload = "native-loader/packages/runtime/1.0.0_1";
  runtime.remix = nl::manifest::Remix{};
  runtime.remix->entry = "runtime/d3d9.dll";
  nl::journal::Generation generation{1, {runtime}, {}};
  nl::config::Config config;
  const auto none = [](const std::string&) -> std::optional<std::string> { return std::nullopt; };
  const auto screen = [] { return nl::activate::Display{1920, 1080}; };
  const auto plan = nl::activate::plan(generation, config, none, L"gmod.exe", screen);
  REQUIRE(plan.activate);
  REQUIRE(plan.module_dependencies.size() == 1);
  CHECK(plan.module_dependencies[0].load_first == std::vector<std::string>{kRuntime});
  // Without RTX the start-up code installs them from the journal itself (proxy startup.cpp).
  config.remix_enabled = false;
  CHECK(nl::activate::plan(generation, config, none, L"gmod.exe", screen).module_dependencies.empty());
}

TEST_CASE("dependencies: only a file as the deployer left it is loaded first (R3-001)") {
  const auto dir = nl::test::scratch_dir("dependencies_deployed");
  const auto root = dir / "game";
  write_file(root / "garrysmod" / "lua" / "bin" / "mmdhl_runtime_win64.dll", "MZ-runtime");
  write_file(root / "garrysmod" / "lua" / "bin" / "extra.dll", "MZ-extra");
  const auto stat = [&](const std::string& relative) { return nl::fs::stat(nl::fs::join(root, relative)); };
  nl::journal::Generation generation{1, {package("hotloader", {{kClient, {kRuntime}}})}, {}};
  generation.files.push_back({kRuntime, "hotloader", kSha, stat(kRuntime).size, stat(kRuntime).mtime, false});

  std::vector<std::string> notes;
  const std::vector<std::string> wanted{kRuntime, "garrysmod/lua/bin/extra.dll"};
  CHECK(nl::session::deployed_files(generation, root, wanted, notes) == std::vector<std::string>{kRuntime});
  REQUIRE(notes.size() == 1);
  CHECK(notes[0].find("did not deploy it") != std::string::npos);  // extra.dll is no file of the journal's

  notes.clear();
  write_file(root / "garrysmod" / "lua" / "bin" / "mmdhl_runtime_win64.dll", "MZ-runtime, replaced");
  CHECK(nl::session::deployed_files(generation, root, {kRuntime}, notes).empty());
  REQUIRE(notes.size() == 1);
  CHECK(notes[0].find("changed since the loader deployed it") != std::string::npos);
  std::error_code ec;
  std::filesystem::remove_all(dir, ec);
}
