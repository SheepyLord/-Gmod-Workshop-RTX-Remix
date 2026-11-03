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
  CHECK(*rtx == "native-loader/remix/rtx-1.conf,native-loader/remix/rtx-2.conf,rtx.conf");
  CHECK(*dxvk == "native-loader/remix/dxvk-1.conf,dxvk.conf");
  // Each is a copy of the package's file in its payload folder (ADR 0036).
  REQUIRE(plan.layer_copies.size() == 3);
  CHECK(plan.layer_copies[0].source == payload + "/config/rtx/01_base.conf");
  CHECK(plan.layer_copies[0].copy == "native-loader/remix/rtx-1.conf");
  CHECK(plan.layer_copies[1].source == payload + "/config/rtx/02_look.conf");
  CHECK(plan.layer_copies[2].source == payload + "/config/dxvk/01_dxvk.conf");
  CHECK(plan.layer_copies[2].copy == "native-loader/remix/dxvk-1.conf");
}

TEST_CASE("activate: the user's own environment wins over the package") {
  manifest::Remix remix = base_remix();
  remix.rtx_conf_layers = {"config/rtx/01_base.conf"};
  remix.env = {{"DXVK_LOG_LEVEL", "info"}, {"RTX_TEST", "on"}};
  const auto gen = with_runtime("p", remix);
  const auto plan = activate::plan(gen, config::Config{}, values({{"DXVK_RTX_CONFIG_FILE", "base.conf,My overrides.conf"},
                                  {"DXVK_LOG_LEVEL", "debug"}}), L"gmod.exe", uhd);
  REQUIRE(env_value(plan, "DXVK_RTX_CONFIG_FILE"));
  CHECK(*env_value(plan, "DXVK_RTX_CONFIG_FILE") == "native-loader/remix/rtx-1.conf,base.conf,My overrides.conf");
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
  CHECK(*env_value(p, "DXVK_RTX_CONFIG_FILE") == "native-loader/remix/rtx-1.conf,用户.conf,final.conf");
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == "native-loader/remix/dxvk-1.conf,dxvk-user.conf,top.conf");
  CHECK(env_value(p, "RTX_TEST") == nullptr);
}

TEST_CASE("activate: the package's layers are listed as short copies, whatever its payload folder (R3-017, ADR 0036)") {
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/dxvk/01_classic_remix_defaults.conf", "config/dxvk/02_compiler_threads.conf"};
  const auto amd = [] { return std::vector<performance::Adapter>{{0x1002, "AMD", 16ull << 30}}; };
  // The published package's folder (the list was 275 characters there without an NVIDIA GPU), and a far
  // longer one: the list is the same.
  for (const std::string& payload : {std::string("native-loader/packages/gmod-rtx-remix/0.0.0-dev.20261030022927+8beef27e_21"),
                                     "native-loader/packages/" + std::string(220, 'p') + "/1_1"}) {
    const auto p = activate::plan(with_runtime(payload, remix), config::Config{}, none(), L"gmod.exe", uhd, amd);
    REQUIRE(env_value(p, "DXVK_CONFIG_FILE") != nullptr);
    CHECK(*env_value(p, "DXVK_CONFIG_FILE") ==
          "native-loader/remix/non-nvidia.conf,native-loader/remix/dxvk-1.conf,native-loader/remix/dxvk-2.conf,dxvk.conf");
    CHECK(p.notes.empty());
    REQUIRE(p.layer_copies.size() == 2);
    CHECK(p.layer_copies[1].source == payload + "/config/dxvk/02_compiler_threads.conf");
  }
  // Only a long list of the user's own can still reach the limit: noted, and still set.
  const auto own = activate::plan(with_runtime("p", remix), config::Config{},
                                  values({{"DXVK_CONFIG_FILE", std::string(250, 'u') + ".conf"}}), L"gmod.exe", uhd);
  REQUIRE(own.notes.size() == 1);
  CHECK(own.notes[0].find("DXVK_CONFIG_FILE is ") == 0);
  CHECK(env_value(own, "DXVK_CONFIG_FILE") != nullptr);  // still set: the note explains the fallback
}

