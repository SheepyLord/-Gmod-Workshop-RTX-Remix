#include "nl/content.h"
#include "nl/manifest.h"
#include "nl_test.h"

#include <string>
#include <utility>
#include <vector>

namespace {

const std::string kSha(64, 'a');

// A manifest from files (package path) and root folders, with the kinds those need; extra members
// start with ", ".
nl::manifest::Manifest manifest(const std::vector<std::string>& files, const std::vector<std::string>& roots,
                                const std::string& kinds = "\"root-files\"", const std::string& extra = "") {
  std::string listed, folders;
  for (const auto& f : files) listed += (listed.empty() ? "\"" : ", \"") + f + "\": {\"size\": 1, \"sha256\": \"" + kSha + "\"}";
  for (const auto& r : roots) folders += (folders.empty() ? "{\"path\": \"" : ", {\"path\": \"") + r + "\"}";
  return nl::manifest::parse("{\"schema\": 1, \"id\": \"pbr\", \"version\": \"1.0.0\", \"kinds\": [" + kinds +
                             "], \"files\": {" + listed + "}, \"root_files\": [" + folders + "]" + extra + "}");
}

}  // namespace

TEST_CASE("content: GMod's Workshop whitelist, as gmad has it") {
  for (const char* yes : {"lua/autorun/pbr.lua", "LUA/Autorun/PBR.LUA", "materials/pbr/a.vtf", "materials/pbr/a.vmt",
                          "models/pbr.mdl", "data_static/mmdhl/rig.dat", "data_static/x.json", "sound/a.ogg",
                          "resource/localization/en/pbr.properties", "shaders/fxc/a_ps30.vcs", "gamemodes/x/x.txt"}) {
    if (!nl::content::workshop_whitelisted(yes)) nl::test::fail(yes, __FILE__, __LINE__);
  }
  for (const char* no : {"README.md", "lua/bin/gmcl_x_win64.dll", "pbr.exe", "lua/x.txt", "models/a.sw.vtx",
                         "gamemodes/x/y/z.txt", "data_static/x.exe", "materials/x.dds", ""}) {
    if (nl::content::workshop_whitelisted(no)) nl::test::fail(no, __FILE__, __LINE__);
  }
}

TEST_CASE("content: Remix mod data") {
  for (const char* yes : {"rtx-remix/mods/pbr/mod.usda", "rtx-remix/mods/pbr/textures/A.DDS", "rtx-remix/mods/pbr/x.usd",
                          "rtx-remix/mods/pbr/m.mdl", "rtx-remix/mods/pbr/notes.txt"}) {
    if (!nl::content::remix_mod_file(yes)) nl::test::fail(yes, __FILE__, __LINE__);
  }
  for (const char* no : {"rtx-remix/mods/pbr/d3d9.dll", "rtx-remix/mods/pbr/tool.exe", "rtx-remix/mods/pbr/run.bat",
                         "rtx-remix/mods/pbr/script.lua"}) {
    if (nl::content::remix_mod_file(no)) nl::test::fail(no, __FILE__, __LINE__);
  }
}

TEST_CASE("content: a PBR package is content; native code and other places are not (ADR 0027)") {
  const std::vector<std::string> mod = {"native/root/rtx-remix/mods/pbr/mod.usda", "native/root/rtx-remix/mods/pbr/a.dds"};
  CHECK(nl::content::problem(manifest(mod, {"rtx-remix/mods/pbr"})).empty());
  // The Guinaifen package's shape: a Remix mod and a Lua add-on with data_static files.
  auto both = mod;
  both.insert(both.end(), {"native/root/garrysmod/addons/mmdhl_pbr/addon.json",
                           "native/root/garrysmod/addons/mmdhl_pbr/data_static/mmdhl/rig.dat",
                           "native/root/garrysmod/addons/mmdhl_pbr/lua/autorun/pbr.lua"});
  CHECK(nl::content::problem(manifest(both, {"rtx-remix/mods/pbr", "garrysmod/addons/mmdhl_pbr"},
                                      "\"root-files\", \"lua-addon\"")).empty());

  const auto refused = [](const nl::manifest::Manifest& m, const std::string& part) {
    const std::string why = nl::content::problem(m);
    if (why.find(part) == std::string::npos) nl::test::fail(("expected \"" + part + "\", got \"" + why + "\"").c_str(), __FILE__, __LINE__);
  };
  refused(manifest({"native/root/garrysmod/lua/bin/gmcl_pbr_win64.dll"}, {"garrysmod/lua/bin/gmcl_pbr_win64.dll"},
                   "\"lua-binary-module\""),
          "lua-binary-module");
  refused(manifest({"native/payload/d3d9.dll"}, {}, "\"remix-runtime\"", ", \"remix\": {\"entry\": \"d3d9.dll\"}"),
          "remix-runtime");
  refused(manifest({"native/root/rtx-remix/mods/pbr/d3d9.dll"}, {"rtx-remix/mods/pbr"}), "not Remix mod data");
  refused(manifest({"native/root/garrysmod/addons/pbr/README.md"}, {"garrysmod/addons/pbr"}, "\"lua-addon\""),
          "not one GMod's Workshop allows");
  refused(manifest({"native/root/garrysmod/addons/pbr/lua/bin/x.dll"}, {"garrysmod/addons/pbr"}, "\"lua-addon\""),
          "not one GMod's Workshop allows");
  // A root in garrysmod/data must be create-only: the path string carries the policy member too.
  refused(manifest({"native/root/garrysmod/data/pbr/seed.txt"}, {"garrysmod/data/pbr\", \"policy\": \"create-only"}),
          "outside rtx-remix/mods");
  refused(manifest(mod, {"rtx-remix/mods/pbr"}, "\"root-files\"", ", \"session_cvars\": {\"mat_specular\": \"0\"}"),
          "changes RTX sessions");
}
