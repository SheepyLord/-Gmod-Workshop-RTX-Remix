#include "catalog.h"
#include "nl/fs.h"
#include "nl/paths.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
namespace fs = std::filesystem;
using nl::client::kModule;
using nl::client::kPackage;
constexpr std::string_view kClient = "garrysmod/addons/nativeloader/lua/autorun/client/owned.lua";

void write(const fs::path& path, std::string_view bytes) {
  fs::create_directories(path.parent_path());
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!stream) throw std::runtime_error("cannot write catalog fixture");
}

struct Fixture {
  fs::path folder;
  fs::path root;
  nl::config::Config config;
  nl::journal::Generation generation;

  explicit Fixture(std::string_view name) : folder(nl::test::scratch_dir(name)), root(folder / "game") {
    fs::create_directories(root);
    config.from_file = true;
    config.local = {"native-package.gma"};
    nl::journal::Package package;
    package.id = kPackage;
    package.version = "1.2.3+fixture";
    package.manifest_sha256 = std::string(64, 'a');
    package.source = "local";
    package.location = "native-package.gma";
    package.payload = "native-loader/packages/gmod-rtx-remix/fixture_1";
    package.requires_remix = true;
    nl::manifest::Remix remix;
    remix.entry = "runtime/d3d9.dll";
    package.remix = remix;
    generation.number = 1;
    generation.packages.push_back(package);
    add(std::string(kModule), "verified native bootstrap");
    add(std::string(kClient), "OWNED_CLIENT = true\n");
  }
  ~Fixture() {
    try { nl::fs::remove_tree(nl::fs::win32(), folder); } catch (...) { }
  }
  void add(std::string path, std::string_view bytes, std::string owner = std::string(kPackage)) {
    write(nl::fs::join(root, path), bytes);
    nl::journal::File file;
    file.path = std::move(path);
    file.package = std::move(owner);
    file.sha256 = nl::sha256::of(bytes);
    file.size = bytes.size();
    generation.files.push_back(std::move(file));
  }
  nl::client::Catalog prepare() const { return nl::client::prepare(root, config, generation); }
  nl::journal::Package& package() { return generation.packages.front(); }
};

bool junction(const fs::path& path, const fs::path& target) {
  const std::string command = "cmd /c mklink /J \"" + path.string() + "\" \"" + target.string() + "\" >nul";
  return std::system(command.c_str()) == 0;
}

std::vector<nl::manifest::PatchSet> renderer_recipes() {
  // The shipped seven rendering fixes, grouped as tools/package_fixes.py emits them.
  // These are independent fixture specs, not the policy's accepted digest strings.
  return {
    {"engine.dll", {
      {"mod_loadlighting_hdr", "ff90????????85c0742b", 0, "b80200000090"},
      {"mod_loadworldlights_hdr", "ff90????????85c00f84fa000000", 0, "b80200000090"}}},
    {"shaderapidx9.dll", {
      {"zero_size_buffer_returns_4", "4833cce8????03004881c448", 0, "85c0750466b80400"},
      {"shader_constants_return_0", "4883ec084c", 0, "31c0c3"},
      {"skip_invalid_vertex_format_error", "4885db75??498b4500", 3, "eb"}}},
    {"materialsystem.dll", {
      {"zero_size_buffer_guard", "f77c24683bc10f4fc1488b8c24300100004833cce8????04004881c448010000", 0,
       "448b4424684585c0740341f7f839c80f4fc14881c448010000c3"}}},
    {"datacache.dll", {
      {"dx80_vtx_to_dx90_vtx", "647838302e767478", 0, "647839302e767478"}}}
  };
}
}