TEST_CASE("activate: a copy the bootstrap could not write is replaced by its source (ADR 0036)") {
  auto remix = base_remix();
  remix.rtx_conf_layers = {"config/rtx/base.conf"};
  remix.dxvk_conf_layers = {"config/dxvk/01.conf", "config/dxvk/02.conf"};
  auto p = activate::plan(with_runtime("p", remix), config::Config{}, none(), L"gmod.exe", uhd);
  activate::use_sources(p, {"native-loader/remix/dxvk-2.conf"});
  REQUIRE(env_value(p, "DXVK_CONFIG_FILE") != nullptr);
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == "native-loader/remix/dxvk-1.conf,p/config/dxvk/02.conf,dxvk.conf");
  CHECK((p.dxvk_layers == std::vector<std::string>{"native-loader/remix/dxvk-1.conf", "p/config/dxvk/02.conf", "dxvk.conf"}));
  CHECK(*env_value(p, "DXVK_RTX_CONFIG_FILE") == "native-loader/remix/rtx-1.conf,rtx.conf");  // the other list is untouched
  REQUIRE(p.layer_copies.size() == 2);  // the copy that was not written is no longer listed as one
  CHECK(p.layer_copies[1].copy == "native-loader/remix/dxvk-1.conf");
  CHECK(p.notes.empty());
  const auto before = p.env;
  activate::use_sources(p, {});
  CHECK(p.env == before);

  // A source too long for the runtime once listed: noted.
  auto q = activate::plan(with_runtime("native-loader/packages/" + std::string(240, 'p') + "/1_1", remix), config::Config{}, none(),
                          L"gmod.exe", uhd);
  CHECK(q.notes.empty());
  activate::use_sources(q, {"native-loader/remix/dxvk-1.conf"});
  REQUIRE(q.notes.size() == 1);
  CHECK(q.notes[0].find("DXVK_CONFIG_FILE is ") == 0);
}

TEST_CASE("activate: empty config variables retain the runtime's default user root layer") {
  auto remix = base_remix();
  remix.rtx_conf_layers = {"config/base.conf"};
  const auto p = activate::plan(with_runtime("p", remix), config::Config{}, values({{"DXVK_RTX_CONFIG_FILE", ""}}), L"gmod.exe", uhd);
  REQUIRE(env_value(p, "DXVK_RTX_CONFIG_FILE"));
  CHECK(*env_value(p, "DXVK_RTX_CONFIG_FILE") == "native-loader/remix/rtx-1.conf,rtx.conf");
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
  const auto gpus = [](std::vector<unsigned> vendors) { return [vendors] {
    std::vector<performance::Adapter> adapters;
    for (unsigned vendor : vendors) adapters.push_back({vendor, "RTX 5090", 32ull << 30});
    return adapters;
  }; };
  const std::string classic = "native-loader/remix/dxvk-1.conf";  // the copy of the package's classic layer

  // An AMD (or Intel) GPU alone: the loader's layer goes above the package's, below the user's dxvk.conf.
  auto p = activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd, gpus({0x1002}));
  CHECK(p.non_nvidia);
  REQUIRE(env_value(p, "DXVK_CONFIG_FILE") != nullptr);
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == "native-loader/remix/non-nvidia.conf," + classic + ",dxvk.conf");
  CHECK((p.dxvk_layers == std::vector<std::string>{"native-loader/remix/non-nvidia.conf", classic, "dxvk.conf"}));
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
  activate::plan(gen, off, none(), L"gmod.exe", uhd, [&asked] { asked = true; return std::vector<performance::Adapter>{}; });
  CHECK(!asked);
}

