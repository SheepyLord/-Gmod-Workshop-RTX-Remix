#include "nl/memory_profile.h"
#include "nl/json.h"
#include "nl_test.h"

namespace {
using nl::memory_profile::Profile;
using nl::config::MemoryProfile;
constexpr std::uint64_t kMib = std::uint64_t{1} << 20;
nl::memory_profile::Budget sized(std::uint64_t vram_mib, std::uint64_t ram_mib, MemoryProfile requested = MemoryProfile::automatic) {
  return nl::memory_profile::plan(vram_mib * kMib, ram_mib * kMib, requested);
}
}  // namespace

TEST_CASE("memory profile: the smaller of VRAM and RAM chooses, with Windows' reported sizes") {
  struct Example { std::uint64_t vram, ram; Profile expected; };
  const Example examples[] = {
    {8188, 16224, Profile::minimum},       // an 8 GB card in a 16 GB computer, as Windows reports them
    {16376, 32605, Profile::recommended},  // 16 GB and 32 GB
    {24564, 65315, Profile::high},         // 24 GB and 64 GB
    {32187, 63117, Profile::high},         // this machine: RTX 5090, 64 GB
    {16376, 16224, Profile::minimum},      // a 16 GB card does not make 16 GB of RAM roomy
    {8188, 65315, Profile::minimum},
    {32187, 32605, Profile::recommended},
    {6144, 16224, Profile::below_minimum},
    {8188, 8095, Profile::below_minimum},
    {7680, 14336, Profile::minimum},       // the inclusive limits
    {7679, 14336, Profile::below_minimum},
    {15360, 28672, Profile::recommended},
    {15359, 28672, Profile::minimum},
    {23552, 57344, Profile::high},
    {23552, 57343, Profile::recommended},
  };
  for (const auto& example : examples) {
    const auto budget = sized(example.vram, example.ram);
    CHECK(budget.profile == example.expected);
    CHECK(budget.source == "auto");
    CHECK(budget.vram_mib == example.vram);
    CHECK(budget.ram_mib == example.ram);
  }
  CHECK(sized(6144, 16224).reason.find("below the supported minimum") != std::string::npos);
}

TEST_CASE("memory profile: budgets scale with the measured memory, never an 8 GB budget on a larger card") {
  const auto minimum = sized(8188, 16224);
  CHECK(minimum.warm_characters == 0);
  CHECK(minimum.warm_mib == 0);
  CHECK(minimum.managed_texture_budget_mib == 2047);
  CHECK(minimum.release_host_copies);

  const auto recommended = sized(16376, 32605);
  CHECK(recommended.warm_characters == 5);
  CHECK(recommended.warm_mib == 3260);
  CHECK(recommended.managed_texture_budget_mib == 4094);
  CHECK(!recommended.release_host_copies);

  const auto high = sized(32187, 63117);
  CHECK(high.warm_characters == 10);
  CHECK(high.warm_mib == 6311);
  CHECK(high.managed_texture_budget_mib == 8046);
  CHECK(!high.release_host_copies);

  // A 16 GB card held back by 16 GB of RAM keeps its own GPU budget; only the RAM-bound choices shrink.
  const auto ram_bound = sized(16376, 16224);
  CHECK(ram_bound.profile == Profile::minimum);
  CHECK(ram_bound.managed_texture_budget_mib == 4094);
  CHECK(ram_bound.warm_characters == 0);
  CHECK(ram_bound.release_host_copies);

  // A below-minimum computer runs the minimum's rules with its own (smaller) sizes.
  const auto small = sized(1024, 8095);
  CHECK(small.profile == Profile::below_minimum);
  CHECK(small.managed_texture_budget_mib == 512);
  CHECK(small.release_host_copies);
}

TEST_CASE("memory profile: sizes that were not read count as the minimum's") {
  const auto unknown = nl::memory_profile::plan(0, 0, MemoryProfile::automatic);
  CHECK(unknown.profile == Profile::minimum);
  CHECK(unknown.vram_mib == 0);
  CHECK(unknown.ram_mib == 0);
  CHECK(unknown.managed_texture_budget_mib == 2048);
  CHECK(unknown.warm_characters == 0);
  CHECK(unknown.reason == "VRAM not read -> minimum; RAM not read -> minimum");
  CHECK(sized(32187, 0).profile == Profile::minimum);
  CHECK(sized(32187, 0).managed_texture_budget_mib == 8046);
  CHECK(sized(0, 63117).profile == Profile::minimum);
}

