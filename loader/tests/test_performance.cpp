#include "nl/performance.h"
#include "nl/json.h"
#include "nl_test.h"

namespace {
using nl::performance::Tier;
using nl::performance::Adapter;
using nl::performance::kNvidia;
using nl::config::PerformanceTier;
}

TEST_CASE("performance: consumer RTX classes and VRAM choose the lower tier") {
  struct Example { const char* description; unsigned gib; Tier expected; };
  const Example examples[] = {
    {"NVIDIA GeForce RTX 5090", 32, Tier::high}, {"NVIDIA GeForce RTX 4090", 24, Tier::high},
    {"NVIDIA GeForce RTX 5090 D", 32, Tier::high}, {"NVIDIA GeForce GTX 1080 Ti", 11, Tier::medium},
    {"NVIDIA RTX A2000 Laptop GPU", 16, Tier::high},
    {"NVIDIA GeForce RTX 4080", 16, Tier::high}, {"NVIDIA GeForce RTX 4070 Ti Super", 16, Tier::medium},
    {"NVIDIA GeForce RTX 4070", 12, Tier::medium}, {"NVIDIA GeForce RTX 3080", 10, Tier::medium},
    {"NVIDIA GeForce RTX 4060 Ti", 16, Tier::low}, {"NVIDIA GeForce RTX 4060 Ti", 8, Tier::low},
    {"NVIDIA GeForce RTX 4060 Laptop GPU", 8, Tier::low}, {"NVIDIA GeForce RTX 4090 Laptop GPU", 16, Tier::medium},
    {"NVIDIA GeForce RTX 3060", 12, Tier::low}, {"NVIDIA GeForce RTX 2060", 6, Tier::low},
    {"NVIDIA RTX A4000", 16, Tier::high}, {"Unknown NVIDIA adapter", 10, Tier::medium},
    {"NVIDIA GeForce RTX 4070 Laptop GPU", 16, Tier::low}, {"NVIDIA GeForce RTX 4050", 16, Tier::low},
    {"nvidia geforce rtx 4080 super", 16, Tier::high}, {"NVIDIA RTX 6000 Ada", 48, Tier::high},
    {"NVIDIA Quadro RTX 8000", 48, Tier::high}, {"NVIDIA RTX 50900", 10, Tier::medium},
    {"NVIDIA RTX 4060X", 16, Tier::high}, {"NVIDIA RTX Next", 8, Tier::low}
  };
  for (const auto& example : examples) {
    const auto selected = nl::performance::classify({{kNvidia, example.description, std::uint64_t{example.gib} << 30}}, PerformanceTier::automatic);
    if (selected.tier != example.expected) nl::test::fail(example.description, __FILE__, __LINE__);
    CHECK(selected.nvidia);
    CHECK(selected.source == "auto");
    CHECK(selected.adapter == example.description);
    CHECK(selected.dedicated_vram_mib == example.gib * 1024ull);
    CHECK(selected.reason.find('\n') == std::string::npos);
  }
}

TEST_CASE("performance: VRAM bounds include exactly 8.5 and 12.5 GiB and use bytes") {
  for (const auto& [bytes, tier] : std::vector<std::pair<std::uint64_t, Tier>>{
         {8704ull << 20, Tier::low}, {(8704ull << 20) + 1, Tier::medium},
         {12800ull << 20, Tier::medium}, {(12800ull << 20) + 1, Tier::high}}) {
    CHECK(nl::performance::classify({{kNvidia, "Unknown", bytes}}, PerformanceTier::automatic).tier == tier);
  }
}

TEST_CASE("performance: largest NVIDIA wins over integrated and other dedicated adapters") {
  const std::vector<Adapter> adapters{{0x8086, "Intel", 0}, {kNvidia, "RTX 4060", 8ull << 30},
                                    {0x1002, "AMD", 48ull << 30}, {kNvidia, "RTX 4090", 24ull << 30}};
  const auto selected = nl::performance::classify(adapters, PerformanceTier::automatic);
  CHECK(selected.tier == Tier::high);
  CHECK(selected.adapter == "RTX 4090");
  for (const auto mode : {PerformanceTier::automatic, PerformanceTier::low, PerformanceTier::medium, PerformanceTier::high}) {
    const auto empty = nl::performance::classify({}, mode);
    CHECK(!empty.nvidia && empty.layer.empty() && empty.adapter.empty());
    CHECK(empty.reason.find("GPU not read") != std::string::npos);
    const auto amd = nl::performance::classify({{0x1002, "AMD", 8ull << 30}}, mode);
    CHECK(!amd.nvidia && amd.layer.empty());
    CHECK(empty.source == (mode == PerformanceTier::automatic ? "auto" : "config"));
    CHECK(amd.source == empty.source);
  }
}

TEST_CASE("performance: explicit override and I2 survive JSON quoting") {
  for (const auto& [mode, expected] : std::vector<std::pair<PerformanceTier, Tier>>{
         {PerformanceTier::high, Tier::high}, {PerformanceTier::medium, Tier::medium}, {PerformanceTier::low, Tier::low}}) {
    const auto selected = nl::performance::classify({{kNvidia, "RTX 4060 \"test\"", 8ull << 30}}, mode);
    CHECK(selected.tier == expected);
    CHECK(selected.source == "config");
    const auto unknown = nl::performance::classify({}, mode);
    CHECK(unknown.tier == expected && unknown.source == "config");
    CHECK(unknown.reason.find("GPU not read") != std::string::npos);
    const auto parsed = nl::json::parse(nl::performance::serialize(selected));
    CHECK(parsed.as_object().size() == 6);
    CHECK(parsed.find("adapter")->as_string() == selected.adapter);
    CHECK(parsed.find("tier")->as_string() == nl::performance::name(expected));
  }
}