TEST_CASE("activate: the runtime's late bare-name DLLs load with it (ADR 0030)") {
  for (const char* name : {"amd_fidelityfx_vk.dll", "AMD_FidelityFX_VK.DLL", "cudart64_13.dll", "nvrtc64_130_0.dll",
                           "nvrtc-builtins64_133.dll"})
    CHECK(activate::late_runtime_dll(name));
  for (const char* name : {"d3d9.dll", "NRD.dll", "cudart64_.dll", "cudart64_13.dll.bak", "amd_fidelityfx_dx12.dll", "nvrtc64_130_0.lib"})
    CHECK(!activate::late_runtime_dll(name));

  // The runtime package's own files at the top of its folder: not a subfolder, not another package's.
  auto gen = with_runtime("p", base_remix());
  const auto file = [&gen](const std::string& path, const std::string& package) {
    journal::File record;
    record.path = path;
    record.package = package;
    gen.files.push_back(record);
  };
  for (const char* name : {"d3d9.dll", "nvrtc64_130_0.dll", "NRD.dll", "cudart64_13.dll", "amd_fidelityfx_vk.dll",
                           "nvrtc-builtins64_133.dll", "usd/plugins/cudart64_13.dll"})
    file(std::string("p/runtime/") + name, "rtx-remix-runtime");
  file("p/runtime/cudart64_12.dll", "root-only");
  const auto p = activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd);
  CHECK(p.activate);
  CHECK((p.preload == std::vector<std::string>{"p/runtime/amd_fidelityfx_vk.dll", "p/runtime/cudart64_13.dll",
                                               "p/runtime/nvrtc-builtins64_133.dll", "p/runtime/nvrtc64_130_0.dll"}));

  // No RTX session, nothing to load.
  config::Config off;
  off.remix_enabled = false;
  CHECK(activate::plan(gen, off, none(), L"gmod.exe", uhd).preload.empty());
}

TEST_CASE("activate: tier and diagnostic layer order for all policy combinations") {
  const auto nvidia = [] { return std::vector<performance::Adapter>{{activate::kNvidia, "RTX 5090", 32ull << 30}}; };
  const auto amd = [] { return std::vector<performance::Adapter>{{0x1002, "AMD", 8ull << 30}}; };
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/dxvk/classic.conf", "config/dxvk/compiler.conf"};
  auto generation = with_runtime("payload", remix);
  for (const char* tier : {"medium", "low"}) {
    journal::File file;
    file.package = "rtx-remix-runtime";
    file.path = "payload/config/dxvk-tiers/" + std::string(tier) + ".conf";
    generation.files.push_back(file);
  }
  for (const auto tier : {config::PerformanceTier::automatic, config::PerformanceTier::high,
                          config::PerformanceTier::medium, config::PerformanceTier::low}) {
    for (const auto mode : {config::GpuCrashDumps::off, config::GpuCrashDumps::next_start, config::GpuCrashDumps::always}) {
      for (bool is_nvidia : {false, true}) {
        config::Config config;
        config.performance_tier = tier;
        config.gpu_crash_dumps = mode;
        const auto p = activate::plan(generation, config, none(), L"gmod.exe", uhd,
                                       is_nvidia ? activate::GpuGet(nvidia) : activate::GpuGet(amd), {false, "C:/game/native-loader/logs/gpu/", {}});
        std::vector<std::string> expected;
        const bool tier_layer = is_nvidia && (tier == config::PerformanceTier::medium || tier == config::PerformanceTier::low);
        if (tier_layer) expected.emplace_back(activate::kTierLayer);
        if (!is_nvidia) expected.emplace_back(activate::kNonNvidiaLayer);
        expected.insert(expected.end(), {"native-loader/remix/dxvk-1.conf", "native-loader/remix/dxvk-2.conf"});
        if (mode != config::GpuCrashDumps::off) expected.emplace_back(gpu_diagnostics::kLayer);
        expected.emplace_back("dxvk.conf");
        CHECK(p.dxvk_layers == expected);
        REQUIRE(env_value(p, "DXVK_CONFIG_FILE"));
        CHECK(env_value(p, "DXVK_CONFIG_FILE")->size() < 260);
        CHECK(p.performance_tier.layer == (tier_layer ? std::string(activate::kTierLayer) : ""));
        CHECK(p.low_tier_fallback == false);
        CHECK(p.layer_copies.size() == (tier_layer ? 3u : 2u));
        if (tier_layer) CHECK(p.layer_copies.back().source == "payload/config/dxvk-tiers/" + std::string(performance::name(p.performance_tier.tier)) + ".conf");
        if (tier_layer) {
          auto missing = p;
          const auto source = missing.layer_copies.back().source;
          activate::use_sources(missing, {std::string(activate::kTierLayer)});
          CHECK(missing.performance_tier.layer == source);
          CHECK(missing.dxvk_layers.front() == source);
        }
        CHECK((env_value(p, std::string(gpu_diagnostics::kDumpVariable)) != nullptr) == p.gpu_crash_dumps);
      }
    }
  }
}