TEST_CASE("client catalog: exact local RTX owner produces canonical immutable source") {
  Fixture f("client_catalog_local");
  const auto catalog = f.prepare();
  REQUIRE(catalog.scripts.size() == 1);
  const auto found = catalog.scripts.find("nativeloader/autorun/client/owned.lua");
  REQUIRE(found != catalog.scripts.end());
  CHECK(found->second.addon == "nativeloader");
  CHECK(found->second.path == "autorun/client/owned.lua");
  CHECK(found->second.text == "OWNED_CLIENT = true\n");
  CHECK(catalog.identity == std::string(64, 'a'));
  CHECK(catalog.runtime == "native-loader/packages/gmod-rtx-remix/fixture_1/runtime/d3d9.dll");
  write(nl::fs::join(f.root, kClient), "REPLACED_CLIENT=true\n");
  CHECK(found->second.text == "OWNED_CLIENT = true\n");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: local and dev-folder allowlists do not authorize one another") {
  Fixture f("client_catalog_source_lists");
  const auto absolute = nl::fs::utf8(f.root / "native-package.gma");
  f.config.local = {absolute};
  CHECK(f.prepare().scripts.size() == 1);
  f.package().source = "dev_folder";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.config.dev_folders = {absolute};
  CHECK(f.prepare().scripts.size() == 1);
  f.config.local.clear();
  f.package().source = "local";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().source = "dev_folder";
  f.config.dev_folders = {"other-package"};
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: only the configured RTX Workshop item is authorized") {
  Fixture f("client_catalog_workshop");
  f.package().source = "workshop";
  f.package().location = nl::fs::utf8(f.folder / "workshop/content/4000/3829070317/package.gma");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.config.workshop = {"3829070317"};
  CHECK(f.prepare().scripts.size() == 1);
  f.package().location = nl::fs::utf8(f.folder / "workshop/content/4000/1111111111/package.gma");
  f.config.workshop.push_back("1111111111");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().location = nl::fs::utf8(f.folder / "workshop/content/9999/3829070317/package.gma");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().location = nl::fs::utf8(f.folder / "unrelated/4000/3829070317/package.gma");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().location = "workshop/content/4000/3829070317/package.gma";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: community ownership and non-addon code are not imported") {
  Fixture f("client_catalog_community");
  // Missing foreign files are deliberately not opened, including one with the same virtual path.
  nl::journal::File foreign;
  foreign.path = "garrysmod/addons/community/lua/autorun/client/owned.lua";
  foreign.package = "community-package";
  foreign.sha256 = std::string(64, 'b');
  foreign.size = 100;
  f.generation.files.push_back(foreign);
  foreign.path = "garrysmod/addons/nativeloader/lua/autorun/client/unrelated.lua";
  f.generation.files.push_back(foreign);
  f.add("garrysmod/data/community/autorun.lua", "DATA_CODE=true\n");
  f.add("rtx-remix/mods/community/script.lua", "MOD_CODE=true\n");
  f.add("garrysmod/addons/nativeloader/materials/not_lua.lua", "ASSET_CODE=true\n");
  const auto catalog = f.prepare();
  CHECK(catalog.scripts.size() == 1);
  CHECK(catalog.scripts.find("community/autorun/client/owned.lua") == catalog.scripts.end());
  CHECK(catalog.scripts.find("nativeloader/autorun/client/unrelated.lua") == catalog.scripts.end());
}

TEST_CASE("client catalog: generic developer source bridges stay excluded") {
  Fixture f("client_catalog_automation");
  f.add("garrysmod/addons/rtx_agent/lua/autorun/client/rtx_agent.lua", "ARBITRARY_SOURCE=true\n");
  f.add("garrysmod/addons/mmd_hotloader/lua/mmdhl/debug.lua", "ARBITRARY_SOURCE=true\n");
  const auto catalog = f.prepare();
  CHECK(catalog.scripts.size() == 1);
  CHECK(catalog.scripts.find("rtx_agent/autorun/client/rtx_agent.lua") == catalog.scripts.end());
  CHECK(catalog.scripts.find("mmd_hotloader/mmdhl/debug.lua") == catalog.scripts.end());
}

