#include "nl/activate.h"
#include "nl_test.h"

#include <algorithm>
#include <set>
#include <string>

using namespace nl;

namespace {

// A deployed generation holding one runtime package at `payload`, plus an optional non-runtime
// package before it (to prove the runtime is still found).
journal::Generation with_runtime(const std::string& payload, const manifest::Remix& remix, bool extra_first = false) {
  journal::Generation gen;
  gen.number = 7;
  if (extra_first) {
    journal::Package other;
    other.id = "root-only";
    other.version = "1.0.0";
    gen.packages.push_back(other);
  }
  journal::Package pkg;
  pkg.id = "rtx-remix-runtime";
  pkg.version = "1.2.3";
  pkg.manifest_sha256 = std::string(64, 'a');
  pkg.source = "local";
  pkg.payload = payload;
  pkg.remix = remix;
  gen.packages.push_back(pkg);
  return gen;
}

manifest::Remix base_remix() {
  manifest::Remix r;
  r.entry = "runtime/d3d9.dll";
  r.launch_args = {"-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"};
  r.prefer_system_vulkan_loader = true;
  return r;
}

activate::EnvHas none() {
  return [](const std::string&) { return false; };
}

activate::EnvHas set_of(std::set<std::string> names) {
  return [names = std::move(names)](const std::string& n) { return names.count(n) > 0; };
}

const std::string* env_value(const activate::Plan& p, const std::string& name) {
  for (const auto& [n, v] : p.env) {
    if (n == name) return &v;
  }
  return nullptr;
}

}  // namespace

TEST_CASE("activate: a deployed runtime with no layers loads d3d9 and leaves config discovery alone") {
  const auto gen = with_runtime("native-loader/packages/rtx-remix-runtime/1.2.3_7", base_remix(), true);
  config::Config config;  // remix_enabled defaults to true
  const activate::Plan p = activate::plan(gen, config, none(), L"gmod.exe -game garrysmod");
  REQUIRE(p.activate);
  CHECK(p.runtime_dll == "native-loader/packages/rtx-remix-runtime/1.2.3_7/runtime/d3d9.dll");
  CHECK(p.runtime_dir == "native-loader/packages/rtx-remix-runtime/1.2.3_7/runtime");
  CHECK(p.prefer_system_vulkan);
  CHECK(env_value(p, "DXVK_RTX_CONFIG_FILE") == nullptr);  // no layers: the runtime keeps its default
  CHECK(env_value(p, "DXVK_CONFIG_FILE") == nullptr);
  CHECK(p.launch_args == std::vector<std::string>({"-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"}));
}

TEST_CASE("activate: config layers go below the user's root conf, in order") {
  manifest::Remix remix = base_remix();
  remix.rtx_conf_layers = {"config/rtx/01_base.conf", "config/rtx/02_look.conf"};
  remix.dxvk_conf_layers = {"config/dxvk/01_dxvk.conf"};
  const std::string payload = "native-loader/packages/rtx-remix-runtime/1.2.3_7";
  const auto plan = activate::plan(with_runtime(payload, remix), config::Config{}, none(), L"gmod.exe");
  const std::string* rtx = env_value(plan, "DXVK_RTX_CONFIG_FILE");
  const std::string* dxvk = env_value(plan, "DXVK_CONFIG_FILE");
  REQUIRE(rtx && dxvk);
  CHECK(*rtx == payload + "/config/rtx/01_base.conf," + payload + "/config/rtx/02_look.conf,rtx.conf");
  CHECK(*dxvk == payload + "/config/dxvk/01_dxvk.conf,dxvk.conf");
}

TEST_CASE("activate: the user's own environment wins over the package") {
  manifest::Remix remix = base_remix();
  remix.rtx_conf_layers = {"config/rtx/01_base.conf"};
  remix.env = {{"DXVK_LOG_LEVEL", "info"}, {"RTX_TEST", "on"}};
  const auto gen = with_runtime("p", remix);
  const auto plan = activate::plan(gen, config::Config{}, set_of({"DXVK_RTX_CONFIG_FILE", "DXVK_LOG_LEVEL"}), L"gmod.exe");
  CHECK(env_value(plan, "DXVK_RTX_CONFIG_FILE") == nullptr);  // user set it: left alone
  CHECK(env_value(plan, "DXVK_LOG_LEVEL") == nullptr);        // user set it: left alone
  const std::string* rtx_test = env_value(plan, "RTX_TEST");
  REQUIRE(rtx_test);
  CHECK(*rtx_test == "on");
}

TEST_CASE("activate: launch arguments the user already passed are not repeated") {
  const auto gen = with_runtime("p", base_remix());
  const config::Config config;
  const auto a = activate::plan(gen, config, none(), L"gmod.exe -dxlevel 95");
  CHECK(a.launch_args == std::vector<std::string>({"-nod3d9ex", "+mat_disable_d3d9ex", "1"}));
  const auto b = activate::plan(gen, config, none(), L"gmod.exe -nod3d9ex +mat_disable_d3d9ex 2");
  CHECK(b.launch_args == std::vector<std::string>({"-dxlevel", "90"}));
  const auto c = activate::plan(gen, config, none(), L"gmod.exe \"-DXLEVEL\" 70 -NoD3D9Ex +MAT_DISABLE_D3D9EX 1");
  CHECK(c.launch_args.empty());  // case-insensitive, quoted argument recognised
}

TEST_CASE("activate: no runtime deployed is inactive") {
  journal::Generation gen;
  gen.number = 1;
  journal::Package pkg;  // a root-files package, no remix
  pkg.id = "fixes";
  pkg.version = "1.0.0";
  gen.packages.push_back(pkg);
  const auto plan = activate::plan(gen, config::Config{}, none(), L"gmod.exe");
  CHECK(!plan.activate);
  CHECK(plan.runtime_dll.empty());
  CHECK(plan.env.empty());
  CHECK(plan.launch_args.empty());
  CHECK(plan.reason == "no runtime package is deployed");
}

TEST_CASE("activate: remix.enabled false deploys but does not load") {
  config::Config config;
  config.remix_enabled = false;
  const auto plan = activate::plan(with_runtime("p", base_remix()), config, none(), L"gmod.exe");
  CHECK(!plan.activate);
  CHECK(plan.runtime_dll.empty());
  CHECK(plan.reason == "remix.enabled is false in native-loader/config.json");
}