TEST_CASE("activate: old packages use the low fallback and no medium tier layer") {
  const auto nvidia = [] { return std::vector<performance::Adapter>{{activate::kNvidia, "RTX 4060 Ti", 16ull << 30}}; };
  const auto gen = with_runtime("payload", base_remix());
  auto config = config::Config{};
  auto p = activate::plan(gen, config, none(), L"gmod.exe", uhd, nvidia);
  CHECK(p.low_tier_fallback);
  CHECK(p.performance_tier.source == "fallback");
  CHECK(p.performance_tier.layer == activate::kTierLayer);
  CHECK(p.layer_copies.empty());
  CHECK((p.dxvk_layers == std::vector<std::string>{std::string(activate::kTierLayer), "dxvk.conf"}));
  const auto fallback = activate::low_tier_layer_text();
  for (const char* line : {"rtx.lowMemoryGpu = True", "rtx.opacityMicromap.cache.maxBudgetSizeMB = 512", "rtx.skyProbeSide = 1024",
                          "rtx.volumetrics.froxelGridResolutionScale = 8", "rtx.terrainBaker.cascadeMap.levelResolution = 2048"})
    CHECK(fallback.find(line) != std::string::npos);
  CHECK(fallback.find("dxvk.") == std::string::npos);
  config.performance_tier = config::PerformanceTier::medium;
  p = activate::plan(gen, config, none(), L"gmod.exe", uhd, nvidia);
  CHECK(!p.low_tier_fallback && p.performance_tier.layer.empty());
  CHECK(env_value(p, "DXVK_CONFIG_FILE") == nullptr);
  CHECK(p.performance_tier.reason.find("no medium tier file") != std::string::npos);

  // A different package's record cannot supply the runtime's tier file.
  auto foreign = gen;
  journal::File file;
  file.package = "other";
  file.path = "payload/config/dxvk-tiers/low.conf";
  foreign.files.push_back(file);
  config.performance_tier = config::PerformanceTier::low;
  CHECK(activate::plan(foreign, config, none(), L"gmod.exe", uhd, nvidia).low_tier_fallback);
}

TEST_CASE("activate: GPU query failure honors config tiers and keeps config as the source") {
  const auto gen = with_runtime("payload", base_remix());
  config::Config config;
  config.performance_tier = config::PerformanceTier::low;
  for (const auto& gpus : {activate::GpuGet{}, activate::GpuGet([] { return std::vector<performance::Adapter>{}; })}) {
    const auto p = activate::plan(gen, config, none(), L"gmod.exe", uhd, gpus);
    CHECK(p.activate && p.low_tier_fallback && !p.non_nvidia);
    CHECK(p.performance_tier.tier == performance::Tier::low);
    CHECK(p.performance_tier.source == "config");
    CHECK(p.performance_tier.layer == activate::kTierLayer);
    CHECK(p.performance_tier.reason.find("GPU not read") != std::string::npos);
  }
  const auto nvidia = [] { return std::vector<performance::Adapter>{{activate::kNvidia, "RTX 5090", 32ull << 30}}; };
  CHECK(activate::plan(gen, config, none(), L"gmod.exe", uhd, nvidia).performance_tier.source == "config");
  const auto amd = [] { return std::vector<performance::Adapter>{{0x1002, "AMD", 8ull << 30}}; };
  const auto non_nvidia = activate::plan(gen, config, none(), L"gmod.exe", uhd, amd);
  CHECK(non_nvidia.non_nvidia && non_nvidia.performance_tier.layer.empty());
  CHECK(non_nvidia.performance_tier.source == "config");
  config.performance_tier = config::PerformanceTier::medium;
  auto packaged = gen;
  journal::File file;
  file.package = "rtx-remix-runtime";
  file.path = "payload/config/dxvk-tiers/medium.conf";
  packaged.files.push_back(file);
  CHECK(activate::plan(packaged, config, none(), L"gmod.exe", uhd).performance_tier.layer == activate::kTierLayer);
}

