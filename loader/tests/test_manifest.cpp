#include "nl/manifest.h"
#include "nl_test.h"

#include <string>
#include <vector>

using nl::manifest::Error;

namespace {

const std::string kSha(64, 'a');

// A complete, valid manifest using every schema-1 feature; tests change one piece at a time.
std::string base() {
  return R"({
  "schema": 1,
  "id": "rtx-remix-runtime",
  "name": "RTX Remix runtime for GMod x64",
  "version": "1.6.1+gmod.20261025",
  "kinds": ["remix-runtime", "root-files", "lua-binary-module"],
  "requires_loader": ">=0.0.1",
  "files": {
    "native/payload/runtime/d3d9.dll": {"size": 10, "sha256": ")" + kSha + R"("},
    "native/payload/config/rtx.conf": {"size": 5, "sha256": ")" + kSha + R"("},
    "native/payload/config/dxvk.conf": {"size": 5, "sha256": ")" + kSha + R"("},
    "native/root/rtx-remix/mods/base_mod/mod.usda": {"size": 3, "sha256": ")" + kSha + R"("},
    "native/root/garrysmod/lua/bin/gmcl_test_win64.dll": {"size": 4, "sha256": ")" + kSha + R"("}
  },
  "remix": {
    "entry": "runtime/d3d9.dll",
    "rtx_conf_layers": ["config/rtx.conf"],
    "dxvk_conf_layers": ["config/dxvk.conf"],
    "env": {"DXVK_LOG_LEVEL": "info"},
    "launch_args": ["-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"],
    "prefer_system_vulkan_loader": true
  },
  "root_files": [
    {"path": "rtx-remix/mods/base_mod", "policy": "replace-owned"},
    {"path": "garrysmod/lua/bin/gmcl_test_win64.dll"}
  ]
})";
}

// base() with one exact, unique substring replaced.
std::string with(const std::string& from, const std::string& to) {
  std::string text = base();
  const std::size_t at = text.find(from);
  if (at == std::string::npos || text.find(from, at + 1) != std::string::npos) {
    throw std::logic_error("test bug: \"" + from + "\" must occur exactly once");
  }
  return text.replace(at, from.size(), to);
}

std::vector<nl::manifest::ContentEntry> base_entries() {
  return {{"native/manifest.json", 900},
          {"native/payload/runtime/d3d9.dll", 10},
          {"native/payload/config/rtx.conf", 5},
          {"native/payload/config/dxvk.conf", 5},
          {"native/root/rtx-remix/mods/base_mod/mod.usda", 3},
          {"native/root/garrysmod/lua/bin/gmcl_test_win64.dll", 4},
          {"lua/autorun/rtx_status.lua", 100}};
}

}  // namespace

TEST_CASE("manifest: a complete schema-1 manifest parses") {
  const auto m = nl::manifest::parse(base());
  CHECK(m.id == "rtx-remix-runtime");
  CHECK(m.name == "RTX Remix runtime for GMod x64");
  CHECK(m.version.major == 1 && m.version.minor == 6 && m.version.patch == 1);
  CHECK(m.version.build == "gmod.20261025");
  CHECK(m.has(nl::manifest::Kind::remix_runtime));
  CHECK(m.has(nl::manifest::Kind::lua_binary_module));
  REQUIRE(m.requires_loader.has_value());
  CHECK(m.requires_loader->patch == 1);
  REQUIRE(m.files.size() == 5);
  CHECK(m.files[0].first == "native/payload/runtime/d3d9.dll");
  CHECK(m.files[0].second.size == 10);
  REQUIRE(m.remix.has_value());
  CHECK(m.remix->entry == "runtime/d3d9.dll");
  CHECK(m.remix->launch_args.size() == 5);
  CHECK(m.remix->env.size() == 1);
  CHECK(m.remix->prefer_system_vulkan_loader);
  REQUIRE(m.root_files.size() == 2);
  CHECK(m.root_files[0].area == nl::paths::RootArea::rtx_remix_mods);
  CHECK(m.root_files[1].area == nl::paths::RootArea::lua_bin);
  CHECK(m.root_files[1].policy == nl::manifest::Policy::replace_owned);
}

TEST_CASE("manifest: name defaults to the id; optional sections may be absent") {
  const std::string minimal = R"({"schema": 1, "id": "mods", "version": "0.1.0", "kinds": ["root-files"],
    "files": {"native/root/rtx-remix/mods/m/mod.usda": {"size": 1, "sha256": ")" + kSha + R"("}},
    "root_files": [{"path": "rtx-remix/mods/m"}]})";
  const auto m = nl::manifest::parse(minimal);
  CHECK(m.name == "mods");
  CHECK(!m.remix.has_value());
  CHECK(!m.requires_loader.has_value());
}

