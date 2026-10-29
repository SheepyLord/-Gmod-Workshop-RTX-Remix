#include "nl/activate.h"
#include "nl_test.h"

#include <algorithm>
#include <map>
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

activate::EnvGet none() {
  return [](const std::string&) -> std::optional<std::string> { return std::nullopt; };
}

activate::EnvGet values(std::map<std::string, std::string> entries) {
  return [entries = std::move(entries)](const std::string& n) -> std::optional<std::string> {
    const auto it = entries.find(n);
    return it == entries.end() ? std::nullopt : std::optional(it->second);
  };
}

const std::string* env_value(const activate::Plan& p, const std::string& name) {
  for (const auto& [n, v] : p.env) {
    if (n == name) return &v;
  }
  return nullptr;
}

activate::Display uhd() { return {3840, 2160}; }

// What an RTX session without a window choice of its own gets on a 3840 x 2160 display (ADR 0018).
const std::vector<std::string> kWindow = {"-windowed", "-noborder", "-w", "3840", "-h", "2160"};

std::vector<std::string> plus(std::vector<std::string> first, const std::vector<std::string>& second) {
  first.insert(first.end(), second.begin(), second.end());
  return first;
}

}  // namespace

TEST_CASE("activate: a deployed runtime with no layers loads d3d9 and leaves config discovery alone") {
  const auto gen = with_runtime("native-loader/packages/rtx-remix-runtime/1.2.3_7", base_remix(), true);
  config::Config config;  // remix_enabled defaults to true
  const activate::Plan p = activate::plan(gen, config, none(), L"gmod.exe -game garrysmod", uhd);
  REQUIRE(p.activate);
  CHECK(p.runtime_dll == "native-loader/packages/rtx-remix-runtime/1.2.3_7/runtime/d3d9.dll");
  CHECK(p.runtime_dir == "native-loader/packages/rtx-remix-runtime/1.2.3_7/runtime");
  CHECK(p.prefer_system_vulkan);
  CHECK(env_value(p, "DXVK_RTX_CONFIG_FILE") == nullptr);  // no layers: the runtime keeps its default
  CHECK(env_value(p, "DXVK_CONFIG_FILE") == nullptr);
  CHECK(p.launch_args == plus({"-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"}, kWindow));
}

TEST_CASE("activate: config layers go below the user's root conf, in order") {
  manifest::Remix remix = base_remix();
  remix.rtx_conf_layers = {"config/rtx/01_base.conf", "config/rtx/02_look.conf"};
  remix.dxvk_conf_layers = {"config/dxvk/01_dxvk.conf"};
  const std::string payload = "native-loader/packages/rtx-remix-runtime/1.2.3_7";
  const auto plan = activate::plan(with_runtime(payload, remix), config::Config{}, none(), L"gmod.exe", uhd);
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
  const auto plan = activate::plan(gen, config::Config{}, values({{"DXVK_RTX_CONFIG_FILE", "base.conf,My overrides.conf"},
                                  {"DXVK_LOG_LEVEL", "debug"}}), L"gmod.exe", uhd);
  REQUIRE(env_value(plan, "DXVK_RTX_CONFIG_FILE"));
  CHECK(*env_value(plan, "DXVK_RTX_CONFIG_FILE") == "p/config/rtx/01_base.conf,base.conf,My overrides.conf");
  CHECK(env_value(plan, "DXVK_LOG_LEVEL") == nullptr);        // user set it: left alone
  const std::string* rtx_test = env_value(plan, "RTX_TEST");
  REQUIRE(rtx_test);
  CHECK(*rtx_test == "on");
}

TEST_CASE("activate: both user config lists remain last and ordinary empty values are preserved") {
  auto remix = base_remix();
  remix.rtx_conf_layers = {"config/rtx/base.conf"};
  remix.dxvk_conf_layers = {"config/dxvk/base.conf"};
  remix.env = {{"RTX_TEST", "on"}};
  const auto env = values({{"DXVK_RTX_CONFIG_FILE", "用户.conf,final.conf"},
                           {"DXVK_CONFIG_FILE", "dxvk-user.conf,top.conf"}, {"RTX_TEST", ""}});
  const auto p = activate::plan(with_runtime("p", remix), config::Config{}, env, L"gmod.exe", uhd);
  REQUIRE(env_value(p, "DXVK_RTX_CONFIG_FILE") && env_value(p, "DXVK_CONFIG_FILE"));
  CHECK(*env_value(p, "DXVK_RTX_CONFIG_FILE") == "p/config/rtx/base.conf,用户.conf,final.conf");
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == "p/config/dxvk/base.conf,dxvk-user.conf,top.conf");
  CHECK(env_value(p, "RTX_TEST") == nullptr);
}