TEST_CASE("activate: a failed low fallback drops every stale tier entry and retains diagnostics and user layers") {
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/base.conf"};
  config::Config config;
  config.performance_tier = config::PerformanceTier::low;
  config.gpu_crash_dumps = config::GpuCrashDumps::always;
  const auto user = values({{"DXVK_CONFIG_FILE", std::string(activate::kTierLayer) + ",mine.conf,last.conf"}});
  auto p = activate::plan(with_runtime("payload", remix), config, user, L"gmod.exe", uhd);
  CHECK(p.low_tier_fallback);
  activate::disable_performance_tier(p, "fallback write failed");
  CHECK(p.activate && !p.low_tier_fallback && p.performance_tier.layer.empty());
  CHECK((p.dxvk_layers == std::vector<std::string>{"native-loader/remix/dxvk-1.conf", std::string(gpu_diagnostics::kLayer), "mine.conf", "last.conf"}));
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == "native-loader/remix/dxvk-1.conf,native-loader/remix/diagnostics.conf,mine.conf,last.conf");
  CHECK(p.notes.back() == "fallback write failed");
}

TEST_CASE("activate: tier and diagnostic layers add 67 characters to the user's DXVK list budget") {
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/base.conf"};
  config::Config config;
  config.performance_tier = config::PerformanceTier::low;
  config.gpu_crash_dumps = config::GpuCrashDumps::always;
  const std::string base_prefix = "native-loader/remix/dxvk-1.conf,";
  const std::string prefix = std::string(activate::kTierLayer) + ',' + base_prefix + std::string(gpu_diagnostics::kLayer) + ',';
  CHECK(prefix.size() == base_prefix.size() + 67);
  for (const std::size_t length : {259u, 260u}) {
    const std::string user = "mine.conf," + std::string(length - prefix.size() - 10, 'x');
    const auto p = activate::plan(with_runtime("payload", remix), config, values({{"DXVK_CONFIG_FILE", user}}), L"gmod.exe", uhd);
    REQUIRE(env_value(p, "DXVK_CONFIG_FILE"));
    CHECK(*env_value(p, "DXVK_CONFIG_FILE") == prefix + user);
    CHECK(env_value(p, "DXVK_CONFIG_FILE")->size() == length);
    CHECK(std::any_of(p.notes.begin(), p.notes.end(), [](const auto& note) { return note.find("DXVK_CONFIG_FILE is 260 characters") != std::string::npos; }) == (length == 260));
  }
}

TEST_CASE("activate: malformed adapter names lose only the description") {
  CHECK(activate::adapter_description(L"NVIDIA RTX 5090") == "NVIDIA RTX 5090");
  CHECK(activate::adapter_description(L"GPU \u00e9") == "GPU \xc3\xa9");
  const wchar_t invalid[] = {0xd800, 0};
  const auto name = activate::adapter_description(invalid);
  CHECK(name.empty());
  const auto p = activate::plan(with_runtime("payload", base_remix()), {}, none(), L"gmod.exe", uhd,
                               [&] { return std::vector<performance::Adapter>{{activate::kNvidia, name, 8ull << 30}}; });
  CHECK(p.activate && p.low_tier_fallback && !p.non_nvidia);
  CHECK(p.performance_tier.dedicated_vram_mib == 8192);
}