TEST_CASE("client catalog: disabled missing and unsupported owners fail closed") {
  Fixture f("client_catalog_owner_gate");
  f.config.from_file = false;
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.config.from_file = true; f.config.enabled = false;
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.config.enabled = true; f.config.remix_enabled = false;
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.config.remix_enabled = true; f.package().source = "unrecognized";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().source = "local"; f.package().requires_remix = false;
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().requires_remix = true; f.package().remix.reset();
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.package().remix = nl::manifest::Remix{};
  f.package().id = "another-allowed-native-package";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: duplicate owner and absent owned module are refused") {
  Fixture f("client_catalog_module_owner");
  const auto owner = f.package();
  f.generation.packages.push_back(owner);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.generation.packages.pop_back();
  CHECK(nl::client::native_bootstrap_present(f.generation));
  f.generation.files.front().package = "other-native-owner";
  CHECK(!nl::client::native_bootstrap_present(f.generation));
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: changed module bytes cannot authorize scripts") {
  Fixture f("client_catalog_module_hash");
  const auto module = nl::fs::join(f.root, kModule);
  write(module, "untrusted native module!");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  fs::remove(module);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: missing changed sized and NUL-containing scripts are refused") {
  Fixture f("client_catalog_script_hash");
  const auto path = nl::fs::join(f.root, kClient);
  write(path, "OWNED_CLIENT = fake\n");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  write(path, "OWNED_CLIENT = true\n");
  f.generation.files.back().size += 1;
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.generation.files.back().size -= 1;
  fs::remove(path);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  const std::string nul("BAD\0CODE", 8);
  write(path, nul);
  f.generation.files.back().size = nul.size();
  f.generation.files.back().sha256 = nl::sha256::of(nul);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: oversized text is refused before snapshot allocation") {
  Fixture f("client_catalog_script_limit");
  const std::string large((std::size_t{2} << 20) + 1, 'x');
  f.add("garrysmod/addons/nativeloader/lua/oversized.lua", large);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: aliases that collide after Windows folding are refused") {
  Fixture f("client_catalog_case_collision");
  f.add("garrysmod/addons/NativeLoader/lua/autorun/client/OWNED.lua", "OWNED_CLIENT = true\n");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("client catalog: directory junctions cannot redirect source reads") {
  Fixture f("client_catalog_junction");
  const auto lua = f.root / "garrysmod/addons/nativeloader/lua";
  const auto target = f.folder / "link-target";
  fs::rename(lua, target);
  if (!junction(lua, target)) {
    std::printf("  (skipped: cannot create catalog junction fixture)\n");
    return;
  }
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(nl::fs::read_file(target / "autorun/client/owned.lua", 100) == "OWNED_CLIENT = true\n");
  fs::remove(lua); // removes the junction only, never its target
}

TEST_CASE("client catalog: existing package path and protected-folder rules are unchanged") {
  CHECK(!nl::paths::is_safe("garrysmod/addons/nativeloader/lua/../community.lua"));
  CHECK(!nl::paths::is_safe("garrysmod/addons/nativeloader/lua/owned.lua:stream"));
  CHECK(nl::paths::root_area("garrysmod/data/native-loader/forged-state.json") == nl::paths::RootArea::none);
  CHECK(nl::paths::root_area("garrysmod/lua/autorun/local.lua") == nl::paths::RootArea::none);
  CHECK(nl::paths::root_area("user.conf") == nl::paths::RootArea::none);
  Fixture f("client_catalog_journal_paths");
  nl::journal::Journal journal;
  journal.loader = "0.9.0";
  journal.current = f.generation;
  journal.current->files.back().path = "garrysmod/addons/nativeloader/lua/../community.lua";
  CHECK_THROWS_AS(nl::journal::parse(nl::journal::serialize(journal)), std::runtime_error);
}

TEST_CASE("client catalog: malformed raw-generation paths cannot escape the owned Lua folder") {
  Fixture f("client_catalog_raw_paths");
  const std::string source = "NOT_IN_LUA_FOLDER=true\n";
  write(f.root / "garrysmod/addons/nativeloader/unrelated.lua", source);
  nl::journal::File file;
  file.path = "garrysmod/addons/nativeloader/lua/../unrelated.lua";
  file.package = kPackage;
  file.sha256 = nl::sha256::of(source);
  file.size = source.size();
  f.generation.files.push_back(file);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  f.generation.files.back().path = "garrysmod/addons/nativeloader/lua/owned.lua:stream";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
}

TEST_CASE("secure render patches: exact shipped recipes require the exact RTX owner") {
  for (const auto& set : renderer_recipes()) {
    CHECK(nl::client::secure_render_patch_set(kPackage, set));
    CHECK(!nl::client::secure_render_patch_set("community-package", set));
    CHECK(!nl::client::secure_render_patch_set("Gmod-RTX-Remix", set));
    CHECK(!nl::client::secure_render_patch_set("", set));
  }
}

TEST_CASE("secure render patches: changed fields extra recipes subsets and order are refused") {
  for (const auto& set : renderer_recipes()) {
    auto changed = set;
    changed.module = "client.dll";
    CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
    changed = set; changed.module[0] = static_cast<char>(changed.module[0] - 'a' + 'A');
    CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
    for (std::size_t index = 0; index < set.patches.size(); ++index) {
      changed = set; changed.patches[index].name += "_modified";
      CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
      changed = set; changed.patches[index].find[0] = changed.patches[index].find[0] == '0' ? '1' : '0';
      CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
      changed = set; changed.patches[index].replace[0] = changed.patches[index].replace[0] == '0' ? '1' : '0';
      CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
      changed = set; ++changed.patches[index].offset;
      CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
    }
    changed = set; changed.patches.push_back(set.patches.front());
    CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
    const unsigned combinations = 1u << static_cast<unsigned>(set.patches.size());
    for (unsigned subset = 0; subset + 1 < combinations; ++subset) {
      changed = set; changed.patches.clear();
      for (unsigned index = 0; index < set.patches.size(); ++index) {
        if (subset & (1u << index)) changed.patches.push_back(set.patches[index]);
      }
      CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
    }
    if (set.patches.size() > 1) {
      changed = set; std::swap(changed.patches.front(), changed.patches.back());
      CHECK(!nl::client::secure_render_patch_set(kPackage, changed));
    }
  }
}