TEST_CASE("activate: a layer list the runtime would ignore (260 characters or more) is noted") {
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/dxvk/01_defaults.conf"};
  const auto short_plan = activate::plan(with_runtime("native-loader/packages/x/1_1", remix), config::Config{}, none(), L"gmod.exe", uhd);
  CHECK(short_plan.notes.empty());
  const std::string payload = "native-loader/packages/" + std::string(220, 'p') + "/1_1";
  const auto long_plan = activate::plan(with_runtime(payload, remix), config::Config{}, none(), L"gmod.exe", uhd);
  REQUIRE(long_plan.notes.size() == 1);
  CHECK(long_plan.notes[0].find("DXVK_CONFIG_FILE is ") == 0);
  CHECK(env_value(long_plan, "DXVK_CONFIG_FILE") != nullptr);  // still set: the note explains the fallback
}

TEST_CASE("activate: empty config variables retain the runtime's default user root layer") {
  auto remix = base_remix();
  remix.rtx_conf_layers = {"config/base.conf"};
  const auto p = activate::plan(with_runtime("p", remix), config::Config{}, values({{"DXVK_RTX_CONFIG_FILE", ""}}), L"gmod.exe", uhd);
  REQUIRE(env_value(p, "DXVK_RTX_CONFIG_FILE"));
  CHECK(*env_value(p, "DXVK_RTX_CONFIG_FILE") == "p/config/base.conf,rtx.conf");
}

TEST_CASE("activate: launch arguments the user already passed are not repeated") {
  const auto gen = with_runtime("p", base_remix());
  const config::Config config;
  const auto a = activate::plan(gen, config, none(), L"gmod.exe -dxlevel 95", uhd);
  CHECK(a.launch_args == plus({"-nod3d9ex", "+mat_disable_d3d9ex", "1"}, kWindow));
  CHECK(a.present_args == std::vector<std::string>({"-dxlevel", "95"}));
  const auto b = activate::plan(gen, config, none(), L"gmod.exe -nod3d9ex +mat_disable_d3d9ex 2", uhd);
  CHECK(b.launch_args == plus({"-dxlevel", "90"}, kWindow));
  const auto c = activate::plan(gen, config, none(), L"gmod.exe \"-DXLEVEL\" 70 -NoD3D9Ex +MAT_DISABLE_D3D9EX 1", uhd);
  CHECK(c.launch_args == kWindow);  // case-insensitive, quoted argument recognised
}

TEST_CASE("activate: an RTX session gets a borderless window the size of the display unless the user chose one") {
  const auto gen = with_runtime("p", base_remix());
  config::Config config;
  int reads = 0;
  const activate::DisplayGet counted = [&reads] {
    ++reads;
    return activate::Display{2560, 1440};
  };
  // The window arguments follow the package's five (none of these command lines carries those).
  const auto window = [](const activate::Plan& p) { return std::vector<std::string>(p.launch_args.begin() + 5, p.launch_args.end()); };
  CHECK(window(activate::plan(gen, config, none(), L"gmod.exe", counted)) ==
        std::vector<std::string>({"-windowed", "-noborder", "-w", "2560", "-h", "1440"}));
  CHECK(reads == 1);
  for (const wchar_t* chosen : {L"gmod.exe -windowed", L"gmod.exe -Window", L"gmod.exe -sw", L"gmod.exe -startwindowed",
                                L"gmod.exe -full", L"gmod.exe -FULLSCREEN -w 640 -h 480"}) {
    const auto p = activate::plan(gen, config, none(), chosen, counted);
    CHECK(window(p).empty());
    CHECK(p.present_args.size() == 1);
  }
  CHECK(reads == 1);  // a mode the user chose needs no display
  const auto border = activate::plan(gen, config, none(), L"gmod.exe -noborder", counted);
  CHECK(window(border) == std::vector<std::string>({"-windowed", "-w", "2560", "-h", "1440"}));
  CHECK(border.present_args == std::vector<std::string>({"-noborder"}));
  const auto sized = activate::plan(gen, config, none(), L"gmod.exe -width 1920 -h 1080", counted);
  CHECK(window(sized) == std::vector<std::string>({"-windowed", "-noborder"}));
  CHECK(sized.present_args == std::vector<std::string>({"-width", "-h"}));
  CHECK(reads == 2);  // the -noborder plan read it; a size the user gave needs none
  const auto unknown = activate::plan(gen, config, none(), L"gmod.exe", [] { return activate::Display{}; });
  CHECK(window(unknown) == std::vector<std::string>({"-windowed", "-noborder"}));
  config.remix_enabled = false;
  CHECK(!activate::plan(gen, config, none(), L"gmod.exe", counted).activate);
  CHECK(reads == 2);  // RTX off reads nothing
}