TEST_CASE("activate: next_start once and diagnostics failures keep package and user lists") {
  auto config = config::Config{};
  config.gpu_crash_dumps = config::GpuCrashDumps::next_start;
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/base.conf"};
  const auto gen = with_runtime("payload", remix);
  const auto env = values({{"DXVK_CONFIG_FILE", "mine.conf,last.conf"}});
  const auto p = activate::plan(gen, config, env, L"gmod.exe", uhd, {}, {false, "C:/game/native-loader/logs/gpu/", {}});
  CHECK(p.gpu_crash_dumps && p.gpu_crash_dumps_once);
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") == "native-loader/remix/dxvk-1.conf,native-loader/remix/diagnostics.conf,mine.conf,last.conf");
  CHECK(*env_value(p, std::string(gpu_diagnostics::kDumpVariable)) == "C:/game/native-loader/logs/gpu/");
  const auto used = activate::plan(gen, config, env, L"gmod.exe", uhd, {}, {true, {}, {}});
  CHECK(!used.gpu_crash_dumps);
  CHECK(*env_value(used, "DXVK_CONFIG_FILE") == "native-loader/remix/dxvk-1.conf,mine.conf,last.conf");
  CHECK(!used.notes.empty());
  auto failed = p;
  activate::disable_gpu_crash_dumps(failed, "fixture failure");
  CHECK(!failed.gpu_crash_dumps);
  CHECK(failed.env == used.env);
  CHECK(failed.notes.back() == "fixture failure");
  config.gpu_crash_dumps = config::GpuCrashDumps::always;
  CHECK(activate::plan(gen, config, env, L"gmod.exe", uhd, {}, {true, {}, {}}).gpu_crash_dumps);
  config.remix_enabled = false;
  CHECK(!activate::plan(gen, config, env, L"gmod.exe", uhd).gpu_crash_dumps);
}

TEST_CASE("activate: invalid tier notes survive planning even without a runtime") {
  const auto config = config::parse(R"({"schema":1,"remix":{"performance_tier":"fast"}})");
  CHECK(!activate::plan({}, config, none(), L"gmod.exe", uhd).notes.empty());
}

TEST_CASE("activate: disabling diagnostics alone restores config discovery and package environment") {
  auto config = config::Config{};
  config.gpu_crash_dumps = config::GpuCrashDumps::always;
  auto bare = activate::plan(with_runtime("payload", base_remix()), config, none(), L"gmod.exe", uhd);
  activate::disable_gpu_crash_dumps(bare, "fixture failure");
  CHECK(env_value(bare, "DXVK_CONFIG_FILE") == nullptr);
  CHECK(env_value(bare, std::string(gpu_diagnostics::kDumpVariable)) == nullptr);

  auto remix = base_remix();
  remix.env = {{std::string(gpu_diagnostics::kDumpVariable), "package-dump-folder"}};
  auto package = activate::plan(with_runtime("payload", remix), config, none(), L"gmod.exe", uhd);
  activate::disable_gpu_crash_dumps(package, "fixture failure");
  REQUIRE(env_value(package, std::string(gpu_diagnostics::kDumpVariable)));
  CHECK(*env_value(package, std::string(gpu_diagnostics::kDumpVariable)) == "package-dump-folder");

  const auto own = values({{"DXVK_CONFIG_FILE", std::string(gpu_diagnostics::kLayer) + ",mine.conf"}});
  auto duplicate = activate::plan(with_runtime("payload", base_remix()), config, own, L"gmod.exe", uhd);
  activate::disable_gpu_crash_dumps(duplicate, "fixture failure");
  CHECK(env_value(duplicate, "DXVK_CONFIG_FILE") == nullptr);  // the user's explicit duplicate stays in their environment
  CHECK((duplicate.dxvk_layers == std::vector<std::string>{std::string(gpu_diagnostics::kLayer), "mine.conf"}));
}