TEST_CASE("memory profile: remix.memory_profile runs another profile's budgets, at most the measured memory") {
  const auto minimum = sized(32187, 63117, MemoryProfile::minimum);
  CHECK(minimum.profile == Profile::minimum);
  CHECK(minimum.source == "config");
  CHECK(minimum.managed_texture_budget_mib == 2048);
  CHECK(minimum.warm_characters == 0);
  CHECK(minimum.release_host_copies);
  CHECK(minimum.vram_mib == 32187);  // the measured sizes are still reported
  CHECK(minimum.reason.rfind("remix.memory_profile=minimum; 32187 MiB VRAM -> high", 0) == 0);
  CHECK(minimum.reason.find("budgets for 8192 MiB VRAM and 16384 MiB RAM") != std::string::npos);

  const auto recommended = sized(32187, 63117, MemoryProfile::recommended);
  CHECK(recommended.managed_texture_budget_mib == 4096);
  CHECK(recommended.warm_characters == 5);
  CHECK(recommended.warm_mib == 3276);
  CHECK(!recommended.release_host_copies);

  // Asking for more than the computer has keeps its measured sizes.
  const auto forced = sized(8188, 16224, MemoryProfile::recommended);
  CHECK(forced.profile == Profile::recommended);
  CHECK(forced.managed_texture_budget_mib == 2047);
  CHECK(forced.warm_mib == 1622);
  const auto high = sized(8188, 16224, MemoryProfile::high);
  CHECK(high.warm_characters == 10);
  CHECK(high.managed_texture_budget_mib == 2047);
  CHECK(sized(32187, 63117, MemoryProfile::high).managed_texture_budget_mib == 8046);
}

TEST_CASE("memory profile: status JSON and the runtime layer") {
  auto budget = sized(16376, 32605);
  budget.layer = "native-loader/remix/memory.conf";
  const auto value = nl::json::parse(nl::memory_profile::serialize(budget));
  CHECK(value.find("profile")->as_string() == "recommended");
  CHECK(value.find("source")->as_string() == "auto");
  CHECK(value.find("vram_mib")->as_int() == 16376);
  CHECK(value.find("ram_mib")->as_int() == 32605);
  CHECK(value.find("warm_characters")->as_int() == 5);
  CHECK(value.find("warm_mib")->as_int() == 3260);
  CHECK(value.find("managed_texture_budget_mib")->as_int() == 4094);
  CHECK(!value.find("release_host_copies")->as_bool());
  CHECK(value.find("layer")->as_string() == "native-loader/remix/memory.conf");
  CHECK(value.find("reason")->as_string() == budget.reason);

  const auto text = nl::memory_profile::layer_text(sized(8188, 16224));
  CHECK(text.find("\r\nd3d9.managedTextureBudgetMiB = 2047\r\n") != std::string::npos);
  CHECK(text.find("\r\nd3d9.releaseManagedHostCopies = True\r\n") != std::string::npos);
  CHECK(text.find("rtx.") == std::string::npos);  // D3D9 options only (ADR 0062)
  CHECK(nl::memory_profile::layer_text(budget).find("d3d9.releaseManagedHostCopies = False\r\n") != std::string::npos);
}

TEST_CASE("memory profile: config values, with a wrong one costing only the override") {
  CHECK(nl::config::parse(R"({"schema":1})").memory_profile == MemoryProfile::automatic);
  CHECK(nl::config::parse(R"({"schema":1,"remix":{"memory_profile":"auto"}})").memory_profile == MemoryProfile::automatic);
  CHECK(nl::config::parse(R"({"schema":1,"remix":{"memory_profile":"minimum"}})").memory_profile == MemoryProfile::minimum);
  CHECK(nl::config::parse(R"({"schema":1,"remix":{"memory_profile":"recommended"}})").memory_profile == MemoryProfile::recommended);
  CHECK(nl::config::parse(R"({"schema":1,"remix":{"memory_profile":"high"}})").memory_profile == MemoryProfile::high);
  for (const char* text : {R"({"schema":1,"remix":{"memory_profile":"huge"}})", R"({"schema":1,"remix":{"memory_profile":3}})"}) {
    const auto config = nl::config::parse(text);
    CHECK(config.memory_profile == MemoryProfile::automatic);
    REQUIRE(config.notes.size() == 1);
    CHECK(config.notes[0] == "remix.memory_profile must be auto, minimum, recommended or high; using auto");
  }
}