TEST_CASE("activate: no runtime deployed is inactive") {
  journal::Generation gen;
  gen.number = 1;
  journal::Package pkg;  // a root-files package, no remix
  pkg.id = "fixes";
  pkg.version = "1.0.0";
  gen.packages.push_back(pkg);
  const auto plan = activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd);
  CHECK(!plan.activate);
  CHECK(plan.runtime_dll.empty());
  CHECK(plan.env.empty());
  CHECK(plan.launch_args.empty());
  CHECK(plan.reason == "no runtime package is deployed");
}

TEST_CASE("activate: remix.enabled false deploys but does not load") {
  config::Config config;
  config.remix_enabled = false;
  const auto plan = activate::plan(with_runtime("p", base_remix()), config, none(), L"gmod.exe", uhd);
  CHECK(!plan.activate);
  CHECK(plan.runtime_dll == "p/runtime/d3d9.dll");
  CHECK(plan.env.empty() && plan.launch_args.empty());
  CHECK(plan.reason == "remix.enabled is false in native-loader/config.json");
}

TEST_CASE("activate: without an NVIDIA GPU Remix chooses its own preset, from a layer of the loader's (ADR 0030)") {
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/dxvk/01_classic_remix_defaults.conf"};
  const auto gen = with_runtime("p", remix);
  const auto gpus = [](std::vector<unsigned> vendors) { return [vendors] { return vendors; }; };
  const std::string classic = "p/config/dxvk/01_classic_remix_defaults.conf";

  // An AMD (or Intel) GPU alone: the loader's layer goes above the package's, below the user's dxvk.conf.
  auto p = activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd, gpus({0x1002}));
  CHECK(p.non_nvidia);
  REQUIRE(env_value(p, "DXVK_CONFIG_FILE") != nullptr);
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == classic + ",native-loader/remix/non-nvidia.conf,dxvk.conf");
  CHECK((p.dxvk_layers == std::vector<std::string>{classic, "native-loader/remix/non-nvidia.conf", "dxvk.conf"}));
  CHECK(env_value(p, "DXVK_RTX_CONFIG_FILE") == nullptr);  // the rtx.conf chain is not touched

  // An NVIDIA GPU anywhere, no adapter read, or no reader: nothing changes.
  for (const auto& plan : {activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd, gpus({0x1002, 0x10DE})),
                           activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd, gpus({})),
                           activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd)}) {
    CHECK(!plan.non_nvidia);
    REQUIRE(env_value(plan, "DXVK_CONFIG_FILE") != nullptr);
    CHECK(*env_value(plan, "DXVK_CONFIG_FILE") == classic + ",dxvk.conf");
  }

  // The layer itself: Auto (5), and the user's own files on top. A package without dxvk layers still gets it.
  CHECK(activate::non_nvidia_layer_text().find("rtx.graphicsPreset = 5") != std::string::npos);
  const auto bare = activate::plan(with_runtime("p", base_remix()), config::Config{}, values({{"DXVK_CONFIG_FILE", "mine.conf"}}),
                                   L"gmod.exe", uhd, gpus({0x8086}));
  REQUIRE(env_value(bare, "DXVK_CONFIG_FILE") != nullptr);
  CHECK(*env_value(bare, "DXVK_CONFIG_FILE") == "native-loader/remix/non-nvidia.conf,mine.conf");

  // No RTX session, no adapter query.
  config::Config off;
  off.remix_enabled = false;
  bool asked = false;
  activate::plan(gen, off, none(), L"gmod.exe", uhd, [&asked] { asked = true; return std::vector<unsigned>{}; });
  CHECK(!asked);
}