TEST_CASE("manifest: every schema-1 rule is enforced") {
  const std::string sha_line = R"("native/payload/config/rtx.conf": {"size": 5, "sha256": ")" + kSha + R"("})";
  const std::vector<std::string> bad = {
      "[]",
      "{\"schema\": 1",
      with(R"("schema": 1)", R"("schema": 2)"),
      with(R"("schema": 1)", R"("schema": "1")"),
      with(R"("schema": 1,)", R"("schema": 1, "extra": true,)"),
      with(R"("id": "rtx-remix-runtime")", R"("id": "Bad_ID")"),
      with(R"("id": "rtx-remix-runtime")", R"("id": "-x")"),
      with(R"("id": "rtx-remix-runtime")", R"("id": ")" + std::string(65, 'a') + "\""),
      with(R"("name": "RTX Remix runtime for GMod x64")", R"("name": "")"),
      with(R"("version": "1.6.1+gmod.20261025")", R"("version": "1.6")"),
      with(R"("version": "1.6.1+gmod.20261025")", R"("version": "v1.6.1")"),
      with(R"("kinds": ["remix-runtime", "root-files", "lua-binary-module"])", R"("kinds": [])"),
      with(R"("kinds": ["remix-runtime", "root-files", "lua-binary-module"])", R"("kinds": ["remix-runtime", "root-files", "lua-binary-module", "patch-set"])"),
      with(R"("kinds": ["remix-runtime", "root-files", "lua-binary-module"])", R"("kinds": ["remix-runtime", "root-files", "lua-binary-module", "root-files"])"),
      with(R"("kinds": ["remix-runtime", "root-files", "lua-binary-module"])", R"("kinds": ["remix-runtime", "root-files", "lua-binary-module", "magic"])"),
      with(R"("requires_loader": ">=0.0.1")", R"("requires_loader": "0.0.1")"),
      with(R"("requires_loader": ">=0.0.1")", R"("requires_loader": ">=1")"),
      with(sha_line, R"("native/payload/config/../rtx.conf": {"size": 5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, R"("lua/autorun/x.lua": {"size": 5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, R"("native/manifest.json": {"size": 5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, R"("native/payload/config/rtx.conf": {"size": 5, "sha256": ")" + std::string(64, 'A') + R"("})"),
      with(sha_line, R"("native/payload/config/rtx.conf": {"size": 5, "sha256": "abc"})"),
      with(sha_line, R"("native/payload/config/rtx.conf": {"size": -5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, R"("native/payload/config/rtx.conf": {"size": 5.5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, R"("native/payload/config/rtx.conf": {"size": 5, "sha256": ")" + kSha + R"(", "mode": 1})"),
      with(sha_line, sha_line + R"(, "NATIVE/PAYLOAD/CONFIG/RTX.CONF": {"size": 5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, R"("native/payload/con:fig/rtx.conf": {"size": 5, "sha256": ")" + kSha + R"("})"),
      with(sha_line, sha_line + ", \"native/payload/config/r\xC3\xA9sum\xC3\xA9.dat\": {\"size\": 5, \"sha256\": \"" + kSha + "\"}"),
      with(R"("entry": "runtime/d3d9.dll")", R"("entry": "runtime/dxvk.dll")"),
      with(R"("entry": "runtime/d3d9.dll")", R"("entry": "other/d3d9.dll")"),
      with(R"("rtx_conf_layers": ["config/rtx.conf"])", R"("rtx_conf_layers": ["config/rtx.ini"])"),
      with(R"("rtx_conf_layers": ["config/rtx.conf"])", R"("rtx_conf_layers": ["config/missing.conf"])"),
      with(R"("env": {"DXVK_LOG_LEVEL": "info"})", R"("env": {"PATH": "C:\\evil"})"),
      with(R"("env": {"DXVK_LOG_LEVEL": "info"})", R"("env": {"DXVK_LOG_LEVEL": "a\nb"})"),
      with(R"("env": {"DXVK_LOG_LEVEL": "info"})", R"("env": {"DXVK_": "x"})"),
      with(R"("launch_args": ["-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"])", R"("launch_args": ["+exec", "evil"])"),
      with(R"("launch_args": ["-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"])", R"("launch_args": ["-dxlevel"])"),
      with(R"("launch_args": ["-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"])", R"("launch_args": ["-dxlevel", "9x"])"),
      with(R"("prefer_system_vulkan_loader": true)", R"("prefer_system_vulkan_loader": "yes")"),
      with(R"("prefer_system_vulkan_loader": true)", R"("prefer_system_vulkan_loader": true, "extra": 1)"),
      with(R"(["remix-runtime", "root-files", "lua-binary-module"])", R"(["root-files", "lua-binary-module"])"),
      with(R"({"path": "rtx-remix/mods/base_mod", "policy": "replace-owned"})", R"({"path": "bin/win64/d3d9.dll"})"),
      with(R"({"path": "rtx-remix/mods/base_mod", "policy": "replace-owned"})", R"({"path": "rtx-remix/mods/base_mod", "policy": "overwrite"})"),
      with(R"({"path": "rtx-remix/mods/base_mod", "policy": "replace-owned"})", R"({"path": "rtx-remix/mods/base_mod"}, {"path": "rtx-remix/mods/base_mod/mod.usda"})"),
      with(R"({"path": "rtx-remix/mods/base_mod", "policy": "replace-owned"})", R"({"path": "rtx-remix/mods/other_mod"})"),
      with(R"({"path": "garrysmod/lua/bin/gmcl_test_win64.dll"})", R"({"path": "garrysmod/cfg/rtx.cfg"})"),
      with(R"("kinds": ["remix-runtime", "root-files", "lua-binary-module"])", R"("kinds": ["remix-runtime", "root-files"])"),
  };
  for (std::size_t i = 0; i < bad.size(); ++i) {
    bool rejected = false;
    try {
      nl::manifest::parse(bad[i]);
    } catch (const Error&) {
      rejected = true;
    }
    if (!rejected) nl::test::fail(("bad manifest #" + std::to_string(i) + " was accepted").c_str(), __FILE__, __LINE__);
  }
}

TEST_CASE("manifest: cfg root files must be create-only") {
  const std::string text = R"({"schema": 1, "id": "cfg", "version": "1.0.0", "kinds": ["root-files"],
    "files": {"native/root/garrysmod/cfg/rtx_remix.cfg": {"size": 1, "sha256": ")" + kSha + R"("}},
    "root_files": [{"path": "garrysmod/cfg/rtx_remix.cfg", "policy": "create-only"}]})";
  CHECK(nl::manifest::parse(text).root_files[0].area == nl::paths::RootArea::cfg);
  std::string replace = text;
  replace.replace(replace.find("create-only"), 11, "replace-owned");
  CHECK_THROWS_AS(nl::manifest::parse(replace), Error);
}

TEST_CASE("manifest: semantic version parsing and precedence") {
  using nl::manifest::compare;
  using nl::manifest::parse_version;
  // The precedence example from semver.org, item 11.
  const char* ordered[] = {"1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                           "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "2.0.0", "2.1.0", "2.1.1"};
  for (std::size_t i = 0; i + 1 < std::size(ordered); ++i) {
    const auto a = parse_version(ordered[i]);
    const auto b = parse_version(ordered[i + 1]);
    REQUIRE(a && b);
    if (!(compare(*a, *b) < 0 && compare(*b, *a) > 0)) nl::test::fail(ordered[i], __FILE__, __LINE__);
  }
  CHECK(compare(*parse_version("1.0.0+a"), *parse_version("1.0.0+b")) == 0);
  for (const char* bad : {"01.0.0", "1.0", "1.0.0-", "1.0.0+", "1.0.0-01", "v1.0.0", "1.0.0-a..b", "1.0.0 ", ""}) {
    if (parse_version(bad)) nl::test::fail(bad, __FILE__, __LINE__);
  }
}

TEST_CASE("manifest: contents must match the listed files") {
  const auto m = nl::manifest::parse(base());
  nl::manifest::check_contents(m, base_entries());  // ordinary GMod content (lua/) is ignored

  auto upper = base_entries();
  for (auto& e : upper) {
    for (char& c : e.path) c = static_cast<char>(c >= 'a' && c <= 'z' ? c - 32 : c);
  }
  nl::manifest::check_contents(m, upper);  // paths compare without case

  auto missing = base_entries();
  missing.erase(missing.begin() + 1);
  CHECK_THROWS_AS(nl::manifest::check_contents(m, missing), Error);

  auto resized = base_entries();
  resized[2].size = 6;
  CHECK_THROWS_AS(nl::manifest::check_contents(m, resized), Error);

  auto extra = base_entries();
  extra.push_back({"native/payload/runtime/extra.dll", 1});
  CHECK_THROWS_AS(nl::manifest::check_contents(m, extra), Error);
}
