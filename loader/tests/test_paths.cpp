#include "nl/paths.h"
#include "nl_test.h"

#include <string>

using nl::paths::problem;

TEST_CASE("paths: safe relative paths pass") {
  for (const char* good : {"native/manifest.json", "native/payload/runtime/d3d9.dll", "rtx-remix/mods/base_mod/mod.usda",
                           "garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll", "a", "a.b.c/d-e_f",
                           "materials/\xC3\xA4.vmt", "configs/v1.2/x", "console/log.txt", "com10/x", "my~file"}) {
    if (!nl::paths::is_safe(good)) nl::test::fail((std::string(good) + ": " + problem(good)).c_str(), __FILE__, __LINE__);
  }
}

TEST_CASE("paths: everything that could escape or alias is refused") {
  const char* bad[] = {
      "", "/abs", "a//b", "a/", "./a", "a/./b", "../a", "a/../b", "a\\b", "C:/x", "c:x", "a:b",  // drive/ADS
      "a<b", "a>b", "a\"b", "a|b", "a?b", "a*b", "a/b.", "a/b ", " a", "a/ b",
      "con", "CON.txt", "a/nul", "a/aux.dll", "prn", "com1", "LPT9.log", "com0", "conin$", "CONOUT$.x",
      "com\xC2\xB9", "lpt\xC2\xB3.txt",                                                             // superscript ports
      "progra~1/x", "a/GMCL_R~2.DLL", "a\x01" "b", "a\x7F", "\xFF", "\xC0\xAF",
  };
  for (const char* path : bad) {
    if (nl::paths::is_safe(path)) nl::test::fail(path, __FILE__, __LINE__);
  }
  CHECK(nl::paths::is_safe(std::string(nl::paths::kMaxPathBytes, 'a')) == false);  // one component too long
  CHECK(!nl::paths::is_safe(std::string(nl::paths::kMaxPathBytes + 1, 'a')));
  CHECK(!nl::paths::is_safe(std::string(256, 'a')));
  CHECK(nl::paths::is_safe(std::string(255, 'a')));
}

TEST_CASE("paths: fold and within compare case-insensitively on whole components") {
  CHECK(nl::paths::fold("Rtx-Remix/MODS") == "rtx-remix/mods");
  CHECK(nl::paths::within("rtx-remix/mods/x", "RTX-REMIX/mods"));
  CHECK(nl::paths::within("rtx-remix/mods", "rtx-remix/mods"));
  CHECK(!nl::paths::within("rtx-remix/modsx/y", "rtx-remix/mods"));
  CHECK(!nl::paths::within("rtx-remix", "rtx-remix/mods"));
}

TEST_CASE("paths: root areas") {
  using nl::paths::RootArea;
  CHECK(nl::paths::root_area("rtx-remix/mods/base_mod") == RootArea::rtx_remix_mods);
  CHECK(nl::paths::root_area("RTX-Remix/Mods/base_mod/mod.usda") == RootArea::rtx_remix_mods);
  CHECK(nl::paths::root_area("rtx-remix/mods") == RootArea::none);  // the folder itself is not a target
  CHECK(nl::paths::root_area("garrysmod/lua/bin/gmcl_x_win64.dll") == RootArea::lua_bin);
  // garrysmod/cfg holds Steam depot files (config_default.cfg, valve.rc, ...): not an area (ADR 0014).
  CHECK(nl::paths::root_area("garrysmod/cfg/rtx_remix.cfg") == RootArea::none);
  CHECK(nl::paths::root_area("garrysmod/cfg/config_default.cfg") == RootArea::none);
  CHECK(nl::paths::root_area("bin/win64/d3d9.dll") == RootArea::none);
  CHECK(nl::paths::root_area("user.conf") == RootArea::none);
  CHECK(nl::paths::root_area("garrysmod/lua/autorun/x.lua") == RootArea::none);
  CHECK(std::string(nl::paths::area_name(RootArea::lua_bin)) == "garrysmod/lua/bin");
}

TEST_CASE("paths: files in the folder areas must be inside a named folder") {
  CHECK(nl::paths::file_depth_ok("garrysmod/lua/bin/gmcl_x_win64.dll"));
  CHECK(nl::paths::file_depth_ok("garrysmod/addons/rtx/lua/autorun/x.lua"));
  CHECK(nl::paths::file_depth_ok("garrysmod/data/rtx_agent/seed.txt"));
  CHECK(nl::paths::file_depth_ok("rtx-remix/mods/base_mod/mod.usda"));
  CHECK(!nl::paths::file_depth_ok("garrysmod/addons/direct.gma"));
  CHECK(!nl::paths::file_depth_ok("garrysmod/data/direct.txt"));
  CHECK(!nl::paths::file_depth_ok("rtx-remix/mods/mod.usda"));
  CHECK(!nl::paths::file_depth_ok("garrysmod/cfg/sub/x.cfg"));
  CHECK(!nl::paths::file_depth_ok("bin/win64/sub/d3d9.dll"));
}