TEST_CASE("activate: the memory profile's layer follows the package's layers and precedes the user's") {
  auto remix = base_remix();
  remix.dxvk_conf_layers = {"config/base.conf"};
  const auto gen = with_runtime("payload", remix);
  const auto adapters = [] { return std::vector<performance::Adapter>{{activate::kNvidia, "NVIDIA GeForce RTX 4060", 8188ull << 20},
                                                                     {0x8086, "Intel UHD", 128ull << 20}}; };
  int asked = 0;
  const auto ram = [&asked] { ++asked; return std::uint64_t{16224} << 20; };
  auto p = activate::plan(gen, config::Config{}, values({{"DXVK_CONFIG_FILE", "mine.conf"}}), L"gmod.exe", uhd, adapters, {}, ram);
  CHECK(asked == 1);
  CHECK(p.memory.profile == memory_profile::Profile::minimum);
  CHECK(p.memory.vram_mib == 8188);
  CHECK(p.memory.layer == activate::kMemoryLayer);
  CHECK((p.dxvk_layers == std::vector<std::string>{std::string(activate::kTierLayer), "native-loader/remix/dxvk-1.conf",
                                                   std::string(activate::kMemoryLayer), "mine.conf"}));
  CHECK(*env_value(p, "DXVK_CONFIG_FILE") ==
        "native-loader/remix/tier.conf,native-loader/remix/dxvk-1.conf,native-loader/remix/memory.conf,mine.conf");

  // Diagnostics stay last among the loader's layers; a failed memory layer leaves the rest as before.
  config::Config dumps;
  dumps.gpu_crash_dumps = config::GpuCrashDumps::always;
  dumps.memory_profile = config::MemoryProfile::recommended;
  auto q = activate::plan(gen, dumps, none(), L"gmod.exe", uhd, adapters, {}, ram);
  CHECK(q.memory.source == "config");
  CHECK(q.memory.warm_characters == 5);
  CHECK(*env_value(q, "DXVK_CONFIG_FILE") ==
        "native-loader/remix/tier.conf,native-loader/remix/dxvk-1.conf,native-loader/remix/memory.conf,native-loader/remix/diagnostics.conf,dxvk.conf");
  activate::disable_memory_layer(q, "memory layer failed");
  CHECK(q.memory.layer.empty());
  CHECK(q.memory.warm_characters == 5);  // the profile stays for the hotloader's status
  CHECK(*env_value(q, "DXVK_CONFIG_FILE") ==
        "native-loader/remix/tier.conf,native-loader/remix/dxvk-1.conf,native-loader/remix/diagnostics.conf,dxvk.conf");
  CHECK(q.notes.back() == "memory layer failed");
}

TEST_CASE("activate: without a RAM reader, or without RTX, no memory profile or layer") {
  const auto gen = with_runtime("payload", base_remix());
  const auto bare = activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd);
  CHECK(bare.memory.reason.empty());
  CHECK(bare.memory.layer.empty());
  CHECK(env_value(bare, "DXVK_CONFIG_FILE") == nullptr);

  bool asked = false;
  config::Config off;
  off.remix_enabled = false;
  const auto inactive = activate::plan(gen, off, none(), L"gmod.exe", uhd, {}, {}, [&asked] { asked = true; return std::uint64_t{1} << 34; });
  CHECK(!inactive.activate);
  CHECK(!asked);
  CHECK(inactive.memory.reason.empty());

  // Only the memory layer: disabling it removes the list and restores the runtime's own discovery.
  auto only = activate::plan(gen, config::Config{}, none(), L"gmod.exe", uhd, {}, {}, [] { return std::uint64_t{0}; });
  CHECK(only.memory.profile == memory_profile::Profile::minimum);
  CHECK(*env_value(only, "DXVK_CONFIG_FILE") == "native-loader/remix/memory.conf,dxvk.conf");
  activate::disable_memory_layer(only, "memory layer failed");
  CHECK(env_value(only, "DXVK_CONFIG_FILE") == nullptr);
}